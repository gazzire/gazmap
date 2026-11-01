import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/track.dart';

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Gera GPX 1.1 (compatível com Strava, Wikiloc, Komoot, Garmin...).
String buildGpx(Track t, List<TrackPoint> points) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<gpx version="1.1" creator="Rastro" '
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
