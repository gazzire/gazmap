import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/track.dart';
import '../services/database.dart';
import '../services/gpx.dart';
import '../services/settings.dart';
import '../utils/format.dart';
import '../widgets/base_map.dart';
import '../widgets/elevation_chart.dart';

class TrackDetailScreen extends StatefulWidget {
  const TrackDetailScreen({super.key, required this.trackId});

  final int trackId;

  @override
  State<TrackDetailScreen> createState() => _TrackDetailScreenState();
}

class _TrackDetailScreenState extends State<TrackDetailScreen> {
  final _db = AppDatabase.instance;
  Track? _track;
  List<TrackPoint> _points = [];
  StatsAccumulator? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await _db.track(widget.trackId);
    final pts = await _db.points(widget.trackId);
    if (!mounted) return;
    setState(() {
      _track = t;
      _points = pts;
      _stats = StatsAccumulator.compute(pts,
          movingSpeed: t?.activity.movingSpeed ?? 0.35);
    });
  }

  Future<void> _rename() async {
    final t = _track!;
    final c = TextEditingController(text: t.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renomear'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('Salvar')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    t.name = name.trim();
    await _db.updateTrack(t);
    setState(() {});
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir atividade?'),
        content: const Text('Essa ação não pode ser desfeita.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true) return;
    await _db.deleteTrack(widget.trackId);
    if (mounted) Navigator.pop(context);
  }

  List<List<LatLng>> get _segments {
    final out = <List<LatLng>>[];
    int? seg;
    for (final p in _points) {
      if (p.segment != seg) {
        out.add([]);
        seg = p.segment;
      }
      out.last.add(LatLng(p.lat, p.lon));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final t = _track;
    if (t == null) {
      return Scaffold(
          appBar: AppBar(),
          body: const Center(child: CircularProgressIndicator()));
    }
    final scheme = Theme.of(context).colorScheme;
    final style = Settings.instance.style;
    final all = _points.map((p) => LatLng(p.lat, p.lon)).toList();
    final profile = _stats?.profile ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(t.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
              tooltip: 'Exportar GPX',
              icon: const Icon(Icons.ios_share),
              onPressed: _points.isEmpty ? null : () => shareGpx(t, _points)),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'rename' ? _rename() : _delete(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Renomear')),
              PopupMenuItem(value: 'delete', child: Text('Excluir')),
            ],
          ),
        ],
      ),
      body: ListView(
        children: [
          SizedBox(
            height: 300,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: all.isEmpty ? const LatLng(-15.8, -47.9) : all.first,
                initialZoom: 14,
                maxZoom: 19,
                initialCameraFit: all.length >= 2
                    ? CameraFit.bounds(
                        bounds: LatLngBounds.fromPoints(all),
                        padding: const EdgeInsets.all(36),
                        maxZoom: 17,
                      )
                    : null,
              ),
              children: [
                ...baseMapLayers(style),
                PolylineLayer(polylines: [
                  for (final s in _segments)
                    if (s.length >= 2)
                      Polyline(
                        points: s,
                        strokeWidth: 5,
                        color: scheme.primary,
                        borderStrokeWidth: 2,
                        borderColor: Colors.white,
                      ),
                ]),
                if (all.isNotEmpty)
                  MarkerLayer(markers: [
                    Marker(
                        point: all.first,
                        width: 22,
                        height: 22,
                        child: const _Pin(color: Colors.green)),
                    Marker(
                        point: all.last,
                        width: 22,
                        height: 22,
                        child: const _Pin(color: Colors.red)),
                  ]),
                mapAttribution(style),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(t.activity.icon, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text('${t.activity.label} · ${fmtDate(t.startedAt)}'),
                ]),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 2.2,
                  children: [
                    StatTile(
                        label: 'Distância',
                        value: fmtKm(t.distance),
                        unit: 'km'),
                    StatTile(
                        label: 'Em movimento',
                        value: fmtDuration(Duration(milliseconds: t.movingMs))),
                    t.activity.usesSpeed
                        ? StatTile(
                            label: 'Velocidade média',
                            value: fmtSpeed(avgSpeed(t.distance, t.movingMs)),
                            unit: 'km/h')
                        : StatTile(
                            label: 'Ritmo médio',
                            value: fmtPace(paceSecPerKm(t.distance, t.movingMs)),
                            unit: '/km'),
                    StatTile(
                        label: 'Tempo total',
                        value: fmtDuration(Duration(milliseconds: t.elapsedMs))),
                    StatTile(
                        label: 'Subida', value: '${t.gain.round()}', unit: 'm'),
                    StatTile(
                        label: 'Descida', value: '${t.loss.round()}', unit: 'm'),
                    StatTile(
                        label: 'Velocidade máx.',
                        value: fmtSpeed(t.maxSpeed),
                        unit: 'km/h'),
                    StatTile(label: 'Pontos GPS', value: '${_points.length}'),
                  ],
                ),
                if (profile.length >= 2) ...[
                  const SizedBox(height: 16),
                  Text('Altimetria',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ElevationChart(profile: profile),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
        ),
      );
}
