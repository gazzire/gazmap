import 'dart:math' as math;

const double _earthRadius = 6371000.0;

double _rad(double deg) => deg * math.pi / 180.0;

/// Distância em metros entre dois pontos (fórmula de haversine).
double haversine(double lat1, double lon1, double lat2, double lon2) {
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return 2 * _earthRadius * math.asin(math.min(1.0, math.sqrt(a)));
}

/// Conversões entre coordenadas e tiles (padrão "slippy map" XYZ).
class TileMath {
  static int lonToX(double lon, int z) {
    final n = 1 << z;
    return ((lon + 180.0) / 360.0 * n).floor().clamp(0, n - 1);
  }

  static int latToY(double lat, int z) {
    final n = 1 << z;
    final r = _rad(lat.clamp(-85.0511, 85.0511));
    final y = (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n;
    return y.floor().clamp(0, n - 1);
  }
}
