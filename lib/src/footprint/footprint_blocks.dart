import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'footprint_block_model.dart';
import 'footprint_progress.dart';
import 'footprint_storage.dart';
import 'footprint_transport.dart';

const double footprintBlockFetchRadiusMeters = 420;
const double footprintBlockRenderRadiusMeters = 520;
const double _blockBoundaryToleranceMeters = 12;
const double _minimumBlockAreaMeters = 180;
const double _maximumBlockAreaMeters = 52000;
const double _blockActivationCoverageThreshold = 0.96;

final Distance _blockDistance = const Distance();

class FootprintBlocks {
  FootprintBlocks._();

  static Future<void> recordVisit({
    required LatLng point,
    required LatLng? previousPoint,
    required DateTime at,
    required FootprintTransportMode transportMode,
  }) async {
    if (previousPoint == null) {
      await _ensureBlockNetwork(point);
      return;
    }

    final movementMeters = _blockDistance.as(
      LengthUnit.Meter,
      previousPoint,
      point,
    );
    if (movementMeters < 8) {
      return;
    }

    await _ensureBlockNetwork(point);

    final storage = FootprintStorage();
    final nearbyBlocks = await storage.loadBlocksNear(
      center: point,
      radiusMeters: footprintBlockFetchRadiusMeters * 1.1,
    );
    if (nearbyBlocks.isEmpty) {
      return;
    }

    final segmentIds = nearbyBlocks
        .expand((block) => block.segmentIds)
        .toSet();
    final segments = await storage.loadSegmentsByIds(segmentIds);
    if (segments.isEmpty) {
      return;
    }

    final touchedSegmentIds = _segmentsTouchedByMovement(
      segments.values,
      previousPoint: previousPoint,
      point: point,
    );
    if (touchedSegmentIds.isEmpty) {
      return;
    }

    await storage.markRoadSegmentsVisited(
      touchedSegmentIds,
      at: at,
      transportMode: transportMode,
    );
    final refreshedSegments = await storage.loadSegmentsByIds(segmentIds);

    final activatedBlocks = <String>{};
    for (final block in nearbyBlocks) {
      if (!block.segmentIds.any(touchedSegmentIds.contains)) {
        continue;
      }

      final coverage = _coverageForBlock(
        block,
        refreshedSegments,
        at,
      );
      if (coverage >= _blockActivationCoverageThreshold) {
        activatedBlocks.add(block.id);
      }
    }

    if (activatedBlocks.isNotEmpty) {
      await storage.activateBlocks(
        activatedBlocks,
        at: at,
        transportMode: transportMode,
      );
    }
  }

  static Future<List<CapturedBlockSnapshot>> loadVisibleBlocks({
    required LatLng center,
    required DateTime now,
  }) async {
    final storage = FootprintStorage();
    final blocks = await storage.loadBlocksNear(
      center: center,
      radiusMeters: footprintBlockRenderRadiusMeters,
    );
    if (blocks.isEmpty) {
      return const [];
    }

    final allSegmentIds = blocks.expand((block) => block.segmentIds).toSet();
    final segments = await storage.loadSegmentsByIds(allSegmentIds);

    final snapshots = <CapturedBlockSnapshot>[];
    for (final block in blocks) {
      final lastSeen = block.lastSeen;
      if (lastSeen == null) {
        continue;
      }

      final freshness =
          1 -
          (now.difference(lastSeen).inSeconds / footprintForgetAfter.inSeconds);
      if (freshness <= 0) {
        continue;
      }

      snapshots.add(
        CapturedBlockSnapshot(
          id: block.id,
          points: block.points,
          center: block.center,
          areaSquareMeters: block.areaSquareMeters,
          coverageRatio: _coverageForBlock(block, segments, now),
          visits: block.visits,
          transportMode: block.dominantTransport,
          lastSeen: block.lastSeen,
        ),
      );
    }

    snapshots.sort((a, b) {
      final freshnessA =
          1 -
          (now.difference(a.lastSeen!).inSeconds / footprintForgetAfter.inSeconds);
      final freshnessB =
          1 -
          (now.difference(b.lastSeen!).inSeconds / footprintForgetAfter.inSeconds);
      final freshnessComparison = freshnessB.compareTo(freshnessA);
      if (freshnessComparison != 0) {
        return freshnessComparison;
      }
      return b.coverageRatio.compareTo(a.coverageRatio);
    });

    return snapshots;
  }

