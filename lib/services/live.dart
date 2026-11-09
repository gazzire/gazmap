import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import 'recorder.dart';
import 'safety.dart';
import 'settings.dart';

/// Localização ao vivo por link (servidor próprio no WordPress/Hostinger).
/// Sem internet, guarda a última posição e envia quando o sinal volta.
class LiveShare extends ChangeNotifier {
  LiveShare._() {
    Recorder.instance.addListener(_onRecorder);
    SafetyService.instance.liveLinkProvider = () => url;
  }
  static final LiveShare instance = LiveShare._();

  String? _id;
  String? _key;
  String? url;
  bool starting = false;
  DateTime? lastSentAt;
  String? error;
  Timer? _timer;
  bool _wasActive = false;

  bool get active => url != null;

  String get _api => '${Settings.instance.liveServer.replaceAll(RegExp(r'/+$'), '')}/wp-json/gazmap/v1';

  void _onRecorder() {
    final rec = Recorder.instance;
    if (rec.active && !_wasActive) {
      _wasActive = true;
      if (Settings.instance.liveShare) start();
    } else if (!rec.active && _wasActive) {
      _wasActive = false;
      stop();
    }
  }

  Future<bool> start() async {
    if (active || starting) return active;
    starting = true;
    error = null;
    notifyListeners();
    try {
      final r = await http
          .post(Uri.parse('$_api/live'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'name': Settings.instance.ownerName,
                'activity': Recorder.instance.track?.activity.label ?? '',
              }))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200 && r.statusCode != 201) throw Exception('HTTP ${r.statusCode}');
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      _id = j['id'] as String;
      _key = j['key'] as String;
      url = j['url'] as String;
      _timer = Timer.periodic(const Duration(seconds: 60), (_) => _push());
      unawaited(_push());
      if (SafetyService.instance.contacts.isNotEmpty) {
        unawaited(SafetyService.instance.sendToAll(
            'GAZMAP: acompanhe ${Settings.instance.ownerName.isEmpty ? 'a atividade' : Settings.instance.ownerName} ao vivo: $url'));
      }
      return true;
    } catch (e) {
      error = 'Sem internet para iniciar o "ao vivo". O SOS por SMS continua funcionando.';
      return false;
    } finally {
      starting = false;
      notifyListeners();
    }
  }

  Future<void> _push() async {
    final id = _id, key = _key;
    final rec = Recorder.instance;
    final p = rec.position;
    if (id == null || key == null || p == null) return;
    try {
      final r = await http
          .post(Uri.parse('$_api/live/$id'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'key': key,
                'lat': p.latitude,
                'lon': p.longitude,
                'acc': p.accuracy,
                'dist': rec.distance.round(),
                'bat': SafetyService.instance.batteryLevel,
                'sos': SafetyService.instance.sos == SosState.active,
              }))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        lastSentAt = DateTime.now();
        notifyListeners();
      }
    } catch (_) {
      // Sem sinal: tenta de novo no próximo ciclo com a posição mais recente.
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final id = _id, key = _key;
    _id = null;
    _key = null;
    url = null;
    notifyListeners();
    if (id == null) return;
    try {
      await http
          .post(Uri.parse('$_api/live/$id/stop'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'key': key}))
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  Future<void> shareLink() async {
    final u = url;
    if (u == null) return;
    await Share.share('Acompanhe minha atividade ao vivo no GAZMAP: $u');
  }
}
