import 'dart:convert';

import 'package:latlong2/latlong.dart';

import 'footprint_transport.dart';

class FootprintCell {
  const FootprintCell({
    required this.latitude,
    required this.longitude,
    required this.visits,
    required this.lastSeen,
    this.h3Index,
    this.coverageWeight = 1,
    this.walkingVisits = 0,
    this.vehicleVisits = 0,
  });

  final double latitude;
  final double longitude;
  final int visits;
  final DateTime lastSeen;
  final String? h3Index;
  final double coverageWeight;
  final int walkingVisits;
  final int vehicleVisits;

  LatLng get latLng => LatLng(latitude, longitude);
  bool get isH3 => h3Index != null;
  String get storageKey =>
      h3Index ?? '${latitude.toStringAsFixed(5)}:${longitude.toStringAsFixed(5)}';
  FootprintTransportMode get dominantTransport {
    if (vehicleVisits > walkingVisits && vehicleVisits > 0) {
      return FootprintTransportMode.vehicle;
    }
    if (walkingVisits > 0) {
      return FootprintTransportMode.walking;
    }
    return FootprintTransportMode.unknown;
  }

  FootprintCell refresh(DateTime timestamp) {
    return FootprintCell(
      latitude: latitude,
      longitude: longitude,
      visits: visits,
      lastSeen: timestamp,
      h3Index: h3Index,
      coverageWeight: coverageWeight,
      walkingVisits: walkingVisits,
      vehicleVisits: vehicleVisits,
    );
  }

  FootprintCell registerVisit(
    DateTime timestamp, {
    FootprintTransportMode transportMode = FootprintTransportMode.unknown,
  }) {
    return FootprintCell(
      latitude: latitude,
      longitude: longitude,
      visits: visits + 1,
      lastSeen: timestamp,
      h3Index: h3Index,
      coverageWeight: coverageWeight,
      walkingVisits: walkingVisits +
          (transportMode == FootprintTransportMode.walking ? 1 : 0),
      vehicleVisits: vehicleVisits +
          (transportMode == FootprintTransportMode.vehicle ? 1 : 0),
    );
  }

  FootprintCell copyWith({
    double? latitude,
    double? longitude,
    int? visits,
    DateTime? lastSeen,
    String? h3Index,
    double? coverageWeight,
    int? walkingVisits,
    int? vehicleVisits,
  }) {
    return FootprintCell(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      visits: visits ?? this.visits,
      lastSeen: lastSeen ?? this.lastSeen,
      h3Index: h3Index ?? this.h3Index,
      coverageWeight: coverageWeight ?? this.coverageWeight,
      walkingVisits: walkingVisits ?? this.walkingVisits,
      vehicleVisits: vehicleVisits ?? this.vehicleVisits,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
      'visits': visits,
      'lastSeen': lastSeen.toIso8601String(),
      if (h3Index != null) 'h3Index': h3Index,
      'coverageWeight': coverageWeight,
      'walkingVisits': walkingVisits,
      'vehicleVisits': vehicleVisits,
    };
  }

  static FootprintCell fromMap(Map<String, dynamic> map) {
    return FootprintCell(
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      visits: ((map['visits'] as num?) ?? 1).toInt(),
      lastSeen: DateTime.parse(
        (map['lastSeen'] as String?) ?? DateTime.now().toIso8601String(),
      ),
      h3Index: map['h3Index'] as String?,
      coverageWeight: (map['coverageWeight'] as num?)?.toDouble() ?? 1,
      walkingVisits: ((map['walkingVisits'] as num?) ?? 0).toInt(),
      vehicleVisits: ((map['vehicleVisits'] as num?) ?? 0).toInt(),
    );
  }

  static String encodeList(List<FootprintCell> cells) {
    return jsonEncode(cells.map((cell) => cell.toMap()).toList());
  }

  static List<FootprintCell> decodeList(String raw) {
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map(
          (item) => FootprintCell.fromMap(
            Map<String, dynamic>.from(item as Map<dynamic, dynamic>),
          ),
        )
        .toList();
  }
}
