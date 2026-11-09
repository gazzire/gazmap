import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/recorder.dart';
import '../services/safety.dart';
import '../services/settings.dart';
import '../utils/format.dart';
import 'safety_settings_screen.dart';

/// Tela de emergência: segurar 3 s → contagem de 5 s → SMS para os contatos.
class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen>
    with SingleTickerProviderStateMixin {
  final _safety = SafetyService.instance;
  late final AnimationController _hold = AnimationController(
      vsync: this, duration: const Duration(seconds: 3))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _hold.reset();
        _safety.startCountdown();
      }
    });

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  Future<void> _call(String number) async {
    await launchUrl(Uri(scheme: 'tel', path: number));
  }

  Future<void> _whatsApp() async {
    final text = Uri.encodeComponent(_safety.sosText);
    await launchUrl(Uri.parse('https://wa.me/?text=$text'),
        mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_safety, Recorder.instance]),
      builder: (context, _) {
        if (_safety.screenFlash) {
          return GestureDetector(
            onTap: _safety.stopRescueSignal,
            child: Container(color: Colors.white),
          );
        }
        final s = _safety;
        return Scaffold(
          backgroundColor: const Color(0xFF1A0B0B),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            title: const Text('SOS'),
            actions: [
              IconButton(
                tooltip: 'Contatos e ficha',
                icon: const Icon(Icons.contacts),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const SafetySettingsScreen())),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (s.contacts.isEmpty)
                  _Warn(
                    text: 'Nenhum contato de emergência cadastrado. Cadastre pelo menos um.',
                    action: 'Cadastrar',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const SafetySettingsScreen())),
                  ),
                const SizedBox(height: 8),
                Center(child: _main(context)),
                const SizedBox(height: 24),
                _Coords(),
                const SizedBox(height: 20),
                const Text('Ligar para emergência',
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(children: [
                  _CallBtn('193', 'Bombeiros', () => _call('193')),
                  _CallBtn('192', 'SAMU', () => _call('192')),
                  _CallBtn('190', 'Polícia', () => _call('190')),
                ]),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                      padding: const EdgeInsets.all(14)),
                  onPressed: _whatsApp,
                  icon: const Icon(Icons.chat),
                  label: const Text('Enviar também pelo WhatsApp (com internet)'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                      padding: const EdgeInsets.all(14)),
                  onPressed: s.rescueSignal ? s.stopRescueSignal : s.startRescueSignal,
                  icon: Icon(s.rescueSignal ? Icons.flashlight_off : Icons.flashlight_on),
                  label: Text(s.rescueSignal
                      ? 'Parar sinal de resgate'
                      : 'Sinal de resgate (luz + som SOS)'),
                ),
                const SizedBox(height: 20),
                const _EmergencyCard(),
                const SizedBox(height: 16),
                const Text(
                  'Sem nenhum sinal de celular? Se o seu aparelho tiver SOS por satélite, '
                  'use-o pelas configurações de emergência do próprio celular. '
                  'Os SMS do GAZMAP ficam na fila e saem sozinhos quando o sinal voltar.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _main(BuildContext context) {
    final s = _safety;
    const red = Color(0xFFE5484D);
    switch (s.sos) {
      case SosState.idle:
        return Column(children: [
          GestureDetector(
            onLongPressStart: (_) => _hold.forward(),
            onLongPressEnd: (_) {
              if (_hold.status != AnimationStatus.completed) _hold.reverse();
            },
            child: AnimatedBuilder(
              animation: _hold,
              builder: (_, __) => SizedBox(
                width: 200,
                height: 200,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: _hold.value,
                      strokeWidth: 10,
                      color: Colors.white,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                  Container(
                    width: 170,
                    height: 170,
                    decoration: const BoxDecoration(color: red, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: const Text('SOS',
                        style: TextStyle(
                            color: Colors.white, fontSize: 52, fontWeight: FontWeight.w900)),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Segure por 3 segundos para pedir socorro',
              style: TextStyle(color: Colors.white, fontSize: 16)),
        ]);
      case SosState.countdown:
        return Column(children: [
          Text('${s.countdown}',
              style: const TextStyle(color: Colors.white, fontSize: 120, fontWeight: FontWeight.w900)),
          const Text('Enviando SOS…', style: TextStyle(color: Colors.white70, fontSize: 18)),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.white, foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18)),
            onPressed: s.cancelSos,
            child: const Text('CANCELAR', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
        ]);
      case SosState.active:
        final next = s.sosLastSentAt?.add(Duration(minutes: Settings.instance.sosResendMinutes));
        return Column(children: [
          const Icon(Icons.sos, color: red, size: 72),
          const Text('SOS ATIVO',
              style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(
            s.sosLastSentAt == null
                ? 'Enviando…'
                : 'SMS entregue a ${s.sosLastDelivered} de ${s.contacts.length} contatos às '
                    '${fmtDate(s.sosLastSentAt!).split(' ').last}.'
                    '${s.queued > 0 ? ' ${s.queued} na fila (sem sinal).' : ''}'
                    '${next != null ? '\nPróximo envio às ${fmtDate(next).split(' ').last}.' : ''}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onLongPress: s.cancelSos,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: const Text('Segure: ESTOU BEM, CANCELAR',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ]);
    }
  }
}

class _Coords extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = Recorder.instance.position;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white10, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        const Text('SUAS COORDENADAS', style: TextStyle(color: Colors.white54, letterSpacing: 2, fontSize: 12)),
        const SizedBox(height: 6),
        SelectableText(
          p == null
              ? 'Buscando GPS…'
              : '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}',
          style: const TextStyle(
              color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()]),
        ),
        if (p != null)
          Text('Precisão: ${p.accuracy.round()} m · Altitude: ${p.altitude.round()} m',
              style: const TextStyle(color: Colors.white54)),
      ]),
    );
  }
}

