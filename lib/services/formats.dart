import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/extra.dart';
import '../models/track.dart';
import 'gpx.dart';

/// Formatos padrão de atividades e rotas, aceitos pela maioria dos apps e relógios.
enum FileFormat {
  gpx('GPX', 'gpx', 'application/gpx+xml'),
  tcx('TCX', 'tcx', 'application/vnd.garmin.tcx+xml'),
  fit('FIT', 'fit', 'application/vnd.ant.fit');

  const FileFormat(this.label, this.ext, this.mime);
  final String label;
  final String ext;
  final String mime;
}

// ======================================================================
// Leitura (detecta o formato pelo conteúdo; aceita arquivos .gz exportados de outros apps)
// ======================================================================

ParsedGpx? parseAny(String fileName, Uint8List bytes) {
  var name = fileName;
  var data = bytes;
  if (data.length > 2 && data[0] == 0x1f && data[1] == 0x8b) {
    try {
      data = Uint8List.fromList(gzip.decode(data));
      name = name.replaceAll(RegExp(r'\.gz$', caseSensitive: false), '');
    } catch (_) {
      return null;
    }
  }
  final base = p.basenameWithoutExtension(name);
  if (data.length > 12 &&
      data[8] == 0x2E && data[9] == 0x46 && data[10] == 0x49 && data[11] == 0x54) {
    return parseFit(data, fallbackName: base);
  }
  final text = utf8.decode(data, allowMalformed: true);
  if (text.contains('<TrainingCenterDatabase')) return parseTcx(text, fallbackName: base);
  if (text.contains('<gpx')) return parseGpx(text, fallbackName: base);
  return null;
}

// ---------- TCX ----------

final _tcxPt = RegExp(r'<Trackpoint>(.*?)</Trackpoint>', dotAll: true);
final _tcxLat = RegExp(r'<LatitudeDegrees>\s*([-0-9.eE+]+)\s*</LatitudeDegrees>');
final _tcxLon = RegExp(r'<LongitudeDegrees>\s*([-0-9.eE+]+)\s*</LongitudeDegrees>');
final _tcxAlt = RegExp(r'<AltitudeMeters>\s*([-0-9.eE+]+)\s*</AltitudeMeters>');
final _tcxTime = RegExp(r'<Time>\s*([^<]+?)\s*</Time>');
final _tcxSport = RegExp(r'''<Activity\s+Sport\s*=\s*["']([^"']+)["']''');
final _tcxName = RegExp(r'<(?:Name|Notes)>\s*(.*?)\s*</(?:Name|Notes)>', dotAll: true);

ParsedGpx? parseTcx(String xml, {String fallbackName = 'Importado'}) {
  final pts = <(double, double, double?, DateTime?)>[];
  for (final m in _tcxPt.allMatches(xml)) {
    final b = m.group(1)!;
    final lat = double.tryParse(_tcxLat.firstMatch(b)?.group(1) ?? '');
    final lon = double.tryParse(_tcxLon.firstMatch(b)?.group(1) ?? '');
    if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) continue;
    pts.add((
      lat,
      lon,
      double.tryParse(_tcxAlt.firstMatch(b)?.group(1) ?? ''),
      DateTime.tryParse(_tcxTime.firstMatch(b)?.group(1) ?? ''),
    ));
  }
  if (pts.length < 2) return null;
  final sport = (_tcxSport.firstMatch(xml)?.group(1) ?? '').toLowerCase();
  final name = _tcxName.firstMatch(xml)?.group(1)?.trim();
  return ParsedGpx(
      (name == null || name.isEmpty || name.length > 80) ? fallbackName : name, pts, sport);
}

// ---------- FIT (formato binário de relógios e ciclocomputadores) ----------

const _fitEpoch = 631065600; // 1989-12-31T00:00:00Z em segundos Unix
const _semi = 2147483648.0 / 180.0;

