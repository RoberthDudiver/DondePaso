import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../background/tracking_preferences.dart';
import 'footprint_block_model.dart';
import 'footprint_cell.dart';
import 'footprint_transport.dart';

class FootprintStorageState {
  const FootprintStorageState({
    required this.cells,
    required this.legacyCells,
    required this.onboardingSeen,
    required this.lightMapMode,
    required this.totalPoints,
    required this.totalDistanceMeters,
    required this.totalVehicleDistanceMeters,
    required this.todayDistanceMeters,
    required this.todayDistanceDayKey,
    required this.currentStreak,
    required this.bestStreak,
    required this.streakLastDayKey,
    required this.radarNudgeDayKey,
    required this.passiveTrackingEnabled,
    required this.trackingPreferences,
    required this.lastLatitude,
    required this.lastLongitude,
    required this.lastTrackedAt,
  });

  final List<FootprintCell> cells;
  final List<FootprintCell> legacyCells;
  final bool onboardingSeen;
  final bool lightMapMode;
  final int totalPoints;
  final double totalDistanceMeters;
  final double totalVehicleDistanceMeters;
  final double todayDistanceMeters;
  final String? todayDistanceDayKey;
  final int currentStreak;
  final int bestStreak;
  final String? streakLastDayKey;
  final String? radarNudgeDayKey;
  final bool passiveTrackingEnabled;
  final PassiveTrackingPreferences trackingPreferences;
  final double? lastLatitude;
  final double? lastLongitude;
  final DateTime? lastTrackedAt;

  LatLng? get lastLatLng {
    final latitude = lastLatitude;
    final longitude = lastLongitude;
    if (latitude == null || longitude == null) {
      return null;
    }
    return LatLng(latitude, longitude);
  }

  bool get needsH3Migration => cells.isEmpty && legacyCells.isNotEmpty;

  FootprintStorageState copyWith({
    List<FootprintCell>? cells,
    List<FootprintCell>? legacyCells,
    bool? onboardingSeen,
    bool? lightMapMode,
    int? totalPoints,
    double? totalDistanceMeters,
    double? totalVehicleDistanceMeters,
    double? todayDistanceMeters,
    String? todayDistanceDayKey,
    int? currentStreak,
    int? bestStreak,
    String? streakLastDayKey,
    String? radarNudgeDayKey,
    bool? passiveTrackingEnabled,
    PassiveTrackingPreferences? trackingPreferences,
    double? lastLatitude,
    double? lastLongitude,
    DateTime? lastTrackedAt,
  }) {
    return FootprintStorageState(
      cells: cells ?? this.cells,
      legacyCells: legacyCells ?? this.legacyCells,
      onboardingSeen: onboardingSeen ?? this.onboardingSeen,
      lightMapMode: lightMapMode ?? this.lightMapMode,
      totalPoints: totalPoints ?? this.totalPoints,
      totalDistanceMeters: totalDistanceMeters ?? this.totalDistanceMeters,
      totalVehicleDistanceMeters:
          totalVehicleDistanceMeters ?? this.totalVehicleDistanceMeters,
      todayDistanceMeters: todayDistanceMeters ?? this.todayDistanceMeters,
      todayDistanceDayKey: todayDistanceDayKey ?? this.todayDistanceDayKey,
      currentStreak: currentStreak ?? this.currentStreak,
      bestStreak: bestStreak ?? this.bestStreak,
      streakLastDayKey: streakLastDayKey ?? this.streakLastDayKey,
      radarNudgeDayKey: radarNudgeDayKey ?? this.radarNudgeDayKey,
      passiveTrackingEnabled:
          passiveTrackingEnabled ?? this.passiveTrackingEnabled,
      trackingPreferences: trackingPreferences ?? this.trackingPreferences,
      lastLatitude: lastLatitude ?? this.lastLatitude,
      lastLongitude: lastLongitude ?? this.lastLongitude,
      lastTrackedAt: lastTrackedAt ?? this.lastTrackedAt,
    );
  }
}

