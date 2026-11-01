import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/track.dart';
import '../services/recorder.dart';
import '../services/settings.dart';
import '../utils/format.dart';
import '../widgets/base_map.dart';
import 'track_detail_screen.dart';

class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final _map = MapController();
  final _rec = Recorder.instance;
  final _settings = Settings.instance;
  bool _mapReady = false;
  bool _follow = true;
  String? _permError;

  // Centro inicial: Brasil. Substituído pela posição real assim que houver GPS.
  static const _fallback = LatLng(-19.92, -43.94);

  @override
  void initState() {
    super.initState();
    _rec.addListener(_onRecorder);
    _initGps();
  }

  @override
  void dispose() {
    _rec.removeListener(_onRecorder);
    super.dispose();
  }

  Future<void> _initGps() async {
    final err = await _rec.ensurePermission();
    if (!mounted) return;
    setState(() => _permError = err);
    if (err == null) _rec.startPreview();
  }

  void _onRecorder() {
    final pos = _rec.position;
    if (!_follow || !_mapReady || pos == null) return;
    final zoom = _map.camera.zoom < 14 ? 16.0 : _map.camera.zoom;
    _map.move(LatLng(pos.latitude, pos.longitude), zoom);
  }

  Future<void> _start() async {
    final err = await _rec.ensurePermission();
    if (!mounted) return;
    if (err != null) {
      setState(() => _permError = err);
      return;
    }
    setState(() {
      _permError = null;
      _follow = true;
    });
    await _rec.start(_settings.activity);
  }

  Future<void> _finish() async {
    final t = _rec.track;
    if (t == null) return;
    final controller = TextEditingController(text: t.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar atividade'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Nome'),
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('Descartar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Continuar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (!mounted || result == null) return;

    if (result == 'discard') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Descartar atividade?'),
          content: const Text('Os dados gravados serão apagados.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Descartar')),
          ],
        ),
      );
      if (ok == true) await _rec.discard();
      return;
    }

    final saved = await _rec.finish(name: controller.text);
    if (!mounted || saved?.id == null) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TrackDetailScreen(trackId: saved!.id!)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_rec, _settings]),
      builder: (context, _) {
        final style = _settings.style;
        final pos = _rec.position;
        return Stack(
          children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: pos == null
                    ? _fallback
                    : LatLng(pos.latitude, pos.longitude),
                initialZoom: pos == null ? 5 : 16,
                maxZoom: 19,
                onMapReady: () => _mapReady = true,
                onPositionChanged: (camera, hasGesture) {
                  if (hasGesture && _follow) setState(() => _follow = false);
                },
              ),
              children: [
                ...baseMapLayers(style),
                PolylineLayer(
                  polylines: [
                    for (final s in _rec.segments)
                      if (s.length >= 2)
                        Polyline(
                          points: s,
                          strokeWidth: 6,
                          color: Theme.of(context).colorScheme.primary,
                          borderStrokeWidth: 2,
                          borderColor: Colors.white,
                        ),
                  ],
                ),
                if (pos != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: LatLng(pos.latitude, pos.longitude),
                      width: 24,
                      height: 24,
                      child: const PositionDot(),
                    ),
                  ]),
                mapAttribution(style),
              ],
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    _GpsChip(position: pos),
                    const SizedBox(width: 8),
                    if (_rec.state == RecState.paused)
                      const _StatusChip(
                          icon: Icons.pause, text: 'Pausado'),
                    if (_rec.autoPaused)
                      const _StatusChip(
                          icon: Icons.pause_circle_outline,
                          text: 'Pausa automática'),
                    const Spacer(),
                    if (!_follow)
                      FloatingActionButton.small(
                        heroTag: 'recenter',
                        onPressed: () {
                          setState(() => _follow = true);
                          _onRecorder();
                        },
                        child: const Icon(Icons.my_location),
                      ),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: _Panel(
                permError: _permError,
                onRetryPermission: _permError != null &&
                        _permError!.contains('configurações')
                    ? () => Geolocator.openAppSettings()
                    : _initGps,
                onStart: _start,
                onFinish: _finish,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.permError,
    required this.onRetryPermission,
    required this.onStart,
    required this.onFinish,
  });

  final String? permError;
  final VoidCallback onRetryPermission;
  final VoidCallback onStart;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final rec = Recorder.instance;
    final settings = Settings.instance;
    final scheme = Theme.of(context).colorScheme;

    Widget body;
    if (rec.state == RecState.idle) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (permError != null) ...[
            Text(permError!, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onRetryPermission,
              icon: const Icon(Icons.location_on),
              label: const Text('Permitir localização'),
            ),
            const SizedBox(height: 12),
          ],
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final a in Activity.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      avatar: Icon(a.icon, size: 20),
                      label: Text(a.label),
                      selected: settings.activity == a,
                      onSelected: (_) => settings.setActivity(a),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 112,
            height: 112,
            child: FilledButton(
              onPressed: onStart,
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                textStyle: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800),
              ),
              child: const Text('INICIAR'),
            ),
          ),
        ],
      );
    } else {
      final usesSpeed = rec.track!.activity.usesSpeed;
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatTile(
              label: 'Distância',
              value: fmtKm(rec.stats.distance),
              unit: 'km',
              big: true),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              StatTile(label: 'Em movimento', value: fmtDuration(rec.movingTime)),
              usesSpeed
                  ? StatTile(
                      label: 'Velocidade',
                      value: fmtSpeed(rec.position?.speed ?? 0),
                      unit: 'km/h')
                  : StatTile(
                      label: 'Ritmo médio',
                      value: fmtPace(rec.pace),
                      unit: '/km'),
              StatTile(
                  label: 'Subida',
                  value: rec.stats.elevation.gain.round().toString(),
                  unit: 'm'),
            ],
          ),
          const SizedBox(height: 4),
          Text('Tempo total ${fmtDuration(rec.elapsed)}',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _RoundButton(
                icon: rec.state == RecState.recording
                    ? Icons.pause
                    : Icons.play_arrow,
                label: rec.state == RecState.recording ? 'Pausar' : 'Retomar',
                color: scheme.primary,
                onTap: rec.state == RecState.recording
                    ? rec.pause
                    : rec.resume,
              ),
              _RoundButton(
                icon: Icons.stop,
                label: 'Segure para\nfinalizar',
                color: scheme.error,
                onLongPress: onFinish,
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Segure o botão para finalizar.'),
                    duration: Duration(seconds: 2),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return SafeArea(
      top: false,
      child: Card(
        margin: const EdgeInsets.all(12),
        color: scheme.surface.withOpacity(0.96),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: SizedBox(width: double.infinity, child: body),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            onLongPress: onLongPress,
            child: SizedBox(
              width: 80,
              height: 80,
              child: Icon(icon, color: Colors.white, size: 40),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _GpsChip extends StatelessWidget {
  const _GpsChip({required this.position});

  final Position? position;

  @override
  Widget build(BuildContext context) {
    final acc = position?.accuracy;
    final (Color c, String t) = acc == null
        ? (Colors.grey, 'Buscando GPS')
        : acc <= 10
            ? (Colors.green, 'GPS ótimo')
            : acc <= Recorder.maxAccuracy
                ? (Colors.orange, 'GPS ok')
                : (Colors.red, 'GPS fraco');
    return _StatusChip(icon: Icons.gps_fixed, text: t, color: c);
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: scheme.surface.withOpacity(0.92),
        borderRadius: BorderRadius.circular(20),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: color ?? scheme.primary),
            const SizedBox(width: 6),
            Text(text, style: Theme.of(context).textTheme.labelMedium),
          ]),
        ),
      ),
    );
  }
}
