import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/extra.dart';
import '../utils/format.dart';
import '../utils/sun.dart';
import 'database.dart';
import 'native.dart';
import 'recorder.dart';
import 'settings.dart';

enum SosState { idle, countdown, active }

class _QueuedSms {
  _QueuedSms(this.phone, this.text);
  final String phone;
  final String text;
  int attempts = 0;
}

/// Segurança na trilha: SOS por SMS, Plano de trilha, aviso de bateria,
/// pôr do sol, imobilidade ("Você está bem?") e sinal de resgate.
/// Tudo funciona sem internet: basta sinal de celular para o SMS.
class SafetyService extends ChangeNotifier {
  SafetyService._();
  static final SafetyService instance = SafetyService._();

  final _battery = Battery();
  List<EmergencyContact> contacts = [];

  // SOS
  SosState sos = SosState.idle;
  int countdown = 0;
  String sosReason = '';
  DateTime? sosLastSentAt;
  int sosLastDelivered = 0;
  Timer? _countdownTimer;
  Timer? _resendTimer;

  // Fila de SMS que falharam (sem sinal): nova tentativa a cada minuto.
  final List<_QueuedSms> _queue = [];
  Timer? _queueTimer;
  int get queued => _queue.length;

  // Plano de trilha
  DateTime? pendingPlanReturn; // escolhido antes de iniciar
  DateTime? planReturn; // plano ativo
  bool _planAlertSent = false;

  // "Você está bem?"
  DateTime? checkInDeadline;
  String checkInReason = '';
  Timer? _checkInTimer;

  // Bateria e pôr do sol
  bool _batterySent = false;
  bool _sunsetWarned = false;
  int? batteryLevel;
  DateTime? sunset;

  // Sinal de resgate
  bool rescueSignal = false;
  bool screenFlash = false;

  Timer? _monitor;
  int _tick = 0;
  String? Function()? liveLinkProvider; // preenchido pelo módulo ao vivo
  Future<void> Function(String sosText, List<String> phones)? groupRelay;

  String get _name =>
      Settings.instance.ownerName.isEmpty ? 'Usuário do GAZMAP' : Settings.instance.ownerName;

  Future<void> init() async {
    contacts = await AppDatabase.instance.contacts();
    AppDatabase.instance.changes.addListener(_reloadContacts);
    _monitor = Timer.periodic(const Duration(seconds: 5), (_) => _check());
  }

  Future<void> _reloadContacts() async {
    contacts = await AppDatabase.instance.contacts();
    notifyListeners();
  }

  @override
  void dispose() {
    _monitor?.cancel();
    super.dispose();
  }

  // ---------- Permissão e envio ----------