class FootprintStorage {
  static const _legacyCellsKey = 'footprint_cells';
  static const _legacyCellsV2Key = 'footprint_cells_v2';
  static const _onboardingKey = 'footprint_onboarding_seen';
  static const _lightMapModeKey = 'footprint_light_map_mode';
  static const _pointsKey = 'footprint_total_points';
  static const _totalDistanceMetersKey = 'footprint_total_distance_meters';
  static const _totalVehicleDistanceMetersKey =
      'footprint_total_vehicle_distance_meters';
  static const _todayDistanceMetersKey = 'footprint_today_distance_meters';
  static const _todayDistanceDayKey = 'footprint_today_distance_day_key';
  static const _streakCountKey = 'footprint_streak_count';
  static const _bestStreakKey = 'footprint_best_streak';
  static const _streakLastDayKey = 'footprint_streak_last_day_key';
  static const _radarNudgeDayKey = 'footprint_radar_nudge_day_key';
  static const _passiveTrackingEnabledKey = 'footprint_passive_tracking';
  static const _trackingProfileKey = 'footprint_tracking_profile';
  static const _trackingCustomDistanceKey =
      'footprint_tracking_custom_distance';
  static const _trackingCustomIntervalKey =
      'footprint_tracking_custom_interval';
  static const _trackingAdaptiveModeKey = 'footprint_tracking_adaptive';
  static const _lastLatitudeKey = 'footprint_last_latitude';
  static const _lastLongitudeKey = 'footprint_last_longitude';
  static const _lastTrackedAtKey = 'footprint_last_tracked_at';

  static const _databaseName = 'dondepaso_footprint.db';
  static const _metaTable = 'footprint_meta';
  static const _cellsTable = 'footprint_cells';
  static const _blockSegmentsTable = 'footprint_block_segments';
  static const _blocksTable = 'footprint_blocks';
  static Database? _cachedDatabase;

  Future<FootprintStorageState> load() async {
    final db = await _database();
    final rowCount = sqflite.Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $_cellsTable'),
    );

    if ((rowCount ?? 0) == 0) {
      final migrated = await _migrateLegacyPrefsIfNeeded(db);
      if (migrated != null) {
        return migrated;
      }
    }

