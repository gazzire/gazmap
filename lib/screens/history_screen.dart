import 'package:flutter/material.dart';

import '../models/extra.dart';
import '../models/track.dart';
import '../services/database.dart';
import '../services/formats.dart';
import '../services/gpx.dart';
import '../services/native.dart';
import '../services/navigation.dart';
import '../services/records.dart';
import '../utils/format.dart';
import 'home_screen.dart';
import 'stats_screen.dart';
import 'track_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _db = AppDatabase.instance;
  List<Track>? _tracks;
  final _search = TextEditingController();
  Activity? _activity;
  String? _month; // 'aaaa-mm'
  final Set<int> _selected = {};

  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _db.changes.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _db.changes.removeListener(_load);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final t = await _db.finishedTracks();
    if (mounted) setState(() => _tracks = t);
  }

  static String _monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
  static const _monthNames = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
  static String _monthLabel(String k) =>
      '${_monthNames[int.parse(k.substring(5)) - 1]}/${k.substring(0, 4)}';

  List<Track> get _filtered {
    final q = _search.text.trim().toLowerCase();
    return (_tracks ?? const <Track>[])
        .where((t) =>
            (q.isEmpty || t.name.toLowerCase().contains(q)) &&
            (_activity == null || t.activity == _activity) &&
            (_month == null || _monthKey(t.startedAt) == _month))
        .toList();
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  // ---------- Importar ----------

  Future<void> _import() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(
            title: Text('Importar arquivo GPX, TCX ou FIT', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('Arquivos exportados de outros apps, relógios e sites de trilha, inclusive .fit.gz.'),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Trilha feita'),
            subtitle: const Text('Entra no seu histórico, com tempo e estatísticas'),
            onTap: () => Navigator.pop(ctx, 'activity'),
          ),
          ListTile(
            leading: const Icon(Icons.route),
            title: const Text('Rota para seguir'),
            subtitle: const Text('Vai para Rotas, para navegar com alerta de fora da rota'),
            onTap: () => Navigator.pop(ctx, 'route'),
          ),
        ]),
      ),
    );
    if (kind == null) return;
    final files = await NativeBridge.pickFiles();
    if (files.isEmpty) return;
    if (kind == 'route') {
      final n = await importRoutes(files);
      _snack(n == 0 ? 'Nenhuma rota reconhecida.' : '$n ${n == 1 ? 'rota importada' : 'rotas importadas'} em Rotas.');
      return;
    }
    final n = await importActivities(files);
    if (n > 0) {
      _snack('$n ${n == 1 ? 'trilha importada' : 'trilhas importadas'}.');
      return;
    }
    // Sem horários: só serve como rota.
    final r = await importRoutes(files);
    _snack(r > 0
        ? 'O arquivo não tem horários, então entrou como rota (aba Rotas).'
        : 'Nenhuma trilha reconhecida. Use GPX, TCX ou FIT.');
  }

  // ---------- Exportar ----------

  Future<FileFormat?> _pickFormat(String title) => showModalBottomSheet<FileFormat>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
            for (final (f, sub) in [
              (FileFormat.gpx, 'O mais compatível com apps e sites de trilha'),
              (FileFormat.tcx, 'Relógios e plataformas de treino'),
              (FileFormat.fit, 'Formato nativo de relógios e ciclocomputadores'),
            ])
              ListTile(
                leading: const Icon(Icons.description),
                title: Text(f.label),
                subtitle: Text(sub),
                onTap: () => Navigator.pop(ctx, f),
              ),
          ]),
        ),
      );

  Future<void> _exportTracks(List<Track> list) async {
    if (list.isEmpty) return;
    final f = await _pickFormat(list.length == 1 ? 'Exportar "${list.first.name}"' : 'Exportar ${list.length} trilhas');
    if (f == null) return;
    final items = <(Track, List<TrackPoint>)>[];
    for (final t in list) {
      items.add((t, await _db.points(t.id!)));
    }
    await shareActivities(items, f);
    setState(_selected.clear);
  }

  void _startExportSelection() {
    final list = _filtered;
    if (list.isEmpty) return;
    setState(() => _selected.add(list.first.id!));
    _snack('Marque as trilhas que quer exportar e toque em Exportar.');
  }

  // ---------- Ações de uma trilha ----------

  Future<void> _action(Track t, String a) async {
    switch (a) {
      case 'open':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TrackDetailScreen(trackId: t.id!)));
      case 'export':
        await _exportTracks([t]);
      case 'route':
        await _db.insertRoute(SavedRoute.fromTrack(t, await _db.points(t.id!)));
        _snack('Salva em Rotas.');
      case 'race':
        final rec = await Records.forTrack(t);
        final best = rec?.best ?? t;
        RouteNavigator.instance
          ..pendingGhost = best
          ..pendingGhostPoints = await _db.points(best.id!)
          ..pendingRoute = null
          ..refresh();
        homeTab.value = 0;
        _snack('Pronto: toque em INICIAR para correr contra o recorde.');
      case 'rename':
        final c = TextEditingController(text: t.name);
        final name = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Renomear'),
            content: TextField(controller: c, autofocus: true, maxLength: 80),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Salvar')),
            ],
          ),
        );
        if (name != null && name.trim().isNotEmpty) {
          t.name = name.trim();
          await _db.updateTrack(t);
        }
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Excluir "${t.name}"?'),
            content: const Text('Essa ação não pode ser desfeita.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
            ],
          ),
        );
        if (ok == true) await _db.deleteTrack(t.id!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _tracks;
    final list = _filtered;
    final months = {...?tracks?.map((t) => _monthKey(t.startedAt))}.toList()..sort((a, b) => b.compareTo(a));
    return Scaffold(
      appBar: _selecting
          ? AppBar(
              leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear)),
              title: Text('${_selected.length} ${_selected.length == 1 ? 'selecionada' : 'selecionadas'}'),
              actions: [
                IconButton(
                  tooltip: 'Selecionar todas',
                  icon: const Icon(Icons.select_all),
                  onPressed: () => setState(() => _selected.addAll(list.map((t) => t.id!))),
                ),
                IconButton(
                  tooltip: 'Exportar',
                  icon: const Icon(Icons.ios_share),
                  onPressed: () => _exportTracks(
                      (tracks ?? const <Track>[]).where((t) => _selected.contains(t.id)).toList()),
                ),
              ],
            )
          : AppBar(
              title: const Text('Trilhas'),
              actions: [
                IconButton(
                  tooltip: 'Retrospectiva e conquistas',
                  icon: const Icon(Icons.emoji_events),
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const StatsScreen())),
                ),
              ],
            ),
      body: tracks == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              children: [
                Row(children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _import,
                      icon: const Icon(Icons.file_download),
                      label: const Text('Importar trilha'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: tracks.isEmpty ? null : _startExportSelection,
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Exportar'),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                if (tracks.isEmpty)
                  const _Empty()
                else ...[
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Buscar trilha pelo nome',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => setState(_search.clear),
                            ),
                      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      ChoiceChip(
                        label: const Text('Todas'),
                        selected: _activity == null,
                        onSelected: (_) => setState(() => _activity = null),
                      ),
                      for (final a in Activity.values)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: ChoiceChip(
                            avatar: Icon(a.icon, size: 16),
                            label: Text(a.label),
                            selected: _activity == a,
                            onSelected: (_) => setState(() => _activity = _activity == a ? null : a),
                          ),
                        ),
                      const SizedBox(width: 8),
                      DropdownButton<String?>(
                        value: _month,
                        hint: const Text('Todos os meses'),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('Todos os meses')),
                          for (final m in months) DropdownMenuItem<String?>(value: m, child: Text(_monthLabel(m))),
                        ],
                        onChanged: (v) => setState(() => _month = v),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  _MonthSummary(tracks: tracks),
                  if (list.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Nenhuma trilha com esses filtros.', textAlign: TextAlign.center),
                    ),
                  for (final t in list)
                    _TrackCard(
                      track: t,
                      selecting: _selecting,
                      selected: _selected.contains(t.id),
                      onTap: () => _selecting
                          ? setState(() => _selected.contains(t.id) ? _selected.remove(t.id) : _selected.add(t.id!))
                          : _action(t, 'open'),
                      onLongPress: () => setState(() => _selected.add(t.id!)),
                      onAction: (a) => _action(t, a),
                    ),
                ],
              ],
            ),
    );
  }
}

