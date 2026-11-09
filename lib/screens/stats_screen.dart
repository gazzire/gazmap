import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/track.dart';
import '../services/database.dart';
import '../services/settings.dart';
import '../utils/format.dart';
import '../widgets/base_map.dart';

class Achievement {
  const Achievement(this.emoji, this.title, this.description, this.done);
  final String emoji;
  final String title;
  final String description;
  final bool done;
}

/// Conquistas pessoais calculadas do seu histórico (tudo local).
List<Achievement> achievementsFor(List<Track> all) {
  final km = all.fold<double>(0, (s, t) => s + t.distance) / 1000;
  final gain = all.fold<double>(0, (s, t) => s + t.gain);
  final steps = all.fold<int>(0, (s, t) => s + t.steps);
  final longest = all.fold<double>(0, (m, t) => t.distance > m ? t.distance : m) / 1000;
  final biggestClimb = all.fold<double>(0, (m, t) => t.gain > m ? t.gain : m);
  final early = all.any((t) => t.startedAt.hour < 6);
  final kinds = all.map((t) => t.activity).toSet();
  return [
    Achievement('👣', 'Primeiros passos', 'Grave sua primeira atividade', all.isNotEmpty),
    Achievement('🔟', 'Dezena', '10 atividades gravadas', all.length >= 10),
    Achievement('💯', 'Centenário', '100 km somados', km >= 100),
    Achievement('🌎', 'Mil quilômetros', '1.000 km somados', km >= 1000),
    Achievement('🥾', 'Trilha longa', 'Uma atividade com 20 km ou mais', longest >= 20),
    Achievement('⛰️', 'Escalador', '1.000 m de subida numa atividade', biggestClimb >= 1000),
    Achievement('🏔️', 'Everest', '8.849 m de subida somados', gain >= 8849),
    Achievement('🚶', 'Milhão de passos', '1.000.000 de passos', steps >= 1000000),
    Achievement('🌅', 'Madrugador', 'Começar uma atividade antes das 6h', early),
    Achievement('🎯', 'Completo', 'Fazer as 4 atividades', kinds.length == Activity.values.length),
  ];
}

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  List<Track> _tracks = [];
  List<List<LatLng>> _heat = [];
  int _year = DateTime.now().year;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = AppDatabase.instance;
    final t = await db.finishedTracks();
    final pts = await db.allTrackPoints(every: 4);
    if (!mounted) return;
    setState(() {
      _tracks = t;
      _heat = [for (final l in pts) [for (final p in l) LatLng(p.lat, p.lon)]];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final year = _tracks.where((t) => t.startedAt.year == _year).toList();
    final km = year.fold<double>(0, (s, t) => s + t.distance);
    final ms = year.fold<int>(0, (s, t) => s + t.movingMs);
    final gain = year.fold<double>(0, (s, t) => s + t.gain);
    final steps = year.fold<int>(0, (s, t) => s + t.steps);
    final byMonth = List<double>.filled(12, 0);
    for (final t in year) {
      byMonth[t.startedAt.month - 1] += t.distance / 1000;
    }
    final maxMonth = byMonth.fold<double>(0, (m, v) => v > m ? v : m);
    final longest = year.isEmpty ? null : (year.toList()..sort((a, b) => b.distance.compareTo(a.distance))).first;
    final years = {..._tracks.map((t) => t.startedAt.year), DateTime.now().year}.toList()..sort();
    final ach = achievementsFor(_tracks);
    final style = Settings.instance.style;
    const months = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];

    return Scaffold(
      appBar: AppBar(title: const Text('Retrospectiva e conquistas')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(children: [
                  Text('Ano', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: _year,
                    items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
                    onChanged: (v) => setState(() => _year = v!),
                  ),
                ]),
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Seu $_year na trilha',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 12),
                      Wrap(spacing: 24, runSpacing: 12, children: [
                        StatTile(label: 'distância', value: fmtKm(km), unit: 'km'),
                        StatTile(label: 'atividades', value: '${year.length}'),
                        StatTile(label: 'em movimento', value: fmtDuration(Duration(milliseconds: ms))),
                        StatTile(label: 'subida', value: '${gain.round()}', unit: 'm'),
                        if (steps > 0) StatTile(label: 'passos', value: '$steps'),
                      ]),
                      if (longest != null) ...[
                        const SizedBox(height: 12),
                        Text('Maior atividade: ${longest.name} (${fmtKm(longest.distance)} km)'),
                      ],
                      if (gain > 0)
                        Text('Você subiu o equivalente a ${(gain / 8849).toStringAsFixed(2).replaceAll('.', ',')} Everest(s).'),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Quilômetros por mês', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SizedBox(
                  height: 120,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    for (var i = 0; i < 12; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                            Container(
                              height: maxMonth == 0 ? 0 : 90 * byMonth[i] / maxMonth,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(months[i], style: const TextStyle(fontSize: 11)),
                          ]),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 16),
                Text('Mapa de calor (todas as atividades)', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SizedBox(
                  height: 280,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: _heat.isEmpty
                        ? const Center(child: Text('Grave atividades para ver seu mapa de calor.'))
                        : FlutterMap(
                            options: MapOptions(
                              initialCenter: _heat.first.first,
                              initialZoom: 10,
                              initialCameraFit: CameraFit.bounds(
                                bounds: LatLngBounds.fromPoints(_heat.expand((e) => e).toList()),
                                padding: const EdgeInsets.all(20),
                                maxZoom: 15,
                              ),
                            ),
                            children: [
                              ...baseMapLayers(style),
                              PolylineLayer(polylines: [
                                for (final l in _heat)
                                  if (l.length > 1)
                                    Polyline(
                                        points: l,
                                        strokeWidth: 4,
                                        color: const Color(0xFFFF3D00).withValues(alpha: 0.35)),
                              ]),
                              mapAttribution(style),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Conquistas (${ach.where((a) => a.done).length}/${ach.length})',
                    style: Theme.of(context).textTheme.titleMedium),
                for (final a in ach)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Opacity(
                      opacity: a.done ? 1 : 0.3,
                      child: Text(a.emoji, style: const TextStyle(fontSize: 30)),
                    ),
                    title: Text(a.title, style: TextStyle(fontWeight: a.done ? FontWeight.w800 : null)),
                    subtitle: Text(a.description),
                    trailing: a.done ? const Icon(Icons.check_circle, color: Color(0xFF22C55E)) : null,
                  ),
              ],
            ),
    );
  }
}
