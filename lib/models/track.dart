import 'package:flutter/material.dart';

import '../utils/geo.dart';

/// Tipo de atividade. Define ícone, limiar de movimento e unidade principal.
enum Activity {
  trilha('Trilha', Icons.terrain, 0.35),
  caminhada('Caminhada', Icons.directions_walk, 0.35),
  corrida('Corrida', Icons.directions_run, 0.8),
  bike('Bike', Icons.directions_bike, 1.2);

  const Activity(this.label, this.icon, this.movingSpeed);

  final String label;
  final IconData icon;

  /// Velocidade mínima (m/s) para considerar que está em movimento.
  final double movingSpeed;

  /// Bike mostra velocidade (km/h); as demais mostram ritmo (min/km).
  bool get usesSpeed => this == Activity.bike;

  static Activity fromName(String? name) => Activity.values
      .firstWhere((a) => a.name == name, orElse: () => Activity.trilha);
}

class TrackPoint {
  const TrackPoint({
    required this.lat,
    required this.lon,
    required this.time,
    this.ele,
    this.speed,
    this.accuracy,
    this.segment = 0,
  });

  final double lat;
  final double lon;
  final double? ele;
  final DateTime time;
  final double? speed;
  final double? accuracy;

  /// Trechos separados por pausas manuais.
  final int segment;

  Map<String, Object?> toMap(int trackId) => {
        'track_id': trackId,
        'lat': lat,
        'lon': lon,
        'ele': ele,
        'time': time.millisecondsSinceEpoch,
        'speed': speed,
        'acc': accuracy,
        'segment': segment,
      };

  factory TrackPoint.fromMap(Map<String, Object?> m) => TrackPoint(
        lat: (m['lat'] as num).toDouble(),
        lon: (m['lon'] as num).toDouble(),
        ele: (m['ele'] as num?)?.toDouble(),
        time: DateTime.fromMillisecondsSinceEpoch(m['time'] as int),
        speed: (m['speed'] as num?)?.toDouble(),
        accuracy: (m['acc'] as num?)?.toDouble(),
        segment: (m['segment'] as int?) ?? 0,
      );
}

class Track {
  Track({
    this.id,
    required this.name,
    required this.activity,
    required this.startedAt,
    this.endedAt,
    this.distance = 0,
    this.movingMs = 0,
    this.elapsedMs = 0,
    this.gain = 0,
    this.loss = 0,
    this.maxSpeed = 0,
    this.finished = false,
    this.steps = 0,
  });

  int? id;
  String name;
  Activity activity;
  DateTime startedAt;
  DateTime? endedAt;
  double distance;
  int movingMs;
  int elapsedMs;
  double gain;
  double loss;
  double maxSpeed;
  bool finished;

  /// Passos contados pelo sensor do celular (0 em Bike).
  int steps;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'activity': activity.name,
        'started_at': startedAt.millisecondsSinceEpoch,
        'ended_at': endedAt?.millisecondsSinceEpoch,
        'distance': distance,
        'moving_ms': movingMs,
        'elapsed_ms': elapsedMs,
        'gain': gain,
        'loss': loss,
        'max_speed': maxSpeed,
        'finished': finished ? 1 : 0,
        'steps': steps,
      };

  factory Track.fromMap(Map<String, Object?> m) => Track(
        id: m['id'] as int?,
        name: m['name'] as String,
        activity: Activity.fromName(m['activity'] as String?),
        startedAt: DateTime.fromMillisecondsSinceEpoch(m['started_at'] as int),
        endedAt: m['ended_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['ended_at'] as int),
        distance: (m['distance'] as num).toDouble(),
        movingMs: m['moving_ms'] as int,
        elapsedMs: m['elapsed_ms'] as int,
        gain: (m['gain'] as num).toDouble(),
        loss: (m['loss'] as num).toDouble(),
        maxSpeed: (m['max_speed'] as num).toDouble(),
        finished: (m['finished'] as int) == 1,
        steps: (m['steps'] as int?) ?? 0,
      );

  void applyStats(StatsAccumulator s) {
    distance = s.distance;
    movingMs = s.movingMs;
    gain = s.elevation.gain;
    loss = s.elevation.loss;
    maxSpeed = s.maxSpeed;
  }
}

/// Soma subida/descida ignorando o "ruído" da altitude do GPS (histerese).
class ElevationAccumulator {
  ElevationAccumulator({this.threshold = 4.0});

  final double threshold;
  double? _ref;
  double gain = 0;
  double loss = 0;

  void add(double? ele) {
    if (ele == null || ele == 0) return;
    final ref = _ref;
    if (ref == null) {
      _ref = ele;
      return;
    }
    final d = ele - ref;
    if (d >= threshold) {
      gain += d;
      _ref = ele;
    } else if (d <= -threshold) {
      loss -= d;
      _ref = ele;
    }
  }
}

/// Calcula estatísticas ponto a ponto. Usado ao vivo e ao reprocessar.
class StatsAccumulator {
  StatsAccumulator({this.movingSpeed = 0.35});

  final double movingSpeed;
  static const int maxGapMs = 30000;
  static const double maxPlausibleSpeed = 70; // m/s (~250 km/h)

  double distance = 0;
  int movingMs = 0;
  double maxSpeed = 0;
  final ElevationAccumulator elevation = ElevationAccumulator();

  /// Perfil de altimetria: (distância acumulada em m, altitude em m).
  final List<(double, double)> profile = [];

  TrackPoint? _last;

  void add(TrackPoint p) {
    final last = _last;
    if (last != null && last.segment == p.segment) {
      final d = haversine(last.lat, last.lon, p.lat, p.lon);
      final dtMs = p.time.difference(last.time).inMilliseconds;
      if (dtMs > 0) {
        final v = d / (dtMs / 1000);
        if (v > maxPlausibleSpeed) return; // salto de GPS: descarta
        distance += d;
        if (v >= movingSpeed && dtMs <= maxGapMs) movingMs += dtMs;
        final s = (p.speed != null && p.speed! > 0) ? p.speed! : v;
        if (s > maxSpeed && s < maxPlausibleSpeed) maxSpeed = s;
      }
    }
    elevation.add(p.ele);
    if (p.ele != null && p.ele != 0) profile.add((distance, p.ele!));
    _last = p;
  }

  static StatsAccumulator compute(List<TrackPoint> points,
      {double movingSpeed = 0.35}) {
    final s = StatsAccumulator(movingSpeed: movingSpeed);
    for (final p in points) {
      s.add(p);
    }
    return s;
  }
}
