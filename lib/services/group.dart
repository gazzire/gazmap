import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

import 'native.dart';
import 'recorder.dart';
import 'safety.dart';
import 'settings.dart';

class GroupMember {
  GroupMember(this.id, this.name, this.group);
  final String id;
  String name;
  String group;
  LatLng? pos;
  DateTime lastSeen = DateTime.now();

  // Gamificação: estatísticas da atividade atual
  double distance = 0;
  double gain = 0;
  int steps = 0;
  int movingMs = 0;
  bool finished = false;

  int get points => GroupService.pointsFor(distance, gain, steps);
  bool farWarned = false;
  bool lostWarned = false;
}

class GroupMessage {
  GroupMessage(this.from, this.text, this.at, {this.sos = false});
  final String from;
  final String text;
  final DateTime at;
  final bool sos;
}

/// Modo Grupo sem internet (Bluetooth + Wi‑Fi Direct, Google Nearby).
/// Mensagens "pulam" de celular em celular (mesh, até 6 saltos).
/// Cada grupo vê só os seus membros; o SOS atravessa todos os grupos.
class GroupService extends ChangeNotifier {
  GroupService._();
  static final GroupService instance = GroupService._();

  static const _serviceId = 'br.com.gazire.gazmap';
  static const _maxHops = 6;
  static const quickMessages = [
    'Esperem por mim',
    'Parada para água',
    'Peguei o caminho errado',
    'Tudo bem por aqui',
    'Vou voltar',
    'Preciso de ajuda',
  ];

  final _nearby = Nearby();
  final _rand = math.Random.secure();
  late final String deviceId = _makeId();

  bool active = false;
  String group = '';
  String status = '';
  final Map<String, String> _endpoints = {}; // endpointId -> deviceId
  final Map<String, GroupMember> members = {}; // deviceId -> membro (todos os grupos)
  final List<GroupMessage> messages = [];
  final Set<String> _seen = {};
  final Set<String> _relayedSos = {};
  Timer? _beacon;

  List<GroupMember> get myGroup =>
      members.values.where((m) => m.group == group).toList();

  /// Pontos GAZ: 10 por km, 1 a cada 10 m de subida, 1 a cada 1.000 passos.
  static int pointsFor(double meters, double gain, int steps) =>
      (meters / 100).round() + (gain / 10).round() + steps ~/ 1000;

  /// Ranking ao vivo do grupo, incluindo você.
  List<GroupMember> get ranking {
    final rec = Recorder.instance;
    final me = GroupMember(deviceId, 'Você', group)
      ..distance = rec.distance
      ..gain = rec.stats.elevation.gain
      ..steps = rec.steps
      ..movingMs = rec.stats.movingMs
      ..pos = rec.position == null ? null : LatLng(rec.position!.latitude, rec.position!.longitude);
    final all = [me, ...myGroup]..sort((a, b) => b.points.compareTo(a.points));
    return all;
  }

  /// Ordem de chegada (quem finalizou primeiro).
  final List<String> arrivals = [];

  String _makeId() {
    final saved = Settings.instance.str('deviceId');
    if (saved.isNotEmpty) return saved;
    const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
    final id = List.generate(8, (_) => chars[_rand.nextInt(chars.length)]).join();
    Settings.instance.setStr('deviceId', id);
    return id;
  }

  String get _myName =>
      Settings.instance.ownerName.isEmpty ? 'Sem nome' : Settings.instance.ownerName;

  String _clean(String s) => s.replaceAll('|', '/').trim();

  Future<String?> _permissions() async {
    final req = await [
      Permission.location,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.nearbyWifiDevices,
    ].request();
    if (req[Permission.location]?.isGranted != true) {
      return 'O Modo Grupo precisa da localização.';
    }
    final bt = [Permission.bluetoothAdvertise, Permission.bluetoothConnect, Permission.bluetoothScan];
    if (bt.any((p) => req[p]?.isPermanentlyDenied == true)) {
      return 'Libere "Dispositivos próximos" nas configurações do app.';
    }
    return null;
  }

  /// Entra (ou cria) um grupo pelo nome. Retorna erro ou null.
  Future<String?> join(String name) async {
    final g = _clean(name);
    if (g.isEmpty) return 'Dê um nome ao grupo.';
    final err = await _permissions();
    if (err != null) return err;
    if (active) await leave();
    group = g;
    await Settings.instance.setStr('groupName', g);
    final nick = '$g|${_clean(_myName)}|$deviceId';
    try {
      await _nearby.startAdvertising(
        nick,
        Strategy.P2P_CLUSTER,
        serviceId: _serviceId,
        onConnectionInitiated: _onInitiated,
        onConnectionResult: _onResult,
        onDisconnected: _onDisconnected,
      );
      await _nearby.startDiscovery(
        nick,
        Strategy.P2P_CLUSTER,
        serviceId: _serviceId,
        onEndpointFound: (id, epName, _) => _onFound(id, epName, nick),
        onEndpointLost: (_) {},
      );
    } catch (e) {
      return 'Não foi possível iniciar o Modo Grupo. Ative Bluetooth e localização.';
    }
    active = true;
    status = 'Procurando pessoas por perto…';
    SafetyService.instance.groupRelay = _broadcastSos;
    _beacon = Timer.periodic(const Duration(seconds: 20), (_) => _tick());
    _tick();
    notifyListeners();
    return null;
  }

