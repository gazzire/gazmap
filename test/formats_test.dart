import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gazmap/models/extra.dart';
import 'package:gazmap/models/track.dart';
import 'package:gazmap/services/formats.dart';
import 'package:gazmap/services/gpx.dart';
import 'package:gazmap/services/group.dart';
import 'package:gazmap/utils/sun.dart';

Track _track() => Track(
      id: 1,
      name: 'Serra & Cipó <teste>',
      activity: Activity.trilha,
      startedAt: DateTime.utc(2026, 11, 9, 9),
      distance: 1234,
      movingMs: 600000,
      gain: 120,
      finished: true,
    );

List<TrackPoint> _points() => [
      for (var i = 0; i < 50; i++)
        TrackPoint(
          lat: -19.3 + i * 0.0002,
          lon: -43.6 + i * 0.0001,
          ele: 800 + i.toDouble(),
          time: DateTime.utc(2026, 11, 9, 9).add(Duration(seconds: i * 10)),
        ),
    ];

void main() {
  test('GPX: exporta e importa de volta', () {
    final xml = buildGpx(_track(), _points());
    final g = parseAny('a.gpx', Uint8List.fromList(utf8.encode(xml)))!;
    expect(g.points.length, 50);
    expect(g.name, 'Serra & Cipó <teste>');
    expect(g.points.first.$1, closeTo(-19.3, 1e-6));
    expect(g.points.last.$3, closeTo(849, 0.1));
    expect(g.hasTimes, isTrue);
  });

  test('TCX: exporta e importa de volta', () {
    final xml = buildTcx(_track(), _points());
    final g = parseAny('a.tcx', Uint8List.fromList(utf8.encode(xml)))!;
    expect(g.points.length, 50);
    expect(g.points[10].$2, closeTo(-43.599, 1e-6));
    expect(g.points[10].$4, DateTime.utc(2026, 11, 9, 9, 1, 40));
  });

  test('TCX Course (rota) é lido como rota', () {
    final r = SavedRoute(
      name: 'Rota teste',
      points: [for (final p in _points()) RoutePoint(p.lat, p.lon, p.ele)],
      createdAt: DateTime(2026),
    );
    final g = parseAny('r.tcx', Uint8List.fromList(utf8.encode(buildTcxCourse(r))))!;
    expect(g.points.length, 50);
    expect(g.hasTimes, isFalse);
  });

  test('FIT: exporta e importa de volta (binário com CRC)', () {
    final bytes = buildFit(_track(), _points());
    expect(String.fromCharCodes(bytes.sublist(8, 12)), '.FIT');
    // CRC do arquivo inteiro (incluindo os 2 bytes finais) deve dar zero.
    expect(fitCrc(bytes), 0);
    final g = parseAny('a.fit', bytes)!;
    expect(g.points.length, 50);
    expect(g.points.first.$1, closeTo(-19.3, 1e-6));
    expect(g.points.first.$2, closeTo(-43.6, 1e-6));
    expect(g.points[5].$3, closeTo(805, 0.3));
    expect(g.points[5].$4, DateTime.utc(2026, 11, 9, 9, 0, 50));
    expect(g.type, 'hiking');
  });

  test('FIT compactado (.fit.gz exportado de outros apps)', () {
    final gz = Uint8List.fromList(gzip.encode(buildFit(_track(), _points())));
    final g = parseAny('atividade.fit.gz', gz)!;
    expect(g.points.length, 50);
  });

  test('GPX de rota com rtept e sem horários', () {
    const xml = '<?xml version="1.0"?><gpx><rte><name>Pico</name>'
        '<rtept lat="-19.1" lon="-43.5"><ele>1000</ele></rtept>'
        "<rtept lon='-43.6' lat='-19.2'/></rte></gpx>";
    final g = parseGpx(xml)!;
    expect(g.name, 'Pico');
    expect(g.points.length, 2);
    expect(g.points[1].$1, -19.2);
    expect(g.hasTimes, isFalse);
  });

  test('Arquivo inválido não quebra o app', () {
    expect(parseAny('x.gpx', Uint8List.fromList(utf8.encode('olá'))), isNull);
    expect(parseAny('x.fit', Uint8List.fromList([14, 16, 0, 0, 255, 255, 255, 255, 46, 70, 73, 84])), isNull);
  });

  test('Tipo de atividade a partir do arquivo', () {
    expect(activityFromGpxType('cycling'), Activity.bike);
    expect(activityFromGpxType('running'), Activity.corrida);
    expect(activityFromGpxType('walking'), Activity.caminhada);
    expect(activityFromGpxType('hiking'), Activity.trilha);
  });

  test('Pôr do sol em Belo Horizonte (9/nov) por volta das 18h09', () {
    final s = sunsetTime(DateTime(2026, 11, 9), -19.92, -43.94)!;
    final utc = s.toUtc();
    final minutes = utc.hour * 60 + utc.minute;
    expect(minutes, inInclusiveRange(21 * 60 + 4, 21 * 60 + 14)); // 18h09 em UTC-3
  });

  test('Pontos GAZ do Modo Grupo', () {
    expect(GroupService.pointsFor(5000, 300, 7000), 50 + 30 + 7);
  });

  test('Validação de telefone de emergência', () {
    expect(EmergencyContact.isValid('(31) 99999-8888'), isTrue);
    expect(EmergencyContact.isValid('+55 31 99999-8888'), isTrue);
    expect(EmergencyContact.isValid('123'), isFalse);
    expect(EmergencyContact.normalize('(31) 99999-8888'), '31999998888');
  });
}
