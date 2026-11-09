import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import 'recorder.dart';

/// Direção para onde você está virado (graus a partir do norte verdadeiro).
/// Parado ou devagar: bússola do celular. Em movimento: direção do GPS,
/// que é mais estável (igual aos apps de navegação de carro).
class HeadingService extends ChangeNotifier {
  HeadingService._() {
    Recorder.instance.addListener(_onPosition);
  }
  static final HeadingService instance = HeadingService._();

  static const _events = EventChannel('gazmap/heading');
  static const _native = MethodChannel('gazmap/native');

  StreamSubscription<dynamic>? _sub;
  int _users = 0;

  double? _compass; // norte verdadeiro, suavizado
  double _declination = 0;
  LatLng? _declinationAt;

  /// Direção final usada pela seta e pelo mapa (null = desconhecida).
  double? heading;

  /// true quando a direção vem do GPS (em movimento).
  bool fromGps = false;

  /// false quando o celular não tem bússola (só GPS em movimento).
  bool hasCompass = true;

  void attach() {
    if (_users++ > 0) return;
    _sub = _events.receiveBroadcastStream().listen((e) {
      if (e is num) _onCompass(e.toDouble());
    }, onError: (Object _) {
      hasCompass = false;
      notifyListeners();
    });
  }

  void detach() {
    _users = math.max(0, _users - 1);
    if (_users == 0) {
      _sub?.cancel();
      _sub = null;
    }
  }

  void _onCompass(double magnetic) {
    final trueNorth = (magnetic + _declination) % 360;
    final c = _compass;
    _compass = c == null ? trueNorth : _blend(c, trueNorth, 0.25);
    _update();
  }

  void _onPosition() {
    final p = Recorder.instance.position;
    if (p == null) return;
    final here = LatLng(p.latitude, p.longitude);
    final at = _declinationAt;
    if (at == null || const Distance().as(LengthUnit.Kilometer, at, here) > 50) {
      _declinationAt = here;
      _native.invokeMethod<double>('declination', {
        'lat': p.latitude,
        'lon': p.longitude,
        'alt': p.altitude,
      }).then((d) => _declination = d ?? 0, onError: (Object _) {});
    }
    _update();
  }

  void _update() {
    final p = Recorder.instance.position;
    double? h;
    var gps = false;
    if (p != null && p.speed > 0.8 && p.heading > 0) {
      h = p.heading % 360;
      gps = true;
    } else {
      h = _compass;
    }
    if (h == null) return;
    final old = heading;
    if (old != null && _diff(old, h) < 1 && gps == fromGps) return;
    heading = h;
    fromGps = gps;
    notifyListeners();
  }

  /// Interpolação circular (evita o "pulo" entre 359° e 0°).
  static double _blend(double a, double b, double t) {
    final d = ((b - a + 540) % 360) - 180;
    return (a + d * t + 360) % 360;
  }

  static double _diff(double a, double b) {
    final d = (a - b).abs() % 360;
    return d > 180 ? 360 - d : d;
  }
}
