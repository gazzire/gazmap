import 'package:flutter/material.dart';

/// Atribuição de autoria. Deve ser preservada em versões modificadas
/// (termo adicional da GPL v3, seção 7(b) — veja o arquivo NOTICE).
const poweredByText = 'POWERED BY GAZIRE';

class PoweredBy extends StatelessWidget {
  const PoweredBy({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      poweredByText,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 8.5,
        letterSpacing: 1.6,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
      ),
    );
  }
}
