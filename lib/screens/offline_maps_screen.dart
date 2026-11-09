import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/region.dart';
import '../services/database.dart';
import '../services/settings.dart';
import '../services/tile_cache.dart';
import '../utils/format.dart';
import 'download_area_screen.dart';

class OfflineMapsScreen extends StatefulWidget {
  const OfflineMapsScreen({super.key});

  @override
  State<OfflineMapsScreen> createState() => _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends State<OfflineMapsScreen> {
  final _db = AppDatabase.instance;
  List<Region> _regions = [];
  int? _size;

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
    final r = await _db.regions();
    final s = await TileCache.instance.sizeBytes();
    if (mounted) {
      setState(() {
        _regions = r;
        _size = s;
      });
    }
  }

  /// Minas Gerais inteiro em visão geral (zoom 6 a 11, ~100 MB).
  static final _mgBounds = LatLngBounds(const LatLng(-22.93, -51.05), const LatLng(-14.23, -39.85));

  Future<void> _downloadMg() async {
    final style = Settings.instance.style;
    final total = TileCache.countTiles(_mgBounds, 6, 11);
    final progress = ValueNotifier<(int, int)>((0, 0));
    var cancelled = false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Baixando Minas Gerais'),
        content: ValueListenableBuilder<(int, int)>(
          valueListenable: progress,
          builder: (_, v, __) => Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: v.$1 / total),
            const SizedBox(height: 12),
            Text('${v.$1} de $total blocos${v.$2 > 0 ? ' · ${v.$2} falharam' : ''}'),
            const SizedBox(height: 4),
            const Text('Pode levar alguns minutos. Use Wi‑Fi.', style: TextStyle(fontSize: 12)),
          ]),
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
      bounds: _mgBounds,
      minZoom: 6,
      maxZoom: 11,
      onProgress: (d, t, f) => progress.value = (d, f),
      isCancelled: () => cancelled,
    );
    if (!mounted || cancelled) return;
    Navigator.of(context).pop();
    await _db.insertRegion(Region(
      name: 'Minas Gerais (visão geral)',
      styleId: style.id,
      south: _mgBounds.south,
      west: _mgBounds.west,
      north: _mgBounds.north,
      east: _mgBounds.east,
      minZoom: 6,
      maxZoom: 11,
      tiles: total - failed,
      createdAt: DateTime.now(),
    ));
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar mapas offline?'),
        content: const Text(
            'Todas as áreas baixadas serão removidas. Suas atividades não serão afetadas.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true) return;
    await TileCache.instance.clear();
    await _db.deleteAllRegions();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Mapas offline')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DownloadAreaScreen())),
        icon: const Icon(Icons.download),
        label: const Text('Baixar área'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
        children: [
          Card(
            color: scheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.info_outline),
                    SizedBox(width: 8),
                    Text('Antes de sair para a trilha',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                      'Busque o lugar pelo nome e baixe a área. Sem sinal, o mapa '
                      'continua funcionando e o GPS grava normalmente. '
                      'Tudo grátis, sem limite de regiões.'),
                  const SizedBox(height: 8),
                  Text(
                      'Estilo atual: ${Settings.instance.style.name}  ·  '
                      'Espaço usado: ${_size == null ? '...' : fmtBytes(_size!)}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Text('🗺️', style: TextStyle(fontSize: 28)),
              title: const Text('Pacote Minas Gerais'),
              subtitle: const Text(
                  'O estado inteiro em visão geral (~100 MB). Para o detalhe das trilhas, '
                  'baixe a área da trilha ou o entorno de uma rota.'),
              trailing: FilledButton(onPressed: _downloadMg, child: const Text('Baixar')),
            ),
          ),
          if (_regions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('Nenhuma área baixada ainda.',
                  textAlign: TextAlign.center),
            ),
          for (final r in _regions)
            Card(
              color: scheme.surfaceContainerHighest,
              child: ListTile(
                leading: const Icon(Icons.map),
                title: Text(r.name),
                subtitle: Text(
                    '${r.tiles} blocos · zoom até ${r.maxZoom} · ${fmtDate(r.createdAt)}'),
              ),
            ),
          if (_regions.isNotEmpty || (_size ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextButton.icon(
                onPressed: _clear,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Apagar todos os mapas offline'),
              ),
            ),
        ],
      ),
    );
  }
}
