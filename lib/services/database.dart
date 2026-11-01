import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/region.dart';
import '../models/track.dart';

/// Banco local (SQLite). Tudo fica no aparelho: funciona 100% offline.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  /// Incrementa a cada mudança, para as telas recarregarem.
  final ValueNotifier<int> changes = ValueNotifier(0);

  Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, 'gazmap.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tracks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            activity TEXT NOT NULL,
            started_at INTEGER NOT NULL,
            ended_at INTEGER,
            distance REAL NOT NULL DEFAULT 0,
            moving_ms INTEGER NOT NULL DEFAULT 0,
            elapsed_ms INTEGER NOT NULL DEFAULT 0,
            gain REAL NOT NULL DEFAULT 0,
            loss REAL NOT NULL DEFAULT 0,
            max_speed REAL NOT NULL DEFAULT 0,
            finished INTEGER NOT NULL DEFAULT 0
          )''');
        await db.execute('''
          CREATE TABLE points (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            track_id INTEGER NOT NULL,
            lat REAL NOT NULL,
            lon REAL NOT NULL,
            ele REAL,
            time INTEGER NOT NULL,
            speed REAL,
            acc REAL,
            segment INTEGER NOT NULL DEFAULT 0
          )''');
        await db.execute('CREATE INDEX idx_points_track ON points(track_id)');
        await db.execute('''
          CREATE TABLE regions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            style_id TEXT NOT NULL,
            south REAL NOT NULL, west REAL NOT NULL,
            north REAL NOT NULL, east REAL NOT NULL,
            min_zoom INTEGER NOT NULL, max_zoom INTEGER NOT NULL,
            tiles INTEGER NOT NULL,
            created_at INTEGER NOT NULL
          )''');
      },
    );
  }

  void _changed() => changes.value++;

  // ---------- Atividades ----------

  Future<int> insertTrack(Track t) async {
    final id = await (await db).insert('tracks', t.toMap());
    t.id = id;
    return id;
  }

  Future<void> updateTrack(Track t) async {
    await (await db)
        .update('tracks', t.toMap(), where: 'id = ?', whereArgs: [t.id]);
    _changed();
  }

  Future<void> insertPoint(int trackId, TrackPoint p) async {
    await (await db).insert('points', p.toMap(trackId));
  }

  Future<List<Track>> finishedTracks() async {
    final rows = await (await db).query('tracks',
        where: 'finished = 1', orderBy: 'started_at DESC');
    return rows.map(Track.fromMap).toList();
  }

  Future<List<Track>> unfinishedTracks() async {
    final rows = await (await db).query('tracks', where: 'finished = 0');
    return rows.map(Track.fromMap).toList();
  }

  Future<Track?> track(int id) async {
    final rows =
        await (await db).query('tracks', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Track.fromMap(rows.first);
  }

  Future<List<TrackPoint>> points(int trackId) async {
    final rows = await (await db).query('points',
        where: 'track_id = ?', whereArgs: [trackId], orderBy: 'id ASC');
    return rows.map(TrackPoint.fromMap).toList();
  }

  Future<void> deleteTrack(int id) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('points', where: 'track_id = ?', whereArgs: [id]);
      await txn.delete('tracks', where: 'id = ?', whereArgs: [id]);
    });
    _changed();
  }

  // ---------- Regiões offline ----------

  Future<void> insertRegion(Region r) async {
    await (await db).insert('regions', r.toMap());
    _changed();
  }

  Future<List<Region>> regions() async {
    final rows = await (await db).query('regions', orderBy: 'created_at DESC');
    return rows.map(Region.fromMap).toList();
  }

  Future<void> deleteAllRegions() async {
    await (await db).delete('regions');
    _changed();
  }
}
