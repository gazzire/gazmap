import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/extra.dart';
import '../services/database.dart';
import '../services/formats.dart';
import '../services/gpx.dart';
import '../services/native.dart';
import '../services/navigation.dart';
import '../services/settings.dart';
import '../utils/format.dart';
import '../widgets/base_map.dart';
import 'download_area_screen.dart';
import 'home_screen.dart';

/// Rotas para navegar: importadas (GPX, TCX, FIT) ou salvas de atividades.
class RoutesScreen extends StatefulWidget {
  const RoutesScreen({super.key});

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
  final _db = AppDatabase.instance;
  List<SavedRoute>? _routes;

  @override
  void initState() {
    super.initState();
    _db.changes.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _db.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final r = await _db.routes();
    if (mounted) setState(() => _routes = r);
  }

  Future<void> _import() async {
    final files = await NativeBridge.pickFiles();
    if (files.isEmpty) return;
    final n = await importRoutes(files);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(n == 0
            ? 'Nenhuma rota reconhecida. Use arquivos GPX, TCX ou FIT.'
            : '$n ${n == 1 ? 'rota importada' : 'rotas importadas'}.')));
  }

  @override
  Widget build(BuildContext context) {
    final routes = _routes;
    return Scaffold(
      appBar: AppBar(title: const Text('Rotas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _import,
        icon: const Icon(Icons.file_open),
        label: const Text('Importar GPX/TCX/FIT'),
      ),
      body: routes == null
          ? const Center(child: CircularProgressIndicator())
          : routes.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Nenhuma rota ainda.\n\nImporte um arquivo GPX, TCX ou FIT (Wikiloc, Strava, Komoot, Garmin) '
                      'ou salve uma atividade sua como rota.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                  children: [
                    for (final r in routes)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.route),
                          title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${fmtKm(r.distance)} km · ↑${r.gain.round()} m'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => RouteDetailScreen(route: r))),
                        ),
                      ),
                  ],
                ),
    );
  }
}

class RouteDetailScreen extends StatelessWidget {
  const RouteDetailScreen({super.key, required this.route});

  final SavedRoute route;

  LatLngBounds get _bounds => LatLngBounds.fromPoints(route.points.map((p) => p.latLng).toList());

  void _navigate(BuildContext context) {
    RouteNavigator.instance.pendingRoute = route;
    homeTab.value = 0;
    Navigator.of(context).popUntil((r) => r.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Rota escolhida. Toque em INICIAR para navegar.')));
  }

  void _downloadAround(BuildContext context) {
    final b = _bounds;
    const m = 0.01; // ~1 km de margem
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DownloadAreaScreen(
              initialBounds: LatLngBounds(
                  LatLng(b.south - m, b.west - m), LatLng(b.north + m, b.east + m)),
              initialName: route.name,
            )));
  }

  Future<void> _export(BuildContext context) async {
    final f = await showModalBottomSheet<FileFormat>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('Exportar rota como')),
          ListTile(
              leading: const Icon(Icons.description),
              title: const Text('GPX'),
              subtitle: const Text('Strava, Wikiloc, Komoot, Garmin'),
              onTap: () => Navigator.pop(ctx, FileFormat.gpx)),
          ListTile(
              leading: const Icon(Icons.watch),
              title: const Text('TCX (Course)'),
              subtitle: const Text('Relógios e ciclocomputadores Garmin'),
              onTap: () => Navigator.pop(ctx, FileFormat.tcx)),
        ]),
      ),
    );
    if (f != null) await shareRoute(route, f);
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir rota?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true) return;
    await AppDatabase.instance.deleteRoute(route.id!);
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final style = Settings.instance.style;
    final pts = route.points.map((p) => p.latLng).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(route.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(tooltip: 'Exportar', icon: const Icon(Icons.ios_share), onPressed: () => _export(context)),
          IconButton(tooltip: 'Excluir', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(context)),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: FlutterMap(
            options: MapOptions(
              initialCenter: pts.first,
              initialZoom: 13,
              maxZoom: 19,
              initialCameraFit: CameraFit.bounds(
                  bounds: _bounds, padding: const EdgeInsets.all(32), maxZoom: 16),
            ),
            children: [
              ...baseMapLayers(style),
              PolylineLayer(polylines: [
                Polyline(points: pts, strokeWidth: 5, color: const Color(0xFF1E88E5),
                    borderStrokeWidth: 2, borderColor: Colors.white),
              ]),
              mapAttribution(style),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                StatTile(label: 'Distância', value: fmtKm(route.distance), unit: 'km'),
                StatTile(label: 'Subida', value: '${route.gain.round()}', unit: 'm'),
                StatTile(label: 'Pontos', value: '${route.points.length}'),
              ]),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _navigate(context),
                icon: const Icon(Icons.navigation),
                label: const Text('Navegar esta rota'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _downloadAround(context),
                icon: const Icon(Icons.download_for_offline),
                label: const Text('Baixar mapa offline do entorno'),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
