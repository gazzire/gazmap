String _two(int n) => n.toString().padLeft(2, '0');

/// "2,45" (km, vírgula decimal).
String fmtKm(double meters) =>
    (meters / 1000).toStringAsFixed(2).replaceAll('.', ',');

String fmtDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  return h > 0 ? '$h:${_two(m)}:${_two(s)}' : '${_two(m)}:${_two(s)}';
}

/// Ritmo em min/km, ex.: 12'05".
String fmtPace(double? secPerKm) {
  if (secPerKm == null ||
      !secPerKm.isFinite ||
      secPerKm <= 0 ||
      secPerKm > 3600) {
    return '--';
  }
  var m = secPerKm ~/ 60;
  var s = (secPerKm % 60).round();
  if (s == 60) {
    m += 1;
    s = 0;
  }
  return "$m'${_two(s)}\"";
}

/// Velocidade em km/h, ex.: 18,4.
String fmtSpeed(double metersPerSecond) {
  if (!metersPerSecond.isFinite || metersPerSecond < 0) return '--';
  return (metersPerSecond * 3.6).toStringAsFixed(1).replaceAll('.', ',');
}

String fmtDate(DateTime d) =>
    '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';

String fmtBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2).replaceAll('.', ',')} GB';
}

/// Ritmo (s/km) a partir de distância e tempo em movimento.
double? paceSecPerKm(double meters, int movingMs) {
  if (meters < 50 || movingMs <= 0) return null;
  return (movingMs / 1000) / (meters / 1000);
}

/// Velocidade média (m/s).
double avgSpeed(double meters, int movingMs) =>
    movingMs <= 0 ? 0 : meters / (movingMs / 1000);
