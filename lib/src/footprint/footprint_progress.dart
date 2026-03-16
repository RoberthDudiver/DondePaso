import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'footprint_cell.dart';
import 'footprint_storage.dart';

const footprintBucketStep = 0.00022;
const footprintRevisitGap = Duration(minutes: 2);
const footprintForgetAfter = Duration(days: 14);
const footprintKnownKilometersPerCell = 0.032;

final Distance _distance = const Distance();

class FootprintSnapshot {
  const FootprintSnapshot({
    required this.cells,
    required this.totalPoints,
    required this.onboardingSeen,
    required this.lastLatLng,
    required this.lastTrackedAt,
  });

  final List<FootprintCell> cells;
  final int totalPoints;
  final bool onboardingSeen;
  final LatLng? lastLatLng;
  final DateTime? lastTrackedAt;
}

class FootprintProgress {
  FootprintProgress._();

  static Future<FootprintSnapshot> loadSnapshot() async {
    final storageState = await FootprintStorage().load();
    return FootprintSnapshot(
      cells: storageState.cells,
      totalPoints: storageState.totalPoints,
      onboardingSeen: storageState.onboardingSeen,
      lastLatLng: storageState.lastLatLng,
      lastTrackedAt: storageState.lastTrackedAt,
    );
  }

  static Future<FootprintSnapshot> recordVisit({
    required LatLng point,
    DateTime? at,
  }) async {
    final storage = FootprintStorage();
    final storageState = await storage.load();
    final now = at ?? DateTime.now();
    final cellsByKey = <String, FootprintCell>{
      for (final cell in storageState.cells) _keyFor(cell.latLng): cell,
    };
    var totalPoints = storageState.totalPoints;

    final key = _keyFor(point);
    final existingCell = cellsByKey[key];

    if (existingCell == null) {
      cellsByKey[key] = FootprintCell(
        latitude: _snap(point.latitude),
        longitude: _snap(point.longitude),
        visits: 1,
        lastSeen: now,
      );
      totalPoints += 120;
    } else {
      final freshnessBefore = freshnessFor(existingCell, now);
      final movedEnough =
          _distance.as(LengthUnit.Meter, point, existingCell.latLng) > 6;

      if (now.difference(existingCell.lastSeen) >= footprintRevisitGap &&
          movedEnough) {
        cellsByKey[key] = existingCell.registerVisit(now);
        if (freshnessBefore < 0.3) {
          totalPoints += 25;
        }
      } else {
        cellsByKey[key] = existingCell.refresh(now);
      }
    }

    final cells = cellsByKey.values.toList();
    await storage.saveProgress(
      cells: cells,
      totalPoints: totalPoints,
      lastLatLng: point,
      lastTrackedAt: now,
    );

    return FootprintSnapshot(
      cells: cells,
      totalPoints: totalPoints,
      onboardingSeen: storageState.onboardingSeen,
      lastLatLng: point,
      lastTrackedAt: now,
    );
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
      return sum + (footprintKnownKilometersPerCell * freshness * weight);
    });
  }

  static String _keyFor(LatLng point) {
    final lat = _snap(point.latitude).toStringAsFixed(5);
    final lng = _snap(point.longitude).toStringAsFixed(5);
    return '$lat:$lng';
  }

  static double _snap(double value) {
    return (value / footprintBucketStep).roundToDouble() * footprintBucketStep;
  }
}
