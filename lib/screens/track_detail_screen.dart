import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/extra.dart';
import '../models/track.dart';
import '../services/database.dart';
import '../services/formats.dart';
import '../services/navigation.dart';
import '../services/records.dart';
import '../services/settings.dart';
import 'home_screen.dart';
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
  TrailRecord? _record;
  List<Waypoint> _waypoints = [];
  List<(FavoriteSegment, int, int, int)> _segEfforts = []; // trecho, ms, posição, total

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
    if (t == null) return;
    final wps = await _db.waypoints(trackId: t.id);
    final rec = await Records.forTrack(t);
    final segs = <(FavoriteSegment, int, int, int)>[];
    for (final s in await _db.segments()) {
      if (s.activity != t.activity) continue;
      final ms = Records.effortIn(pts, s);
      if (ms == null) continue;
      final all = await Records.efforts(s);
      final pos = all.indexWhere((e) => e.track.id == t.id) + 1;
      segs.add((s, ms, pos, all.length));
    }
    if (!mounted) return;
    setState(() {
      _waypoints = wps;
      _record = rec;
      _segEfforts = segs;
    });
  }

  Future<void> _export() async {
    final f = await showModalBottomSheet<FileFormat>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('Exportar atividade como')),
          for (final (fmt, sub) in [
            (FileFormat.gpx, 'Strava, Wikiloc, Komoot, Garmin (mais compatível)'),
            (FileFormat.tcx, 'Garmin, TrainingPeaks, Strava'),
            (FileFormat.fit, 'Formato nativo de relógios; Strava e Garmin Connect'),
          ])
            ListTile(
              leading: const Icon(Icons.description),
              title: Text(fmt.label),
              subtitle: Text(sub),
              onTap: () => Navigator.pop(ctx, fmt),
            ),
        ]),
      ),
    );
    if (f != null && _track != null) await shareActivity(_track!, _points, f);
  }

  Future<void> _saveAsRoute() async {
    await _db.insertRoute(SavedRoute.fromTrack(_track!, _points));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Salva em Rotas. Use para navegar ou repetir.')));
  }

  void _raceRecord() {
    final best = _record?.best ?? _track!;
    _db.points(best.id!).then((pts) {
      final nav = RouteNavigator.instance
        ..pendingGhost = best
        ..pendingGhostPoints = pts
        ..pendingRoute = null;
      nav.refresh();
      homeTab.value = 0;
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    });
  }

  Future<void> _createSegment() async {
    if (_points.length < 10) return;
    var range = const RangeValues(0.2, 0.6);
    final name = TextEditingController(text: 'Trecho');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final a = _stats?.profile;
          String label(double f) => a == null || a.isEmpty
              ? '${(f * 100).round()}%'
              : '${fmtKm(a.last.$1 * f)} km';
          return AlertDialog(
            title: const Text('Novo trecho favorito'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome'), maxLength: 40),
              RangeSlider(
                values: range,
                divisions: 100,
                labels: RangeLabels(label(range.start), label(range.end)),
                onChanged: (v) => set(() => range = v),
              ),
              Text('De ${label(range.start)} até ${label(range.end)}'),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Criar')),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final i = (range.start * (_points.length - 1)).round();
    final j = (range.end * (_points.length - 1)).round();
    if (j - i < 3) return;
    await _db.insertSegment(FavoriteSegment(
      name: name.text.trim().isEmpty ? 'Trecho' : name.text.trim(),
      activity: _track!.activity,
      start: LatLng(_points[i].lat, _points[i].lon),
      end: LatLng(_points[j].lat, _points[j].lon),
      createdAt: DateTime.now(),
    ));
    await _load();
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
              tooltip: 'Exportar (GPX, TCX, FIT)',
              icon: const Icon(Icons.ios_share),
              onPressed: _points.isEmpty ? null : _export),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'rename':
                  _rename();
                case 'route':
                  _saveAsRoute();
                case 'race':
                  _raceRecord();
                case 'segment':
                  _createSegment();
                case 'delete':
                  _delete();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'race', child: Text('Repetir contra o recorde')),
              PopupMenuItem(value: 'route', child: Text('Salvar como rota')),
              PopupMenuItem(value: 'segment', child: Text('Criar trecho favorito')),
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
                    for (final w in _waypoints)
                      Marker(
                          point: w.latLng,
                          width: 30,
                          height: 30,
                          child: Text(w.kind.emoji, style: const TextStyle(fontSize: 22))),
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
                    t.steps > 0
                        ? StatTile(label: 'Passos', value: '${t.steps}')
                        : StatTile(label: 'Pontos GPS', value: '${_points.length}'),
                  ],
                ),
                if (profile.length >= 2) ...[
                  const SizedBox(height: 16),
                  Text('Altimetria',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ElevationChart(profile: profile),
                ],
                if (_record != null && _record!.times > 1) ...[
                  const SizedBox(height: 16),
                  _RecordCard(record: _record!),
                ],
                if (_segEfforts.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Trechos favoritos', style: Theme.of(context).textTheme.titleMedium),
                  for (final (s, ms, pos, total) in _segEfforts)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Text(switch (pos) { 1 => '🥇', 2 => '🥈', 3 => '🥉', _ => '⏱️' },
                          style: const TextStyle(fontSize: 24)),
                      title: Text(s.name),
                      subtitle: Text('${fmtDuration(Duration(milliseconds: ms))} · $posº de $total'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await _db.deleteSegment(s.id!);
                          await _load();
                        },
                      ),
                    ),
                ],
                if (_waypoints.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Pontos marcados', style: Theme.of(context).textTheme.titleMedium),
                  for (final w in _waypoints)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: w.photoPath != null && File(w.photoPath!).existsSync()
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(File(w.photoPath!), width: 48, height: 48, fit: BoxFit.cover))
                          : Text(w.kind.emoji, style: const TextStyle(fontSize: 28)),
                      title: Text(w.note.isEmpty ? w.kind.label : '${w.kind.label}: ${w.note}'),
                      subtitle: Text('${w.lat.toStringAsFixed(5)}, ${w.lon.toStringAsFixed(5)}'),
                    ),
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

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record});
  final TrailRecord record;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final prev = r.previous;
    final diff = prev == null ? null : r.track.movingMs - prev.movingMs;
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(r.medal.isEmpty ? '🏁' : r.medal, style: const TextStyle(fontSize: 30)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                r.isBest ? 'Novo recorde pessoal!' : 'Melhor Volta: ${r.rank}º de ${r.times}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text('Você fez esta trilha ${r.times} vezes.'),
          Text('Recorde: ${fmtDuration(Duration(milliseconds: r.best.movingMs))} (${fmtDate(r.best.startedAt).split(' ').first})'),
          Text('Média: ${fmtDuration(Duration(milliseconds: r.averageMs))}'),
          if (diff != null)
            Text(diff <= 0
                ? '${fmtDuration(Duration(milliseconds: -diff))} mais rápido que a última vez'
                : '${fmtDuration(Duration(milliseconds: diff))} mais lento que a última vez'),
        ]),
      ),
    );
  }
}