  static Future<void> _ensureBlockNetwork(LatLng center) async {
    final storage = FootprintStorage();
    final nearbyBlocks = await storage.loadBlocksNear(
      center: center,
      radiusMeters: footprintBlockFetchRadiusMeters * 0.85,
    );
    if (nearbyBlocks.length >= 4) {
      return;
    }

    final network = await _downloadNetwork(center);
    if (network == null || network.blocks.isEmpty || network.segments.isEmpty) {
      return;
    }

    final existingSegments = await storage.loadSegmentsByIds(
      network.segments.map((segment) => segment.id),
    );
    final existingBlocks = await storage.loadBlocksByIds(
      network.blocks.map((block) => block.id),
    );

    final mergedSegments = network.segments
        .map((segment) {
          final existing = existingSegments[segment.id];
          if (existing == null) {
            return segment;
          }
          return FootprintRoadSegment(
            id: segment.id,
            start: segment.start,
            end: segment.end,
            midpoint: segment.midpoint,
            visits: existing.visits,
            lastSeen: existing.lastSeen,
          );
        })
        .toList(growable: false);

    final mergedBlocks = network.blocks
        .map((block) {
          final existing = existingBlocks[block.id];
          if (existing == null) {
            return block;
          }
          return FootprintBlockRecord(
            id: block.id,
            points: block.points,
            segmentIds: block.segmentIds,
            center: block.center,
            areaSquareMeters: block.areaSquareMeters,
            visits: existing.visits,
            lastSeen: existing.lastSeen,
          );
        })
        .toList(growable: false);

    await storage.saveBlockNetwork(
      segments: mergedSegments,
      blocks: mergedBlocks,
    );
  }

