import 'dart:math' as math;

import 'package:h3_flutter/h3_flutter.dart';

import 'footprint_cell.dart';
import 'footprint_h3_grid.dart';
import 'footprint_progress.dart';

final H3 _zonesH3 = const H3Factory().load();

class FootprintZone {
  const FootprintZone({
    required this.title,
    required this.centerLatitude,
    required this.centerLongitude,
    required this.zoneKey,
    required this.discoveredCells,
    required this.totalCellsEstimate,
    required this.knownKilometers,
    required this.averageFreshness,
    required this.totalVisits,
  });

  final String title;
  final double centerLatitude;
  final double centerLongitude;
  final String zoneKey;
  final int discoveredCells;
  final int totalCellsEstimate;
  final double knownKilometers;
  final double averageFreshness;
  final int totalVisits;

  double get discoveredRatio {
    if (totalCellsEstimate <= 0) {
      return 0;
    }
    return (discoveredCells / totalCellsEstimate).clamp(0, 1).toDouble();
  }
}

class FootprintZonesSnapshot {
  const FootprintZonesSnapshot({
    required this.primaryZone,
    required this.zones,
  });

  final FootprintZone? primaryZone;
  final List<FootprintZone> zones;
}

class FootprintZones {
  FootprintZones._();

  static const int zoneParentResolution = 9;
  static const int estimatedCellsPerZone = 49;

  static FootprintZonesSnapshot build({
    required List<FootprintCell> cells,
    required DateTime now,
  }) {
    final h3Cells = cells.where((cell) => cell.isH3).toList(growable: false);
    if (h3Cells.isEmpty) {
      return const FootprintZonesSnapshot(primaryZone: null, zones: []);
    }

    final buckets = <String, _ZoneAccumulator>{};
    for (final cell in h3Cells) {
      final zoneKey = _zoneKeyFor(cell);
      buckets.update(
        zoneKey,
        (bucket) {
          bucket.add(cell, now);
          return bucket;
        },
        ifAbsent: () => _ZoneAccumulator(zoneKey)..add(cell, now),
      );
    }

    final zones = buckets.values
        .map((bucket) => bucket.toZone())
        .toList(growable: false)
      ..sort((a, b) {
        final ratioComparison = b.discoveredRatio.compareTo(a.discoveredRatio);
        if (ratioComparison != 0) {
          return ratioComparison;
        }
        return b.knownKilometers.compareTo(a.knownKilometers);
      });

    return FootprintZonesSnapshot(
      primaryZone: zones.isEmpty ? null : zones.first,
      zones: zones.take(6).toList(growable: false),
    );
  }

  static String _zoneKeyFor(FootprintCell cell) {
    final index = BigInt.parse(cell.h3Index!);
    final parent = _zonesH3.cellToParent(index, zoneParentResolution);
    return parent.toString();
  }
}

class _ZoneAccumulator {
  _ZoneAccumulator(this.zoneKey);

  final String zoneKey;
  final List<FootprintCell> _cells = <FootprintCell>[];
  double _freshnessSum = 0;
  double _knownKilometers = 0;
  int _totalVisits = 0;

  void add(FootprintCell cell, DateTime now) {
    _cells.add(cell);
    _freshnessSum += FootprintProgress.freshnessFor(cell, now);
    _knownKilometers +=
        FootprintH3Grid.knownKilometersContribution(cell) *
        FootprintProgress.freshnessFor(cell, now);
    _totalVisits += cell.visits;
  }

  FootprintZone toZone() {
    final discoveredCells = _cells.length;
    final estimatedTotalCells = math.max(
      FootprintZones.estimatedCellsPerZone,
      discoveredCells,
    );
    final center = _zonesH3.cellToGeo(BigInt.parse(zoneKey));
    final suffix = zoneKey.length > 4 ? zoneKey.substring(zoneKey.length - 4) : zoneKey;
    final title = 'Area $suffix';

    return FootprintZone(
      title: title,
      centerLatitude: center.lat,
      centerLongitude: center.lon,
      zoneKey: zoneKey,
      discoveredCells: discoveredCells,
      totalCellsEstimate: estimatedTotalCells,
      knownKilometers: _knownKilometers,
      averageFreshness: discoveredCells == 0 ? 0 : _freshnessSum / discoveredCells,
      totalVisits: _totalVisits,
    );
  }
}
