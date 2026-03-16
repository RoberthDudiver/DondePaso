import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'footprint_cell.dart';

class FootprintStorageState {
  const FootprintStorageState({
    required this.cells,
    required this.onboardingSeen,
    required this.totalPoints,
    required this.lastLatitude,
    required this.lastLongitude,
    required this.lastTrackedAt,
  });

  final List<FootprintCell> cells;
  final bool onboardingSeen;
  final int totalPoints;
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
}

class FootprintStorage {
  static const _cellsKey = 'footprint_cells';
  static const _onboardingKey = 'footprint_onboarding_seen';
  static const _pointsKey = 'footprint_total_points';
  static const _lastLatitudeKey = 'footprint_last_latitude';
  static const _lastLongitudeKey = 'footprint_last_longitude';
  static const _lastTrackedAtKey = 'footprint_last_tracked_at';

  Future<FootprintStorageState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawCells = prefs.getString(_cellsKey);
    final lastTrackedAt = prefs.getString(_lastTrackedAtKey);

    return FootprintStorageState(
      cells: rawCells == null ? const [] : FootprintCell.decodeList(rawCells),
      onboardingSeen: prefs.getBool(_onboardingKey) ?? false,
      totalPoints: prefs.getInt(_pointsKey) ?? 0,
      lastLatitude: prefs.getDouble(_lastLatitudeKey),
      lastLongitude: prefs.getDouble(_lastLongitudeKey),
      lastTrackedAt: lastTrackedAt == null
          ? null
          : DateTime.parse(lastTrackedAt),
    );
  }

  Future<void> saveProgress({
    required List<FootprintCell> cells,
    required int totalPoints,
    required LatLng? lastLatLng,
    required DateTime? lastTrackedAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cellsKey, FootprintCell.encodeList(cells));
    await prefs.setInt(_pointsKey, totalPoints);
    final latitude = lastLatLng?.latitude;
    final longitude = lastLatLng?.longitude;
    if (latitude != null && longitude != null) {
      await prefs.setDouble(_lastLatitudeKey, latitude);
      await prefs.setDouble(_lastLongitudeKey, longitude);
    }
    if (lastTrackedAt != null) {
      await prefs.setString(_lastTrackedAtKey, lastTrackedAt.toIso8601String());
    }
  }

  Future<void> setOnboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingKey, true);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cellsKey);
    await prefs.remove(_pointsKey);
    await prefs.remove(_lastLatitudeKey);
    await prefs.remove(_lastLongitudeKey);
    await prefs.remove(_lastTrackedAtKey);
    await prefs.remove('activity_day_key');
    await prefs.remove('activity_base_steps');
    await prefs.remove('activity_daily_steps');
  }
}