  static Future<_DownloadedBlockNetwork?> _downloadNetwork(LatLng center) async {
    final deltaLat = footprintBlockFetchRadiusMeters / 111320;
    final deltaLon =
        footprintBlockFetchRadiusMeters /
        (111320 * math.max(0.2, math.cos(center.latitude * math.pi / 180)));
    final south = center.latitude - deltaLat;
    final north = center.latitude + deltaLat;
    final west = center.longitude - deltaLon;
    final east = center.longitude + deltaLon;

    final query = '''
[out:json][timeout:25];
(
  way["highway"]
    ["highway"!~"motorway|trunk|primary|secondary|tertiary|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link|footway|path|cycleway|steps|track|corridor|service|pedestrian"]
    ($south,$west,$north,$east);
);
out geom;
''';

    try {
      final response = await http
          .post(
            Uri.parse('https://overpass-api.de/api/interpreter'),
            headers: const {
              'Content-Type': 'text/plain; charset=utf-8',
              'Accept': 'application/json',
              'User-Agent': 'DondePaso/1.0 (https://github.com/RoberthDudiver/DondePaso)',
            },
            body: query,
          )
          .timeout(const Duration(seconds: 18));

      if (response.statusCode != 200) {
        return null;
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = (payload['elements'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();

      final extraction = _buildBlockNetwork(
        elements,
        south: south,
        north: north,
        west: west,
        east: east,
      );
      return extraction;
    } catch (_) {
      return null;
    }
  }

  static _DownloadedBlockNetwork _buildBlockNetwork(
    List<Map<String, dynamic>> elements, {
    required double south,
    required double north,
    required double west,
    required double east,
  }) {
    final segmentsById = <String, FootprintRoadSegment>{};

    for (final element in elements) {
      if (element['type'] != 'way') {
        continue;
      }
      final geometry = (element['geometry'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      if (geometry.length < 2) {
        continue;
      }

      for (var index = 0; index < geometry.length - 1; index++) {
        final start = LatLng(
          (geometry[index]['lat'] as num).toDouble(),
          (geometry[index]['lon'] as num).toDouble(),
        );
        final end = LatLng(
          (geometry[index + 1]['lat'] as num).toDouble(),
          (geometry[index + 1]['lon'] as num).toDouble(),
        );
        final lengthMeters = _blockDistance.as(LengthUnit.Meter, start, end);
        if (lengthMeters < 8 || lengthMeters > 280) {
          continue;
        }

        final id = _segmentId(start, end);
        if (segmentsById.containsKey(id)) {
          continue;
        }
        segmentsById[id] = FootprintRoadSegment(
          id: id,
          start: start,
          end: end,
          midpoint: LatLng(
            (start.latitude + end.latitude) / 2,
            (start.longitude + end.longitude) / 2,
          ),
          visits: 0,
          lastSeen: null,
        );
      }
    }

    final graph = _RoadGraph.fromSegments(segmentsById.values.toList());
    final rawFaces = graph.extractFaces();
    if (rawFaces.isEmpty) {
      return _DownloadedBlockNetwork(
        segments: segmentsById.values.toList(growable: false),
        blocks: const [],
      );
    }

    final keptFaces = rawFaces
        .where((face) => !_touchesFetchBoundary(face.points, south, north, west, east))
        .where((face) => face.points.length >= 4 && face.points.length <= 12)
        .where((face) => face.areaSquareMeters >= _minimumBlockAreaMeters)
        .where((face) => face.areaSquareMeters <= _maximumBlockAreaMeters)
        .toList(growable: false);

    final blocks = keptFaces
        .map(
          (face) => FootprintBlockRecord(
            id: face.id,
            points: face.points,
            segmentIds: face.segmentIds,
            center: face.center,
            areaSquareMeters: face.areaSquareMeters,
            visits: 0,
            lastSeen: null,
          ),
        )
        .toList(growable: false);

    return _DownloadedBlockNetwork(
      segments: segmentsById.values.toList(growable: false),
      blocks: blocks,
    );
  }

  static Set<String> _segmentsTouchedByMovement(
    Iterable<FootprintRoadSegment> segments, {
    required LatLng previousPoint,
    required LatLng point,
  }) {
    final touched = <String>{};
    for (final segment in segments) {
      final distance = _distanceBetweenSegmentsMeters(
        previousPoint,
        point,
        segment.start,
        segment.end,
      );
      if (distance <= _blockBoundaryToleranceMeters) {
        touched.add(segment.id);
      }
    }
    return touched;
  }

  static double _coverageForBlock(
    FootprintBlockRecord block,
    Map<String, FootprintRoadSegment> segments,
    DateTime now,
  ) {
    if (block.segmentIds.isEmpty) {
      return 0;
    }

    var weightedCoverage = 0.0;
    var counted = 0;
    for (final segmentId in block.segmentIds) {
      final segment = segments[segmentId];
      if (segment == null) {
        continue;
      }
      counted += 1;
      final lastSeen = segment.lastSeen;
      if (lastSeen == null) {
        continue;
      }
      final freshness =
          1 -
          (now.difference(lastSeen).inSeconds / footprintForgetAfter.inSeconds);
      weightedCoverage += freshness.clamp(0, 1).toDouble();
    }

    if (counted == 0) {
      return 0;
    }
    return (weightedCoverage / counted).clamp(0, 1).toDouble();
  }

  static bool _touchesFetchBoundary(
    List<LatLng> points,
    double south,
    double north,
    double west,
    double east,
  ) {
    const boundaryMargin = 0.00012;
    for (final point in points) {
      if ((point.latitude - south).abs() <= boundaryMargin ||
          (point.latitude - north).abs() <= boundaryMargin ||
          (point.longitude - west).abs() <= boundaryMargin ||
          (point.longitude - east).abs() <= boundaryMargin) {
        return true;
      }
    }
    return false;
  }

  static String _segmentId(LatLng start, LatLng end) {
    final a = _nodeKey(start);
    final b = _nodeKey(end);
    return a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';
  }

  static String _nodeKey(LatLng point) {
    return '${point.latitude.toStringAsFixed(7)},${point.longitude.toStringAsFixed(7)}';
  }

  static double _distanceBetweenSegmentsMeters(
    LatLng a1,
    LatLng a2,
    LatLng b1,
    LatLng b2,
  ) {
    final anchor = LatLng(
      (a1.latitude + a2.latitude + b1.latitude + b2.latitude) / 4,
      (a1.longitude + a2.longitude + b1.longitude + b2.longitude) / 4,
    );
    final p1 = _project(anchor, a1);
    final p2 = _project(anchor, a2);
    final q1 = _project(anchor, b1);
    final q2 = _project(anchor, b2);

    if (_segmentsIntersect(p1, p2, q1, q2)) {
      return 0;
    }

    final d1 = _pointToSegmentDistance(p1, q1, q2);
    final d2 = _pointToSegmentDistance(p2, q1, q2);
    final d3 = _pointToSegmentDistance(q1, p1, p2);
    final d4 = _pointToSegmentDistance(q2, p1, p2);
    return math.min(math.min(d1, d2), math.min(d3, d4));
  }

  static _ProjectedPoint _project(LatLng anchor, LatLng point) {
    const earthMeters = 111320.0;
    final x =
        (point.longitude - anchor.longitude) *
        earthMeters *
        math.cos(anchor.latitude * math.pi / 180);
    final y = (point.latitude - anchor.latitude) * earthMeters;
    return _ProjectedPoint(x, y);
  }

  static bool _segmentsIntersect(
    _ProjectedPoint a,
    _ProjectedPoint b,
    _ProjectedPoint c,
    _ProjectedPoint d,
  ) {
    final o1 = _orientation(a, b, c);
    final o2 = _orientation(a, b, d);
    final o3 = _orientation(c, d, a);
    final o4 = _orientation(c, d, b);
    return o1 * o2 < 0 && o3 * o4 < 0;
  }

  static double _orientation(
    _ProjectedPoint a,
    _ProjectedPoint b,
    _ProjectedPoint c,
  ) {
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
  }

  static double _pointToSegmentDistance(
    _ProjectedPoint p,
    _ProjectedPoint a,
    _ProjectedPoint b,
  ) {
    final abx = b.x - a.x;
    final aby = b.y - a.y;
    final apx = p.x - a.x;
    final apy = p.y - a.y;
    final abLengthSquared = (abx * abx) + (aby * aby);
    if (abLengthSquared == 0) {
      return math.sqrt((apx * apx) + (apy * apy));
    }

    final t = ((apx * abx) + (apy * aby)) / abLengthSquared;
    final clampedT = t.clamp(0, 1);
    final closestX = a.x + (abx * clampedT);
    final closestY = a.y + (aby * clampedT);
    final dx = p.x - closestX;
    final dy = p.y - closestY;
    return math.sqrt((dx * dx) + (dy * dy));
  }
}

class _DownloadedBlockNetwork {
  const _DownloadedBlockNetwork({
    required this.segments,
    required this.blocks,
  });

  final List<FootprintRoadSegment> segments;
  final List<FootprintBlockRecord> blocks;
}

class _RoadGraph {
  _RoadGraph._({
    required this.nodes,
    required this.outgoing,
  });

  final Map<String, LatLng> nodes;
  final Map<String, List<_DirectedEdge>> outgoing;

  factory _RoadGraph.fromSegments(List<FootprintRoadSegment> segments) {
    final nodes = <String, LatLng>{};
    final outgoing = <String, List<_DirectedEdge>>{};

    for (final segment in segments) {
      final startKey = FootprintBlocks._nodeKey(segment.start);
      final endKey = FootprintBlocks._nodeKey(segment.end);
      nodes[startKey] = segment.start;
      nodes[endKey] = segment.end;
      final forward = _DirectedEdge(
        fromKey: startKey,
        toKey: endKey,
        segmentId: segment.id,
      );
      final backward = _DirectedEdge(
        fromKey: endKey,
        toKey: startKey,
        segmentId: segment.id,
      );
      outgoing.putIfAbsent(startKey, () => <_DirectedEdge>[]).add(forward);
      outgoing.putIfAbsent(endKey, () => <_DirectedEdge>[]).add(backward);
    }

    for (final entry in outgoing.entries) {
      final origin = nodes[entry.key]!;
      entry.value.sort((a, b) {
        final angleA = a.angleFrom(origin, nodes[a.toKey]!);
        final angleB = b.angleFrom(origin, nodes[b.toKey]!);
        return angleA.compareTo(angleB);
      });
    }

    return _RoadGraph._(nodes: nodes, outgoing: outgoing);
  }

  List<_FacePolygon> extractFaces() {
    final faces = <_FacePolygon>[];
    final visited = <String>{};
    final seenFaceKeys = <String>{};

    for (final edges in outgoing.values) {
      for (final edge in edges) {
        final directedKey = edge.directedKey;
        if (visited.contains(directedKey)) {
          continue;
        }

        final boundaryEdges = <_DirectedEdge>[];
        final boundaryNodes = <String>[];
        var current = edge;
        var closed = false;

        for (var guard = 0; guard < 64; guard++) {
          final currentKey = current.directedKey;
          if (visited.contains(currentKey) && currentKey != directedKey) {
            break;
          }
          visited.add(currentKey);
          boundaryEdges.add(current);
          boundaryNodes.add(current.fromKey);

          final next = _nextFaceEdge(current);
          if (next == null) {
            break;
          }
          current = next;
          if (current.directedKey == directedKey) {
            closed = true;
            break;
          }
        }

        if (!closed || boundaryNodes.length < 3) {
          continue;
        }

        final faceKey = _normalizedFaceKey(boundaryEdges);
        if (!seenFaceKeys.add(faceKey)) {
          continue;
        }

        final points = boundaryNodes
            .map((nodeKey) => nodes[nodeKey]!)
            .toList(growable: false);
        final area = _polygonArea(points).abs();
        if (area <= 0) {
          continue;
        }
        faces.add(
          _FacePolygon(
            id: faceKey,
            points: points,
            segmentIds: boundaryEdges
                .map((edge) => edge.segmentId)
                .toSet()
                .toList(growable: false),
            center: _polygonCenter(points),
            areaSquareMeters: area,
          ),
        );
      }
    }

    if (faces.length <= 1) {
      return faces;
    }

    faces.sort((a, b) => a.areaSquareMeters.compareTo(b.areaSquareMeters));
    return faces.sublist(0, faces.length - 1);
  }

  _DirectedEdge? _nextFaceEdge(_DirectedEdge current) {
    final nextEdges = outgoing[current.toKey];
    if (nextEdges == null || nextEdges.isEmpty) {
      return null;
    }
    final reverseIndex = nextEdges.indexWhere((edge) => edge.toKey == current.fromKey);
    if (reverseIndex == -1) {
      return null;
    }
    final nextIndex = (reverseIndex - 1 + nextEdges.length) % nextEdges.length;
    return nextEdges[nextIndex];
  }

  String _normalizedFaceKey(List<_DirectedEdge> edges) {
    final ids = edges.map((edge) => edge.segmentId).toSet().toList(growable: false)
      ..sort();
    return ids.join('>');
  }

  double _polygonArea(List<LatLng> points) {
    final anchor = _polygonCenter(points);
    final projected = points
        .map((point) => FootprintBlocks._project(anchor, point))
        .toList(growable: false);
    var area = 0.0;
    for (var index = 0; index < projected.length; index++) {
      final current = projected[index];
      final next = projected[(index + 1) % projected.length];
      area += (current.x * next.y) - (next.x * current.y);
    }
    return area.abs() / 2;
  }

  LatLng _polygonCenter(List<LatLng> points) {
    var lat = 0.0;
    var lon = 0.0;
    for (final point in points) {
      lat += point.latitude;
      lon += point.longitude;
    }
    return LatLng(lat / points.length, lon / points.length);
  }
}

class _DirectedEdge {
  const _DirectedEdge({
    required this.fromKey,
    required this.toKey,
    required this.segmentId,
  });

  final String fromKey;
  final String toKey;
  final String segmentId;

  String get directedKey => '$fromKey->$toKey';

  double angleFrom(LatLng origin, LatLng destination) {
    final dy = destination.latitude - origin.latitude;
    final dx = destination.longitude - origin.longitude;
    return math.atan2(dy, dx);
  }
}

class _FacePolygon {
  const _FacePolygon({
    required this.id,
    required this.points,
    required this.segmentIds,
    required this.center,
    required this.areaSquareMeters,
  });

  final String id;
  final List<LatLng> points;
  final List<String> segmentIds;
  final LatLng center;
  final double areaSquareMeters;
}

class _ProjectedPoint {
  const _ProjectedPoint(this.x, this.y);

  final double x;
  final double y;
}
