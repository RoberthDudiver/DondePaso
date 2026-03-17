import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../background/tracking_preferences.dart';
import 'footprint_cell.dart';

class FootprintStorageState {
  const FootprintStorageState({
    required this.cells,
    required this.legacyCells,
    required this.onboardingSeen,
    required this.totalPoints,
    required this.totalDistanceMeters,
    required this.todayDistanceMeters,
    required this.todayDistanceDayKey,
    required this.passiveTrackingEnabled,
    required this.trackingPreferences,
    required this.lastLatitude,
    required this.lastLongitude,
    required this.lastTrackedAt,
  });

  final List<FootprintCell> cells;
  final List<FootprintCell> legacyCells;
  final bool onboardingSeen;
  final int totalPoints;
  final double totalDistanceMeters;
  final double todayDistanceMeters;
  final String? todayDistanceDayKey;
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
    int? totalPoints,
    double? totalDistanceMeters,
    double? todayDistanceMeters,
    String? todayDistanceDayKey,
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
      totalPoints: totalPoints ?? this.totalPoints,
      totalDistanceMeters: totalDistanceMeters ?? this.totalDistanceMeters,
      todayDistanceMeters: todayDistanceMeters ?? this.todayDistanceMeters,
      todayDistanceDayKey: todayDistanceDayKey ?? this.todayDistanceDayKey,
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
  static const _pointsKey = 'footprint_total_points';
  static const _totalDistanceMetersKey = 'footprint_total_distance_meters';
  static const _todayDistanceMetersKey = 'footprint_today_distance_meters';
  static const _todayDistanceDayKey = 'footprint_today_distance_day_key';
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

    return _readStateFromDatabase(db);
  }

  Future<void> saveProgress({
    required List<FootprintCell> cells,
    required int totalPoints,
    required double totalDistanceMeters,
    required double todayDistanceMeters,
    required String todayDistanceDayKey,
    required LatLng? lastLatLng,
    required DateTime? lastTrackedAt,
  }) async {
    final current = await load();
    final next = current.copyWith(
      cells: cells,
      totalPoints: totalPoints,
      totalDistanceMeters: totalDistanceMeters,
      todayDistanceMeters: todayDistanceMeters,
      todayDistanceDayKey: todayDistanceDayKey,
      lastLatitude: lastLatLng?.latitude,
      lastLongitude: lastLatLng?.longitude,
      lastTrackedAt: lastTrackedAt,
    );
    await overwriteState(next);
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
      await _writeMeta(txn, _pointsKey, state.totalPoints);
      await _writeMeta(txn, _totalDistanceMetersKey, state.totalDistanceMeters);
      await _writeMeta(txn, _todayDistanceMetersKey, state.todayDistanceMeters);
      await _writeMeta(txn, _todayDistanceDayKey, state.todayDistanceDayKey);
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
    final current = await load();
    await overwriteState(current.copyWith(onboardingSeen: true));
  }

  Future<void> setPassiveTrackingEnabled(bool enabled) async {
    final current = await load();
    await overwriteState(current.copyWith(passiveTrackingEnabled: enabled));
  }

  Future<void> saveTrackingPreferences(
    PassiveTrackingPreferences preferences,
  ) async {
    final current = await load();
    await overwriteState(current.copyWith(trackingPreferences: preferences));
  }

  Future<void> clear() async {
    final db = await _database();
    await db.transaction((txn) async {
      await txn.delete(_cellsTable);
      await txn.delete(_metaTable);
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyCellsKey);
    await prefs.remove(_legacyCellsV2Key);
    await prefs.remove(_onboardingKey);
    await prefs.remove(_pointsKey);
    await prefs.remove(_totalDistanceMetersKey);
    await prefs.remove(_todayDistanceMetersKey);
    await prefs.remove(_todayDistanceDayKey);
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
        version: 1,
        onCreate: (db, _) async {
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
              coverage_weight REAL NOT NULL
            )
          ''');
        },
      ),
    );
    return _cachedDatabase!;
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
      totalPoints: prefs.getInt(_pointsKey) ?? 0,
      totalDistanceMeters: prefs.getDouble(_totalDistanceMetersKey) ?? 0,
      todayDistanceMeters: prefs.getDouble(_todayDistanceMetersKey) ?? 0,
      todayDistanceDayKey: prefs.getString(_todayDistanceDayKey),
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
      totalPoints: _intValue(meta[_pointsKey], fallback: 0),
      totalDistanceMeters: _doubleValue(meta[_totalDistanceMetersKey], fallback: 0),
      todayDistanceMeters: _doubleValue(meta[_todayDistanceMetersKey], fallback: 0),
      todayDistanceDayKey: meta[_todayDistanceDayKey],
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
}