class _FitField {
  _FitField(this.num, this.size, this.baseType);
  final int num;
  final int size;
  final int baseType;
}

class _FitDef {
  _FitDef(this.global, this.bigEndian, this.fields, this.devSize);
  final int global;
  final bool bigEndian;
  final List<_FitField> fields;
  final int devSize;
}

int _readUint(Uint8List b, int o, int size, bool be) {
  var v = 0;
  for (var i = 0; i < size; i++) {
    final byte = b[o + (be ? i : size - 1 - i)];
    v = (v << 8) | byte;
  }
  return v;
}

int _toSigned(int v, int size) {
  final bits = size * 8;
  final max = 1 << (bits - 1);
  return v >= max ? v - (1 << bits) : v;
}

ParsedGpx? parseFit(Uint8List b, {String fallbackName = 'Importado'}) {
  try {
    final headerSize = b[0];
    final dataSize = _readUint(b, 4, 4, false);
    var o = headerSize;
    final end = (headerSize + dataSize).clamp(0, b.length);
    final defs = <int, _FitDef>{};
    final pts = <(double, double, double?, DateTime?)>[];
    var lastTs = 0;
    var sport = '';

    while (o < end) {
      final h = b[o++];
      int local;
      int? compressedTs;
      if (h & 0x80 != 0) {
        local = (h >> 5) & 0x03;
        final offset = h & 0x1F;
        var ts = (lastTs & ~0x1F) + offset;
        if (offset < (lastTs & 0x1F)) ts += 0x20;
        compressedTs = ts;
        lastTs = ts;
      } else if (h & 0x40 != 0) {
        local = h & 0x0F;
        final hasDev = h & 0x20 != 0;
        final be = b[o + 1] == 1;
        final global = _readUint(b, o + 2, 2, be);
        final n = b[o + 4];
        o += 5;
        final fields = <_FitField>[];
        for (var i = 0; i < n; i++) {
          fields.add(_FitField(b[o], b[o + 1], b[o + 2]));
          o += 3;
        }
        var dev = 0;
        if (hasDev) {
          final nd = b[o++];
          for (var i = 0; i < nd; i++) {
            dev += b[o + 1];
            o += 3;
          }
        }
        defs[local] = _FitDef(global, be, fields, dev);
        continue;
      } else {
        local = h & 0x0F;
      }

      final def = defs[local];
      if (def == null) return null;
      int? ts = compressedTs;
      int? lat, lon, alt, ealt, sportVal;
      for (final f in def.fields) {
        final raw = f.size <= 4 ? _readUint(b, o, f.size, def.bigEndian) : null;
        if (raw != null) {
          if (f.num == 253 && f.size == 4) {
            ts = raw;
            lastTs = raw;
          } else if (def.global == 20) {
            if (f.num == 0 && f.size == 4 && raw != 0x7FFFFFFF) lat = _toSigned(raw, 4);
            if (f.num == 1 && f.size == 4 && raw != 0x7FFFFFFF) lon = _toSigned(raw, 4);
            if (f.num == 2 && f.size == 2 && raw != 0xFFFF) alt = raw;
            if (f.num == 78 && f.size == 4 && raw != 0xFFFFFFFF) ealt = raw;
          } else if ((def.global == 18 && f.num == 5) || (def.global == 12 && f.num == 0)) {
            if (f.size == 1 && raw != 0xFF) sportVal = raw;
          }
        }
        o += f.size;
      }
      o += def.devSize;
      if (sportVal != null && sport.isEmpty) {
        sport = switch (sportVal) { 1 => 'running', 2 => 'cycling', 11 => 'walking', _ => 'hiking' };
      }
      if (def.global == 20 && lat != null && lon != null) {
        final altitude = ealt != null ? ealt / 5 - 500 : (alt != null ? alt / 5 - 500 : null);
        pts.add((
          lat / _semi,
          lon / _semi,
          altitude,
          ts == null ? null : DateTime.fromMillisecondsSinceEpoch((ts + _fitEpoch) * 1000, isUtc: true),
        ));
      }
    }
    if (pts.length < 2) return null;
    return ParsedGpx(fallbackName, pts, sport);
  } catch (_) {
    return null;
  }
}

