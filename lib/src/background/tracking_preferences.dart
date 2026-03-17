import 'package:geolocator/geolocator.dart';

enum PassiveTrackingProfile { batterySaver, balanced, precise, custom }

class PassiveTrackingPreferences {
  const PassiveTrackingPreferences({
    required this.profile,
    required this.customDistanceFilterMeters,
    required this.customIntervalSeconds,
    required this.adaptiveModeEnabled,
  });

  final PassiveTrackingProfile profile;
  final int customDistanceFilterMeters;
  final int customIntervalSeconds;
  final bool adaptiveModeEnabled;

  static const defaultPreferences = PassiveTrackingPreferences(
    profile: PassiveTrackingProfile.balanced,
    customDistanceFilterMeters: 14,
    customIntervalSeconds: 12,
    adaptiveModeEnabled: true,
  );

  PassiveTrackingPreferences copyWith({
    PassiveTrackingProfile? profile,
    int? customDistanceFilterMeters,
    int? customIntervalSeconds,
    bool? adaptiveModeEnabled,
  }) {
    return PassiveTrackingPreferences(
      profile: profile ?? this.profile,
      customDistanceFilterMeters:
          customDistanceFilterMeters ?? this.customDistanceFilterMeters,
      customIntervalSeconds:
          customIntervalSeconds ?? this.customIntervalSeconds,
      adaptiveModeEnabled: adaptiveModeEnabled ?? this.adaptiveModeEnabled,
    );
  }
}

class PassiveTrackingTuning {
  const PassiveTrackingTuning({
    required this.accuracy,
    required this.distanceFilterMeters,
    required this.interval,
  });

  final LocationAccuracy accuracy;
  final int distanceFilterMeters;
  final Duration interval;
}

extension PassiveTrackingProfileCodec on PassiveTrackingProfile {
  String get storageValue {
    switch (this) {
      case PassiveTrackingProfile.batterySaver:
        return 'battery_saver';
      case PassiveTrackingProfile.balanced:
        return 'balanced';
      case PassiveTrackingProfile.precise:
        return 'precise';
      case PassiveTrackingProfile.custom:
        return 'custom';
    }
  }

  static PassiveTrackingProfile fromStorage(String? raw) {
    switch (raw) {
      case 'battery_saver':
        return PassiveTrackingProfile.batterySaver;
      case 'precise':
        return PassiveTrackingProfile.precise;
      case 'custom':
        return PassiveTrackingProfile.custom;
      case 'balanced':
      default:
        return PassiveTrackingProfile.balanced;
    }
  }
}

PassiveTrackingTuning resolveTrackingTuning(
  PassiveTrackingPreferences preferences, {
  required bool reducedMode,
}) {
  final base = switch (preferences.profile) {
    PassiveTrackingProfile.batterySaver => const PassiveTrackingTuning(
      accuracy: LocationAccuracy.medium,
      distanceFilterMeters: 45,
      interval: Duration(seconds: 45),
    ),
    PassiveTrackingProfile.balanced => const PassiveTrackingTuning(
      accuracy: LocationAccuracy.high,
      distanceFilterMeters: 18,
      interval: Duration(seconds: 18),
    ),
    PassiveTrackingProfile.precise => const PassiveTrackingTuning(
      accuracy: LocationAccuracy.best,
      distanceFilterMeters: 8,
      interval: Duration(seconds: 8),
    ),
    PassiveTrackingProfile.custom => PassiveTrackingTuning(
      accuracy: LocationAccuracy.high,
      distanceFilterMeters: preferences.customDistanceFilterMeters.clamp(
        5,
        120,
      ),
      interval: Duration(
        seconds: preferences.customIntervalSeconds.clamp(5, 120),
      ),
    ),
  };

  if (!preferences.adaptiveModeEnabled || !reducedMode) {
    return base;
  }

  return PassiveTrackingTuning(
    accuracy: switch (base.accuracy) {
      LocationAccuracy.bestForNavigation => LocationAccuracy.high,
      LocationAccuracy.best => LocationAccuracy.high,
      LocationAccuracy.high => LocationAccuracy.medium,
      _ => base.accuracy,
    },
    distanceFilterMeters: (base.distanceFilterMeters * 2).clamp(12, 140),
    interval: Duration(
      seconds: (base.interval.inSeconds * 2).clamp(12, 150),
    ),
  );
}
