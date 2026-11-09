import 'dart:math' as math;

double _rad(double d) => d * math.pi / 180;
double _deg(double r) => r * 180 / math.pi;
double _norm(double v, double max) => ((v % max) + max) % max;

/// Horário do pôr do sol (hora local do aparelho) para o dia e o local.
/// Algoritmo do Almanaque Náutico (precisão de ~1–2 min). Funciona offline.
/// Retorna null em latitudes/datas sem pôr do sol (dia ou noite polar).
DateTime? sunsetTime(DateTime day, double lat, double lon) {
  final start = DateTime.utc(day.year, 1, 1);
  final n = DateTime.utc(day.year, day.month, day.day).difference(start).inDays + 1;
  final lngHour = lon / 15;
  final t = n + ((18 - lngHour) / 24);
  final m = 0.9856 * t - 3.289;
  final l = _norm(
      m + 1.916 * math.sin(_rad(m)) + 0.020 * math.sin(_rad(2 * m)) + 282.634,
      360);
  var ra = _norm(_deg(math.atan(0.91764 * math.tan(_rad(l)))), 360);
  ra += (l ~/ 90) * 90 - (ra ~/ 90) * 90;
  ra /= 15;
  final sinDec = 0.39782 * math.sin(_rad(l));
  final cosDec = math.cos(math.asin(sinDec));
  final cosH = (math.cos(_rad(90.833)) - sinDec * math.sin(_rad(lat))) /
      (cosDec * math.cos(_rad(lat)));
  if (cosH > 1 || cosH < -1) return null;
  final h = _deg(math.acos(cosH)) / 15;
  final localT = h + ra - 0.06571 * t - 6.622;
  final ut = _norm(localT - lngHour, 24);
  final utc = DateTime.utc(day.year, day.month, day.day)
      .add(Duration(milliseconds: (ut * 3600000).round()));
  var local = utc.toLocal();
  // Garante que o resultado caia no mesmo dia local pedido.
  if (local.day != day.day) {
    local = local.add(Duration(days: local.isBefore(day) ? 1 : -1));
  }
  return local;
}
