import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/geo.dart';
import 'settings.dart';

/// Cache de tiles em disco. Todo tile visto ou baixado fica salvo,
/// e o mapa passa a funcionar sem internet nessas áreas.
class TileCache {
  TileCache._();
  static final TileCache instance = TileCache._();

  static const userAgent = 'Rastro/0.1 (+https://github.com/gazzire/rastro)';

  late Directory root;
  final http.Client _client = http.Client();

  Future<void> init() async {
    final base = await getApplicationSupportDirectory();
    root = Directory(p.join(base.path, 'tiles'));
    await root.create(recursive: true);
  }

  File file(String styleId, int z, int x, int y) =>
      File(p.join(root.path, styleId, '$z', '$x', '$y.png'));

  static String buildUrl(String template, int z, int x, int y) => template
      .replaceAll('{s}', 'a')
      .replaceAll('{z}', '$z')
      .replaceAll('{x}', '$x')
      .replaceAll('{y}', '$y');

  Future<Uint8List> load(MapStyle style, int z, int x, int y) async {
    final f = file(style.id, z, x, y);
    if (await f.exists()) return f.readAsBytes();
    return _download(style, z, x, y, f);
  }

  /// Baixa se ainda não estiver no cache. Retorna true se baixou.
  Future<bool> ensure(MapStyle style, int z, int x, int y) async {
    final f = file(style.id, z, x, y);
    if (await f.exists()) return false;
    await _download(style, z, x, y, f);
    return true;
  }

  Future<Uint8List> _download(
      MapStyle style, int z, int x, int y, File f) async {
    final res = await _client
        .get(Uri.parse(buildUrl(style.url, z, x, y)),
            headers: {'User-Agent': userAgent})
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}');
    }
    await f.parent.create(recursive: true);
    await f.writeAsBytes(res.bodyBytes);
    return res.bodyBytes;
  }

  Future<int> sizeBytes() async {
    var total = 0;
    if (!await root.exists()) return 0;
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  Future<void> clear() async {
    if (await root.exists()) await root.delete(recursive: true);
    await root.create(recursive: true);
  }

  // ---------- Download de áreas ----------

  static int countTiles(LatLngBounds b, int minZoom, int maxZoom) {
    var n = 0;
    for (var z = minZoom; z <= maxZoom; z++) {
      final x0 = TileMath.lonToX(b.west, z), x1 = TileMath.lonToX(b.east, z);
      final y0 = TileMath.latToY(b.north, z), y1 = TileMath.latToY(b.south, z);
      n += (x1 - x0 + 1) * (y1 - y0 + 1);
    }
    return n;
  }

  /// Baixa todos os tiles da área, 4 em paralelo.
  Future<int> downloadArea({
    required MapStyle style,
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    required void Function(int done, int total, int failed) onProgress,
    required bool Function() isCancelled,
  }) async {
    final queue = <(int, int, int)>[];
    for (var z = minZoom; z <= maxZoom; z++) {
      final x0 = TileMath.lonToX(bounds.west, z);
      final x1 = TileMath.lonToX(bounds.east, z);
      final y0 = TileMath.latToY(bounds.north, z);
      final y1 = TileMath.latToY(bounds.south, z);
      for (var x = x0; x <= x1; x++) {
        for (var y = y0; y <= y1; y++) {
          queue.add((z, x, y));
        }
      }
    }
    final total = queue.length;
    var done = 0, failed = 0, index = 0;

    Future<void> worker() async {
      while (!isCancelled()) {
        if (index >= queue.length) return;
        final (z, x, y) = queue[index++];
        try {
          final downloaded = await ensure(style, z, x, y);
          // Respeita os servidores gratuitos: pequena pausa entre downloads.
          if (downloaded) {
            await Future<void>.delayed(const Duration(milliseconds: 60));
          }
        } catch (_) {
          failed++;
        }
        done++;
        onProgress(done, total, failed);
      }
    }

    await Future.wait(List.generate(4, (_) => worker()));
    return failed;
  }
}

/// TileProvider do flutter_map que usa o cache em disco.
class CachedTileProvider extends TileProvider {
  CachedTileProvider(this.style);

  final MapStyle style;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      CachedTileImage(style, coordinates.z, coordinates.x, coordinates.y);
}

class CachedTileImage extends ImageProvider<CachedTileImage> {
  const CachedTileImage(this.style, this.z, this.x, this.y);

  final MapStyle style;
  final int z, x, y;

  @override
  Future<CachedTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<CachedTileImage>(this);

  @override
  ImageStreamCompleter loadImage(
          CachedTileImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1.0);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await TileCache.instance.load(style, z, x, y);
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is CachedTileImage &&
      other.style.id == style.id &&
      other.style.url == style.url &&
      other.z == z &&
      other.x == x &&
      other.y == y;

  @override
  int get hashCode => Object.hash(style.id, style.url, z, x, y);
}
