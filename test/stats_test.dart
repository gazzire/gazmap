import 'package:flutter_test/flutter_test.dart';
import 'package:gazmap/models/track.dart';
import 'package:gazmap/utils/format.dart';
import 'package:gazmap/utils/geo.dart';
import 'package:gazmap/widgets/powered_by.dart';

void main() {
  test('haversine: 1 grau de latitude ≈ 111 km', () {
    final d = haversine(0, 0, 1, 0);
    expect(d, closeTo(111195, 50));
  });

  test('estatísticas: distância, tempo em movimento e salto de GPS', () {
    final t0 = DateTime(2026, 1, 1, 8);
    // ~11 m a cada 10 s (≈1,1 m/s), depois um salto absurdo.
    final pts = [
      for (var i = 0; i < 10; i++)
        TrackPoint(lat: i * 0.0001, lon: 0, time: t0.add(Duration(seconds: i * 10))),
      TrackPoint(lat: 1, lon: 0, time: t0.add(const Duration(seconds: 101))),
    ];
    final s = StatsAccumulator.compute(pts);
    expect(s.distance, closeTo(100, 1)); // salto descartado
    expect(s.movingMs, 90000);
  });

  test('pausa manual separa trechos (sem somar distância entre eles)', () {
    final t0 = DateTime(2026, 1, 1, 8);
    final pts = [
      TrackPoint(lat: 0, lon: 0, time: t0),
      TrackPoint(lat: 0.0001, lon: 0, time: t0.add(const Duration(seconds: 10))),
      TrackPoint(lat: 0.01, lon: 0, time: t0.add(const Duration(seconds: 600)), segment: 1),
      TrackPoint(lat: 0.0101, lon: 0, time: t0.add(const Duration(seconds: 610)), segment: 1),
    ];
    final s = StatsAccumulator.compute(pts);
    expect(s.distance, closeTo(22.2, 0.5));
  });

  test('altimetria ignora ruído menor que o limiar', () {
    final e = ElevationAccumulator();
    for (final v in [800.0, 802, 799, 801, 810, 809, 811, 820, 805]) {
      e.add(v);
    }
    expect(e.gain, closeTo(20, 0.01));
    expect(e.loss, closeTo(15, 0.01));
  });

  test('formatação', () {
    expect(fmtKm(2450), '2,45');
    expect(fmtPace(725), "12'05\"");
    expect(fmtDuration(const Duration(seconds: 3725)), '1:02:05');
    expect(fmtSpeed(5), '18,0');
  });

  test('tiles: Belo Horizonte no zoom 10', () {
    expect(TileMath.lonToX(-43.94, 10), 387);
    expect(TileMath.latToY(-19.92, 10), 569);
  });

  test('atribuição de autoria preservada', () {
    expect(poweredByText, 'POWERED BY GAZIRE');
  });
}
