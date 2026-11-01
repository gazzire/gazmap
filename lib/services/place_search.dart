import 'dart:convert';

import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'tile_cache.dart';

class Place {
  Place(this.name, this.center, this.bounds);

  final String name;
  final LatLng center;
  final LatLngBounds? bounds;
}

/// Busca de lugares pelo nome usando o Nominatim (OpenStreetMap).
/// Uso leve e com identificação, conforme a política do serviço.
Future<List<Place>> searchPlaces(String query) async {
  final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
    'q': query,
    'format': 'jsonv2',
    'limit': '8',
    'accept-language': 'pt-BR',
  });
  final res = await http
      .get(uri, headers: {'User-Agent': TileCache.userAgent})
      .timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) return [];
  final data = jsonDecode(res.body) as List<dynamic>;
  return data.map((e) {
    final m = e as Map<String, dynamic>;
    final center = LatLng(double.parse(m['lat'] as String),
        double.parse(m['lon'] as String));
    LatLngBounds? bounds;
    final bb = m['boundingbox'] as List<dynamic>?;
    if (bb != null && bb.length == 4) {
      final s = double.parse(bb[0] as String);
      final n = double.parse(bb[1] as String);
      final w = double.parse(bb[2] as String);
      final ea = double.parse(bb[3] as String);
      bounds = LatLngBounds(LatLng(s, w), LatLng(n, ea));
    }
    return Place(m['display_name'] as String, center, bounds);
  }).toList();
}
