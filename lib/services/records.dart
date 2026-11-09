import 'package:latlong2/latlong.dart';

import '../models/extra.dart';
import '../models/track.dart';
import 'database.dart';

/// Resultado da "Melhor Volta" para uma atividade.
class TrailRecord {
  TrailRecord({required this.attempts, required this.track});

  /// Todas as vezes nesta trilha (inclui a atual), do mais rápido ao mais lento.
  final List<Track> attempts;
  final Track track;

  int get times => attempts.length;
  Track get best => attempts.first;
  int get rank => attempts.indexWhere((t) => t.id == track.id) + 1;
  bool get isBest => rank == 1 && times > 1;
  int get averageMs =>
      attempts.fold<int>(0, (s, t) => s + t.movingMs) ~/ attempts.length;
  String get medal => switch (rank) { 1 => '🥇', 2 => '🥈', 3 => '🥉', _ => '' };

  /// Última vez antes desta.
  Track? get previous {
    final before = attempts.where((t) => t.startedAt.isBefore(track.startedAt)).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return before.isEmpty ? null : before.first;
  }
}

class SegmentEffort {
  SegmentEffort(this.track, this.ms);
  final Track track;
  final int ms;
}

/// Recordes pessoais 100% locais: só os seus dados, sem rankings entre pessoas.
class Records {
  Records._();

  static const _d = Distance();
  static double _m(LatLng a, LatLng b) => _d.as(LengthUnit.Meter, a, b);

  /// Encontra as outras vezes em que você fez a mesma trilha.
  static Future<TrailRecord?> forTrack(Track t) async {
    final db = AppDatabase.instance;
    final mine = await db.points(t.id!);
    if (mine.length < 10 || t.distance < 300) return null;
    final start = LatLng(mine.first.lat, mine.first.lon);
    final end = LatLng(mine.last.lat, mine.last.lon);
    final step = (mine.length / 15).ceil();
    final samples = [
      for (var i = 0; i < mine.length; i += step) LatLng(mine[i].lat, mine[i].lon)
    ];

    final same = <Track>[t];
    for (final c in await db.finishedTracks()) {
      if (c.id == t.id || c.activity != t.activity) continue;
      if ((c.distance - t.distance).abs() > t.distance * 0.2) continue;
      final pts = await db.points(c.id!);
      if (pts.length < 10) continue;
      if (_m(start, LatLng(pts.first.lat, pts.first.lon)) > 150) continue;
      if (_m(end, LatLng(pts.last.lat, pts.last.lon)) > 150) continue;
      final cStep = (pts.length / 400).ceil();
      final cand = [
        for (var i = 0; i < pts.length; i += cStep) LatLng(pts[i].lat, pts[i].lon)
      ];
      var hits = 0;
      for (final s in samples) {
        if (cand.any((p) => _m(s, p) < 80)) hits++;
      }
      if (hits >= samples.length * 0.8) same.add(c);
    }
    if (same.length < 2) return TrailRecord(attempts: same, track: t);
    same.sort((a, b) => a.movingMs.compareTo(b.movingMs));
    return TrailRecord(attempts: same, track: t);
  }

  /// Tempo gasto num trecho dentro de uma atividade (null se não passou por ele).
  static int? effortIn(List<TrackPoint> pts, FavoriteSegment s) {
    for (var i = 0; i < pts.length; i++) {
      if (_m(LatLng(pts[i].lat, pts[i].lon), s.start) > 40) continue;
      for (var j = i + 1; j < pts.length; j++) {
        if (_m(LatLng(pts[j].lat, pts[j].lon), s.end) <= 40) {
          return pts[j].time.difference(pts[i].time).inMilliseconds;
        }
      }
      return null;
    }
    return null;
  }

  /// Todas as passagens por um trecho, da mais rápida à mais lenta.
  static Future<List<SegmentEffort>> efforts(FavoriteSegment s) async {
    final db = AppDatabase.instance;
    final out = <SegmentEffort>[];
    for (final t in await db.finishedTracks()) {
      if (t.activity != s.activity) continue;
      final ms = effortIn(await db.points(t.id!), s);
      if (ms != null && ms > 0) out.add(SegmentEffort(t, ms));
    }
    out.sort((a, b) => a.ms.compareTo(b.ms));
    return out;
  }
}
