import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../services/settings.dart';
import '../services/tile_cache.dart';

/// Camada de mapa padrão (com cache offline) + crédito obrigatório do OSM.
List<Widget> baseMapLayers(MapStyle style) => [
      TileLayer(
        urlTemplate: style.url,
        maxNativeZoom: style.maxNativeZoom,
        userAgentPackageName: 'br.com.gazire.gazmap',
        tileProvider: CachedTileProvider(style),
      ),
    ];

/// Crédito obrigatório dos dados de mapa, compacto e legível.
Widget mapAttribution(MapStyle style,
        {Alignment alignment = Alignment.bottomRight}) =>
    Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.all(6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          style.attribution,
          style: const TextStyle(fontSize: 9, color: Colors.black87),
        ),
      ),
    );

/// Marcador da posição atual.
class PositionDot extends StatelessWidget {
  const PositionDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E88E5),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black38)],
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.big = false,
  });

  final String label;
  final String value;
  final String? unit;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(
              text: value,
              style: (big ? t.displayMedium : t.headlineSmall)?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (unit != null)
              TextSpan(
                text: ' $unit',
                style: t.titleMedium?.copyWith(color: muted),
              ),
          ]),
          maxLines: 1,
        ),
        Text(label, style: t.labelMedium?.copyWith(color: muted)),
      ],
    );
  }
}

/// O ponto azul da sua posição É a seta: gira conforme a direção
/// (bússola parado, GPS em movimento) e projeta um facho à frente,
/// como no Google Maps. Sem direção, fica só o ponto.
class HeadingArrow extends StatelessWidget {
  const HeadingArrow({super.key, required this.heading});

  final double? heading;

  static const blue = Color(0xFF1E88E5);

  @override
  Widget build(BuildContext context) {
    final h = heading;
    final dot = Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: blue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black38)],
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.navigation, color: Colors.white, size: 15),
    );
    // Sem direção ainda: seta sem facho, até a bússola ou o GPS responderem.
    if (h == null) return Center(child: dot);
    return Transform.rotate(
      angle: h * math.pi / 180,
      child: Stack(alignment: Alignment.center, children: [
        const CustomPaint(size: Size(64, 64), painter: _BeamPainter()),
        dot,
      ]),
    );
  }
}

/// Facho de direção (cone azul translúcido apontando para cima).
class _BeamPainter extends CustomPainter {
  const _BeamPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    final paint = Paint()
      ..shader = RadialGradient(colors: [
        HeadingArrow.blue.withValues(alpha: 0.45),
        HeadingArrow.blue.withValues(alpha: 0.0),
      ]).createShader(rect);
    // 70° de abertura, centrado para cima (-90°).
    const sweep = 70 * math.pi / 180;
    canvas.drawArc(rect, -math.pi / 2 - sweep / 2, sweep, true, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