class _CallBtn extends StatelessWidget {
  const _CallBtn(this.number, this.label, this.onTap);
  final String number;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2A1515),
                padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: onTap,
            child: Column(children: [
              Text(number, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              Text(label, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ),
      );
}

class _Warn extends StatelessWidget {
  const _Warn({required this.text, required this.action, required this.onTap});
  final String text;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: const Color(0xFF4A3410), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.warning_amber, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white))),
          TextButton(onPressed: onTap, child: Text(action)),
        ]),
      );
}

class _EmergencyCard extends StatelessWidget {
  const _EmergencyCard();

  @override
  Widget build(BuildContext context) {
    final s = Settings.instance;
    final rows = <(String, String)>[
      ('Nome', s.ownerName),
      ('Tipo sanguíneo', s.bloodType),
      ('Alergias', s.allergies),
      ('Remédios', s.medications),
      ('Observações', s.healthNotes),
    ].where((r) => r.$2.isNotEmpty).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.badge, color: Color(0xFFE5484D)),
            SizedBox(width: 8),
            Text('FICHA DE EMERGÊNCIA',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
          ]),
          const SizedBox(height: 8),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '${r.$1}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: r.$2),
              ])),
            ),
        ],
      ),
    );
  }
}

/// Aviso "Você está bem?" sobreposto ao app (imobilidade ou atraso).
class CheckInOverlay extends StatefulWidget {
  const CheckInOverlay({super.key});

  @override
  State<CheckInOverlay> createState() => _CheckInOverlayState();
}

class _CheckInOverlayState extends State<CheckInOverlay> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = SafetyService.instance;
    final deadline = s.checkInDeadline;
    if (deadline == null) return const SizedBox.shrink();
    final left = deadline.difference(DateTime.now());
    return Material(
      color: Colors.black87,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.health_and_safety, color: Colors.white, size: 72),
              const SizedBox(height: 12),
              const Text('Você está bem?',
                  style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(
                s.checkInReason == 'atraso'
                    ? 'Já passou do horário de volta do seu Plano de trilha.'
                    : 'Você está parado há bastante tempo.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Sem resposta em ${left.inSeconds.clamp(0, 999)} s, seus contatos recebem um SOS.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF22C55E),
                      padding: const EdgeInsets.symmetric(vertical: 22)),
                  onPressed: s.confirmCheckIn,
                  child: const Text('ESTOU BEM',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
