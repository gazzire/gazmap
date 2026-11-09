import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/extra.dart';
import '../models/track.dart';
import '../utils/format.dart';
import 'native.dart';
import 'recorder.dart';
import 'settings.dart';

/// Navegação por rota (GPX ou trilha gravada), "voltar por onde vim"
/// e corrida contra o próprio recorde (fantasma). Funciona offline.
class RouteNavigator extends ChangeNotifier {
  RouteNavigator._() {
    Recorder.instance.addListener(_onRecorder);
    Recorder.instance.announceExtras = voiceText;
  }
  static final RouteNavigator instance = RouteNavigator._();

  /// Rota escolhida antes de iniciar a gravação.
  SavedRoute? pendingRoute;

  /// Recorde escolhido antes de iniciar ("repetir contra o recorde").
  Track? pendingGhost;
  List<TrackPoint>? pendingGhostPoints;

  SavedRoute? route;
  List<LatLng> points = [];
  List<double> _cum = [];
  List<double> _cumGain = [];
  double _totalGain = 0;

  bool backtracking = false;
  int _idx = 0;
  double distToRoute = 0;
  bool offRoute = false;
  int _offCount = 0;
  double remaining = 0;
  double remainingGain = 0;
  Duration? eta;
  double progress = 0; // metros percorridos ao longo da rota

  // Fantasma
  Track? ghost;
  List<double> _gDist = [];
  List<int> _gMs = [];
  List<LatLng> _gPts = [];
  LatLng? ghostPosition;
  int? ghostDeltaSec; // positivo = atrás do recorde

  DateTime? _lastFix;

  bool get active => route != null;

  /// Atualiza as telas após mudar as escolhas pendentes.
  void refresh() => notifyListeners();

  // ---------- Início / fim ----------

  void startPending() {
    final r = pendingRoute;
    final g = pendingGhost;
    final gp = pendingGhostPoints;
    pendingRoute = null;
    pendingGhost = null;
    pendingGhostPoints = null;
    if (g != null && gp != null && gp.length > 1) {
      _setGhost(g, gp);
      start(SavedRoute.fromTrack(g, gp));
    } else if (r != null) {
      start(r);
    }
  }

  void start(SavedRoute r, {bool isBacktrack = false}) {
    if (r.points.length < 2) return;
    route = r;
    backtracking = isBacktrack;
    points = r.points.map((p) => p.latLng).toList();
    _cum = [0];
    _cumGain = [0];
    final e = ElevationAccumulator();
    for (var i = 1; i < r.points.length; i++) {
      _cum.add(_cum.last + _d(points[i - 1], points[i]));
      e.add(r.points[i].ele);
      _cumGain.add(e.gain);
    }
    _totalGain = e.gain;
    _idx = 0;
    _offCount = 0;
    offRoute = false;
    remaining = _cum.last;
    remainingGain = _totalGain;
    notifyListeners();
  }

  /// Guia de volta pelo caminho já gravado nesta atividade.
  void startBacktrack() {
    final rec = Recorder.instance;
    final all = rec.segments.expand((s) => s).toList().reversed.toList();
    if (all.length < 2) return;
    start(
      SavedRoute(
        name: 'Voltar por onde vim',
        points: all.map((p) => RoutePoint(p.latitude, p.longitude)).toList(),
        createdAt: DateTime.now(),
        source: 'backtrack',
      ),
      isBacktrack: true,
    );
    rec.speak('Guiando de volta pelo caminho que você fez.');
  }

  void stop() {
    route = null;
    points = [];
    ghost = null;
    ghostPosition = null;
    ghostDeltaSec = null;
    backtracking = false;
    eta = null;
    notifyListeners();
  }

  void _setGhost(Track t, List<TrackPoint> pts) {
    ghost = t;
    _gDist = [0];
    _gMs = [0];
    _gPts = pts.map((p) => LatLng(p.lat, p.lon)).toList();
    final acc = StatsAccumulator(movingSpeed: t.activity.movingSpeed);
    for (final p in pts) {
      acc.add(p);
      _gDist.add(acc.distance);
      _gMs.add(acc.movingMs);
    }
    _gDist.removeAt(0);
    _gMs.removeAt(0);
  }

  // ---------- Atualização a cada posição ----------

  void _onRecorder() {
    final rec = Recorder.instance;
    if (!rec.active) {
      if (route != null) stop();
      return;
    }
    final pos = rec.position;
    if (route == null || pos == null || pos.timestamp == _lastFix) return;
    if (rec.state != RecState.recording) return;
    _lastFix = pos.timestamp;
    _update(LatLng(pos.latitude, pos.longitude));
  }

