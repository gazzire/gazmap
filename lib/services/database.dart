import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/extra.dart';
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
      version: 2,
      onCreate: (db, version) async {
        await _createV1(db);
        await _migrateV2(db);
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) await _migrateV2(db);
      },
    );
  }

  Future<void> _createV1(Database db) async {
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
  }

  /// v0.2: passos, contatos de emergência, rotas, trechos e pontos marcados.
  Future<void> _migrateV2(Database db) async {
    await db.execute(
        'ALTER TABLE tracks ADD COLUMN steps INTEGER NOT NULL DEFAULT 0');
    await db.execute('''
      CREATE TABLE contacts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE routes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        points TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        source TEXT NOT NULL DEFAULT 'gpx'
      )''');
    await db.execute('''
      CREATE TABLE segments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        activity TEXT NOT NULL,
        s_lat REAL NOT NULL, s_lon REAL NOT NULL,
        e_lat REAL NOT NULL, e_lon REAL NOT NULL,
        created_at INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE waypoints (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        track_id INTEGER,
        lat REAL NOT NULL,
        lon REAL NOT NULL,
        kind TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        photo TEXT,
        created_at INTEGER NOT NULL
      )''');
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

  Future<void> insertPoints(int trackId, List<TrackPoint> pts) async {
    final b = (await db).batch();
    for (final p in pts) {
      b.insert('points', p.toMap(trackId));
    }
    await b.commit(noResult: true);
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
      await txn.delete('waypoints', where: 'track_id = ?', whereArgs: [id]);
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

  // ---------- Contatos de emergência ----------

  Future<List<EmergencyContact>> contacts() async {
    final rows = await (await db).query('contacts', orderBy: 'id ASC');
    return rows.map(EmergencyContact.fromMap).toList();
  }

  Future<void> saveContact(EmergencyContact c) async {
    final d = await db;
    if (c.id == null) {
      c.id = await d.insert('contacts', c.toMap());
    } else {
      await d.update('contacts', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
    }
    _changed();
  }

  Future<void> deleteContact(int id) async {
    await (await db).delete('contacts', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  // ---------- Rotas ----------

  Future<List<SavedRoute>> routes() async {
    final rows = await (await db).query('routes', orderBy: 'created_at DESC');
    return rows.map(SavedRoute.fromMap).toList();
  }

  Future<SavedRoute?> route(int id) async {
    final rows =
        await (await db).query('routes', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : SavedRoute.fromMap(rows.first);
  }

  Future<int> insertRoute(SavedRoute r) async {
    final id = await (await db).insert('routes', r.toMap());
    r.id = id;
    _changed();
    return id;
  }

  Future<void> deleteRoute(int id) async {
    await (await db).delete('routes', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  // ---------- Trechos favoritos ----------

  Future<List<FavoriteSegment>> segments() async {
    final rows = await (await db).query('segments', orderBy: 'created_at DESC');
    return rows.map(FavoriteSegment.fromMap).toList();
  }

  Future<void> insertSegment(FavoriteSegment s) async {
    s.id = await (await db).insert('segments', s.toMap());
    _changed();
  }

  Future<void> deleteSegment(int id) async {
    await (await db).delete('segments', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  // ---------- Pontos marcados ----------

  Future<List<Waypoint>> waypoints({int? trackId}) async {
    final rows = await (await db).query('waypoints',
        where: trackId == null ? null : 'track_id = ?',
        whereArgs: trackId == null ? null : [trackId],
        orderBy: 'created_at DESC');
    return rows.map(Waypoint.fromMap).toList();
  }

  Future<void> insertWaypoint(Waypoint w) async {
    w.id = await (await db).insert('waypoints', w.toMap());
    _changed();
  }

  Future<void> deleteWaypoint(int id) async {
    await (await db).delete('waypoints', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  /// Todos os pontos de todas as atividades (mapa de calor), amostrados.
  Future<List<List<TrackPoint>>> allTrackPoints({int every = 5}) async {
    final d = await db;
    final rows = await d.rawQuery(
        'SELECT * FROM points WHERE id % ? = 0 ORDER BY track_id, id', [every]);
    final out = <List<TrackPoint>>[];
    int? current;
    for (final r in rows) {
      final tid = r['track_id'] as int;
      if (tid != current) {
        out.add([]);
        current = tid;
      }
      out.last.add(TrackPoint.fromMap(r));
    }
    return out;
  }
}
