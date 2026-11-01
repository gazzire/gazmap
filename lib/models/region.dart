/// Área de mapa baixada para uso offline.
class Region {
  Region({
    this.id,
    required this.name,
    required this.styleId,
    required this.south,
    required this.west,
    required this.north,
    required this.east,
    required this.minZoom,
    required this.maxZoom,
    required this.tiles,
    required this.createdAt,
  });

  final int? id;
  final String name;
  final String styleId;
  final double south, west, north, east;
  final int minZoom, maxZoom, tiles;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'style_id': styleId,
        'south': south,
        'west': west,
        'north': north,
        'east': east,
        'min_zoom': minZoom,
        'max_zoom': maxZoom,
        'tiles': tiles,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Region.fromMap(Map<String, Object?> m) => Region(
        id: m['id'] as int?,
        name: m['name'] as String,
        styleId: m['style_id'] as String,
        south: (m['south'] as num).toDouble(),
        west: (m['west'] as num).toDouble(),
        north: (m['north'] as num).toDouble(),
        east: (m['east'] as num).toDouble(),
        minZoom: m['min_zoom'] as int,
        maxZoom: m['max_zoom'] as int,
        tiles: m['tiles'] as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );
}
