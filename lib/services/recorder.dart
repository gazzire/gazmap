import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/track.dart';
import '../utils/format.dart';
import 'database.dart';
import 'group.dart';
import 'safety.dart';
import 'settings.dart';

enum RecState { idle, recording, paused }

/// Coração do app: recebe o GPS, calcula estatísticas, salva cada ponto
/// no banco (à prova de travamentos) e faz os avisos por voz.
class Recorder extends ChangeNotifier {
  Recorder._();
  static final Recorder instance = Recorder._();

  /// Pontos com precisão pior que isso (metros) são ignorados.
  static const double maxAccuracy = 25;

  RecState state = RecState.idle;
  Track? track;
  Position? position;
  bool autoPaused = false;
  StatsAccumulator stats = StatsAccumulator();
  final List<List<LatLng>> segments = [];

  StreamSubscription<Position>? _sub;
  bool _recordingStream = false;
  Timer? _ticker;
  int _segment = 0;
  DateTime? _lastMovingAt;
  double _nextMarkMeters = 1000;
  Duration _nextTimeMark = const Duration(minutes: 15);
  final FlutterTts _tts = FlutterTts();
  bool _ttsReady = false;

  // Passos (sensor do celular) e reserva de distância quando o GPS falha.
  StreamSubscription<StepCount>? _stepSub;
  int _stepBase = -1;
  int _stepRaw = -1;
  int steps = 0;
  DateTime? _lastStepAt;
  DateTime? _lastFixAt;
  int _stepsAtStart = 0;

  /// Distância estimada pelos passos enquanto o GPS está sem sinal.
  double gapDistance = 0;

  /// Distância exibida: GPS + estimativa pelos passos durante falhas do GPS.
  double get distance => stats.distance + gapDistance;

  /// Comprimento médio da passada (m), calibrado pelo GPS.
  double get strideMeters {
    if (steps >= 200 && stats.distance > 150) {
      return (stats.distance / steps).clamp(0.4, 1.6);
    }
    return track?.activity == Activity.corrida ? 1.0 : 0.72;
  }

  /// Passos por minuto (cadência média em movimento).
  int get cadence =>
      stats.movingMs < 60000 ? 0 : (steps / (stats.movingMs / 60000)).round();

