
import 'package:flutter/services.dart';

/// Ponte para as funções nativas do Android (MainActivity.kt).
class NativeBridge {
  NativeBridge._();

  static const _ch = MethodChannel('gazmap/native');

  /// Envia SMS em segundo plano. Retorna true se a operadora confirmou o envio.
  static Future<bool> sendSms(String phone, String text) async {
    try {
      return await _ch.invokeMethod<bool>(
              'sendSms', {'phone': phone, 'text': text}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> torch(bool on) async {
    try {
      return await _ch.invokeMethod<bool>('torch', {'on': on}) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Padrão em ms: [espera, vibra, espera, vibra, ...].
  static Future<void> vibrate(List<int> pattern) async {
    try {
      await _ch.invokeMethod<bool>('vibrate', {'pattern': pattern});
    } catch (_) {}
  }

  static Future<void> beep(int ms) async {
    try {
      await _ch.invokeMethod<bool>('beep', {'ms': ms});
    } catch (_) {}
  }

  /// Abre o seletor de arquivos do Android e devolve (nome, bytes).
  static Future<List<(String, Uint8List)>> pickFiles() async {
    try {
      final r = await _ch.invokeMethod<List<Object?>>('pickFiles');
      return [
        for (final e in r ?? const [])
          if (e is Map && e['bytes'] is Uint8List)
            ((e['name'] ?? 'arquivo').toString(), e['bytes'] as Uint8List)
      ];
    } catch (_) {
      return [];
    }
  }
}
