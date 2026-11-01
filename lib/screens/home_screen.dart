import 'package:flutter/material.dart';

import 'history_screen.dart';
import 'offline_maps_screen.dart';
import 'record_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _pages = [
    RecordScreen(),
    HistoryScreen(),
    OfflineMapsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.radio_button_checked), label: 'Gravar'),
          NavigationDestination(
              icon: Icon(Icons.format_list_bulleted), label: 'Atividades'),
          NavigationDestination(
              icon: Icon(Icons.download_for_offline_outlined),
              selectedIcon: Icon(Icons.download_for_offline),
              label: 'Mapas'),
          NavigationDestination(
              icon: Icon(Icons.tune), label: 'Ajustes'),
        ],
      ),
    );
  }
}