  /// null = ok; senão, mensagem explicando o problema.
  Future<String?> ensureSmsPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return 'O envio automático de SMS só funciona no Android.';
    }
    final st = await Permission.sms.request();
    if (st.isGranted) return null;
    if (st.isPermanentlyDenied) {
      return 'Permissão de SMS negada. Libere nas configurações do app.';
    }
    return 'O GAZMAP precisa da permissão de SMS para avisar seus contatos.';
  }

  String locationText() {
    final p = Recorder.instance.position;
    final b = batteryLevel;
    final buf = StringBuffer();
    if (p == null) {
      buf.write('Posição ainda desconhecida (sem GPS).');
    } else {
      final lat = p.latitude.toStringAsFixed(5), lon = p.longitude.toStringAsFixed(5);
      buf.write('Local: $lat, $lon (precisão ${p.accuracy.round()} m) às '
          '${fmtDate(p.timestamp.toLocal()).split(' ').last}. '
          'Mapa: https://maps.google.com/?q=$lat,$lon');
    }
    if (b != null) buf.write(' Bateria: $b%.');
    final live = liveLinkProvider?.call();
    if (live != null) buf.write(' Ao vivo: $live');
    return buf.toString();
  }

  /// Envia para todos os contatos. Falhas vão para a fila.
  Future<int> sendToAll(String text) async {
    if (contacts.isEmpty) return 0;
    if (await ensureSmsPermission() != null) return 0;
    var ok = 0;
    for (final c in contacts) {
      if (await NativeBridge.sendSms(c.phone, text)) {
        ok++;
      } else {
        _queue.add(_QueuedSms(c.phone, text));
      }
    }
    _startQueue();
    notifyListeners();
    return ok;
  }

  void _startQueue() {
    if (_queue.isEmpty || _queueTimer != null) return;
    _queueTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      final pending = List<_QueuedSms>.from(_queue);
      for (final q in pending) {
        q.attempts++;
        if (await NativeBridge.sendSms(q.phone, q.text)) _queue.remove(q);
        if (q.attempts > 120) _queue.remove(q); // desiste após ~2 h
      }
      if (_queue.isEmpty) {
        _queueTimer?.cancel();
        _queueTimer = null;
      }
      notifyListeners();
    });
  }

  Future<int> sendTest() => sendToAll(
      'Teste do GAZMAP: este número está cadastrado como contato de emergência '
      'de $_name. Não é um alerta. ${locationText()}');

  // ---------- SOS ----------

  void startCountdown({String reason = 'Pedido de socorro'}) {
    if (sos != SosState.idle) return;
    sos = SosState.countdown;
    sosReason = reason;
    countdown = 5;
    notifyListeners();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      countdown--;
      NativeBridge.vibrate([0, 250]);
      NativeBridge.beep(150);
      if (countdown <= 0) {
        t.cancel();
        _activateSos();
      }
      notifyListeners();
    });
    NativeBridge.vibrate([0, 250]);
  }

  Future<void> _activateSos() async {
    sos = SosState.active;
    notifyListeners();
    await _sendSos();
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(
        Duration(minutes: Settings.instance.sosResendMinutes.clamp(1, 60)),
        (_) => _sendSos());
  }

  String get sosText => 'SOS GAZMAP: $_name precisa de ajuda ($sosReason). '
      '${locationText()}';

  Future<void> _sendSos() async {
    sosLastDelivered = await sendToAll(sosText);
    sosLastSentAt = DateTime.now();
    final relay = groupRelay;
    if (relay != null) {
      unawaited(relay(sosText, contacts.map((c) => c.phone).toList()));
    }
    notifyListeners();
  }

  Future<void> cancelSos() async {
    final wasActive = sos == SosState.active;
    _countdownTimer?.cancel();
    _resendTimer?.cancel();
    sos = SosState.idle;
    countdown = 0;
    stopRescueSignal();
    notifyListeners();
    if (wasActive) {
      await sendToAll('GAZMAP: alarme cancelado. $_name está bem. ${locationText()}');
    }
  }

  // ---------- Plano de trilha ----------

  Future<void> startPlan(String activityName) async {
    final ret = pendingPlanReturn;
    pendingPlanReturn = null;
    if (ret == null || contacts.isEmpty) return;
    planReturn = ret;
    _planAlertSent = false;
    final hh = fmtDate(ret).split(' ').last;
    await sendToAll('GAZMAP: $_name começou "$activityName". Volta prevista às $hh. '
        'Se não houver notícias depois disso, você receberá um alerta com a última posição. '
        '${locationText()}');
  }

  Future<void> finishPlan() async {
    if (planReturn == null) return;
    planReturn = null;
    _planAlertSent = false;
    await sendToAll('GAZMAP: $_name terminou a atividade em segurança.');
    notifyListeners();
  }

  // ---------- "Você está bem?" ----------

  void requestCheckIn(String reason) {
    if (checkInDeadline != null || sos != SosState.idle) return;
    checkInReason = reason;
    checkInDeadline = DateTime.now().add(const Duration(minutes: 2));
    Recorder.instance.speak('Você está bem? Toque em "Estou bem" na tela.');
    _checkInTimer?.cancel();
    _checkInTimer = Timer.periodic(const Duration(seconds: 20), (t) {
      if (checkInDeadline == null) {
        t.cancel();
        return;
      }
      if (DateTime.now().isAfter(checkInDeadline!)) {
        t.cancel();
        checkInDeadline = null;
        _activateSosFromCheckIn();
        return;
      }
      NativeBridge.vibrate([0, 600, 300, 600]);
      NativeBridge.beep(400);
      Recorder.instance.speak('Você está bem? Toque em "Estou bem" na tela.');
    });
    NativeBridge.vibrate([0, 600, 300, 600]);
    notifyListeners();
  }

  Future<void> _activateSosFromCheckIn() async {
    sosReason = checkInReason == 'atraso'
        ? 'não voltou no horário previsto e não respondeu'
        : 'ficou parado por muito tempo e não respondeu';
    if (checkInReason == 'atraso') _planAlertSent = true;
    await _activateSos();
  }

  void confirmCheckIn() {
    if (checkInReason == 'atraso' && planReturn != null) {
      planReturn = DateTime.now()
          .add(Duration(minutes: Settings.instance.planMarginMinutes))
          .subtract(Duration(minutes: Settings.instance.planMarginMinutes ~/ 2));
    }
    checkInDeadline = null;
    _checkInTimer?.cancel();
    Recorder.instance.markActivity();
    notifyListeners();
  }

  // ---------- Monitor (a cada 5 s) ----------

  Future<void> _check() async {
    _tick++;
    final rec = Recorder.instance;
    final s = Settings.instance;
    final now = DateTime.now();

    if (_tick % 12 == 1) {
      try {
        batteryLevel = await _battery.batteryLevel;
      } catch (_) {}
      final p = rec.position;
      if (p != null) sunset = sunsetTime(now, p.latitude, p.longitude);
    }

    if (!rec.active) {
      _batterySent = false;
      _sunsetWarned = false;
      return;
    }

    // Plano de trilha atrasado
    final plan = planReturn;
    if (plan != null && !_planAlertSent &&
        now.isAfter(plan.add(Duration(minutes: s.planMarginMinutes)))) {
      requestCheckIn('atraso');
    }

    // Imobilidade
    final immob = s.immobilityMinutes;
    final last = rec.lastActivityAt;
    if (immob > 0 && rec.state == RecState.recording && last != null &&
        now.difference(last) > Duration(minutes: immob)) {
      requestCheckIn('imobilidade');
    }

    // Bateria baixa
    final b = batteryLevel;
    if (s.batteryAlert && !_batterySent && b != null && b <= 15 && contacts.isNotEmpty) {
      _batterySent = true;
      unawaited(sendToAll('GAZMAP: a bateria de $_name está em $b% durante a atividade. '
          'Última posição: ${locationText()}'));
      rec.speak('Bateria em $b por cento. Seus contatos receberam sua posição.');
    }

    // Pôr do sol
    final ss = sunset;
    if (s.sunsetAlert && !_sunsetWarned && ss != null && now.isBefore(ss)) {
      final left = ss.difference(now);
      final back = rec.movingTime; // voltar pelo mesmo caminho leva ~o mesmo tempo
      if (left < back + const Duration(minutes: 15) && rec.movingTime.inMinutes >= 10) {
        _sunsetWarned = true;
        NativeBridge.vibrate([0, 400, 200, 400]);
        rec.speak('Atenção: escurece em ${left.inMinutes} minutos. '
            'Voltar pelo mesmo caminho leva cerca de ${back.inMinutes} minutos.');
      }
    }
  }

  // ---------- Sinal de resgate (lanterna + bipe + tela) ----------

  /// Padrão SOS em código Morse: ··· ––– ···
  static const _pattern = [
    200, 200, 200, 200, 200, 600, //
    600, 200, 600, 200, 600, 600, //
    200, 200, 200, 200, 200, 1400,
  ];

  Future<void> startRescueSignal() async {
    if (rescueSignal) return;
    rescueSignal = true;
    notifyListeners();
    while (rescueSignal) {
      for (var i = 0; i < _pattern.length && rescueSignal; i += 2) {
        final on = _pattern[i], off = _pattern[i + 1];
        screenFlash = true;
        notifyListeners();
        await NativeBridge.torch(true);
        await NativeBridge.beep(on);
        await Future<void>.delayed(Duration(milliseconds: on));
        screenFlash = false;
        notifyListeners();
        await NativeBridge.torch(false);
        await Future<void>.delayed(Duration(milliseconds: off));
      }
    }
  }

  void stopRescueSignal() {
    if (!rescueSignal) return;
    rescueSignal = false;
    screenFlash = false;
    NativeBridge.torch(false);
    notifyListeners();
  }
}
