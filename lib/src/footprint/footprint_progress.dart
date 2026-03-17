import 'dart:async';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../background/tracking_preferences.dart';
import 'footprint_blocks.dart';
import 'footprint_backup_service.dart';
import 'footprint_cell.dart';
import 'footprint_h3_grid.dart';
import 'footprint_storage.dart';
import 'footprint_transport.dart';

const footprintBucketStep = 0.00022;
const footprintRevisitGap = Duration(minutes: 2);
const footprintForgetAfter = Duration(days: 14);

final Distance _distance = const Distance();

class FootprintSnapshot {
  const FootprintSnapshot({
    required this.cells,
    required this.totalPoints,
    required this.totalDistanceMeters,
    required this.totalVehicleDistanceMeters,
    required this.todayDistanceMeters,
    required this.currentStreak,
    required this.bestStreak,
    required this.lightMapMode,
    required this.passiveTrackingEnabled,
    required this.trackingPreferences,
    required this.onboardingSeen,
    required this.lastLatLng,
    required this.lastTrackedAt,
  });

  final List<FootprintCell> cells;
  final int totalPoints;
  final double totalDistanceMeters;
  final double totalVehicleDistanceMeters;
  final double todayDistanceMeters;
  final int currentStreak;
  final int bestStreak;
  final bool lightMapMode;
  final bool passiveTrackingEnabled;
  final PassiveTrackingPreferences trackingPreferences;
  final bool onboardingSeen;
  final LatLng? lastLatLng;
  final DateTime? lastTrackedAt;
}

class FootprintProgress {
  FootprintProgress._();

  static FootprintStorageState? _cachedStorageState;
  static DateTime? _lastFlushAt;
  static Timer? _flushTimer;
  static Future<void> _writeQueue = Future<void>.value();

  static Future<FootprintSnapshot> loadSnapshot() async {
    return _serialize(() async {
      final storage = FootprintStorage();
      var storageState = await storage.load();
      storageState = await _migrateLegacyCellsIfNeeded(
        storage: storage,
        storageState: storageState,
      );
      _cachedStorageState = storageState;
      return _snapshotFromState(storageState, DateTime.now());
    });
  }