// ======================================================================
// Escrita
// ======================================================================

String _iso(DateTime t) => t.toUtc().toIso8601String();
String _x(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _tcxSportOf(Activity a) => switch (a) {
      Activity.corrida => 'Running',
      Activity.bike => 'Biking',
      _ => 'Other',
    };

/// TCX de atividade (com horários).
String buildTcx(Track t, List<TrackPoint> pts) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">')
    ..writeln('  <Activities>')
    ..writeln('    <Activity Sport="${_tcxSportOf(t.activity)}">')
    ..writeln('      <Id>${_iso(t.startedAt)}</Id>')
    ..writeln('      <Lap StartTime="${_iso(t.startedAt)}">')
    ..writeln('        <TotalTimeSeconds>${(t.movingMs / 1000).toStringAsFixed(0)}</TotalTimeSeconds>')
    ..writeln('        <DistanceMeters>${t.distance.toStringAsFixed(1)}</DistanceMeters>')
    ..writeln('        <Calories>0</Calories>')
    ..writeln('        <Intensity>Active</Intensity>')
    ..writeln('        <TriggerMethod>Manual</TriggerMethod>')
    ..writeln('        <Track>');
  final acc = StatsAccumulator(movingSpeed: t.activity.movingSpeed);
  for (final p in pts) {
    acc.add(p);
    b
      ..write('          <Trackpoint><Time>${_iso(p.time)}</Time>')
      ..write('<Position><LatitudeDegrees>${p.lat.toStringAsFixed(7)}</LatitudeDegrees>')
      ..write('<LongitudeDegrees>${p.lon.toStringAsFixed(7)}</LongitudeDegrees></Position>');
    if (p.ele != null) b.write('<AltitudeMeters>${p.ele!.toStringAsFixed(1)}</AltitudeMeters>');
    b.writeln('<DistanceMeters>${acc.distance.toStringAsFixed(1)}</DistanceMeters></Trackpoint>');
  }
  b
    ..writeln('        </Track>')
    ..writeln('      </Lap>')
    ..writeln('      <Notes>${_x(t.name)} · POWERED BY GAZIRE</Notes>')
    ..writeln('    </Activity>')
    ..writeln('  </Activities>')
    ..writeln('</TrainingCenterDatabase>');
  return b.toString();
}

/// TCX de rota (Course), para importar em relógios e apps como trajeto a seguir.
String buildTcxCourse(SavedRoute r) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">')
    ..writeln('  <Courses>')
    ..writeln('    <Course>')
    ..writeln('      <Name>${_x(r.name.length > 15 ? r.name.substring(0, 15) : r.name)}</Name>')
    ..writeln('      <Track>');
  for (final p in r.points) {
    b.write('        <Trackpoint><Position><LatitudeDegrees>${p.lat.toStringAsFixed(7)}</LatitudeDegrees>'
        '<LongitudeDegrees>${p.lon.toStringAsFixed(7)}</LongitudeDegrees></Position>');
    if (p.ele != null) b.write('<AltitudeMeters>${p.ele!.toStringAsFixed(1)}</AltitudeMeters>');
    b.writeln('</Trackpoint>');
  }
  b
    ..writeln('      </Track>')
    ..writeln('    </Course>')
    ..writeln('  </Courses>')
    ..writeln('</TrainingCenterDatabase>');
  return b.toString();
}

