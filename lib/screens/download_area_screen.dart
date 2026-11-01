
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/region.dart';
import '../services/database.dart';
import '../services/place_search.dart';
import '../services/recorder.dart';
import '../services/settings.dart';
import '../services/tile_cache.dart';
import '../utils/format.dart';
import '../widgets/base_map.dart';

/// Escolha do lugar a baixar: busca pelo nome ou ajuste manual no mapa.
class DownloadAreaScreen extends StatefulWidget {
  const DownloadAreaScreen({super.key});

  @override
  State<DownloadAreaScreen> createState() => _DownloadAreaScreenState();
}

class _DownloadAreaScreenState extends State<DownloadAreaScreen> {
  /// Limite por download, para respeitar os servidores gratuitos de mapas.
  static const maxTiles = 12000;
  static const minZoom = 8;
  static const avgTileBytes = 22 * 1024;

  final _map = MapController();
  final _search = TextEditingController();
  int _maxZoom = 15;
  LatLngBounds? _bounds;
  String _placeName = '';
  List<Place> _results = [];
  bool _searching = false;

  int get _tiles =>
      _bounds == null ? 0 : TileCache.countTiles(_bounds!, minZoom, _maxZoom);

  Future<void> _doSearch() async {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _searching = true);
    try {
      final r = await searchPlaces(q);
      if (!mounted) return;
      setState(() => _results = r);
      if (r.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nenhum lugar encontrado.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Sem internet para buscar. Ajuste a área no mapa.')));
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _select(Place p) {
    setState(() {
      _results = [];
      _placeName = p.name.split(',').first;
    });
    if (p.bounds != null) {
      _map.fitCamera(CameraFit.bounds(
          bounds: p.bounds!,
          padding: const EdgeInsets.all(24),
          maxZoom: 14));
    } else {
      _map.move(p.center, 13);
    }
  }

  Future<void> _download() async {
    final bounds = _bounds;
    if (bounds == null) return;
    final style = Settings.instance.style;
    final total = _tiles;
    final name = _placeName.isNotEmpty ? _placeName : 'Área ${fmtDate(DateTime.now())}';
    final progress = ValueNotifier<(int, int)>((0, 0));
    var cancelled = false;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Baixando "$name"'),
        content: ValueListenableBuilder<(int, int)>(
          valueListenable: progress,
          builder: (_, v, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: total == 0 ? null : v.$1 / total),
              const SizedBox(height: 12),
              Text('${v.$1} de $total blocos'
                  '${v.$2 > 0 ? ' · ${v.$2} falharam' : ''}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
              Navigator.pop(ctx);
            },
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    final failed = await TileCache.instance.downloadArea(
      style: style,
      bounds: bounds,
      minZoom: minZoom,
      maxZoom: _maxZoom,
      onProgress: (d, t, f) => progress.value = (d, f),
      isCancelled: () => cancelled,
    );

    if (!mounted) return;
    if (!cancelled) Navigator.of(context).pop(); // fecha o diálogo
    if (cancelled) return;

    await AppDatabase.instance.insertRegion(Region(
      name: name,
      styleId: style.id,
      south: bounds.south,
      west: bounds.west,
      north: bounds.north,
      east: bounds.east,
      minZoom: minZoom,
      maxZoom: _maxZoom,
      tiles: total - failed,
      createdAt: DateTime.now(),
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(failed == 0
            ? 'Área baixada! Disponível sem internet.'
            : 'Baixada com $failed blocos faltando. Tente de novo com internet.')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final style = Settings.instance.style;
    final pos = Recorder.instance.position;
    final tiles = _tiles;
    final tooBig = tiles > maxTiles;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Escolher área')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _doSearch(),
              decoration: InputDecoration(
                hintText: 'Buscar lugar (ex.: Serra do Cipó)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)))
                    : IconButton(
                        icon: const Icon(Icons.arrow_forward),
                        onPressed: _doSearch),
                border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(28))),
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: pos == null
                        ? const LatLng(-19.3, -43.6)
                        : LatLng(pos.latitude, pos.longitude),
                    initialZoom: 11,
                    minZoom: 4,
                    maxZoom: 17,
                    onMapReady: () => setState(
                        () => _bounds = _map.camera.visibleBounds),
                    onPositionChanged: (camera, _) =>
                        setState(() => _bounds = camera.visibleBounds),
                  ),
                  children: [
                    ...baseMapLayers(style),
                    mapAttribution(style),
                  ],
                ),
                // Moldura indicando a área que será baixada.
                IgnorePointer(
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      border: Border.all(color: scheme.primary, width: 3),
                    ),
                  ),
                ),
                if (_results.isNotEmpty)
                  Card(
                    margin: const EdgeInsets.all(8),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final r in _results)
                          ListTile(
                            leading: const Icon(Icons.place),
                            title: Text(r.name,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            onTap: () => _select(r),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    const Text('Detalhe'),
                    Expanded(
                      child: Slider(
                        value: _maxZoom.toDouble(),
                        min: 12,
                        max: 17,
                        divisions: 5,
                        label: _zoomLabel(_maxZoom),
                        onChanged: (v) => setState(() => _maxZoom = v.round()),
                      ),
                    ),
                    Text(_zoomLabel(_maxZoom)),
                  ]),
                  Text(
                    tooBig
                        ? 'Área grande demais ($tiles blocos). Aproxime o mapa ou reduza o detalhe.'
                        : '$tiles blocos · cerca de ${fmtBytes(tiles * avgTileBytes)}',
                    style: TextStyle(color: tooBig ? scheme.error : null),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: tooBig || tiles == 0 ? null : _download,
                    icon: const Icon(Icons.download),
                    label: Text(_placeName.isEmpty
                        ? 'Baixar área visível'
                        : 'Baixar "$_placeName"'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _zoomLabel(int z) => switch (z) {
        <= 12 => 'Baixo',
        13 || 14 => 'Médio',
        15 => 'Trilhas',
        _ => 'Máximo',
      };
}