  Future<void> leave() async {
    _beacon?.cancel();
    try {
      await _nearby.stopAdvertising();
      await _nearby.stopDiscovery();
      await _nearby.stopAllEndpoints();
    } catch (_) {}
    _endpoints.clear();
    members.clear();
    active = false;
    status = '';
    SafetyService.instance.groupRelay = null;
    notifyListeners();
  }

  // ---------- Conexões ----------

  void _onFound(String endpointId, String epName, String nick) {
    final parts = epName.split('|');
    if (parts.length != 3) return;
    final otherId = parts[2];
    // Só um dos lados pede a conexão, para evitar conflito.
    if (deviceId.compareTo(otherId) >= 0) return;
    _nearby
        .requestConnection(nick, endpointId,
            onConnectionInitiated: _onInitiated,
            onConnectionResult: _onResult,
            onDisconnected: _onDisconnected)
        .catchError((_) => false);
  }

  void _onInitiated(String endpointId, ConnectionInfo info) {
    final parts = info.endpointName.split('|');
    if (parts.length != 3) {
      _nearby.rejectConnection(endpointId).catchError((_) => false);
      return;
    }
    _endpoints[endpointId] = parts[2];
    final m = members.putIfAbsent(parts[2], () => GroupMember(parts[2], parts[1], parts[0]));
    m
      ..name = parts[1]
      ..group = parts[0]
      ..lastSeen = DateTime.now();
    _nearby
        .acceptConnection(endpointId, onPayLoadRecieved: _onPayload)
        .catchError((_) => false);
  }

  void _onResult(String endpointId, Status s) {
    if (s != Status.CONNECTED) _endpoints.remove(endpointId);
    _updateStatus();
    if (s == Status.CONNECTED) _tick();
  }

  void _onDisconnected(String endpointId) {
    _endpoints.remove(endpointId);
    _updateStatus();
  }

  void _updateStatus() {
    final n = myGroup.length;
    status = _endpoints.isEmpty
        ? 'Procurando pessoas por perto…'
        : '$n ${n == 1 ? 'pessoa' : 'pessoas'} do grupo por perto'
            '${_endpoints.length > n ? ' · ${_endpoints.length - n} de outros grupos' : ''}';
    notifyListeners();
  }

  // ---------- Mensagens (mesh) ----------

  String _msgId() => '$deviceId${DateTime.now().microsecondsSinceEpoch}${_rand.nextInt(999)}';

