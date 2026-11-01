import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';

/// Estilo de mapa (servidor de tiles raster XYZ).
class MapStyle {
  const MapStyle({
    required this.id,
    required this.name,
    required this.url,
    required this.maxNativeZoom,
    required this.attribution,
  });

  final String id;
  final String name;
  final String url;
  final int maxNativeZoom;
  final String attribution;

  static const topo = MapStyle(
    id: 'topo',
    name: 'Topográfico (curvas de nível)',
    url: 'https://a.tile.opentopomap.org/{z}/{x}/{y}.png',
    maxNativeZoom: 17,
    attribution: '© OpenStreetMap · SRTM · OpenTopoMap (CC-BY-SA)',
  );

  static const osm = MapStyle(
    id: 'osm',
    name: 'Ruas (OpenStreetMap)',
    url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    maxNativeZoom: 19,
    attribution: '© OpenStreetMap',
  );

  static MapStyle custom(String url) => MapStyle(
        id: 'custom',
        name: 'Servidor próprio',
        url: url,
        maxNativeZoom: 18,
        attribution: '© OpenStreetMap',
      );
}

class Settings extends ChangeNotifier {
  Settings._();
  static final Settings instance = Settings._();

  late SharedPreferences _prefs;

  String _styleId = 'topo';
  String customUrl = '';
  bool voice = true;
  bool autoPause = true;
  Activity activity = Activity.trilha;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _styleId = _prefs.getString('style') ?? 'topo';
    customUrl = _prefs.getString('customUrl') ?? '';
    voice = _prefs.getBool('voice') ?? true;
    autoPause = _prefs.getBool('autoPause') ?? true;
    activity = Activity.fromName(_prefs.getString('activity'));
  }

  String get styleId => _styleId;

  MapStyle get style {
    switch (_styleId) {
      case 'osm':
        return MapStyle.osm;
      case 'custom':
        return customUrl.contains('{z}')
            ? MapStyle.custom(customUrl)
            : MapStyle.topo;
      default:
        return MapStyle.topo;
    }
  }

  Future<void> setStyle(String id) async {
    _styleId = id;
    await _prefs.setString('style', id);
    notifyListeners();
  }

  Future<void> setCustomUrl(String url) async {
    customUrl = url.trim();
    await _prefs.setString('customUrl', customUrl);
    notifyListeners();
  }

  Future<void> setVoice(bool v) async {
    voice = v;
    await _prefs.setBool('voice', v);
    notifyListeners();
  }

  Future<void> setAutoPause(bool v) async {
    autoPause = v;
    await _prefs.setBool('autoPause', v);
    notifyListeners();
  }

  Future<void> setActivity(Activity a) async {
    activity = a;
    await _prefs.setString('activity', a.name);
    notifyListeners();
  }
}