/// GPX de rota (sem horários).
String buildRouteGpx(SavedRoute r) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<gpx version="1.1" creator="GAZMAP - POWERED BY GAZIRE" xmlns="http://www.topografix.com/GPX/1/1">')
    ..writeln('  <trk><name>${_x(r.name)}</name><trkseg>');
  for (final p in r.points) {
    b.write('    <trkpt lat="${p.lat.toStringAsFixed(7)}" lon="${p.lon.toStringAsFixed(7)}">');
    if (p.ele != null) b.write('<ele>${p.ele!.toStringAsFixed(1)}</ele>');
    b.writeln('</trkpt>');
  }
  b.writeln('  </trkseg></trk>\n</gpx>');
  return b.toString();
}

// ---------- FIT (escrita) ----------

const _crcTable = [
  0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
  0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
];

int fitCrc(List<int> data, [int crc = 0]) {
  for (final byte in data) {
    var tmp = _crcTable[crc & 0xF];
    crc = (crc >> 4) & 0x0FFF;
    crc = crc ^ tmp ^ _crcTable[byte & 0xF];
    tmp = _crcTable[crc & 0xF];
    crc = (crc >> 4) & 0x0FFF;
    crc = crc ^ tmp ^ _crcTable[(byte >> 4) & 0xF];
  }
  return crc;
}

class _FitWriter {
  final BytesBuilder _b = BytesBuilder();

  void u8(int v) => _b.addByte(v & 0xFF);
  void u16(int v) {
    u8(v);
    u8(v >> 8);
  }

  void u32(int v) {
    u16(v & 0xFFFF);
    u16((v >> 16) & 0xFFFF);
  }

  /// Mensagem de definição: [(campo, tamanho, tipo base)].
  void define(int local, int global, List<(int, int, int)> fields) {
    u8(0x40 | local);
    u8(0); // reservado
    u8(0); // little endian
    u16(global);
    u8(fields.length);
    for (final f in fields) {
      u8(f.$1);
      u8(f.$2);
      u8(f.$3);
    }
  }

  Uint8List finish() {
    final data = _b.toBytes();
    final header = BytesBuilder()
      ..addByte(14)
      ..addByte(0x20) // protocolo 2.0
      ..add([0x5C, 0x08]) // perfil 21.40
      ..add([data.length & 0xFF, (data.length >> 8) & 0xFF, (data.length >> 16) & 0xFF, (data.length >> 24) & 0xFF])
      ..add('.FIT'.codeUnits);
    final h12 = header.toBytes();
    final hcrc = fitCrc(h12);
    final out = BytesBuilder()
      ..add(h12)
      ..add([hcrc & 0xFF, hcrc >> 8])
      ..add(data);
    final all = out.toBytes();
    final crc = fitCrc(all);
    return Uint8List.fromList([...all, crc & 0xFF, crc >> 8]);
  }
}

