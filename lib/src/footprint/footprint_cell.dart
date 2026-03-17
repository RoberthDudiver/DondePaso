import 'dart:convert';

import 'package:latlong2/latlong.dart';

class FootprintCell {
  const FootprintCell({
    required this.latitude,
    required this.longitude,
    required this.visits,
    required this.lastSeen,
    this.h3Index,
    this.coverageWeight = 1,
  });

  final double latitude;
  final double longitude;
  final int visits;
  final DateTime lastSeen;
  final String? h3Index;
  final double coverageWeight;

  LatLng get latLng => LatLng(latitude, longitude);
  bool get isH3 => h3Index != null;
  String get storageKey =>
      h3Index ?? '${latitude.toStringAsFixed(5)}:${longitude.toStringAsFixed(5)}';

  FootprintCell refresh(DateTime timestamp) {
    return FootprintCell(
      latitude: latitude,
      longitude: longitude,
      visits: visits,
      lastSeen: timestamp,
      h3Index: h3Index,
      coverageWeight: coverageWeight,
    );
  }

  FootprintCell registerVisit(DateTime timestamp) {
    return FootprintCell(
      latitude: latitude,
      longitude: longitude,
      visits: visits + 1,
      lastSeen: timestamp,
      h3Index: h3Index,
      coverageWeight: coverageWeight,
    );
  }

  FootprintCell copyWith({
    double? latitude,
    double? longitude,
    int? visits,
    DateTime? lastSeen,
    String? h3Index,
    double? coverageWeight,
  }) {
    return FootprintCell(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      visits: visits ?? this.visits,
      lastSeen: lastSeen ?? this.lastSeen,
      h3Index: h3Index ?? this.h3Index,
      coverageWeight: coverageWeight ?? this.coverageWeight,
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
