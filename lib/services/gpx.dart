import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/extra.dart';
import '../models/track.dart';
import 'database.dart';
import 'formats.dart';

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Gera GPX 1.1 (o formato mais compatível entre apps e relógios).
String buildGpx(Track t, List<TrackPoint> points) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<gpx version="1.1" creator="GAZMAP - POWERED BY GAZIRE" '
        'xmlns="http://www.topografix.com/GPX/1/1">')
    ..writeln('  <metadata><name>${_esc(t.name)}</name>'
        '<time>${t.startedAt.toUtc().toIso8601String()}</time></metadata>')
    ..writeln('  <trk>')
    ..writeln('    <name>${_esc(t.name)}</name>')
    ..writeln('    <type>${t.activity.name}</type>');

  int? segment;
  for (final pt in points) {
    if (pt.segment != segment) {
      if (segment != null) b.writeln('    </trkseg>');
      b.writeln('    <trkseg>');
      segment = pt.segment;
    }
    b.write('      <trkpt lat="${pt.lat.toStringAsFixed(7)}" '
        'lon="${pt.lon.toStringAsFixed(7)}">');
    if (pt.ele != null) b.write('<ele>${pt.ele!.toStringAsFixed(1)}</ele>');
    b.writeln('<time>${pt.time.toUtc().toIso8601String()}</time></trkpt>');
  }
  if (segment != null) b.writeln('    </trkseg>');
  b
    ..writeln('  </trk>')
    ..writeln('</gpx>');
  return b.toString();
}

Future<void> shareGpx(Track t, List<TrackPoint> points) async {
  final dir = await getTemporaryDirectory();
  final safe = t.name.replaceAll(RegExp(r'[^\w\-]+'), '_');
  final file = File(p.join(dir.path, '$safe.gpx'));
  await file.writeAsString(buildGpx(t, points));
  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'application/gpx+xml')],
    subject: t.name,
  );
}

// ---------- Importação ----------

class ParsedGpx {
  ParsedGpx(this.name, this.points, this.type);
  final String name;
  final List<(double lat, double lon, double? ele, DateTime? time)> points;
  final String type;

  bool get hasTimes => points.isNotEmpty && points.every((p) => p.$4 != null);
}

final _ptRe = RegExp(
    r'<(trkpt|rtept)\b([^>]*)>(.*?)</\1>|<(trkpt|rtept)\b([^>]*)/>',
    dotAll: true);
final _latRe = RegExp(r'''lat\s*=\s*["']([-0-9.eE+]+)["']''');
final _lonRe = RegExp(r'''lon\s*=\s*["']([-0-9.eE+]+)["']''');
final _eleRe = RegExp(r'<ele>\s*([-0-9.eE+]+)\s*</ele>');
final _timeRe = RegExp(r'<time>\s*([^<]+?)\s*</time>');
final _nameRe = RegExp(r'<name>\s*(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?\s*</name>', dotAll: true);
final _typeRe = RegExp(r'<type>\s*(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?\s*</type>', dotAll: true);
final _segRe = RegExp(r'<trkseg\b', dotAll: true);

String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&')
    .trim();

/// Lê um GPX (trilhas, rotas). Ignora o que não reconhece.
ParsedGpx? parseGpx(String xml, {String fallbackName = 'Rota importada'}) {
  if (!xml.contains('<gpx')) return null;
  final pts = <(double, double, double?, DateTime?)>[];
  for (final m in _ptRe.allMatches(xml)) {
    final attrs = m.group(2) ?? m.group(5) ?? '';
    final body = m.group(3) ?? '';
    final lat = double.tryParse(_latRe.firstMatch(attrs)?.group(1) ?? '');
    final lon = double.tryParse(_lonRe.firstMatch(attrs)?.group(1) ?? '');
    if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) continue;
    final ele = double.tryParse(_eleRe.firstMatch(body)?.group(1) ?? '');
    final time = DateTime.tryParse(_timeRe.firstMatch(body)?.group(1) ?? '');
    pts.add((lat, lon, ele, time));
  }
  if (pts.length < 2) return null;
  final nm = _nameRe.firstMatch(xml.substring(xml.indexOf('<gpx')));
  final name = nm == null ? fallbackName : _unescape(nm.group(1) ?? fallbackName);
  final type = _unescape(_typeRe.firstMatch(xml)?.group(1) ?? '').toLowerCase();
  return ParsedGpx(name.isEmpty ? fallbackName : name, pts, type);
}

/// Converte o tipo informado no arquivo em atividade do GAZMAP.
Activity activityFromGpxType(String type) {
  if (type.contains('cycl') || type.contains('bik') || type.contains('ride') || type == '1') {
    return Activity.bike;
  }
  if (type.contains('run') || type == '9') return Activity.corrida;
  if (type.contains('walk') || type.contains('caminh')) return Activity.caminhada;
  return Activity.trilha;
}

int countSegments(String xml) => _segRe.allMatches(xml).length;

/// Importa arquivos GPX como rotas para navegação. Retorna quantas entraram.
Future<int> importRoutes(List<(String, Uint8List)> files) async {
  var n = 0;
  for (final (name, bytes) in files) {
    final g = parseAny(name, bytes);
    if (g == null) continue;
    await AppDatabase.instance.insertRoute(SavedRoute(
      name: g.name,
      points: [for (final p in g.points) RoutePoint(p.$1, p.$2, p.$3)],
      createdAt: DateTime.now(),
    ));
    n++;
  }
  return n;
}

/// Importa atividades com horário (ex.: exportadas de outros apps) para o histórico.
Future<int> importActivities(List<(String, Uint8List)> files) async {
  var n = 0;
  final db = AppDatabase.instance;
  for (final (name, bytes) in files) {
    final g = parseAny(name, bytes);
    if (g == null || !g.hasTimes) continue;
    final act = activityFromGpxType(g.type);
    final start = g.points.first.$4!.toLocal();
    final t = Track(name: g.name, activity: act, startedAt: start);
    await db.insertTrack(t);
    final pts = <TrackPoint>[];
    for (final p in g.points) {
      final tp = TrackPoint(lat: p.$1, lon: p.$2, ele: p.$3, time: p.$4!.toLocal());
      pts.add(tp);
    }
    await db.insertPoints(t.id!, pts);
    final end = pts.last.time;
    t
      ..applyStats(StatsAccumulator.compute(pts, movingSpeed: act.movingSpeed))
      ..endedAt = end
      ..elapsedMs = end.difference(start).inMilliseconds
      ..finished = true;
    await db.updateTrack(t);
    n++;
  }
  return n;
}
