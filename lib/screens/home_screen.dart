import 'package:flutter/material.dart';

import '../services/safety.dart';
import 'history_screen.dart';
import 'offline_maps_screen.dart';
import 'record_screen.dart';
import 'routes_screen.dart';
import 'settings_screen.dart';
import 'sos_screen.dart';

/// Aba atual (permite que outras telas levem o usuário para "Gravar").
final ValueNotifier<int> homeTab = ValueNotifier(0);

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _pages = [
    RecordScreen(),
    HistoryScreen(),
    RoutesScreen(),
    OfflineMapsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: homeTab,
      builder: (context, index, _) => Stack(
        children: [
          Scaffold(
            body: IndexedStack(index: index, children: _pages),
            bottomNavigationBar: NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => homeTab.value = i,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.radio_button_checked), label: 'Gravar'),
                NavigationDestination(icon: Icon(Icons.format_list_bulleted), label: 'Atividades'),
                NavigationDestination(icon: Icon(Icons.route), label: 'Rotas'),
                NavigationDestination(
                    icon: Icon(Icons.download_for_offline_outlined),
                    selectedIcon: Icon(Icons.download_for_offline),
                    label: 'Mapas'),
                NavigationDestination(icon: Icon(Icons.tune), label: 'Ajustes'),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: SafetyService.instance,
            builder: (context, _) => SafetyService.instance.checkInDeadline == null
                ? const SizedBox.shrink()
                : const Positioned.fill(child: CheckInOverlay()),
          ),
        ],
      ),
    );
  }
}