  /// Último sinal de movimento (GPS ou passos), usado na detecção de imobilidade.
  DateTime? get lastActivityAt {
    final a = _lastMovingAt, b = _lastStepAt;
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  void markActivity() => _lastMovingAt = DateTime.now();

  /// Fala uma mensagem (respeita a opção de voz).
  void speak(String text) => _say(text);

  bool get gpsLost =>
      state == RecState.recording &&
      (_lastFixAt == null ||
          DateTime.now().difference(_lastFixAt!) > const Duration(seconds: 20));

  void _onSteps(StepCount e) {
    if (_stepBase < 0) {
      _stepBase = e.steps;
      _stepRaw = e.steps;
      return;
    }
    final delta = e.steps - _stepRaw;
    _stepRaw = e.steps;
    if (delta <= 0) return;
    if (state != RecState.recording) {
      _stepBase += delta; // passos durante a pausa não contam
      return;
    }
    steps = _stepRaw - _stepBase;
    _lastStepAt = DateTime.now();
    autoPaused = false;
    if (gpsLost) gapDistance += delta * strideMeters;
    notifyListeners();
  }

  Future<void> _startSteps(Activity a) async {
    _stepBase = -1;
    _stepRaw = -1;
    steps = 0;
    _lastStepAt = null;
    if (a == Activity.bike) return;
    try {
      final st = await Permission.activityRecognition.request();
      if (!st.isGranted) return;
      _stepSub = Pedometer.stepCountStream.listen(_onSteps, onError: (Object _) {});
    } catch (_) {}
  }

  bool get active => state != RecState.idle;

  /// Trechos extras para o aviso por voz (ex.: comparação com o recorde).
  String? Function()? announceExtras;

  Duration get movingTime => Duration(milliseconds: stats.movingMs);

  Duration get elapsed => track == null
      ? Duration.zero
      : DateTime.now().difference(track!.startedAt);

  double? get pace => paceSecPerKm(stats.distance, stats.movingMs);

  double get avgSpeedMps => avgSpeed(stats.distance, stats.movingMs);

  // ---------- Permissões ----------

  /// Retorna null se está tudo certo, ou uma mensagem para o usuário.
  Future<String?> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Ative a localização (GPS) do celular.';
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      return 'A permissão de localização foi negada. Libere nas configurações do app.';
    }
    if (perm == LocationPermission.denied) {
      return 'O GAZMAP precisa da sua localização para gravar trilhas.';
    }
    return null;
  }

  // ---------- GPS ----------

  LocationSettings _settings({required bool recording}) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: recording ? 3 : 5,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: recording
            ? const ForegroundNotificationConfig(
                notificationTitle: 'GAZMAP está gravando',
                notificationText: 'Sua atividade continua sendo registrada.',
                notificationChannelName: 'Gravação de atividade',
                enableWakeLock: true,
                setOngoing: true,
              )
            : null,
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.best,
        activityType: ActivityType.fitness,
        distanceFilter: recording ? 3 : 5,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: recording,
        showBackgroundLocationIndicator: recording,
      );
    }
    return const LocationSettings(
        accuracy: LocationAccuracy.best, distanceFilter: 3);
  }

  void _listen({required bool recording}) {
    if (_sub != null && _recordingStream == recording) return;
    _sub?.cancel();
    _recordingStream = recording;
    _sub = Geolocator.getPositionStream(
            locationSettings: _settings(recording: recording))
        .listen(_onPosition, onError: (Object _) {});
  }

  /// Mostra a posição no mapa antes de começar a gravar.
  void startPreview() {
    if (state == RecState.idle) _listen(recording: false);
  }

  void stopPreview() {
    if (state == RecState.idle) {
      _sub?.cancel();
      _sub = null;
    }
  }

  void _onPosition(Position pos) {
    position = pos;
    if (state != RecState.recording || track == null) {
      notifyListeners();
      return;
    }
    if (pos.accuracy > maxAccuracy) {
      notifyListeners();
      return;
    }

    final point = TrackPoint(
      lat: pos.latitude,
      lon: pos.longitude,
      ele: pos.altitude,
      time: pos.timestamp,
      speed: pos.speed,
      accuracy: pos.accuracy,
      segment: _segment,
    );
    stats.add(point);
    _lastFixAt = DateTime.now();
    // O GPS voltou: o salto até o novo ponto já cobre o trecho estimado.
    gapDistance = 0;
    segments.last.add(LatLng(pos.latitude, pos.longitude));
    unawaited(AppDatabase.instance.insertPoint(track!.id!, point));

    // Pausa automática (só afeta a exibição; o tempo em movimento já
    // desconsidera os momentos parado).
    final now = DateTime.now();
    if (pos.speed >= track!.activity.movingSpeed) {
      _lastMovingAt = now;
      autoPaused = false;
    } else if (Settings.instance.autoPause &&
        _lastMovingAt != null &&
        now.difference(_lastMovingAt!) > const Duration(seconds: 10)) {
      autoPaused = true;
    }

    final s = Settings.instance;
    if (s.voiceMode == 'distance' && distance >= _nextMarkMeters) {
      _announce();
      final step = s.voiceKm * 1000;
      while (_nextMarkMeters <= distance) {
        _nextMarkMeters += step;
      }
    }
    notifyListeners();
  }

  // ---------- Controles ----------

  Future<void> start(Activity activity) async {
    if (active) return;
    final now = DateTime.now();
    final t = Track(
      name: '${activity.label} ${fmtDate(now)}',
      activity: activity,
      startedAt: now,
    );
    await AppDatabase.instance.insertTrack(t);
    track = t;
    stats = StatsAccumulator(movingSpeed: activity.movingSpeed);
    segments
      ..clear()
      ..add(<LatLng>[]);
    _segment = 0;
    _nextMarkMeters = Settings.instance.voiceKm * 1000;
    _nextTimeMark = Duration(minutes: Settings.instance.voiceMinutes);
    _lastMovingAt = now;
    _lastFixAt = null;
    gapDistance = 0;
    _stepsAtStart = 0;
    autoPaused = false;
    state = RecState.recording;
    _listen(recording: true);
    unawaited(_startSteps(activity));
    unawaited(SafetyService.instance.startPlan(activity.label));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!active) return;
      final s = Settings.instance;
      if (state == RecState.recording &&
          s.voiceMode == 'time' &&
          elapsed >= _nextTimeMark) {
        _announce();
        final step = Duration(minutes: s.voiceMinutes);
        while (_nextTimeMark <= elapsed) {
          _nextTimeMark += step;
        }
      }
      notifyListeners();
    });
    _say('Gravação iniciada.');
    notifyListeners();
  }

  void pause() {
    if (state != RecState.recording) return;
    state = RecState.paused;
    autoPaused = false;
    _say('Gravação pausada.');
    notifyListeners();
  }

  void resume() {
    if (state != RecState.paused) return;
    _segment++;
    segments.add(<LatLng>[]);
    _lastMovingAt = DateTime.now();
    state = RecState.recording;
    _say('Gravação retomada.');
    notifyListeners();
  }

  /// Finaliza e salva. Retorna a atividade salva.
  Future<Track?> finish({String? name}) async {
    final t = track;
    if (t == null) return null;
    _stopStreams();
    final now = DateTime.now();
    t
      ..applyStats(stats)
      ..distance = distance
      ..steps = steps - _stepsAtStart
      ..endedAt = now
      ..elapsedMs = now.difference(t.startedAt).inMilliseconds
      ..finished = true;
    if (name != null && name.trim().isNotEmpty) t.name = name.trim();
    await AppDatabase.instance.updateTrack(t);
    _say('Atividade salva. ${fmtKm(t.distance)} quilômetros.');
    unawaited(SafetyService.instance.finishPlan());
    GroupService.instance.announceFinish(t.distance, t.gain, t.steps, t.movingMs);
    _reset();
    return t;
  }

  Future<void> discard() async {
    final t = track;
    _stopStreams();
    if (t?.id != null) await AppDatabase.instance.deleteTrack(t!.id!);
    _reset();
  }

  void _stopStreams() {
    _ticker?.cancel();
    _ticker = null;
    _stepSub?.cancel();
    _stepSub = null;
    _sub?.cancel();
    _sub = null;
  }

  void _reset() {
    track = null;
    state = RecState.idle;
    autoPaused = false;
    segments.clear();
    stats = StatsAccumulator();
    steps = 0;
    gapDistance = 0;
    notifyListeners();
    startPreview();
  }

  /// Se o app foi fechado no meio de uma gravação, salva o que foi gravado.
  Future<void> recoverUnfinished() async {
    final db = AppDatabase.instance;
    for (final t in await db.unfinishedTracks()) {
      final pts = await db.points(t.id!);
      if (pts.length < 2) {
        await db.deleteTrack(t.id!);
        continue;
      }
      t
        ..applyStats(StatsAccumulator.compute(pts,
            movingSpeed: t.activity.movingSpeed))
        ..endedAt = pts.last.time
        ..elapsedMs = pts.last.time.difference(t.startedAt).inMilliseconds
        ..finished = true;
      await db.updateTrack(t);
    }
  }

  // ---------- Voz ----------

  Future<void> _say(String text) async {
    if (!Settings.instance.voice) return;
    try {
      if (!_ttsReady) {
        await _tts.setLanguage('pt-BR');
        await _tts.setSpeechRate(0.5);
        _ttsReady = true;
      }
      await _tts.speak(text);
    } catch (_) {
      // Sem motor de voz instalado: segue em silêncio.
    }
  }

  void _announce() {
    final s = Settings.instance;
    final buf = StringBuffer();
    if (s.sayDistance) {
      var km = (distance / 1000).toStringAsFixed(1).replaceAll('.', ',');
      if (km.endsWith(',0')) km = km.substring(0, km.length - 2);
      buf.write(km == '1' ? '1 quilômetro. ' : '$km quilômetros. ');
    }
    if (s.sayTime) {
      final t = movingTime;
      final h = t.inHours, m = t.inMinutes % 60;
      final parts = <String>[
        if (h > 0) h == 1 ? '1 hora' : '$h horas',
        if (m > 0 || h == 0) m == 1 ? '1 minuto' : '$m minutos',
      ];
      buf.write('Tempo, ${parts.join(' e ')}. ');
    }
    if (s.sayPace) {
      if (track!.activity.usesSpeed) {
        buf.write(
            'Velocidade média, ${(avgSpeedMps * 3.6).round()} quilômetros por hora. ');
      } else {
        final p = pace;
        if (p != null) {
          buf.write(
              'Ritmo, ${p ~/ 60} minutos e ${(p % 60).round()} segundos por quilômetro. ');
        }
      }
    }
    if (s.sayGain) {
      buf.write('Subida, ${stats.elevation.gain.round()} metros. ');
    }
    if (s.saySteps && steps > 0) {
      buf.write('$steps passos. ');
    }
    final extra = announceExtras?.call();
    if (extra != null && extra.isNotEmpty) buf.write('$extra ');
    final text = buf.toString().trim();
    if (text.isNotEmpty) _say(text);
  }
}
