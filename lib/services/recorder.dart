import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/track.dart';
import '../utils/format.dart';
import 'database.dart';
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

  bool get active => state != RecState.idle;

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
    if (s.voiceMode == 'distance' && stats.distance >= _nextMarkMeters) {
      _announce();
      final step = s.voiceKm * 1000;
      while (_nextMarkMeters <= stats.distance) {
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
    autoPaused = false;
    state = RecState.recording;
    _listen(recording: true);
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
      ..endedAt = now
      ..elapsedMs = now.difference(t.startedAt).inMilliseconds
      ..finished = true;
    if (name != null && name.trim().isNotEmpty) t.name = name.trim();
    await AppDatabase.instance.updateTrack(t);
    _say('Atividade salva. ${fmtKm(stats.distance)} quilômetros.');
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
    _sub?.cancel();
    _sub = null;
  }

  void _reset() {
    track = null;
    state = RecState.idle;
    autoPaused = false;
    segments.clear();
    stats = StatsAccumulator();
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
      var km = (stats.distance / 1000).toStringAsFixed(1).replaceAll('.', ',');
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
    final text = buf.toString().trim();
    if (text.isNotEmpty) _say(text);
  }
}
