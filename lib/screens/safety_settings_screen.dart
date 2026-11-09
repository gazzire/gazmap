import 'package:flutter/material.dart';

import '../models/extra.dart';
import '../services/database.dart';
import '../services/safety.dart';
import '../services/settings.dart';

/// Contatos de emergência, ficha médica e opções de segurança.
class SafetySettingsScreen extends StatefulWidget {
  const SafetySettingsScreen({super.key});

  @override
  State<SafetySettingsScreen> createState() => _SafetySettingsScreenState();
}

class _SafetySettingsScreenState extends State<SafetySettingsScreen> {
  final _safety = SafetyService.instance;
  final _s = Settings.instance;

  Future<void> _editContact([EmergencyContact? c]) async {
    final name = TextEditingController(text: c?.name ?? '');
    final phone = TextEditingController(text: c?.phone ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(c == null ? 'Novo contato' : 'Editar contato'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nome'),
              textCapitalization: TextCapitalization.words),
          TextField(
              controller: phone,
              decoration: const InputDecoration(
                  labelText: 'Celular com DDD', hintText: '31 99999-9999'),
              keyboardType: TextInputType.phone),
        ]),
        actions: [
          if (c != null)
            TextButton(
                onPressed: () async {
                  await AppDatabase.instance.deleteContact(c.id!);
                  if (ctx.mounted) Navigator.pop(ctx, false);
                },
                child: const Text('Excluir')),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true) return;
    if (name.text.trim().isEmpty || !EmergencyContact.isValid(phone.text)) {
      _snack('Informe um nome e um celular válido (com DDD).');
      return;
    }
    final contact = c ?? EmergencyContact(name: '', phone: '');
    contact
      ..name = name.text.trim()
      ..phone = EmergencyContact.normalize(phone.text);
    await AppDatabase.instance.saveContact(contact);
    final err = await _safety.ensureSmsPermission();
    if (err != null) _snack(err);
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _test() async {
    final n = await _safety.sendTest();
    _snack(n == _safety.contacts.length
        ? 'SMS de teste entregue para todos os contatos.'
        : 'Entregue para $n de ${_safety.contacts.length}. Os demais ficam na fila.');
  }

  Future<void> _text(String key, String label, {String hint = ''}) async {
    final c = TextEditingController(text: _s.str(key));
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
            controller: c,
            autofocus: true,
            maxLength: 120,
            decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Salvar')),
        ],
      ),
    );
    if (v != null) await _s.setStr(key, v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Segurança')),
      body: ListenableBuilder(
        listenable: Listenable.merge([_safety, _s]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const _H('Contatos de emergência'),
            for (final c in _safety.contacts)
              ListTile(
                leading: const Icon(Icons.person),
                title: Text(c.name),
                subtitle: Text(c.phone),
                trailing: const Icon(Icons.edit),
                onTap: () => _editContact(c),
              ),
            if (_safety.contacts.length < 5)
              ListTile(
                leading: const Icon(Icons.person_add),
                title: const Text('Adicionar contato'),
                subtitle: const Text('Até 5 contatos recebem os SMS de SOS'),
                onTap: _editContact,
              ),
            if (_safety.contacts.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.sms),
                title: const Text('Enviar SMS de teste'),
                subtitle: const Text('Confirma que os números estão certos'),
                onTap: _test,
              ),
            const _H('Ficha de emergência'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Aparece na tela de SOS para quem for te socorrer. Fica só no seu celular.',
                  style: TextStyle(fontSize: 12)),
            ),
            _F('Seu nome', _s.ownerName, () => _text('ownerName', 'Seu nome')),
            _F('Tipo sanguíneo', _s.bloodType, () => _text('bloodType', 'Tipo sanguíneo', hint: 'O+')),
            _F('Alergias', _s.allergies, () => _text('allergies', 'Alergias')),
            _F('Remédios em uso', _s.medications, () => _text('medications', 'Remédios em uso')),
            _F('Observações', _s.healthNotes, () => _text('healthNotes', 'Observações')),
            const _H('Alertas automáticos'),
            SwitchListTile(
              title: const Text('Avisar contatos com bateria em 15%'),
              subtitle: const Text('Envia sua última posição antes do celular desligar'),
              value: _s.batteryAlert,
              onChanged: (v) => _s.setFlag('batteryAlert', v),
            ),
            SwitchListTile(
              title: const Text('Alerta de pôr do sol'),
              subtitle: const Text('Avisa se não der tempo de voltar antes de escurecer'),
              value: _s.sunsetAlert,
              onChanged: (v) => _s.setFlag('sunsetAlert', v),
            ),
            ListTile(
              title: const Text('Detecção de imobilidade'),
              subtitle: const Text('Pergunta "Você está bem?" se ficar parado'),
              trailing: DropdownButton<int>(
                value: [0, 10, 20, 30, 45, 60].contains(_s.immobilityMinutes)
                    ? _s.immobilityMinutes
                    : 20,
                items: [
                  for (final m in [0, 10, 20, 30, 45, 60])
                    DropdownMenuItem(value: m, child: Text(m == 0 ? 'Desligada' : '$m min')),
                ],
                onChanged: (v) => _s.setNum('immobilityMin', v!),
              ),
            ),
            ListTile(
              title: const Text('Tolerância do Plano de trilha'),
              subtitle: const Text('Tempo extra após o horário de volta'),
              trailing: DropdownButton<int>(
                value: [15, 30, 60, 90, 120].contains(_s.planMarginMinutes)
                    ? _s.planMarginMinutes
                    : 30,
                items: [
                  for (final m in [15, 30, 60, 90, 120])
                    DropdownMenuItem(value: m, child: Text('$m min')),
                ],
                onChanged: (v) => _s.setNum('planMarginMin', v!),
              ),
            ),
            ListTile(
              title: const Text('Reenvio do SOS'),
              subtitle: const Text('Com a posição atualizada'),
              trailing: DropdownButton<int>(
                value: [5, 10, 15, 30].contains(_s.sosResendMinutes) ? _s.sosResendMinutes : 10,
                items: [
                  for (final m in [5, 10, 15, 30])
                    DropdownMenuItem(value: m, child: Text('a cada $m min')),
                ],
                onChanged: (v) => _s.setNum('sosResendMin', v!),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _H extends StatelessWidget {
  const _H(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text,
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
      );
}

class _F extends StatelessWidget {
  const _F(this.label, this.value, this.onTap);
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(label),
        subtitle: Text(value.isEmpty ? 'Toque para preencher' : value),
        trailing: const Icon(Icons.edit, size: 18),
        onTap: onTap,
      );
}