  void _send(Map<String, Object?> msg, {String? exceptEndpoint}) {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(msg)));
    for (final ep in _endpoints.keys.toList()) {
      if (ep == exceptEndpoint) continue;
      _nearby.sendBytesPayload(ep, bytes).catchError((_) {});
    }
  }

  void _onPayload(String endpointId, Payload payload) {
    final bytes = payload.bytes;
    if (payload.type != PayloadType.BYTES || bytes == null || bytes.length > 8192) return;
    Map<String, dynamic> m;
    try {
      m = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final id = m['id'] as String?;
    final from = m['from'] as String?;
    if (id == null || from == null || from == deviceId || !_seen.add(id)) return;
    if (_seen.length > 5000) _seen.clear();

    final name = (m['name'] as String? ?? '?').substring(0, math.min(40, (m['name'] as String? ?? '?').length));
    final grp = m['group'] as String? ?? '';
    final member = members.putIfAbsent(from, () => GroupMember(from, name, grp));
    member
      ..name = name
      ..group = grp
      ..lastSeen = DateTime.now()
      ..lostWarned = false;
    final lat = (m['lat'] as num?)?.toDouble(), lon = (m['lon'] as num?)?.toDouble();
    if (lat != null && lon != null && lat.abs() <= 90 && lon.abs() <= 180) {
      member.pos = LatLng(lat, lon);
    }

    member
      ..distance = (m['d'] as num?)?.toDouble() ?? member.distance
      ..gain = (m['g'] as num?)?.toDouble() ?? member.gain
      ..steps = (m['s'] as int?) ?? member.steps
      ..movingMs = (m['ms'] as int?) ?? member.movingMs;
    if (m['fin'] == true && !member.finished && grp == group) {
      member.finished = true;
      arrivals.add(name);
      final place = arrivals.length;
      messages.insert(0, GroupMessage(name, 'chegou em $placeº lugar 🏁', DateTime.now()));
      Recorder.instance.speak('$name chegou em $placeº lugar.');
    }

    switch (m['t']) {
      case 'msg':
        if (grp == group) {
          final text = (m['text'] as String? ?? '').trim();
          if (text.isNotEmpty && text.length <= 200) {
            messages.insert(0, GroupMessage(name, text, DateTime.now()));
            NativeBridge.vibrate([0, 200]);
            Recorder.instance.speak('$name: $text');
          }
        }
      case 'sos':
        _onSos(m, name);
    }

    final hops = (m['hops'] as int? ?? 0) + 1;
    if (hops < _maxHops) _send({...m, 'hops': hops}, exceptEndpoint: endpointId);
    notifyListeners();
  }

  void _onSos(Map<String, dynamic> m, String name) {
    final id = m['id'] as String;
    final text = (m['text'] as String? ?? '').trim();
    messages.insert(0, GroupMessage(name, 'PEDIU SOCORRO', DateTime.now(), sos: true));
    NativeBridge.vibrate([0, 800, 300, 800, 300, 800]);
    Recorder.instance.speak('Alerta: $name pediu socorro.');
    // Retransmite por SMS aos contatos de quem pediu, se este celular tiver sinal.
    if (!Settings.instance.groupRelaySos || !_relayedSos.add(id)) return;
    final phones = (m['phones'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .where((p) => RegExp(r'^\+?[0-9]{8,15}$').hasMatch(p))
        .take(5);
    final relayText =
        '$text (retransmitido pelo GAZMAP de ${Settings.instance.ownerName.isEmpty ? 'outro trilheiro' : Settings.instance.ownerName})';
    for (final p in phones) {
      NativeBridge.sendSms(p, relayText.length > 600 ? relayText.substring(0, 600) : relayText);
    }
  }

  Map<String, Object?> _base(String type) {
    final p = Recorder.instance.position;
    return {
      't': type,
      'id': _msgId(),
      'from': deviceId,
      'name': _myName,
      'group': group,
      'hops': 0,
      if (p != null) 'lat': p.latitude,
      if (p != null) 'lon': p.longitude,
      'd': Recorder.instance.distance.round(),
      'g': Recorder.instance.stats.elevation.gain.round(),
      's': Recorder.instance.steps,
      'ms': Recorder.instance.stats.movingMs,
    };
  }

  /// Avisa o grupo que você terminou (entra no pódio de chegada).
  void announceFinish(double meters, double gain, int steps, int movingMs) {
    if (!active) return;
    final msg = {
      ..._base('pos'),
      'fin': true,
      'd': meters.round(),
      'g': gain.round(),
      's': steps,
      'ms': movingMs,
    };
    _seen.add(msg['id'] as String);
    _send(msg);
    arrivals.add('Você');
    messages.insert(0, GroupMessage('Você', 'chegou em ${arrivals.length}º lugar 🏁', DateTime.now()));
    notifyListeners();
  }

  void sendMessage(String text) {
    if (!active) return;
    final t = text.trim();
    if (t.isEmpty) return;
    final msg = {..._base('msg'), 'text': t.length > 200 ? t.substring(0, 200) : t};
    _seen.add(msg['id'] as String);
    _send(msg);
    messages.insert(0, GroupMessage('Você', t, DateTime.now()));
    notifyListeners();
  }

  Future<void> _broadcastSos(String text, List<String> phones) async {
    if (!active) return;
    final msg = {..._base('sos'), 'text': text, 'phones': phones};
    _seen.add(msg['id'] as String);
    _send(msg);
  }

  // ---------- Posição e alertas de separação ----------

  void _tick() {
    if (!active) return;
    final p = Recorder.instance.position;
    if (p != null) {
      final msg = _base('pos');
      _seen.add(msg['id'] as String);
      _send(msg);
    }
    final now = DateTime.now();
    for (final m in myGroup) {
      if (p != null && m.pos != null) {
        final d = const Distance().as(LengthUnit.Meter, LatLng(p.latitude, p.longitude), m.pos!);
        if (d > 300 && !m.farWarned) {
          m.farWarned = true;
          NativeBridge.vibrate([0, 400, 200, 400]);
          Recorder.instance.speak('${m.name} está a ${d.round()} metros de você.');
        } else if (d < 200) {
          m.farWarned = false;
        }
      }
      if (now.difference(m.lastSeen) > const Duration(minutes: 10) && !m.lostWarned) {
        m.lostWarned = true;
        Recorder.instance.speak('${m.name} está fora do alcance há 10 minutos.');
      }
    }
    _updateStatus();
  }
}
