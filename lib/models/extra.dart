import 'dart:convert';

import 'package:latlong2/latlong.dart';

import 'track.dart';

/// Contato de emergência.
class EmergencyContact {
  EmergencyContact({this.id, required this.name, required this.phone});

  int? id;
  String name;
  String phone;

  /// Mantém só dígitos e "+" (formato aceito pelo SMS).
  static String normalize(String raw) => raw.replaceAll(RegExp(r'[^0-9+]'), '');

  static bool isValid(String raw) {
    final n = normalize(raw);
    return RegExp(r'^\+?[0-9]{8,15}$').hasMatch(n);
  }

  Map<String, Object?> toMap() =>
      {if (id != null) 'id': id, 'name': name, 'phone': normalize(phone)};

  factory EmergencyContact.fromMap(Map<String, Object?> m) => EmergencyContact(
        id: m['id'] as int?,
        name: m['name'] as String,
        phone: m['phone'] as String,
      );
}

/// Ponto de uma rota planejada (GPX importado ou trilha gravada).
class RoutePoint {
  const RoutePoint(this.lat, this.lon, [this.ele]);

  final double lat;
  final double lon;
  final double? ele;

  LatLng get latLng => LatLng(lat, lon);

  List<num> toJson() => [lat, lon, if (ele != null) ele!];

  factory RoutePoint.fromJson(List<dynamic> j) => RoutePoint(
        (j[0] as num).toDouble(),
        (j[1] as num).toDouble(),
        j.length > 2 ? (j[2] as num).toDouble() : null,
      );
}

/// Rota salva para navegação.
class SavedRoute {
  SavedRoute({
    this.id,
    required this.name,
    required this.points,
    required this.createdAt,
    this.source = 'gpx',
  });

  int? id;
  String name;
  List<RoutePoint> points;
  DateTime createdAt;
  String source;

  double get distance {
    var d = 0.0;
    for (var i = 1; i < points.length; i++) {
      d += _dist(points[i - 1], points[i]);
    }
    return d;
  }

  double get gain {
    final e = ElevationAccumulator();
    for (final p in points) {
      e.add(p.ele);
    }
    return e.gain;
  }

  static double _dist(RoutePoint a, RoutePoint b) =>
      const Distance().as(LengthUnit.Meter, a.latLng, b.latLng);

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'points': jsonEncode(points.map((p) => p.toJson()).toList()),
        'created_at': createdAt.millisecondsSinceEpoch,
        'source': source,
      };

  factory SavedRoute.fromMap(Map<String, Object?> m) => SavedRoute(
        id: m['id'] as int?,
        name: m['name'] as String,
        points: (jsonDecode(m['points'] as String) as List<dynamic>)
            .map((e) => RoutePoint.fromJson(e as List<dynamic>))
            .toList(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        source: (m['source'] as String?) ?? 'gpx',
      );

  factory SavedRoute.fromTrack(Track t, List<TrackPoint> pts) => SavedRoute(
        name: t.name,
        points: pts.map((p) => RoutePoint(p.lat, p.lon, p.ele)).toList(),
        createdAt: DateTime.now(),
        source: 'track',
      );
}

/// Trecho favorito com recorde próprio.
class FavoriteSegment {
  FavoriteSegment({
    this.id,
    required this.name,
    required this.activity,
    required this.start,
    required this.end,
    required this.createdAt,
  });

  int? id;
  String name;
  Activity activity;
  LatLng start;
  LatLng end;
  DateTime createdAt;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'activity': activity.name,
        's_lat': start.latitude,
        's_lon': start.longitude,
        'e_lat': end.latitude,
        'e_lon': end.longitude,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory FavoriteSegment.fromMap(Map<String, Object?> m) => FavoriteSegment(
        id: m['id'] as int?,
        name: m['name'] as String,
        activity: Activity.fromName(m['activity'] as String?),
        start: LatLng((m['s_lat'] as num).toDouble(), (m['s_lon'] as num).toDouble()),
        end: LatLng((m['e_lat'] as num).toDouble(), (m['e_lon'] as num).toDouble()),
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );
}

/// Tipos de ponto marcado na trilha.
enum WaypointKind {
  nascente('Nascente', '💧'),
  mirante('Mirante', '🏞️'),
  perigo('Perigo', '⚠️'),
  bifurcacao('Bifurcação', '🔀'),
  abrigo('Abrigo', '⛺'),
  outro('Ponto', '📍');

  const WaypointKind(this.label, this.emoji);
  final String label;
  final String emoji;

  static WaypointKind fromName(String? n) => WaypointKind.values
      .firstWhere((k) => k.name == n, orElse: () => WaypointKind.outro);
}

class Waypoint {
  Waypoint({
    this.id,
    this.trackId,
    required this.lat,
    required this.lon,
    required this.kind,
    this.note = '',
    this.photoPath,
    required this.createdAt,
  });

  int? id;
  int? trackId;
  double lat;
  double lon;
  WaypointKind kind;
  String note;
  String? photoPath;
  DateTime createdAt;

  LatLng get latLng => LatLng(lat, lon);

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'track_id': trackId,
        'lat': lat,
        'lon': lon,
        'kind': kind.name,
        'note': note,
        'photo': photoPath,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Waypoint.fromMap(Map<String, Object?> m) => Waypoint(
        id: m['id'] as int?,
        trackId: m['track_id'] as int?,
        lat: (m['lat'] as num).toDouble(),
        lon: (m['lon'] as num).toDouble(),
        kind: WaypointKind.fromName(m['kind'] as String?),
        note: (m['note'] as String?) ?? '',
        photoPath: m['photo'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );
}