int _fitTs(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ 1000 - _fitEpoch;

/// FIT de atividade (formato nativo de relógios e plataformas de treino).
Uint8List buildFit(Track t, List<TrackPoint> pts) {
  final w = _FitWriter();
  final start = _fitTs(t.startedAt);
  final endTs = pts.isEmpty ? start : _fitTs(pts.last.time);
  final sport = switch (t.activity) {
    Activity.corrida => 1,
    Activity.bike => 2,
    Activity.caminhada => 11,
    Activity.trilha => 17,
  };

  // file_id
  w.define(0, 0, [(0, 1, 0x00), (1, 2, 0x84), (2, 2, 0x84), (4, 4, 0x86)]);
  w
    ..u8(0)
    ..u8(4) // atividade
    ..u16(255) // fabricante: desenvolvimento
    ..u16(0)
    ..u32(start);

  // record
  w.define(1, 20, [(253, 4, 0x86), (0, 4, 0x85), (1, 4, 0x85), (78, 4, 0x86), (5, 4, 0x86)]);
  final acc = StatsAccumulator(movingSpeed: t.activity.movingSpeed);
  for (final p in pts) {
    acc.add(p);
    w
      ..u8(1)
      ..u32(_fitTs(p.time))
      ..u32((p.lat * _semi).round())
      ..u32((p.lon * _semi).round())
      ..u32(p.ele == null ? 0xFFFFFFFF : ((p.ele! + 500) * 5).round())
      ..u32((acc.distance * 100).round());
  }

  final elapsed = (endTs - start) * 1000;
  // lap
  w.define(2, 19, [(253, 4, 0x86), (2, 4, 0x86), (7, 4, 0x86), (8, 4, 0x86), (9, 4, 0x86)]);
  w
    ..u8(2)
    ..u32(endTs)
    ..u32(start)
    ..u32(elapsed)
    ..u32(t.movingMs)
    ..u32((t.distance * 100).round());
  // session
  w.define(3, 18, [(253, 4, 0x86), (2, 4, 0x86), (7, 4, 0x86), (8, 4, 0x86), (9, 4, 0x86), (5, 1, 0x00), (22, 2, 0x84)]);
  w
    ..u8(3)
    ..u32(endTs)
    ..u32(start)
    ..u32(elapsed)
    ..u32(t.movingMs)
    ..u32((t.distance * 100).round())
    ..u8(sport)
    ..u16(t.gain.round().clamp(0, 65534));
  // activity
  w.define(4, 34, [(253, 4, 0x86), (0, 4, 0x86), (1, 2, 0x84), (2, 1, 0x00), (3, 1, 0x00), (4, 1, 0x00)]);
  w
    ..u8(4)
    ..u32(endTs)
    ..u32(t.movingMs)
    ..u16(1)
    ..u8(0)
    ..u8(26)
    ..u8(1);
  return w.finish();
}

// ======================================================================
// Compartilhar
// ======================================================================

Future<void> shareActivity(Track t, List<TrackPoint> pts, FileFormat f) async {
  final dir = await getTemporaryDirectory();
  final safe = t.name.replaceAll(RegExp(r'[^\w\-]+'), '_');
  final file = File(p.join(dir.path, '$safe.${f.ext}'));
  switch (f) {
    case FileFormat.gpx:
      await file.writeAsString(buildGpx(t, pts));
    case FileFormat.tcx:
      await file.writeAsString(buildTcx(t, pts));
    case FileFormat.fit:
      await file.writeAsBytes(buildFit(t, pts));
  }
  await Share.shareXFiles([XFile(file.path, mimeType: f.mime)], subject: t.name);
}

Future<void> shareRoute(SavedRoute r, FileFormat f) async {
  final dir = await getTemporaryDirectory();
  final safe = r.name.replaceAll(RegExp(r'[^\w\-]+'), '_');
  final ext = f == FileFormat.fit ? 'gpx' : f.ext; // rota: GPX ou TCX
  final file = File(p.join(dir.path, '$safe.$ext'));
  await file.writeAsString(f == FileFormat.tcx ? buildTcxCourse(r) : buildRouteGpx(r));
  await Share.shareXFiles([XFile(file.path)], subject: r.name);
}

/// Exporta várias atividades de uma vez (um arquivo por trilha).
Future<void> shareActivities(List<(Track, List<TrackPoint>)> items, FileFormat f) async {
  if (items.length == 1) return shareActivity(items.first.$1, items.first.$2, f);
  final dir = await getTemporaryDirectory();
  final files = <XFile>[];
  final used = <String>{};
  for (final (t, pts) in items) {
    var safe = t.name.replaceAll(RegExp(r'[^\w\-]+'), '_');
    while (!used.add(safe)) {
      safe = '${safe}_${used.length}';
    }
    final file = File(p.join(dir.path, '$safe.${f.ext}'));
    switch (f) {
      case FileFormat.gpx:
        await file.writeAsString(buildGpx(t, pts));
      case FileFormat.tcx:
        await file.writeAsString(buildTcx(t, pts));
      case FileFormat.fit:
        await file.writeAsBytes(buildFit(t, pts));
    }
    files.add(XFile(file.path, mimeType: f.mime));
  }
  await Share.shareXFiles(files, subject: 'Trilhas do GAZMAP');
}
