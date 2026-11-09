import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/heading.dart';
import '../services/navigation.dart';
import '../services/recorder.dart';
import '../services/safety.dart';
import '../services/settings.dart';
import '../utils/format.dart';

/// Indicadores disponíveis na tela "Só dados".
enum Metric {
  dist('Distância'),
  moving('Tempo em movimento'),
  total('Tempo total'),
  pace('Ritmo médio'),
  speed('Velocidade atual'),
  avgSpeed('Velocidade média'),
  gain('Subida'),
  loss('Descida'),
  alt('Altitude'),
  steps('Passos'),
  cadence('Cadência'),
  maxSpeed('Velocidade máxima'),
  remaining('Faltam (rota)'),
  eta('Chegada prevista'),
  ghost('Contra o recorde'),
  sunset('Pôr do sol'),
  battery('Bateria'),
  clock('Hora'),
  accuracy('Precisão do GPS'),
  direction('Direção'),
  coords('Coordenadas');

  const Metric(this.label);
  final String label;

  static const defaults = [dist, moving, pace, gain, steps, alt, sunset, remaining, ghost];

  /// Antes de iniciar: informações do lugar e do aparelho.
  static const idle = [direction, alt, accuracy, sunset, battery, clock, coords];

  static List<Metric> parse(String raw) {
    if (raw.isEmpty) return defaults;
    final out = <Metric>[];
    for (final n in raw.split(',')) {
      for (final m in Metric.values) {
        if (m.name == n) out.add(m);
      }
    }
    return out.isEmpty ? defaults : out;
  }

  /// (valor, unidade) ou null quando não se aplica agora.
  (String, String)? read() {
    final r = Recorder.instance;
    final nav = RouteNavigator.instance;
    final s = SafetyService.instance;
    final p = r.position;
    switch (this) {
      case dist:
        return (fmtKm(r.distance), 'km');
      case moving:
        return (fmtDuration(r.movingTime), '');
      case total:
        return (fmtDuration(r.elapsed), '');
      case pace:
        return (fmtPace(r.pace), '/km');
      case speed:
        return (fmtSpeed(p?.speed ?? 0), 'km/h');
      case avgSpeed:
        return (fmtSpeed(r.avgSpeedMps), 'km/h');
      case gain:
        return ('${r.stats.elevation.gain.round()}', 'm');
      case loss:
        return ('${r.stats.elevation.loss.round()}', 'm');
      case alt:
        return p == null ? null : ('${p.altitude.round()}', 'm');
      case steps:
        return r.steps == 0 ? null : ('${r.steps}', '');
      case cadence:
        return r.cadence == 0 ? null : ('${r.cadence}', 'passos/min');
      case maxSpeed:
        return (fmtSpeed(r.stats.maxSpeed), 'km/h');
      case remaining:
        return nav.active ? (fmtKm(nav.remaining), 'km') : null;
      case eta:
        final e = nav.eta;
        return nav.active && e != null
            ? (fmtDate(DateTime.now().add(e)).split(' ').last, '')
            : null;
      case ghost:
        final g = nav.ghostDeltaSec;
        if (g == null) return null;
        return (g > 0 ? '+${fmtDuration(Duration(seconds: g))}' : '-${fmtDuration(Duration(seconds: -g))}',
            g > 0 ? 'atrás' : 'à frente');
      case sunset:
        final ss = s.sunset;
        return ss == null ? null : (fmtDate(ss).split(' ').last, '');
      case battery:
        final b = s.batteryLevel;
        return b == null ? null : ('$b', '%');
      case clock:
        return (fmtDate(DateTime.now()).split(' ').last, '');
      case accuracy:
        return p == null ? null : ('${p.accuracy.round()}', 'm');
      case direction:
        final h = HeadingService.instance.heading;
        if (h == null) return null;
        const n = ['N', 'NE', 'L', 'SE', 'S', 'SO', 'O', 'NO'];
        return ('${n[((h + 22.5) % 360) ~/ 45]} ${h.round()}°', '');
      case coords:
        return p == null
            ? null
            : ('${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)}', '');
    }
  }
}

/// Tela cheia só com os números (sem mapa: gasta menos bateria).
class DataView extends StatelessWidget {
  const DataView({
    super.key,
    required this.onFinish,
    required this.onSos,
    required this.onToggleView,
    this.onStart,
  });

  /// Preenchido quando ainda não começou a gravar (mostra INICIAR).
  final VoidCallback? onStart;
  bool get _idle => onStart != null;

  final VoidCallback onFinish;
  final VoidCallback onSos;
  final VoidCallback onToggleView;

