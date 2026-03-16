import 'dart:convert';

import 'package:latlong2/latlong.dart';

class FootprintCell {
  const FootprintCell({
    required this.latitude,
    required this.longitude,
    required this.visits,
    required this.lastSeen,
  });

  final double latitude;
  final double longitude;
  final int visits;
  final DateTime lastSeen;

  LatLng get latLng => LatLng(latitude, longitude);

  FootprintCell refresh(DateTime timestamp) {
    return FootprintCell(
      latitude: latitude,
      longitude: longitude,
      visits: visits,
      lastSeen: timestamp,
    );
  }

  FootprintCell registerVisit(DateTime timestamp) {
    return FootprintCell(
      latitude: latitude,
      longitude: longitude,
      visits: visits + 1,
      lastSeen: timestamp,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
      'visits': visits,
      'lastSeen': lastSeen.toIso8601String(),
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
