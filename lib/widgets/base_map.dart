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

/// Seta da posição que gira conforme a direção (bússola ou GPS).
/// Sem direção conhecida, mostra o ponto azul.
class HeadingArrow extends StatelessWidget {
  const HeadingArrow({super.key, required this.heading});

  final double? heading;

  @override
  Widget build(BuildContext context) {
    final h = heading;
    if (h == null) {
      return const Center(child: SizedBox(width: 24, height: 24, child: PositionDot()));
    }
    return Transform.rotate(
      angle: h * math.pi / 180,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black38)],
        ),
        child: const Icon(Icons.navigation, color: Color(0xFF1E88E5), size: 34),
      ),
    );
  }
}