  Future<void> _editFields(BuildContext context) async {
    final s = Settings.instance;
    final chosen = Metric.parse(s.str('dataFields'));
    final order = [...chosen, ...Metric.values.where((m) => !chosen.contains(m))];
    final on = {...chosen};
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: Column(children: [
              const ListTile(
                title: Text('Números na tela', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('Marque o que quer ver e arraste para mudar a ordem.'),
              ),
              Expanded(
                child: ReorderableListView(
                  onReorder: (a, b) => set(() {
                    if (b > a) b--;
                    order.insert(b, order.removeAt(a));
                  }),
                  children: [
                    for (final m in order)
                      CheckboxListTile(
                        key: ValueKey(m),
                        value: on.contains(m),
                        title: Text(m.label),
                        secondary: const Icon(Icons.drag_handle),
                        onChanged: (v) => set(() => v == true ? on.add(m) : on.remove(m)),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      s.setStr('dataFields', order.where(on.contains).map((m) => m.name).join(','));
                      Navigator.pop(ctx);
                    },
                    child: const Text('Salvar'),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = Recorder.instance;
    final scheme = Theme.of(context).colorScheme;
    final metrics = _idle ? Metric.idle : Metric.parse(Settings.instance.str('dataFields'));
    final values = [
      for (final m in metrics)
        if (m.read() case final v?) (m, v),
    ];
    final main = values.isEmpty ? null : values.first;
    final rest = values.skip(1).toList();
    final nav = RouteNavigator.instance;

    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(children: [
              IconButton(
                tooltip: 'Trocar visualização',
                icon: const Icon(Icons.dashboard),
                onPressed: onToggleView,
              ),
              if (!_idle)
                IconButton(
                  tooltip: 'Escolher números',
                  icon: const Icon(Icons.tune),
                  onPressed: () => _editFields(context),
                ),
              if (_idle)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Text('Pronto para iniciar', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              const Spacer(),
              if (r.state == RecState.paused)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Text('PAUSADO', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE5484D)),
                onPressed: onSos,
                child: const Text('SOS', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ]),
          ),
          if (nav.offRoute)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFE5484D), borderRadius: BorderRadius.circular(12)),
              child: Text('FORA DA ROTA: ${nav.distToRoute.round()} m',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            ),
          if (main != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(children: [
                FittedBox(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                      text: main.$2.$1,
                      style: const TextStyle(
                          fontSize: 96, fontWeight: FontWeight.w900,
                          fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                    TextSpan(text: ' ${main.$2.$2}', style: TextStyle(fontSize: 28, color: scheme.onSurfaceVariant)),
                  ])),
                ),
                Text(main.$1.label.toUpperCase(),
                    style: TextStyle(letterSpacing: 2, color: scheme.onSurfaceVariant)),
              ]),
            ),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.6,
              children: [
                for (final (m, v) in rest)
                  Container(
                    decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
                    padding: const EdgeInsets.all(10),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      FittedBox(
                        child: Text.rich(TextSpan(children: [
                          TextSpan(
                              text: v.$1,
                              style: const TextStyle(
                                  fontSize: 38, fontWeight: FontWeight.w900,
                                  fontFeatures: [FontFeature.tabularFigures()])),
                          if (v.$2.isNotEmpty)
                            TextSpan(text: ' ${v.$2}', style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant)),
                        ])),
                      ),
                      Text(m.label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    ]),
                  ),
              ],
            ),
          ),
          if (_idle)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(children: [
                Wrap(spacing: 6, children: [
                  for (final act in Activity.values)
                    ChoiceChip(
                      avatar: Icon(act.icon, size: 18),
                      label: Text(act.label),
                      selected: Settings.instance.activity == act,
                      onSelected: (_) => Settings.instance.setActivity(act),
                    ),
                ]),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: FilledButton.icon(
                    onPressed: onStart,
                    icon: const Icon(Icons.play_arrow_rounded, size: 34),
                    label: const Text('INICIAR', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  ),
                ),
              ]),
            )
          else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(children: [
              Expanded(
                child: SizedBox(
                  height: 64,
                  child: FilledButton.icon(
                    onPressed: r.state == RecState.recording ? r.pause : r.resume,
                    icon: Icon(r.state == RecState.recording ? Icons.pause : Icons.play_arrow, size: 30),
                    label: Text(r.state == RecState.recording ? 'Pausar' : 'Retomar',
                        style: const TextStyle(fontSize: 18)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 64,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: scheme.error),
                    onLongPress: onFinish,
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Segure o botão para finalizar.'))),
                    icon: const Icon(Icons.stop, size: 30),
                    label: const Text('Segure p/ finalizar', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
