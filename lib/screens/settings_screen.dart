import 'package:flutter/material.dart';

import '../services/settings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Settings.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ListView(
          children: [
            const _Header('Gravação'),
            SwitchListTile(
              title: const Text('Avisos por voz'),
              subtitle: const Text('Distância, tempo e ritmo a cada km'),
              value: s.voice,
              onChanged: s.setVoice,
            ),
            SwitchListTile(
              title: const Text('Pausa automática'),
              subtitle: const Text('Indica quando você está parado'),
              value: s.autoPause,
              onChanged: s.setAutoPause,
            ),
            const _Header('Mapa'),
            for (final st in [MapStyle.topo, MapStyle.osm])
              RadioListTile<String>(
                title: Text(st.name),
                value: st.id,
                groupValue: s.styleId,
                onChanged: (v) => s.setStyle(v!),
              ),
            RadioListTile<String>(
              title: const Text('Servidor próprio'),
              subtitle: Text(s.customUrl.isEmpty
                  ? 'Ex.: https://seusite.com.br/tiles/{z}/{x}/{y}.png'
                  : s.customUrl),
              value: 'custom',
              groupValue: s.styleId,
              onChanged: (_) => _editUrl(context, s),
            ),
            const _Header('Sobre'),
            const ListTile(
              leading: Icon(Icons.terrain),
              title: Text('GAZMAP 0.1.0'),
              subtitle: Text(
                  'Software livre (GPL v3). Gratuito para sempre, sem anúncios '
                  'e sem conta. Seus dados ficam no seu celular.\n'
                  'github.com/gazzire/gazmap'),
            ),
            const ListTile(
              leading: Icon(Icons.map_outlined),
              title: Text('Dados de mapa'),
              subtitle: Text('© Colaboradores do OpenStreetMap · OpenTopoMap'),
            ),
            const ListTile(
              leading: Icon(Icons.battery_alert_outlined),
              title: Text('Dica de bateria'),
              subtitle: Text(
                  'Se a gravação parar com a tela apagada, desative a otimização '
                  'de bateria para o GAZMAP nas configurações do Android.'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editUrl(BuildContext context, Settings s) async {
    final c = TextEditingController(text: s.customUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Servidor de mapas'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(
              hintText: 'https://.../{z}/{x}/{y}.png'),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('Usar')),
        ],
      ),
    );
    if (url == null) return;
    if (!url.contains('{z}') || !url.contains('{x}') || !url.contains('{y}')) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('O endereço precisa conter {z}, {x} e {y}.')));
      }
      return;
    }
    await s.setCustomUrl(url);
    await s.setStyle('custom');
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text,
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700)),
      );
}
