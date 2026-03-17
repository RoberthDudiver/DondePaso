import 'dart:convert';

import 'package:latlong2/latlong.dart';

import 'footprint_transport.dart';

class FootprintRoadSegment {
  const FootprintRoadSegment({
    required this.id,
    required this.start,
    required this.end,
    required this.midpoint,
    required this.visits,
    this.walkingVisits = 0,
    this.vehicleVisits = 0,
    required this.lastSeen,
  });

  final String id;
  final LatLng start;
  final LatLng end;
  final LatLng midpoint;
  final int visits;
  final int walkingVisits;
  final int vehicleVisits;
  final DateTime? lastSeen;

  FootprintTransportMode get dominantTransport {
    if (vehicleVisits > walkingVisits && vehicleVisits > 0) {
      return FootprintTransportMode.vehicle;
    }
    if (walkingVisits > 0) {
      return FootprintTransportMode.walking;
    }
    return FootprintTransportMode.unknown;
  }

  Map<String, Object?> toRow() {
    return <String, Object?>{
      'id': id,
      'start_lat': start.latitude,
      'start_lon': start.longitude,
      'end_lat': end.latitude,
      'end_lon': end.longitude,
      'mid_lat': midpoint.latitude,
      'mid_lon': midpoint.longitude,
      'visits': visits,
      'walking_visits': walkingVisits,
      'vehicle_visits': vehicleVisits,
      'last_seen': lastSeen?.toIso8601String(),
    };
  }

  factory FootprintRoadSegment.fromRow(Map<String, Object?> row) {
    return FootprintRoadSegment(
      id: row['id'] as String,
      start: LatLng(
        (row['start_lat'] as num).toDouble(),
        (row['start_lon'] as num).toDouble(),
      ),
      end: LatLng(
        (row['end_lat'] as num).toDouble(),
        (row['end_lon'] as num).toDouble(),
      ),
      midpoint: LatLng(
        (row['mid_lat'] as num).toDouble(),
        (row['mid_lon'] as num).toDouble(),
      ),
      visits: ((row['visits'] as num?) ?? 0).toInt(),
      walkingVisits: ((row['walking_visits'] as num?) ?? 0).toInt(),
      vehicleVisits: ((row['vehicle_visits'] as num?) ?? 0).toInt(),
      lastSeen: row['last_seen'] == null
          ? null
          : DateTime.parse(row['last_seen'] as String),
    );
  }
}

class FootprintBlockRecord {
  const FootprintBlockRecord({
    required this.id,
    required this.points,
    required this.segmentIds,
    required this.center,
    required this.areaSquareMeters,
    required this.visits,
    this.walkingVisits = 0,
    this.vehicleVisits = 0,
    required this.lastSeen,
  });

  final String id;
  final List<LatLng> points;
  final List<String> segmentIds;
  final LatLng center;
  final double areaSquareMeters;
  final int visits;
  final int walkingVisits;
  final int vehicleVisits;
  final DateTime? lastSeen;

  FootprintTransportMode get dominantTransport {
    if (vehicleVisits > walkingVisits && vehicleVisits > 0) {
      return FootprintTransportMode.vehicle;
    }
    if (walkingVisits > 0) {
      return FootprintTransportMode.walking;
    }
    return FootprintTransportMode.unknown;
  }

  Map<String, Object?> toRow() {
    return <String, Object?>{
      'id': id,
      'points_json': jsonEncode(
        points
            .map(
              (point) => <String, double>{
                'lat': point.latitude,
                'lon': point.longitude,
              },
            )
            .toList(growable: false),
      ),
      'segment_ids_json': jsonEncode(segmentIds),
      'center_lat': center.latitude,
      'center_lon': center.longitude,
      'area_m2': areaSquareMeters,
      'visits': visits,
      'walking_visits': walkingVisits,
      'vehicle_visits': vehicleVisits,
      'last_seen': lastSeen?.toIso8601String(),
    };
  }

  factory FootprintBlockRecord.fromRow(Map<String, Object?> row) {
    final rawPoints = jsonDecode(row['points_json'] as String) as List<dynamic>;
    final rawSegmentIds =
        jsonDecode(row['segment_ids_json'] as String) as List<dynamic>;
    return FootprintBlockRecord(
      id: row['id'] as String,
      points: rawPoints
          .map(
            (item) => LatLng(
              (item as Map<String, dynamic>)['lat'] as double,
              item['lon'] as double,
            ),
          )
          .toList(growable: false),
      segmentIds: rawSegmentIds.cast<String>(),
      center: LatLng(
        (row['center_lat'] as num).toDouble(),
        (row['center_lon'] as num).toDouble(),
      ),
      areaSquareMeters: (row['area_m2'] as num).toDouble(),
      visits: ((row['visits'] as num?) ?? 0).toInt(),
      walkingVisits: ((row['walking_visits'] as num?) ?? 0).toInt(),
      vehicleVisits: ((row['vehicle_visits'] as num?) ?? 0).toInt(),
      lastSeen: row['last_seen'] == null
          ? null
          : DateTime.parse(row['last_seen'] as String),
    );
  }
}

class CapturedBlockSnapshot {
  const CapturedBlockSnapshot({
    required this.id,
    required this.points,
    required this.center,
    required this.areaSquareMeters,
    required this.coverageRatio,
    required this.visits,
    required this.transportMode,
    required this.lastSeen,
  });

  final String id;
  final List<LatLng> points;
  final LatLng center;
  final double areaSquareMeters;
  final double coverageRatio;
  final int visits;
  final FootprintTransportMode transportMode;
  final DateTime? lastSeen;
}
