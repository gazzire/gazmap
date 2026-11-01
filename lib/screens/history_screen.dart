import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/database.dart';
import '../utils/format.dart';
import 'track_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _db = AppDatabase.instance;
  List<Track>? _tracks;

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
    final t = await _db.finishedTracks();
    if (mounted) setState(() => _tracks = t);
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _tracks;
    return Scaffold(
      appBar: AppBar(title: const Text('Atividades')),
      body: tracks == null
          ? const Center(child: CircularProgressIndicator())
          : tracks.isEmpty
              ? const _Empty()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  children: [
                    _MonthSummary(tracks: tracks),
                    for (final t in tracks) _TrackCard(track: t),
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
  const _TrackCard({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = track;
    final metric = t.activity.usesSpeed
        ? '${fmtSpeed(avgSpeed(t.distance, t.movingMs))} km/h'
        : '${fmtPace(paceSecPerKm(t.distance, t.movingMs))} /km';
    return Card(
      color: scheme.surfaceContainerHighest,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TrackDetailScreen(trackId: t.id!))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                child: Icon(t.activity.icon),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(fmtDate(t.startedAt),
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 6),
                    Text(
                      '${fmtKm(t.distance)} km  ·  '
                      '${fmtDuration(Duration(milliseconds: t.movingMs))}  ·  '
                      '$metric  ·  ↑${t.gain.round()} m',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
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
