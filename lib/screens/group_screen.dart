import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../services/group.dart';
import '../services/recorder.dart';
import '../services/settings.dart';
import '../utils/format.dart';

/// Modo Grupo: sem internet, por Bluetooth e Wi‑Fi Direct.
class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  final _g = GroupService.instance;
  late final _name = TextEditingController(text: Settings.instance.groupName);
  bool _busy = false;

  Future<void> _join() async {
    setState(() => _busy = true);
    final err = await _g.join(_name.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  String _dist(GroupMember m) {
    final p = Recorder.instance.position;
    if (p == null || m.pos == null) return 'posição desconhecida';
    final d = const Distance().as(LengthUnit.Meter, LatLng(p.latitude, p.longitude), m.pos!);
    return d < 1000 ? '${d.round()} m' : '${fmtKm(d)} km';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Modo Grupo')),
      body: ListenableBuilder(
        listenable: Listenable.merge([_g, Settings.instance]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (Settings.instance.ownerName.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Preencha seu nome em Ajustes → Segurança'),
                  subtitle: Text('É o nome que os outros verão no grupo.'),
                ),
              ),
            if (!_g.active) ...[
              const Text(
                'Funciona sem internet: os celulares se conectam por Bluetooth e Wi‑Fi Direct. '
                'Todos devem usar o mesmo nome de grupo. Pode haver vários grupos na mesma trilha: '
                'cada um vê só os seus membros, mas um SOS chega a todos por perto.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                maxLength: 30,
                decoration: const InputDecoration(
                    labelText: 'Nome do grupo', hintText: 'Ex.: Turma do Cipó'),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _join,
                icon: const Icon(Icons.groups),
                label: const Text('Entrar no grupo'),
              ),
            ] else ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.groups),
                  title: Text(_g.group, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(_g.status),
                  trailing: TextButton(onPressed: _g.leave, child: const Text('Sair')),
                ),
              ),
              const SizedBox(height: 8),
              Text('Membros por perto', style: Theme.of(context).textTheme.titleMedium),
              if (_g.myGroup.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Ninguém do grupo ao alcance ainda.'),
                ),
              for (final m in _g.myGroup)
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(m.name),
                  subtitle: Text('${_dist(m)} · visto às ${fmtDate(m.lastSeen).split(' ').last}'),
                ),
              const SizedBox(height: 12),
              Text('Ranking do grupo · pontos GAZ', style: Theme.of(context).textTheme.titleMedium),
              const Text('10 pontos por km · 1 a cada 10 m de subida · 1 a cada 1.000 passos',
                  style: TextStyle(fontSize: 12)),
              for (final (i, m) in _g.ranking.indexed)
                ListTile(
                  dense: true,
                  leading: Text(
                      switch (i) { 0 => '🥇', 1 => '🥈', 2 => '🥉', _ => '${i + 1}º' },
                      style: const TextStyle(fontSize: 22)),
                  title: Text('${m.name}${m.finished ? ' 🏁' : ''}',
                      style: TextStyle(fontWeight: m.name == 'Você' ? FontWeight.w800 : null)),
                  subtitle: Text('${fmtKm(m.distance)} km · ↑${m.gain.round()} m · ${m.steps} passos'),
                  trailing: Text('${m.points} pts',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                ),
              if (_g.arrivals.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Pódio de chegada', style: Theme.of(context).textTheme.titleMedium),
                for (final (i, n) in _g.arrivals.indexed)
                  ListTile(
                    dense: true,
                    leading: Text(switch (i) { 0 => '🥇', 1 => '🥈', 2 => '🥉', _ => '🏁' },
                        style: const TextStyle(fontSize: 22)),
                    title: Text(n),
                  ),
              ],
              const SizedBox(height: 12),
              Text('Mensagens rápidas', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final q in GroupService.quickMessages)
                  ActionChip(label: Text(q), onPressed: () => _g.sendMessage(q)),
              ]),
              const SizedBox(height: 16),
              for (final msg in _g.messages.take(30))
                ListTile(
                  dense: true,
                  leading: Icon(msg.sos ? Icons.sos : Icons.chat_bubble_outline,
                      color: msg.sos ? Colors.red : null),
                  title: Text('${msg.from}: ${msg.text}'),
                  subtitle: Text(fmtDate(msg.at).split(' ').last),
                ),
            ],
            const Divider(height: 32),
            SwitchListTile(
              title: const Text('Retransmitir SOS por SMS'),
              subtitle: const Text(
                  'Se alguém por perto pedir socorro e você tiver sinal, seu celular avisa os contatos dessa pessoa.'),
              value: Settings.instance.groupRelaySos,
              onChanged: (v) => Settings.instance.setFlag('groupRelaySos', v),
            ),
          ],
        ),
      ),
    );
  }
}
