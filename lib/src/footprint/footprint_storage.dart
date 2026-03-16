import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../background/tracking_preferences.dart';
import 'footprint_cell.dart';

class FootprintStorageState {
  const FootprintStorageState({
    required this.cells,
    required this.onboardingSeen,
    required this.totalPoints,
    required this.totalDistanceMeters,
    required this.todayDistanceMeters,
    required this.todayDistanceDayKey,
    required this.passiveTrackingEnabled,
    required this.trackingPreferences,
    required this.lastLatitude,
    required this.lastLongitude,
    required this.lastTrackedAt,
  });

  final List<FootprintCell> cells;
  final bool onboardingSeen;
  final int totalPoints;
  final double totalDistanceMeters;
  final double todayDistanceMeters;
  final String? todayDistanceDayKey;
  final bool passiveTrackingEnabled;
  final PassiveTrackingPreferences trackingPreferences;
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
  static const _totalDistanceMetersKey = 'footprint_total_distance_meters';
  static const _todayDistanceMetersKey = 'footprint_today_distance_meters';
  static const _todayDistanceDayKey = 'footprint_today_distance_day_key';
  static const _passiveTrackingEnabledKey = 'footprint_passive_tracking';
  static const _trackingProfileKey = 'footprint_tracking_profile';
  static const _trackingCustomDistanceKey =
      'footprint_tracking_custom_distance';
  static const _trackingCustomIntervalKey =
      'footprint_tracking_custom_interval';
  static const _trackingAdaptiveModeKey = 'footprint_tracking_adaptive';
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
      totalDistanceMeters: prefs.getDouble(_totalDistanceMetersKey) ?? 0,
      todayDistanceMeters: prefs.getDouble(_todayDistanceMetersKey) ?? 0,
      todayDistanceDayKey: prefs.getString(_todayDistanceDayKey),
      passiveTrackingEnabled:
          prefs.getBool(_passiveTrackingEnabledKey) ?? true,
      trackingPreferences: PassiveTrackingPreferences(
        profile: PassiveTrackingProfileCodec.fromStorage(
          prefs.getString(_trackingProfileKey),
        ),
        customDistanceFilterMeters:
            prefs.getInt(_trackingCustomDistanceKey) ??
            PassiveTrackingPreferences
                .defaultPreferences
                .customDistanceFilterMeters,
        customIntervalSeconds:
            prefs.getInt(_trackingCustomIntervalKey) ??
            PassiveTrackingPreferences
                .defaultPreferences
                .customIntervalSeconds,
        adaptiveModeEnabled:
            prefs.getBool(_trackingAdaptiveModeKey) ??
            PassiveTrackingPreferences.defaultPreferences.adaptiveModeEnabled,
      ),
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
    required double totalDistanceMeters,
    required double todayDistanceMeters,
    required String todayDistanceDayKey,
    required LatLng? lastLatLng,
    required DateTime? lastTrackedAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cellsKey, FootprintCell.encodeList(cells));
    await prefs.setInt(_pointsKey, totalPoints);
    await prefs.setDouble(_totalDistanceMetersKey, totalDistanceMeters);
    await prefs.setDouble(_todayDistanceMetersKey, todayDistanceMeters);
    await prefs.setString(_todayDistanceDayKey, todayDistanceDayKey);
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

  Future<void> setPassiveTrackingEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_passiveTrackingEnabledKey, enabled);
  }

  Future<void> saveTrackingPreferences(
    PassiveTrackingPreferences preferences,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _trackingProfileKey,
      preferences.profile.storageValue,
    );
    await prefs.setInt(
      _trackingCustomDistanceKey,
      preferences.customDistanceFilterMeters,
    );
    await prefs.setInt(
      _trackingCustomIntervalKey,
      preferences.customIntervalSeconds,
    );
    await prefs.setBool(
      _trackingAdaptiveModeKey,
      preferences.adaptiveModeEnabled,
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cellsKey);
    await prefs.remove(_pointsKey);
    await prefs.remove(_totalDistanceMetersKey);
    await prefs.remove(_todayDistanceMetersKey);
    await prefs.remove(_todayDistanceDayKey);
    await prefs.remove(_trackingProfileKey);
    await prefs.remove(_trackingCustomDistanceKey);
    await prefs.remove(_trackingCustomIntervalKey);
    await prefs.remove(_trackingAdaptiveModeKey);
    await prefs.remove(_lastLatitudeKey);
    await prefs.remove(_lastLongitudeKey);
    await prefs.remove(_lastTrackedAtKey);
    await prefs.remove('activity_day_key');
    await prefs.remove('activity_base_steps');
    await prefs.remove('activity_daily_steps');
  }
}
