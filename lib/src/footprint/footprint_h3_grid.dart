import 'dart:math' as math;

import 'package:h3_flutter/h3_flutter.dart';
import 'package:latlong2/latlong.dart';

import 'footprint_cell.dart';
import 'footprint_transport.dart';

const footprintH3Resolution = 11;

H3? _cachedH3;
double? _cachedBaseKnownKilometersPerCell;

H3 get _h3 => _cachedH3 ??= const H3Factory().load();

class FootprintH3Grid {
  FootprintH3Grid._();

  static final Map<String, List<LatLng>> _boundaryCache =
      <String, List<LatLng>>{};

  static FootprintCell cellForPoint(
    LatLng point, {
    required DateTime lastSeen,
    int visits = 1,
    double coverageWeight = 1,
    FootprintTransportMode transportMode = FootprintTransportMode.unknown,
  }) {
    final index = _indexForPoint(point);
    return cellForIndex(
      index,
      lastSeen: lastSeen,
      visits: visits,
      coverageWeight: coverageWeight,
      transportMode: transportMode,
    );
  }

  static FootprintCell cellForIndex(
    H3Index index, {
    required DateTime lastSeen,
    int visits = 1,
    double coverageWeight = 1,
    FootprintTransportMode transportMode = FootprintTransportMode.unknown,
  }) {
    final center = _h3.cellToGeo(index);
    return FootprintCell(
      latitude: center.lat,
      longitude: center.lon,
      visits: visits,
      lastSeen: lastSeen,
      h3Index: index.toString(),
      coverageWeight: coverageWeight,
      walkingVisits: transportMode == FootprintTransportMode.walking ? visits : 0,
      vehicleVisits: transportMode == FootprintTransportMode.vehicle ? visits : 0,
    );
  }

  static String keyForPoint(LatLng point) => _indexForPoint(point).toString();

  static List<LatLng> boundaryForCell(FootprintCell cell) {
    final indexString = cell.h3Index;
    if (indexString == null) {
      return const <LatLng>[];
    }

    return _boundaryCache.putIfAbsent(indexString, () {
      final boundary = _h3.cellToBoundary(BigInt.parse(indexString));
      return boundary
          .map((coord) => LatLng(coord.lat, coord.lon))
          .toList(growable: false);
    });
  }

  static List<FootprintCell> migrateLegacyCells(Iterable<FootprintCell> legacy) {
    final aggregated = <String, _MigrationBucket>{};

    for (final cell in legacy) {
      if (cell.isH3) {
        aggregated.update(
          cell.storageKey,
          (bucket) => bucket.merge(cell),
          ifAbsent: () => _MigrationBucket.fromCell(cell),
        );
        continue;
      }

      final migratedKey = keyForPoint(cell.latLng);
      aggregated.update(
        migratedKey,
        (bucket) => bucket.absorbLegacy(cell),
        ifAbsent: () => _MigrationBucket.fromLegacy(cell),
      );
    }

    return aggregated.values
        .map((bucket) => bucket.toFootprintCell())
        .toList(growable: false);
  }

  static double knownKilometersContribution(FootprintCell cell) {
    final coverageBoost = 1 + ((cell.coverageWeight - 1) * 0.35);
    return _baseKnownKilometersPerCell() * coverageBoost.clamp(1, 1.7);
  }

  static H3Index _indexForPoint(LatLng point) {
    return _h3.geoToCell(
      GeoCoord(lon: point.longitude, lat: point.latitude),
      footprintH3Resolution,
    );
  }

  static double _baseKnownKilometersPerCell() {
    return _cachedBaseKnownKilometersPerCell ??=
        math.sqrt(
          _h3.getHexagonAreaAvg(footprintH3Resolution, H3MetricUnits.km),
        ) *
        1.25;
  }
}

class _MigrationBucket {
  _MigrationBucket({
    required this.indexString,
    required this.visits,
    required this.lastSeen,
    required this.coverageWeight,
  });

  factory _MigrationBucket.fromCell(FootprintCell cell) {
    return _MigrationBucket(
      indexString: cell.storageKey,
      visits: cell.visits,
      lastSeen: cell.lastSeen,
      coverageWeight: cell.coverageWeight,
    );
  }

  factory _MigrationBucket.fromLegacy(FootprintCell cell) {
    return _MigrationBucket(
      indexString: FootprintH3Grid.keyForPoint(cell.latLng),
      visits: cell.visits,
      lastSeen: cell.lastSeen,
      coverageWeight: 1,
    );
  }

  final String indexString;
  int visits;
  DateTime lastSeen;
  double coverageWeight;

  _MigrationBucket absorbLegacy(FootprintCell cell) {
    visits += cell.visits;
    if (cell.lastSeen.isAfter(lastSeen)) {
      lastSeen = cell.lastSeen;
    }
    coverageWeight = (coverageWeight + 0.18).clamp(1, 1.8);
    return this;
  }

  _MigrationBucket merge(FootprintCell cell) {
    visits += cell.visits;
    if (cell.lastSeen.isAfter(lastSeen)) {
      lastSeen = cell.lastSeen;
    }
    coverageWeight = math.max(coverageWeight, cell.coverageWeight);
    return this;
  }

  FootprintCell toFootprintCell() {
    return FootprintH3Grid.cellForIndex(
      BigInt.parse(indexString),
      lastSeen: lastSeen,
      visits: visits,
      coverageWeight: coverageWeight,
    );
  }
}