  static Future<FootprintSnapshot> recordVisit({
    required LatLng point,
    DateTime? at,
    FootprintTransportMode transportMode = FootprintTransportMode.unknown,
    bool persistImmediately = true,
  }) async {
    return _serialize(() async {
      final storage = FootprintStorage();
      final initialState = _cachedStorageState ?? await storage.load();
      final storageState = await _migrateLegacyCellsIfNeeded(
        storage: storage,
        storageState: initialState,
      );
      final now = at ?? DateTime.now();
      final cellsByKey = <String, FootprintCell>{
        for (final cell in storageState.cells) cell.storageKey: cell,
      };
      var totalPoints = storageState.totalPoints;
      var totalDistanceMeters = storageState.totalDistanceMeters;
      var totalVehicleDistanceMeters = storageState.totalVehicleDistanceMeters;
      final todayKey = _dayKeyFor(now);
      var todayDistanceMeters = storageState.todayDistanceDayKey == todayKey
          ? storageState.todayDistanceMeters
          : 0.0;
      final streakUpdate = _resolveStreakUpdate(
        previousDayKey: storageState.streakLastDayKey,
        currentDayKey: todayKey,
        currentStreak: storageState.currentStreak,
        bestStreak: storageState.bestStreak,
      );

      final previousPoint = storageState.lastLatLng;
      final previousTrackedAt = storageState.lastTrackedAt;
      if (previousPoint != null && previousTrackedAt != null) {
        final traveledMeters = _distance.as(
          LengthUnit.Meter,
          previousPoint,
          point,
        );
        final secondsSinceLast = now.difference(previousTrackedAt).inSeconds;
        if (traveledMeters >= 8 &&
            secondsSinceLast > 0 &&
            secondsSinceLast <= 60 * 20) {
          final inferredSpeed = traveledMeters / secondsSinceLast;
          if (inferredSpeed <= 55) {
            totalDistanceMeters += traveledMeters;
            todayDistanceMeters += traveledMeters;
            if (transportMode == FootprintTransportMode.vehicle) {
              totalVehicleDistanceMeters += traveledMeters;
            }
          }
        }
      }

      final key = FootprintH3Grid.keyForPoint(point);
      final existingCell = cellsByKey[key];

      if (existingCell == null) {
        cellsByKey[key] = FootprintH3Grid.cellForPoint(
          point,
          lastSeen: now,
          transportMode: transportMode,
        );
        totalPoints += 120;
      } else {
        final freshnessBefore = freshnessFor(existingCell, now);
        final movedEnough =
            _distance.as(LengthUnit.Meter, point, existingCell.latLng) > 6;

        if (now.difference(existingCell.lastSeen) >= footprintRevisitGap &&
            movedEnough) {
          cellsByKey[key] = existingCell.registerVisit(
            now,
            transportMode: transportMode,
          );
          if (freshnessBefore < 0.3) {
            totalPoints += 25;
          }
        } else {
          cellsByKey[key] = existingCell.refresh(now);
        }
      }

      final nextState = FootprintStorageState(
        cells: cellsByKey.values.toList(),
        legacyCells: storageState.legacyCells,
        onboardingSeen: storageState.onboardingSeen,
        lightMapMode: storageState.lightMapMode,
        totalPoints: totalPoints,
        totalDistanceMeters: totalDistanceMeters,
        totalVehicleDistanceMeters: totalVehicleDistanceMeters,
        todayDistanceMeters: todayDistanceMeters,
        todayDistanceDayKey: todayKey,
        currentStreak: streakUpdate.currentStreak,
        bestStreak: streakUpdate.bestStreak,
        streakLastDayKey: streakUpdate.streakLastDayKey,
        radarNudgeDayKey: storageState.radarNudgeDayKey,
        passiveTrackingEnabled: storageState.passiveTrackingEnabled,
        trackingPreferences: storageState.trackingPreferences,
        lastLatitude: point.latitude,
        lastLongitude: point.longitude,
        lastTrackedAt: now,
      );

    await FootprintBlocks.recordVisit(
      point: point,
      previousPoint: previousPoint,
      at: now,
      transportMode: transportMode,
    );

      _cachedStorageState = nextState;
      await _persistIfNeeded(
        storage: storage,
        storageState: nextState,
        now: now,
        force: persistImmediately,
      );

      return _snapshotFromState(nextState, now);
    });
  }

  static Future<void> flushPending() async {
    await _serialize(() async {
      _flushTimer?.cancel();
      _flushTimer = null;
      final storageState = _cachedStorageState;
      if (storageState == null) {
        return;
      }
      await _saveState(FootprintStorage(), storageState);
    });
  }

