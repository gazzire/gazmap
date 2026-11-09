import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/extra.dart';
import '../models/track.dart';
import '../services/database.dart';
import '../services/group.dart';
import '../services/heading.dart';
import '../services/live.dart';
import '../services/navigation.dart';
import '../services/recorder.dart';
import '../services/safety.dart';
import '../services/settings.dart';
import '../utils/format.dart';
import '../widgets/base_map.dart';
import '../widgets/powered_by.dart';
import '../widgets/waypoint_sheet.dart';
import 'group_screen.dart';
import 'offline_maps_screen.dart';
import 'safety_settings_screen.dart';
import 'sos_screen.dart';
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

  /// Mapa gira para a direção em que você está virado (como app de carro).
  bool _headingUp = false;
  String? _permError;
  final List<Waypoint> _waypoints = [];

  // Centro inicial: Brasil. Substituído pela posição real assim que houver GPS.
  static const _fallback = LatLng(-19.92, -43.94);

  @override
  void initState() {
    super.initState();
    _rec.addListener(_onRecorder);
    HeadingService.instance
      ..attach()
      ..addListener(_onRecorder);
    _initGps();
  }

  @override
  void dispose() {
    _rec.removeListener(_onRecorder);
    HeadingService.instance
      ..removeListener(_onRecorder)
      ..detach();
    super.dispose();
  }

  /// Alterna: livre → seguir (norte para cima) → seguir na direção → norte.
  void _cycleMapMode() {
    setState(() {
      if (!_follow) {
        _follow = true;
        _headingUp = false;
      } else if (!_headingUp) {
        _headingUp = true;
      } else {
        _headingUp = false;
      }
    });
    if (!_headingUp && _mapReady) {
      _map.rotate(0);
    }
    _onRecorder();
  }

  Future<void> _chooseMapStyle() async {
    final s = _settings;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListenableBuilder(
          listenable: s,
          builder: (ctx, _) => Column(mainAxisSize: MainAxisSize.min, children: [
            const ListTile(
              title: Text('Tipo de mapa', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('Os mapas offline são baixados por tipo. Ao trocar, '
                  'baixe de novo as áreas que vai usar sem internet.'),
            ),
            for (final (id, name, icon) in [
              ('topo', 'Topográfico (curvas de nível)', Icons.terrain),
              ('osm', 'Ruas (OpenStreetMap)', Icons.map),
              if (s.customUrl.contains('{z}')) ('custom', 'Servidor próprio', Icons.dns),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(name),
                trailing: s.styleId == id ? const Icon(Icons.check_circle, color: Color(0xFF22C55E)) : null,
                onTap: () {
                  s.setStyle(id);
                  Navigator.pop(ctx);
                },
              ),
          ]),
        ),
      ),
    );
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
    final center = LatLng(pos.latitude, pos.longitude);
    final h = HeadingService.instance.heading;
    if (_headingUp && h != null) {
      _map.moveAndRotate(center, zoom, -h);
    } else {
      _map.move(center, zoom);
    }
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
    _waypoints.clear();
    await _rec.start(_settings.activity);
    RouteNavigator.instance.startPending();
    await _checkOfflineMap();
  }

  /// Avisa se não há mapa offline baixado para o local atual.
  Future<void> _checkOfflineMap() async {
    final p = _rec.position;
    if (p == null) return;
    final regions = await AppDatabase.instance.regions();
    final covered = regions.any((r) =>
        p.latitude >= r.south && p.latitude <= r.north &&
        p.longitude >= r.west && p.longitude <= r.east && r.maxZoom >= 13);
    if (covered || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      content: const Text('Você está sem mapa offline detalhado para esta área.'),
      action: SnackBarAction(
        label: 'Baixar',
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const OfflineMapsScreen())),
      ),
    ));
  }

  Future<void> _pickPlan() async {
    final safety = SafetyService.instance;
    if (safety.contacts.isEmpty) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const SafetySettingsScreen()));
      if (safety.contacts.isEmpty) return;
    }
    if (!mounted) return;
    final now = DateTime.now();
    final t = await showTimePicker(
      context: context,
      helpText: 'Horário previsto de volta',
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 3))),
    );
    if (t == null) return;
    var ret = DateTime(now.year, now.month, now.day, t.hour, t.minute);
    if (ret.isBefore(now)) ret = ret.add(const Duration(days: 1));
    setState(() => safety.pendingPlanReturn = ret);
  }

  Future<void> _markPoint() async {
    final p = _rec.position;
    if (p == null) return;
    final w = await showWaypointSheet(context,
        lat: p.latitude, lon: p.longitude, trackId: _rec.track?.id);
    if (w != null) setState(() => _waypoints.add(w));
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
      listenable: Listenable.merge([
        _rec,
        _settings,
        SafetyService.instance,
        RouteNavigator.instance,
        GroupService.instance,
        LiveShare.instance,
        HeadingService.instance,
      ]),
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
                  if (hasGesture && _follow) {
                    setState(() {
                      _follow = false;
                      _headingUp = false;
                    });
                  }
                },
              ),
              children: [
                ...baseMapLayers(style),
                if (RouteNavigator.instance.points.length > 1)
                  PolylineLayer(polylines: [
                    Polyline(
                      points: RouteNavigator.instance.points,
                      strokeWidth: 7,
                      color: const Color(0xFF1E88E5).withValues(alpha: 0.75),
                    ),
                  ]),
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
                MarkerLayer(markers: [
                  for (final w in _waypoints)
                    Marker(
                      point: w.latLng,
                      rotate: true,
                      width: 30,
                      height: 30,
                      child: Text(w.kind.emoji, style: const TextStyle(fontSize: 22)),
                    ),
                  for (final m in GroupService.instance.myGroup)
                    if (m.pos != null)
                      Marker(
                        point: m.pos!,
                        rotate: true,
                        width: 90,
                        height: 44,
                        child: Column(children: [
                          const Icon(Icons.person_pin_circle, color: Color(0xFF7C3AED), size: 26),
                          Text(m.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                  if (RouteNavigator.instance.ghostPosition != null)
                    Marker(
                      point: RouteNavigator.instance.ghostPosition!,
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.8),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  if (pos != null)
                    Marker(
                      point: LatLng(pos.latitude, pos.longitude),
                      width: 40,
                      height: 40,
                      child: HeadingArrow(heading: HeadingService.instance.heading),
                    ),
                ]),
              ],
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 58),
                child: mapAttribution(style, alignment: Alignment.topRight),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(runSpacing: 6, children: [
                        _GpsChip(position: pos),
                        if (_rec.gpsLost && _rec.steps > 0)
                          const _StatusChip(
                              icon: Icons.directions_walk,
                              text: 'Sem GPS: estimando pelos passos',
                              color: Colors.orange),
                        if (_rec.state == RecState.paused)
                          const _StatusChip(icon: Icons.pause, text: 'Pausado'),
                        if (_rec.autoPaused)
                          const _StatusChip(
                              icon: Icons.pause_circle_outline, text: 'Pausa automática'),
                        if (SafetyService.instance.sunset != null)
                          _StatusChip(
                              icon: Icons.wb_twilight,
                              text: 'Pôr do sol ${fmtDate(SafetyService.instance.sunset!).split(' ').last}',
                              color: Colors.deepOrange),
                        if (SafetyService.instance.planReturn != null)
                          _StatusChip(
                              icon: Icons.schedule,
                              text: 'Volta ${fmtDate(SafetyService.instance.planReturn!).split(' ').last}'),
                        if (GroupService.instance.active)
                          _StatusChip(
                              icon: Icons.groups,
                              text: '${GroupService.instance.group} (${GroupService.instance.myGroup.length})',
                              color: const Color(0xFF7C3AED)),
                        if (LiveShare.instance.active)
                          const _StatusChip(icon: Icons.podcasts, text: 'Ao vivo', color: Colors.red),
                      ]),
                    ),
],
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 92, right: 12),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    FloatingActionButton(
                    heroTag: 'sos',
                    backgroundColor: const Color(0xFFE5484D),
                    foregroundColor: Colors.white,
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const SosScreen())),
                    child: const Text('SOS', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                    const SizedBox(height: 10),
                    FloatingActionButton.small(
                      heroTag: 'layers',
                      tooltip: 'Tipo de mapa',
                      onPressed: _chooseMapStyle,
                      child: const Icon(Icons.layers),
                    ),
                    const SizedBox(height: 6),
                    FloatingActionButton.small(
                      heroTag: 'mode',
                      tooltip: !_follow
                          ? 'Centralizar em mim'
                          : _headingUp
                              ? 'Norte para cima'
                              : 'Girar mapa na direção',
                      backgroundColor: _headingUp ? const Color(0xFF1E88E5) : null,
                      foregroundColor: _headingUp ? Colors.white : null,
                      onPressed: _cycleMapMode,
                      child: Icon(!_follow
                          ? Icons.my_location
                          : _headingUp
                              ? Icons.navigation
                              : Icons.explore),
                    ),
                  ]),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: _Panel(
                onPlan: _pickPlan,
                onMarkPoint: _markPoint,
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
    required this.onPlan,
    required this.onMarkPoint,
    required this.permError,
    required this.onRetryPermission,
    required this.onStart,
    required this.onFinish,
  });

  final VoidCallback onPlan;
  final VoidCallback onMarkPoint;
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
          Row(
            children: [
              for (final a in Activity.values)
                Expanded(
                  child: _ActivityOption(
                    activity: a,
                    selected: settings.activity == a,
                    onTap: () => settings.setActivity(a),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _IdleOptions(onPlan: onPlan),
          const SizedBox(height: 12),
          _StartButton(onTap: onStart),
          const SizedBox(height: 14),
          const PoweredBy(),
        ],
      );
    } else {
      final usesSpeed = rec.track!.activity.usesSpeed;
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatTile(
              label: 'Distância',
              value: fmtKm(rec.distance),
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
          if (rec.steps > 0)
            Text('${rec.steps} passos · ${rec.cadence} passos/min',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          const _NavInfo(),
          const SizedBox(height: 8),
          Wrap(alignment: WrapAlignment.center, spacing: 4, children: [
            TextButton.icon(
              onPressed: RouteNavigator.instance.startBacktrack,
              icon: const Icon(Icons.u_turn_left, size: 18),
              label: const Text('Voltar por onde vim'),
            ),
            TextButton.icon(
              onPressed: onMarkPoint,
              icon: const Icon(Icons.add_location_alt, size: 18),
              label: const Text('Marcar ponto'),
            ),
            TextButton.icon(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const GroupScreen())),
              icon: const Icon(Icons.groups, size: 18),
              label: const Text('Grupo'),
            ),
            if (LiveShare.instance.active)
              TextButton.icon(
                onPressed: LiveShare.instance.shareLink,
                icon: const Icon(Icons.share, size: 18),
                label: const Text('Link ao vivo'),
              ),
          ]),
          const SizedBox(height: 8),
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
        color: scheme.surface.withValues(alpha: 0.96),
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
        color: scheme.surface.withValues(alpha: 0.92),
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

class _ActivityOption extends StatelessWidget {
  const _ActivityOption({
    required this.activity,
    required this.selected,
    required this.onTap,
  });

  final Activity activity;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? Colors.white : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: selected ? scheme.primary : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(activity.icon, size: 26, color: selected ? fg : scheme.primary),
                const SizedBox(height: 4),
                Text(
                  activity.label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: scheme.primary.withValues(alpha: 0.5),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 108,
          height: 108,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.play_arrow_rounded, size: 46, color: Colors.white),
              Text(
                'INICIAR',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IdleOptions extends StatelessWidget {
  const _IdleOptions({required this.onPlan});
  final VoidCallback onPlan;

  @override
  Widget build(BuildContext context) {
    final safety = SafetyService.instance;
    final nav = RouteNavigator.instance;
    final plan = safety.pendingPlanReturn;
    final route = nav.pendingRoute;
    final ghost = nav.pendingGhost;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        InputChip(
          avatar: const Icon(Icons.schedule, size: 18),
          label: Text(plan == null
              ? 'Plano de trilha'
              : 'Volta às ${fmtDate(plan).split(' ').last}'),
          onPressed: onPlan,
          onDeleted: plan == null
              ? null
              : () {
                  safety.pendingPlanReturn = null;
                  nav.refresh();
                },
        ),
        if (route != null || ghost != null)
          InputChip(
            avatar: Icon(ghost != null ? Icons.emoji_events : Icons.route, size: 18),
            label: Text(
              ghost != null ? 'Contra o recorde' : route!.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onDeleted: () {
              nav.pendingRoute = null;
              nav.pendingGhost = null;
              nav.pendingGhostPoints = null;
              nav.refresh();
            },
          ),
        ActionChip(
          avatar: Icon(Icons.groups,
              size: 18,
              color: GroupService.instance.active ? const Color(0xFF7C3AED) : null),
          label: Text(GroupService.instance.active ? GroupService.instance.group : 'Grupo'),
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const GroupScreen())),
        ),
      ],
    );
  }
}

class _NavInfo extends StatelessWidget {
  const _NavInfo();

  @override
  Widget build(BuildContext context) {
    final nav = RouteNavigator.instance;
    if (!nav.active && nav.ghostDeltaSec == null) return const SizedBox.shrink();
    final eta = nav.eta;
    final g = nav.ghostDeltaSec;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(children: [
        if (nav.offRoute)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: const Color(0xFFE5484D), borderRadius: BorderRadius.circular(10)),
            child: Text('Fora da rota: ${nav.distToRoute.round()} m',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        if (nav.active)
          Text(
            '${nav.backtracking ? 'Voltando · ' : ''}Faltam ${fmtKm(nav.remaining)} km'
            ' · ↑${nav.remainingGain.round()} m'
            '${eta != null ? ' · chegada ~${fmtDate(DateTime.now().add(eta)).split(' ').last}' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1E88E5)),
          ),
        if (g != null)
          Text(
            g > 0
                ? '+${fmtDuration(Duration(seconds: g))} atrás do recorde'
                : '${fmtDuration(Duration(seconds: -g))} à frente do recorde',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: g > 0 ? const Color(0xFFE5484D) : const Color(0xFF22C55E)),
          ),
      ]),
    );
  }
}
