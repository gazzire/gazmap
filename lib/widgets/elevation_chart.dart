import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Gráfico simples de altimetria: (distância em m, altitude em m).
class ElevationChart extends StatelessWidget {
  const ElevationChart({super.key, required this.profile});

  final List<(double, double)> profile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final eles = profile.map((e) => e.$2);
    final minE = eles.reduce(math.min);
    final maxE = eles.reduce(math.max);
    final style = Theme.of(context).textTheme.labelSmall;
    return SizedBox(
      height: 140,
      child: Row(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${maxE.round()} m', style: style),
              Text('${minE.round()} m', style: style),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: CustomPaint(
              painter: _ElevationPainter(
                profile: profile,
                minE: minE,
                maxE: maxE,
                line: scheme.primary,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ElevationPainter extends CustomPainter {
  _ElevationPainter({
    required this.profile,
    required this.minE,
    required this.maxE,
    required this.line,
  });

  final List<(double, double)> profile;
  final double minE, maxE;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    if (profile.length < 2) return;
    final maxD = profile.last.$1 <= 0 ? 1.0 : profile.last.$1;
    final range = math.max(maxE - minE, 10.0);
    Offset at((double, double) p) => Offset(
          p.$1 / maxD * size.width,
          size.height - (p.$2 - minE) / range * size.height * 0.9 - 4,
        );

    final path = Path()..moveTo(at(profile.first).dx, at(profile.first).dy);
    for (final p in profile.skip(1)) {
      final o = at(p);
      path.lineTo(o.dx, o.dy);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [line.withOpacity(0.45), line.withOpacity(0.02)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ElevationPainter old) =>
      old.profile != profile || old.line != line;
}