  void _update(LatLng me) {
    final n = points.length;
    final from = math.max(0, _idx - 40);
    final to = _offCount > 5 ? n - 1 : math.min(n - 1, _idx + 400);
    var best = double.infinity;
    var bestI = _idx;
    var bestT = 0.0;
    for (var i = from; i < to; i++) {
      final (d, t) = _segDist(me, points[i], points[i + 1]);
      if (d < best) {
        best = d;
        bestI = i;
        bestT = t;
      }
    }
    _idx = bestI;
    distToRoute = best;
    progress = _cum[bestI] + bestT * (_cum[bestI + 1] - _cum[bestI]);
    remaining = math.max(0, _cum.last - progress);
    remainingGain = math.max(0, _totalGain - _cumGain[bestI]);
    final v = Recorder.instance.avgSpeedMps;
    eta = v > 0.3 ? Duration(seconds: (remaining / v).round()) : null;

    final limit = Settings.instance.offRouteMeters.toDouble();
    if (best > limit) {
      _offCount++;
      if (_offCount == 3 && !offRoute) {
        offRoute = true;
        NativeBridge.vibrate([0, 500, 200, 500, 200, 500]);
        Recorder.instance.speak('Atenção: você saiu da rota. Está a ${best.round()} metros dela.');
      }
    } else {
      if (offRoute) Recorder.instance.speak('De volta à rota.');
      _offCount = 0;
      offRoute = false;
    }

    if (remaining < 30 && route != null) {
      Recorder.instance.speak(backtracking ? 'Você chegou ao ponto de partida.' : 'Você chegou ao fim da rota.');
      route = null; // evita repetir o aviso
    }

    _updateGhost();
    notifyListeners();
  }

  void _updateGhost() {
    if (ghost == null || _gDist.isEmpty) return;
    final myMs = Recorder.instance.stats.movingMs;
    // Tempo que o recorde levou para chegar onde estou agora.
    final tAtMyDist = _interp(_gDist, _gMs.map((e) => e.toDouble()).toList(), progress);
    ghostDeltaSec = ((myMs - tAtMyDist) / 1000).round();
    // Onde o recorde estava neste mesmo tempo.
    final i = _lowerBound(_gMs, myMs).clamp(0, _gPts.length - 1);
    ghostPosition = _gPts[i];
  }

  // ---------- Voz ----------

  String? voiceText() {
    final parts = <String>[];
    if (route != null) {
      parts.add('Faltam ${fmtKm(remaining).replaceAll(',', ' vírgula ')} quilômetros.');
    }
    final g = ghostDeltaSec;
    if (g != null && Settings.instance.sayGhost) {
      final m = g.abs() ~/ 60, s = g.abs() % 60;
      final t = m > 0 ? '$m minutos e $s segundos' : '$s segundos';
      parts.add(g > 0 ? '$t atrás do seu recorde.' : '$t à frente do seu recorde.');
    }
    return parts.isEmpty ? null : parts.join(' ');
  }

  // ---------- Geometria ----------

  static double _d(LatLng a, LatLng b) =>
      const Distance().as(LengthUnit.Meter, a, b);

  /// Distância (m) do ponto ao segmento AB e posição relativa (0..1).
  static (double, double) _segDist(LatLng p, LatLng a, LatLng b) {
    const r = 6371000.0;
    final lat0 = a.latitude * math.pi / 180;
    double x(LatLng q) => q.longitude * math.pi / 180 * math.cos(lat0) * r;
    double y(LatLng q) => q.latitude * math.pi / 180 * r;
    final ax = x(a), ay = y(a), bx = x(b), by = y(b), px = x(p), py = y(p);
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    var t = len2 == 0 ? 0.0 : ((px - ax) * dx + (py - ay) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    final cx = ax + t * dx, cy = ay + t * dy;
    return (math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy)), t);
  }

  static double _interp(List<double> xs, List<double> ys, double x) {
    if (xs.isEmpty) return 0;
    if (x <= xs.first) return ys.first;
    if (x >= xs.last) return ys.last;
    var lo = 0, hi = xs.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (xs[mid] <= x) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final span = xs[hi] - xs[lo];
    final f = span == 0 ? 0.0 : (x - xs[lo]) / span;
    return ys[lo] + f * (ys[hi] - ys[lo]);
  }

  static int _lowerBound(List<int> xs, int v) {
    var lo = 0, hi = xs.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (xs[mid] < v) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}
