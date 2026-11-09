import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/extra.dart';
import '../services/database.dart';

/// Marca um ponto na trilha (nascente, mirante, perigo...) com nota e foto.
Future<Waypoint?> showWaypointSheet(BuildContext context,
    {required double lat, required double lon, int? trackId}) {
  return showModalBottomSheet<Waypoint>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _WaypointSheet(lat: lat, lon: lon, trackId: trackId),
  );
}

class _WaypointSheet extends StatefulWidget {
  const _WaypointSheet({required this.lat, required this.lon, this.trackId});
  final double lat;
  final double lon;
  final int? trackId;

  @override
  State<_WaypointSheet> createState() => _WaypointSheetState();
}

class _WaypointSheetState extends State<_WaypointSheet> {
  WaypointKind _kind = WaypointKind.mirante;
  final _note = TextEditingController();
  String? _photo;
  bool _saving = false;

  Future<void> _takePhoto() async {
    try {
      final x = await ImagePicker()
          .pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 80);
      if (x == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory(p.join(dir.path, 'fotos'));
      await folder.create(recursive: true);
      final dest = p.join(folder.path, 'ponto_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(x.path).copy(dest);
      setState(() => _photo = dest);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Não foi possível abrir a câmera.')));
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final w = Waypoint(
      trackId: widget.trackId,
      lat: widget.lat,
      lon: widget.lon,
      kind: _kind,
      note: _note.text.trim().length > 200 ? _note.text.trim().substring(0, 200) : _note.text.trim(),
      photoPath: _photo,
      createdAt: DateTime.now(),
    );
    await AppDatabase.instance.insertWaypoint(w);
    if (mounted) Navigator.pop(context, w);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Marcar ponto', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in WaypointKind.values)
            ChoiceChip(
              label: Text('${k.emoji} ${k.label}'),
              selected: _kind == k,
              onSelected: (_) => setState(() => _kind = k),
            ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          maxLength: 200,
          decoration: const InputDecoration(labelText: 'Nota (opcional)'),
        ),
        Row(children: [
          OutlinedButton.icon(
            onPressed: _takePhoto,
            icon: const Icon(Icons.photo_camera),
            label: Text(_photo == null ? 'Tirar foto' : 'Trocar foto'),
          ),
          const SizedBox(width: 12),
          if (_photo != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(File(_photo!), width: 56, height: 56, fit: BoxFit.cover),
            ),
        ]),
        const SizedBox(height: 12),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Salvar ponto')),
      ]),
    );
  }
}
