import 'package:flutter/material.dart';

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
