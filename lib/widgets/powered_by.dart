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
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}