    await _printDiagnostics(db);
    await _purgeExpiredCells(db);
    return _readStateFromDatabase(db);
  }

  Future<void> saveProgress({
    required List<FootprintCell> cells,
    required int totalPoints,
    required double totalDistanceMeters,
    required double totalVehicleDistanceMeters,
    required double todayDistanceMeters,
    required String todayDistanceDayKey,
    required int currentStreak,
    required int bestStreak,
    required String? streakLastDayKey,
    required String? radarNudgeDayKey,
    required LatLng? lastLatLng,
    required DateTime? lastTrackedAt,
  }) async {
    final db = await _database();
    await db.transaction((txn) async {
      await _syncCells(txn, cells);
      await _writeMeta(txn, _pointsKey, totalPoints);
      await _writeMeta(txn, _totalDistanceMetersKey, totalDistanceMeters);
      await _writeMeta(
        txn,
        _totalVehicleDistanceMetersKey,
        totalVehicleDistanceMeters,
        );
        await _writeMeta(txn, _todayDistanceMetersKey, todayDistanceMeters);
        await _writeMeta(txn, _todayDistanceDayKey, todayDistanceDayKey);
        await _writeMeta(txn, _streakCountKey, currentStreak);
        await _writeMeta(txn, _bestStreakKey, bestStreak);
        await _writeMeta(txn, _streakLastDayKey, streakLastDayKey);
        await _writeMeta(txn, _radarNudgeDayKey, radarNudgeDayKey);
        await _writeMeta(txn, _lastLatitudeKey, lastLatLng?.latitude);
      await _writeMeta(txn, _lastLongitudeKey, lastLatLng?.longitude);
      await _writeMeta(txn, _lastTrackedAtKey, lastTrackedAt?.toIso8601String());
    });
  }

  Future<void> overwriteState(FootprintStorageState state) async {
    final db = await _database();
    await db.transaction((txn) async {
      await txn.delete(_cellsTable);
      final batch = txn.batch();
      for (final cell in state.cells) {
        batch.insert(_cellsTable, _cellToRow(cell));
      }
      await batch.commit(noResult: true);

      await _writeMeta(txn, _onboardingKey, state.onboardingSeen);
      await _writeMeta(txn, _lightMapModeKey, state.lightMapMode);
      await _writeMeta(txn, _pointsKey, state.totalPoints);
      await _writeMeta(txn, _totalDistanceMetersKey, state.totalDistanceMeters);
      await _writeMeta(
        txn,
        _totalVehicleDistanceMetersKey,
        state.totalVehicleDistanceMeters,
      );
      await _writeMeta(txn, _todayDistanceMetersKey, state.todayDistanceMeters);
      await _writeMeta(txn, _todayDistanceDayKey, state.todayDistanceDayKey);
      await _writeMeta(txn, _streakCountKey, state.currentStreak);
      await _writeMeta(txn, _bestStreakKey, state.bestStreak);
      await _writeMeta(txn, _streakLastDayKey, state.streakLastDayKey);
      await _writeMeta(txn, _radarNudgeDayKey, state.radarNudgeDayKey);
      await _writeMeta(
        txn,
        _passiveTrackingEnabledKey,
        state.passiveTrackingEnabled,
      );
      await _writeMeta(
        txn,
        _trackingProfileKey,
        state.trackingPreferences.profile.storageValue,
      );
      await _writeMeta(
        txn,
        _trackingCustomDistanceKey,
        state.trackingPreferences.customDistanceFilterMeters,
      );
      await _writeMeta(
        txn,
        _trackingCustomIntervalKey,
        state.trackingPreferences.customIntervalSeconds,
      );
      await _writeMeta(
        txn,
        _trackingAdaptiveModeKey,
        state.trackingPreferences.adaptiveModeEnabled,
      );
      await _writeMeta(txn, _lastLatitudeKey, state.lastLatitude);
      await _writeMeta(txn, _lastLongitudeKey, state.lastLongitude);
      await _writeMeta(
        txn,
        _lastTrackedAtKey,
        state.lastTrackedAt?.toIso8601String(),
      );
      await _writeMeta(
        txn,
        _legacyCellsKey,
        state.legacyCells.isEmpty
            ? null
            : jsonEncode(state.legacyCells.map((cell) => cell.toMap()).toList()),
      );
    });
  }

  Future<void> setOnboardingSeen() async {
    final db = await _database();
    await _writeMeta(db, _onboardingKey, true);
  }

  Future<void> setLightMapMode(bool enabled) async {
    final db = await _database();
    await _writeMeta(db, _lightMapModeKey, enabled);
  }

  Future<void> setPassiveTrackingEnabled(bool enabled) async {
    final db = await _database();
    await _writeMeta(db, _passiveTrackingEnabledKey, enabled);
  }

  Future<void> saveRadarNudgeDayKey(String? dayKey) async {
    final db = await _database();
    await _writeMeta(db, _radarNudgeDayKey, dayKey);
  }

  Future<void> saveTrackingPreferences(
    PassiveTrackingPreferences preferences,
  ) async {
    final db = await _database();
    await db.transaction((txn) async {
      await _writeMeta(txn, _trackingProfileKey, preferences.profile.storageValue);
      await _writeMeta(
        txn,
        _trackingCustomDistanceKey,
        preferences.customDistanceFilterMeters,
      );
      await _writeMeta(
        txn,
        _trackingCustomIntervalKey,
        preferences.customIntervalSeconds,
      );
      await _writeMeta(
        txn,
        _trackingAdaptiveModeKey,
        preferences.adaptiveModeEnabled,
      );
    });
  }

  Future<void> clear() async {
    final db = await _database();
    await db.transaction((txn) async {
      await txn.delete(_cellsTable);
      await txn.delete(_blockSegmentsTable);
      await txn.delete(_blocksTable);
      await txn.delete(_metaTable);
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyCellsKey);
    await prefs.remove(_legacyCellsV2Key);
    await prefs.remove(_onboardingKey);
    await prefs.remove(_lightMapModeKey);
    await prefs.remove(_pointsKey);
    await prefs.remove(_totalDistanceMetersKey);
    await prefs.remove(_totalVehicleDistanceMetersKey);
    await prefs.remove(_todayDistanceMetersKey);
    await prefs.remove(_todayDistanceDayKey);
    await prefs.remove(_streakCountKey);
    await prefs.remove(_bestStreakKey);
    await prefs.remove(_streakLastDayKey);
    await prefs.remove(_radarNudgeDayKey);
    await prefs.remove(_passiveTrackingEnabledKey);
    await prefs.remove(_trackingProfileKey);
    await prefs.remove(_trackingCustomDistanceKey);
    await prefs.remove(_trackingCustomIntervalKey);
    await prefs.remove(_trackingAdaptiveModeKey);
    await prefs.remove(_lastLatitudeKey);
    await prefs.remove(_lastLongitudeKey);
    await prefs.remove(_lastTrackedAtKey);
    await prefs.remove('activity_day_key');
    await prefs.remove('activity_base_steps');
    await prefs.remove('activity_daily_steps');
  }

  Future<Database> _database() async {
    final cached = _cachedDatabase;
    if (cached != null) {
      return cached;
    }

    final path = p.join(await _databaseDirectoryPath(), _databaseName);
    final factory = _databaseFactory();
    _cachedDatabase = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: (db, _) async {
          await _createSchema(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS $_blockSegmentsTable (
                id TEXT PRIMARY KEY,
                start_lat REAL NOT NULL,
                start_lon REAL NOT NULL,
                end_lat REAL NOT NULL,
                end_lon REAL NOT NULL,
                mid_lat REAL NOT NULL,
                mid_lon REAL NOT NULL,
                visits INTEGER NOT NULL DEFAULT 0,
                last_seen TEXT
              )
            ''');
            await db.execute('''
              CREATE TABLE IF NOT EXISTS $_blocksTable (
                id TEXT PRIMARY KEY,
                points_json TEXT NOT NULL,
                segment_ids_json TEXT NOT NULL,
                center_lat REAL NOT NULL,
                center_lon REAL NOT NULL,
                area_m2 REAL NOT NULL,
                visits INTEGER NOT NULL DEFAULT 0,
                last_seen TEXT
              )
            ''');
          }
          if (oldVersion < 3) {
            await db.execute(
              'ALTER TABLE $_cellsTable ADD COLUMN walking_visits INTEGER NOT NULL DEFAULT 0',
            );
            await db.execute(
              'ALTER TABLE $_cellsTable ADD COLUMN vehicle_visits INTEGER NOT NULL DEFAULT 0',
            );
          }
          if (oldVersion < 4) {
            await db.execute(
              'ALTER TABLE $_blockSegmentsTable ADD COLUMN walking_visits INTEGER NOT NULL DEFAULT 0',
            );
            await db.execute(
              'ALTER TABLE $_blockSegmentsTable ADD COLUMN vehicle_visits INTEGER NOT NULL DEFAULT 0',
            );
            await db.execute(
              'ALTER TABLE $_blocksTable ADD COLUMN walking_visits INTEGER NOT NULL DEFAULT 0',
            );
            await db.execute(
              'ALTER TABLE $_blocksTable ADD COLUMN vehicle_visits INTEGER NOT NULL DEFAULT 0',
            );
          }
          if (oldVersion < 5) {
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_cells_last_seen ON $_cellsTable (last_seen)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_cells_h3 ON $_cellsTable (h3_index)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_segments_mid ON $_blockSegmentsTable (mid_lat, mid_lon)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_blocks_center ON $_blocksTable (center_lat, center_lon)',
            );
          }
        },
      ),
    );
    return _cachedDatabase!;
  }

  Future<void> saveBlockNetwork({
    required List<FootprintRoadSegment> segments,
    required List<FootprintBlockRecord> blocks,
  }) async {
    final db = await _database();
    await db.transaction((txn) async {
      final segmentBatch = txn.batch();
      for (final segment in segments) {
        segmentBatch.insert(
          _blockSegmentsTable,
          segment.toRow(),
          conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
        );
      }
      await segmentBatch.commit(noResult: true);

      final blockBatch = txn.batch();
      for (final block in blocks) {
        blockBatch.insert(
          _blocksTable,
          block.toRow(),
          conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
        );
      }
      await blockBatch.commit(noResult: true);
    });
  }

  Future<List<FootprintBlockRecord>> loadBlocksNear({
    required LatLng center,
    required double radiusMeters,
  }) async {
    final db = await _database();
    final latBuffer = radiusMeters / 111320;
    final lonBuffer =
        radiusMeters /
        (111320 * math.max(0.2, math.cos(center.latitude * math.pi / 180)));
    final rows = await db.query(
      _blocksTable,
      where:
          'center_lat BETWEEN ? AND ? AND center_lon BETWEEN ? AND ?',
      whereArgs: [
        center.latitude - latBuffer,
        center.latitude + latBuffer,
        center.longitude - lonBuffer,
        center.longitude + lonBuffer,
      ],
    );
    return rows
        .map((row) => FootprintBlockRecord.fromRow(row))
        .toList(growable: false);
  }

  Future<Map<String, FootprintBlockRecord>> loadBlocksByIds(
    Iterable<String> ids,
  ) async {
    final uniqueIds = ids.toSet();
    if (uniqueIds.isEmpty) {
      return const {};
    }

    final db = await _database();
    final placeholders = List.filled(uniqueIds.length, '?').join(', ');
    final rows = await db.query(
      _blocksTable,
      where: 'id IN ($placeholders)',
      whereArgs: uniqueIds.toList(growable: false),
    );

    return <String, FootprintBlockRecord>{
      for (final row in rows)
        (row['id'] as String): FootprintBlockRecord.fromRow(row),
    };
  }

  Future<Map<String, FootprintRoadSegment>> loadSegmentsByIds(
    Iterable<String> ids,
  ) async {
    final uniqueIds = ids.toSet();
    if (uniqueIds.isEmpty) {
      return const {};
    }

    final db = await _database();
    final placeholders = List.filled(uniqueIds.length, '?').join(', ');
    final rows = await db.query(
      _blockSegmentsTable,
      where: 'id IN ($placeholders)',
      whereArgs: uniqueIds.toList(growable: false),
    );

    return <String, FootprintRoadSegment>{
      for (final row in rows)
        (row['id'] as String): FootprintRoadSegment.fromRow(row),
    };
  }

  Future<void> markRoadSegmentsVisited(
    Iterable<String> segmentIds, {
    required DateTime at,
    required FootprintTransportMode transportMode,
  }) async {
    final uniqueIds = segmentIds.toSet();
    if (uniqueIds.isEmpty) {
      return;
    }

    final db = await _database();
    final walkingInc =
        transportMode == FootprintTransportMode.walking ? 1 : 0;
    final vehicleInc =
        transportMode == FootprintTransportMode.vehicle ? 1 : 0;
    final lastSeen = at.toIso8601String();
    await db.transaction((txn) async {
      for (final id in uniqueIds) {
        await txn.rawUpdate(
          'UPDATE $_blockSegmentsTable '
          'SET visits = visits + 1, '
          'walking_visits = walking_visits + ?, '
          'vehicle_visits = vehicle_visits + ?, '
          'last_seen = ? '
          'WHERE id = ?',
          [walkingInc, vehicleInc, lastSeen, id],
        );
      }
    });
  }

  Future<void> activateBlocks(
    Iterable<String> blockIds, {
    required DateTime at,
    required FootprintTransportMode transportMode,
  }) async {
    final uniqueIds = blockIds.toSet();
    if (uniqueIds.isEmpty) {
      return;
    }

    final db = await _database();
    final idList = uniqueIds.toList(growable: false);
    final placeholders = List.filled(idList.length, '?').join(', ');
    final rows = await db.query(
      _blocksTable,
      columns: const ['id', 'visits', 'last_seen', 'walking_visits', 'vehicle_visits'],
      where: 'id IN ($placeholders)',
      whereArgs: idList,
    );
    final blockMap = <String, Map<String, Object?>>{
      for (final row in rows) row['id'] as String: row,
    };
    final walkingInc =
        transportMode == FootprintTransportMode.walking ? 1 : 0;
    final vehicleInc =
        transportMode == FootprintTransportMode.vehicle ? 1 : 0;
    final lastSeenStr = at.toIso8601String();
    await db.transaction((txn) async {
      for (final id in uniqueIds) {
        final row = blockMap[id];
        if (row == null) continue;
        final currentVisits = ((row['visits'] as num?) ?? 0).toInt();
        final rawLastSeen = row['last_seen'] as String?;
        final lastSeen = rawLastSeen == null ? null : DateTime.parse(rawLastSeen);
        final shouldIncrement =
            lastSeen == null || at.difference(lastSeen) >= const Duration(hours: 6);
        await txn.update(
          _blocksTable,
          <String, Object?>{
            'visits': shouldIncrement ? currentVisits + 1 : currentVisits,
            'walking_visits': ((row['walking_visits'] as num?) ?? 0).toInt() + walkingInc,
            'vehicle_visits': ((row['vehicle_visits'] as num?) ?? 0).toInt() + vehicleInc,
            'last_seen': lastSeenStr,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });
  }

  Future<void> purgeBlocksNear({
    required LatLng center,
    required double radiusMeters,
  }) async {
    final db = await _database();
    final latBuffer = radiusMeters / 111320;
    final lonBuffer =
        radiusMeters /
        (111320 * math.max(0.2, math.cos(center.latitude * math.pi / 180)));
    final rows = await db.query(
      _blocksTable,
      columns: const ['id', 'segment_ids_json'],
      where:
          'center_lat BETWEEN ? AND ? AND center_lon BETWEEN ? AND ?',
      whereArgs: [
        center.latitude - latBuffer,
        center.latitude + latBuffer,
        center.longitude - lonBuffer,
        center.longitude + lonBuffer,
      ],
    );

    if (rows.isEmpty) {
      return;
    }

    final blockIds = rows.map((row) => row['id'] as String).toList(growable: false);
    final segmentIds = <String>{};
    for (final row in rows) {
      final raw = row['segment_ids_json'] as String;
      segmentIds.addAll((jsonDecode(raw) as List<dynamic>).cast<String>());
    }

    await db.transaction((txn) async {
      final blockPlaceholders = List.filled(blockIds.length, '?').join(', ');
      await txn.delete(
        _blocksTable,
        where: 'id IN ($blockPlaceholders)',
        whereArgs: blockIds,
      );
      if (segmentIds.isNotEmpty) {
        final segmentPlaceholders = List.filled(segmentIds.length, '?').join(', ');
        await txn.delete(
          _blockSegmentsTable,
          where: 'id IN ($segmentPlaceholders)',
          whereArgs: segmentIds.toList(growable: false),
        );
      }
    });
  }

  DatabaseFactory _databaseFactory() {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      return databaseFactoryFfi;
    }
    return sqflite.databaseFactory;
  }

  Future<String> _databaseDirectoryPath() async {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      final directory = Directory(
        p.join(Directory.systemTemp.path, 'dondepaso_db'),
      );
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
      return directory.path;
    }

    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<FootprintStorageState?> _migrateLegacyPrefsIfNeeded(Database db) async {
    final prefs = await SharedPreferences.getInstance();
    final rawCellsV2 = prefs.getString(_legacyCellsV2Key);
    final rawCellsLegacy = prefs.getString(_legacyCellsKey);

    if (rawCellsV2 == null &&
        rawCellsLegacy == null &&
        !prefs.containsKey(_pointsKey) &&
        !prefs.containsKey(_onboardingKey)) {
      return null;
    }

    final migratedState = FootprintStorageState(
      cells: rawCellsV2 == null ? const [] : FootprintCell.decodeList(rawCellsV2),
      legacyCells: rawCellsLegacy == null
          ? const []
          : FootprintCell.decodeList(rawCellsLegacy),
      onboardingSeen: prefs.getBool(_onboardingKey) ?? false,
      lightMapMode: prefs.getBool(_lightMapModeKey) ?? false,
      totalPoints: prefs.getInt(_pointsKey) ?? 0,
      totalDistanceMeters: prefs.getDouble(_totalDistanceMetersKey) ?? 0,
      totalVehicleDistanceMeters:
          prefs.getDouble(_totalVehicleDistanceMetersKey) ?? 0,
      todayDistanceMeters: prefs.getDouble(_todayDistanceMetersKey) ?? 0,
      todayDistanceDayKey: prefs.getString(_todayDistanceDayKey),
      currentStreak: prefs.getInt(_streakCountKey) ?? 0,
      bestStreak: prefs.getInt(_bestStreakKey) ?? 0,
      streakLastDayKey: prefs.getString(_streakLastDayKey),
      radarNudgeDayKey: prefs.getString(_radarNudgeDayKey),
      passiveTrackingEnabled: prefs.getBool(_passiveTrackingEnabledKey) ?? true,
      trackingPreferences: PassiveTrackingPreferences(
        profile: PassiveTrackingProfileCodec.fromStorage(
          prefs.getString(_trackingProfileKey),
        ),
        customDistanceFilterMeters:
            prefs.getInt(_trackingCustomDistanceKey) ??
            PassiveTrackingPreferences
                .defaultPreferences
                .customDistanceFilterMeters,
        customIntervalSeconds:
            prefs.getInt(_trackingCustomIntervalKey) ??
            PassiveTrackingPreferences
                .defaultPreferences
                .customIntervalSeconds,
        adaptiveModeEnabled:
            prefs.getBool(_trackingAdaptiveModeKey) ??
            PassiveTrackingPreferences.defaultPreferences.adaptiveModeEnabled,
      ),
      lastLatitude: prefs.getDouble(_lastLatitudeKey),
      lastLongitude: prefs.getDouble(_lastLongitudeKey),
      lastTrackedAt: prefs.getString(_lastTrackedAtKey) == null
          ? null
          : DateTime.parse(prefs.getString(_lastTrackedAtKey)!),
    );

    await overwriteState(migratedState);
    return _readStateFromDatabase(db);
  }

  Future<FootprintStorageState> _readStateFromDatabase(Database db) async {
    final cellRows = await db.query(_cellsTable);
    final metaRows = await db.query(_metaTable);
    final meta = <String, String?>{
      for (final row in metaRows)
        row['key'] as String: row['value'] as String?,
    };

    return FootprintStorageState(
      cells: cellRows.map(_cellFromRow).toList(growable: false),
      legacyCells: _decodeLegacyCells(meta[_legacyCellsKey]),
      onboardingSeen: _boolValue(meta[_onboardingKey], fallback: false),
      lightMapMode: _boolValue(meta[_lightMapModeKey], fallback: false),
      totalPoints: _intValue(meta[_pointsKey], fallback: 0),
      totalDistanceMeters: _doubleValue(meta[_totalDistanceMetersKey], fallback: 0),
      totalVehicleDistanceMeters: _doubleValue(
        meta[_totalVehicleDistanceMetersKey],
        fallback: 0,
      ),
      todayDistanceMeters: _doubleValue(meta[_todayDistanceMetersKey], fallback: 0),
      todayDistanceDayKey: meta[_todayDistanceDayKey],
      currentStreak: _intValue(meta[_streakCountKey], fallback: 0),
      bestStreak: _intValue(meta[_bestStreakKey], fallback: 0),
      streakLastDayKey: meta[_streakLastDayKey],
      radarNudgeDayKey: meta[_radarNudgeDayKey],
      passiveTrackingEnabled: _boolValue(
        meta[_passiveTrackingEnabledKey],
        fallback: true,
      ),
      trackingPreferences: PassiveTrackingPreferences(
        profile: PassiveTrackingProfileCodec.fromStorage(meta[_trackingProfileKey]),
        customDistanceFilterMeters: _intValue(
          meta[_trackingCustomDistanceKey],
          fallback:
              PassiveTrackingPreferences
                  .defaultPreferences
                  .customDistanceFilterMeters,
        ),
        customIntervalSeconds: _intValue(
          meta[_trackingCustomIntervalKey],
          fallback:
              PassiveTrackingPreferences.defaultPreferences.customIntervalSeconds,
        ),
        adaptiveModeEnabled: _boolValue(
          meta[_trackingAdaptiveModeKey],
          fallback: PassiveTrackingPreferences.defaultPreferences.adaptiveModeEnabled,
        ),
      ),
      lastLatitude: _nullableDouble(meta[_lastLatitudeKey]),
      lastLongitude: _nullableDouble(meta[_lastLongitudeKey]),
      lastTrackedAt: meta[_lastTrackedAtKey] == null
          ? null
          : DateTime.parse(meta[_lastTrackedAtKey]!),
    );
  }

  static Map<String, Object?> _cellToRow(FootprintCell cell) {
    return <String, Object?>{
      'id': cell.storageKey,
      'latitude': cell.latitude,
      'longitude': cell.longitude,
      'visits': cell.visits,
      'last_seen': cell.lastSeen.toIso8601String(),
      'h3_index': cell.h3Index,
      'coverage_weight': cell.coverageWeight,
      'walking_visits': cell.walkingVisits,
      'vehicle_visits': cell.vehicleVisits,
    };
  }

  static FootprintCell _cellFromRow(Map<String, Object?> row) {
    return FootprintCell(
      latitude: (row['latitude'] as num).toDouble(),
      longitude: (row['longitude'] as num).toDouble(),
      visits: (row['visits'] as num).toInt(),
      lastSeen: DateTime.parse(row['last_seen'] as String),
      h3Index: row['h3_index'] as String?,
      coverageWeight: (row['coverage_weight'] as num?)?.toDouble() ?? 1,
      walkingVisits: ((row['walking_visits'] as num?) ?? 0).toInt(),
      vehicleVisits: ((row['vehicle_visits'] as num?) ?? 0).toInt(),
    );
  }

  static Future<void> _writeMeta(
    DatabaseExecutor db,
    String key,
    Object? value,
  ) async {
    if (value == null) {
      await db.delete(_metaTable, where: 'key = ?', whereArgs: [key]);
      return;
    }

    await db.insert(_metaTable, <String, Object?>{
      'key': key,
      'value': value.toString(),
    }, conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
  }

  static Future<void> _syncCells(
    DatabaseExecutor db,
    List<FootprintCell> cells,
  ) async {
    if (cells.isEmpty) {
      await db.delete(_cellsTable);
      return;
    }

    final existingRows = await db.query(_cellsTable, columns: const ['id']);
    final existingIds = existingRows
        .map((row) => row['id'] as String)
        .toSet();
    final nextIds = cells.map((cell) => cell.storageKey).toSet();
    final idsToDelete = existingIds.difference(nextIds).toList(growable: false);

    if (idsToDelete.isNotEmpty) {
      final placeholders = List.filled(idsToDelete.length, '?').join(', ');
      await db.delete(
        _cellsTable,
        where: 'id IN ($placeholders)',
        whereArgs: idsToDelete,
      );
    }

    final batch = db.batch();
    for (final cell in cells) {
      batch.insert(
        _cellsTable,
        _cellToRow(cell),
        conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  static List<FootprintCell> _decodeLegacyCells(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    return FootprintCell.decodeList(raw);
  }

  static bool _boolValue(String? raw, {required bool fallback}) {
    if (raw == null) {
      return fallback;
    }
    return raw == 'true';
  }

  static int _intValue(String? raw, {required int fallback}) {
    return raw == null ? fallback : int.tryParse(raw) ?? fallback;
  }

  static double _doubleValue(String? raw, {required double fallback}) {
    return raw == null ? fallback : double.tryParse(raw) ?? fallback;
  }

  static double? _nullableDouble(String? raw) {
    return raw == null ? null : double.tryParse(raw);
  }

  static Future<void> _printDiagnostics(Database db) async {
    final cells = sqflite.Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $_cellsTable'),
    ) ?? 0;
    final segments = sqflite.Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $_blockSegmentsTable'),
    ) ?? 0;
    final blocks = sqflite.Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $_blocksTable'),
    ) ?? 0;
    final meta = sqflite.Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $_metaTable'),
    ) ?? 0;

    final oldestCell = await db.rawQuery(
      'SELECT MIN(last_seen) as oldest FROM $_cellsTable',
    );
    final newestCell = await db.rawQuery(
      'SELECT MAX(last_seen) as newest FROM $_cellsTable',
    );
    final expiredCells = sqflite.Sqflite.firstIntValue(
      await db.rawQuery(
        "SELECT COUNT(*) FROM $_cellsTable WHERE last_seen < ?",
        [DateTime.now().subtract(const Duration(days: 14)).toIso8601String()],
      ),
    ) ?? 0;

    debugPrint('╔══════════════════════════════════════════╗');
    debugPrint('║     DONDEPASO DATABASE DIAGNOSTICS       ║');
    debugPrint('╠══════════════════════════════════════════╣');
    debugPrint('║ Cells:          $cells');
    debugPrint('║ Block segments: $segments');
    debugPrint('║ Blocks:         $blocks');
    debugPrint('║ Meta entries:   $meta');
    debugPrint('║ Expired cells (>14d): $expiredCells');
    debugPrint('║ Oldest cell:    ${oldestCell.first['oldest']}');
    debugPrint('║ Newest cell:    ${newestCell.first['newest']}');
    debugPrint('╚══════════════════════════════════════════╝');
  }

  static Future<void> _purgeExpiredCells(Database db) async {
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 14))
        .toIso8601String();
    final deleted = await db.delete(
      _cellsTable,
      where: 'last_seen < ?',
      whereArgs: [cutoff],
    );
    if (deleted > 0) {
      debugPrint('[DondePaso] Purged $deleted expired cells (>14 days old)');
    }
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE $_metaTable (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE $_cellsTable (
        id TEXT PRIMARY KEY,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        visits INTEGER NOT NULL,
        last_seen TEXT NOT NULL,
        h3_index TEXT,
        coverage_weight REAL NOT NULL,
        walking_visits INTEGER NOT NULL DEFAULT 0,
        vehicle_visits INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE $_blockSegmentsTable (
        id TEXT PRIMARY KEY,
        start_lat REAL NOT NULL,
        start_lon REAL NOT NULL,
        end_lat REAL NOT NULL,
        end_lon REAL NOT NULL,
        mid_lat REAL NOT NULL,
        mid_lon REAL NOT NULL,
        visits INTEGER NOT NULL DEFAULT 0,
        walking_visits INTEGER NOT NULL DEFAULT 0,
        vehicle_visits INTEGER NOT NULL DEFAULT 0,
        last_seen TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE $_blocksTable (
        id TEXT PRIMARY KEY,
        points_json TEXT NOT NULL,
        segment_ids_json TEXT NOT NULL,
        center_lat REAL NOT NULL,
        center_lon REAL NOT NULL,
        area_m2 REAL NOT NULL,
        visits INTEGER NOT NULL DEFAULT 0,
        walking_visits INTEGER NOT NULL DEFAULT 0,
        vehicle_visits INTEGER NOT NULL DEFAULT 0,
        last_seen TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cells_last_seen ON $_cellsTable (last_seen)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cells_h3 ON $_cellsTable (h3_index)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_segments_mid ON $_blockSegmentsTable (mid_lat, mid_lon)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_blocks_center ON $_blocksTable (center_lat, center_lon)',
    );
  }
}