  static void invalidateCache() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _cachedStorageState = null;
    _lastFlushAt = null;
  }

  static double freshnessFor(FootprintCell cell, DateTime now) {
    final ratio =
        1 -
        (now.difference(cell.lastSeen).inSeconds /
            footprintForgetAfter.inSeconds);
    return ratio.clamp(0, 1).toDouble();
  }

  static double knownKilometersFor(
    Iterable<FootprintCell> cells,
    DateTime now,
  ) {
    return cells.fold<double>(0, (sum, cell) {
      final freshness = freshnessFor(cell, now);
      final weight = 1 + math.min(0.45, (cell.visits - 1) * 0.06);
      return sum +
          (FootprintH3Grid.knownKilometersContribution(cell) *
              freshness *
              weight);
    });
  }

  static double todayKilometersFor(FootprintSnapshot snapshot) {
    return snapshot.todayDistanceMeters / 1000;
  }

  static double totalDistanceKilometersFor(FootprintSnapshot snapshot) {
    return snapshot.totalDistanceMeters / 1000;
  }

  static double vehicleDistanceKilometersFor(FootprintSnapshot snapshot) {
    return snapshot.totalVehicleDistanceMeters / 1000;
  }

  static Future<void> _persistIfNeeded({
    required FootprintStorage storage,
    required FootprintStorageState storageState,
    required DateTime now,
    required bool force,
  }) async {
    final shouldFlushNow =
        force ||
        _lastFlushAt == null ||
        now.difference(_lastFlushAt!) >= const Duration(seconds: 45);

    if (shouldFlushNow) {
      await _saveState(storage, storageState);
      return;
    }

    _flushTimer ??= Timer(const Duration(seconds: 30), () async {
      await _serialize(() async {
        _flushTimer = null;
        final latestState = _cachedStorageState;
        if (latestState != null) {
          await _saveState(storage, latestState);
        }
      });
    });
  }

  static Future<void> _saveState(
    FootprintStorage storage,
    FootprintStorageState storageState,
  ) async {
    await storage.saveProgress(
      cells: storageState.cells,
      totalPoints: storageState.totalPoints,
      totalDistanceMeters: storageState.totalDistanceMeters,
      totalVehicleDistanceMeters: storageState.totalVehicleDistanceMeters,
      todayDistanceMeters: storageState.todayDistanceMeters,
      todayDistanceDayKey:
          storageState.todayDistanceDayKey ?? _dayKeyFor(DateTime.now()),
      currentStreak: storageState.currentStreak,
      bestStreak: storageState.bestStreak,
      streakLastDayKey: storageState.streakLastDayKey,
      radarNudgeDayKey: storageState.radarNudgeDayKey,
      lastLatLng: storageState.lastLatLng,
      lastTrackedAt: storageState.lastTrackedAt,
    );
    await FootprintBackupService.writeAutomaticBackup(storageState);
    _lastFlushAt = DateTime.now();
  }

  static Future<FootprintStorageState> _migrateLegacyCellsIfNeeded({
    required FootprintStorage storage,
    required FootprintStorageState storageState,
  }) async {
    if (!storageState.needsH3Migration) {
      return storageState;
    }

    final migratedCells = FootprintH3Grid.migrateLegacyCells(
      storageState.legacyCells,
    );
    final migratedState = storageState.copyWith(
      cells: migratedCells,
      legacyCells: const [],
    );
    await _saveState(storage, migratedState);
    return migratedState;
  }

  static Future<T> _serialize<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _writeQueue = _writeQueue.catchError((_) {});
    return completer.future;
  }

  static FootprintSnapshot _snapshotFromState(
    FootprintStorageState storageState,
    DateTime now,
  ) {
    return FootprintSnapshot(
      cells: storageState.cells,
      totalPoints: storageState.totalPoints,
      totalDistanceMeters: storageState.totalDistanceMeters,
      totalVehicleDistanceMeters: storageState.totalVehicleDistanceMeters,
      todayDistanceMeters: _todayDistanceMetersFor(storageState, now),
      currentStreak: storageState.currentStreak,
      bestStreak: storageState.bestStreak,
      lightMapMode: storageState.lightMapMode,
      passiveTrackingEnabled: storageState.passiveTrackingEnabled,
      trackingPreferences: storageState.trackingPreferences,
      onboardingSeen: storageState.onboardingSeen,
      lastLatLng: storageState.lastLatLng,
      lastTrackedAt: storageState.lastTrackedAt,
    );
  }

  static String _dayKeyFor(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  static double _todayDistanceMetersFor(
    FootprintStorageState storageState,
    DateTime now,
  ) {
    return storageState.todayDistanceDayKey == _dayKeyFor(now)
        ? storageState.todayDistanceMeters
        : 0;
  }

  static _StreakUpdate _resolveStreakUpdate({
    required String? previousDayKey,
    required String currentDayKey,
    required int currentStreak,
    required int bestStreak,
  }) {
    if (previousDayKey == currentDayKey) {
      return _StreakUpdate(
        currentStreak: currentStreak,
        bestStreak: bestStreak,
        streakLastDayKey: previousDayKey,
      );
    }

    final daysBetween = previousDayKey == null
        ? null
        : _daysBetweenDayKeys(previousDayKey, currentDayKey);
    final nextCurrentStreak = switch (daysBetween) {
      null => 1,
      0 => currentStreak,
      1 => currentStreak + 1,
      _ => 1,
    };
    final nextBestStreak = math.max(bestStreak, nextCurrentStreak);

    return _StreakUpdate(
      currentStreak: nextCurrentStreak,
      bestStreak: nextBestStreak,
      streakLastDayKey: currentDayKey,
    );
  }

  static int _daysBetweenDayKeys(String previousDayKey, String currentDayKey) {
    final previous = DateTime.parse(previousDayKey);
    final current = DateTime.parse(currentDayKey);
    return current.difference(previous).inDays;
  }
}

class _StreakUpdate {
  const _StreakUpdate({
    required this.currentStreak,
    required this.bestStreak,
    required this.streakLastDayKey,
  });

  final int currentStreak;
  final int bestStreak;
  final String? streakLastDayKey;
}
