import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/live.dart';
import 'services/navigation.dart';
import 'services/recorder.dart';
import 'services/safety.dart';
import 'services/settings.dart';
import 'services/tile_cache.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Settings.instance.load();
  await TileCache.instance.init();
  await Recorder.instance.recoverUnfinished();
  await SafetyService.instance.init();
  // Serviços que acompanham o gravador.
  RouteNavigator.instance;
  LiveShare.instance;
  runApp(const GazmapApp());
}

const brandOrange = Color(0xFFFF6B1A);

class GazmapApp extends StatelessWidget {
  const GazmapApp({super.key});

  ThemeData _theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(
      seedColor: brandOrange,
      brightness: b,
    ).copyWith(primary: brandOrange, onPrimary: Colors.white);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      cardTheme: const CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GAZMAP',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
