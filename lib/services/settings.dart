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
    attribution: '© OpenStreetMap · OpenTopoMap',
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

  /// Avisos por voz: 'distance' (a cada X km) ou 'time' (a cada X min).
  String voiceMode = 'distance';
  double voiceKm = 1;
  int voiceMinutes = 15;
  bool sayDistance = true;
  bool sayTime = true;
  bool sayPace = true;
  bool sayGain = false;

  static const voiceKmOptions = [0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 20.0];
  static const voiceMinuteOptions = [5, 10, 15, 30, 60];
  Activity activity = Activity.trilha;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _styleId = _prefs.getString('style') ?? 'topo';
    customUrl = _prefs.getString('customUrl') ?? '';
    voice = _prefs.getBool('voice') ?? true;
    autoPause = _prefs.getBool('autoPause') ?? true;
    activity = Activity.fromName(_prefs.getString('activity'));
    voiceMode = _prefs.getString('voiceMode') ?? 'distance';
    voiceKm = _prefs.getDouble('voiceKm') ?? 1;
    voiceMinutes = _prefs.getInt('voiceMinutes') ?? 15;
    sayDistance = _prefs.getBool('sayDistance') ?? true;
    sayTime = _prefs.getBool('sayTime') ?? true;
    sayPace = _prefs.getBool('sayPace') ?? true;
    sayGain = _prefs.getBool('sayGain') ?? false;
  }

  Future<void> setVoiceMode(String mode) async {
    voiceMode = mode;
    await _prefs.setString('voiceMode', mode);
    notifyListeners();
  }

  Future<void> setVoiceKm(double km) async {
    voiceKm = km;
    await _prefs.setDouble('voiceKm', km);
    notifyListeners();
  }

  Future<void> setVoiceMinutes(int min) async {
    voiceMinutes = min;
    await _prefs.setInt('voiceMinutes', min);
    notifyListeners();
  }

  /// key: 'sayDistance' | 'sayTime' | 'sayPace' | 'sayGain'
  Future<void> setSay(String key, bool v) async {
    switch (key) {
      case 'sayDistance':
        sayDistance = v;
      case 'sayTime':
        sayTime = v;
      case 'sayPace':
        sayPace = v;
      case 'sayGain':
        sayGain = v;
    }
    await _prefs.setBool(key, v);
    notifyListeners();
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