class _MonthSummary extends StatelessWidget {
  const _MonthSummary({required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final month = tracks.where(
        (t) => t.startedAt.year == now.year && t.startedAt.month == now.month);
    final dist = month.fold<double>(0, (s, t) => s + t.distance);
    final ms = month.fold<int>(0, (s, t) => s + t.movingMs);
    final gain = month.fold<double>(0, (s, t) => s + t.gain);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Este mês',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Big('${fmtKm(dist)} km', 'distância'),
                _Big(fmtDuration(Duration(milliseconds: ms)), 'tempo'),
                _Big('${gain.round()} m', 'subida'),
                _Big('${month.length}', 'atividades'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Big extends StatelessWidget {
  const _Big(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        Text(label, style: t.labelSmall),
      ],
    );
  }
}

class _TrackCard extends StatelessWidget {
  const _TrackCard({
    required this.track,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onAction,
  });

  final Track track;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = track;
    final metric = t.activity.usesSpeed
        ? '${fmtSpeed(avgSpeed(t.distance, t.movingMs))} km/h'
        : '${fmtPace(paceSecPerKm(t.distance, t.movingMs))} /km';
    return Card(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(
            children: [
              selecting
                  ? Checkbox(value: selected, onChanged: (_) => onTap())
                  : CircleAvatar(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      child: Icon(t.activity.icon),
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(fmtDate(t.startedAt), style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text(
                      '${fmtKm(t.distance)} km  ·  '
                      '${fmtDuration(Duration(milliseconds: t.movingMs))}  ·  '
                      '$metric  ·  ↑${t.gain.round()} m',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              if (!selecting)
                PopupMenuButton<String>(
                  tooltip: 'Mais opções',
                  onSelected: onAction,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'export', child: ListTile(leading: Icon(Icons.ios_share), title: Text('Exportar (GPX, TCX, FIT)'))),
                    PopupMenuItem(value: 'route', child: ListTile(leading: Icon(Icons.route), title: Text('Salvar como rota'))),
                    PopupMenuItem(value: 'race', child: ListTile(leading: Icon(Icons.emoji_events), title: Text('Repetir contra o recorde'))),
                    PopupMenuItem(value: 'rename', child: ListTile(leading: Icon(Icons.edit), title: Text('Renomear'))),
                    PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Excluir'))),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terrain, size: 64),
            SizedBox(height: 12),
            Text('Nenhuma atividade ainda.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            SizedBox(height: 4),
            Text('Vá até "Gravar" e comece sua primeira trilha.',
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
