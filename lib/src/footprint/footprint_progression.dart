import 'package:flutter/material.dart';

import '../i18n/app_strings.dart';
import 'footprint_zones.dart';
import 'zone_name_service.dart';

class ProgressionAchievement {
  const ProgressionAchievement({
    required this.title,
    required this.description,
    required this.icon,
    required this.unlocked,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool unlocked;
}

class ProgressionSnapshot {
  const ProgressionSnapshot({
    required this.level,
    required this.title,
    required this.currentPoints,
    required this.nextLevelPoints,
    required this.achievements,
  });

  final int level;
  final String title;
  final int currentPoints;
  final int nextLevelPoints;
  final List<ProgressionAchievement> achievements;

  int get unlockedAchievements =>
      achievements.where((achievement) => achievement.unlocked).length;
}

class FootprintProgression {
  FootprintProgression._();

  static ProgressionSnapshot build({
    required AppStrings strings,
    required int totalPoints,
    required double knownKilometers,
    required double traveledTodayKilometers,
    required double totalDistanceKilometers,
    required double vehicleKilometers,
    required int currentStreak,
    required int bestStreak,
    required int dailySteps,
    required FootprintZonesSnapshot zonesSnapshot,
    Map<String, String> zoneDisplayNames = const {},
  }) {
    final level = _levelFor(totalPoints);
    final title = _titleFor(strings, level);
    final nextLevelPoints = _pointsForLevel(level + 1);
    final primaryCoverage = zonesSnapshot.primaryZone?.discoveredRatio ?? 0;
    final zoneCount = zonesSnapshot.zones.length;

    return ProgressionSnapshot(
      level: level,
      title: title,
      currentPoints: totalPoints,
      nextLevelPoints: nextLevelPoints,
      achievements: [
        ProgressionAchievement(
          title: strings.achievementFirstTraceTitle,
          description: strings.achievementFirstTraceBody,
          icon: Icons.explore_rounded,
          unlocked: totalPoints >= 120,
        ),
        _pointsMilestone(strings, 2500, totalPoints, Icons.map_rounded),
        _pointsMilestone(strings, 6000, totalPoints, Icons.auto_awesome_rounded),
        _pointsMilestone(strings, 12000, totalPoints, Icons.bolt_rounded),
        _pointsMilestone(
          strings,
          25000,
          totalPoints,
          Icons.workspace_premium_rounded,
        ),
        _knownMilestone(strings, 2, knownKilometers, Icons.route_rounded),
        _knownMilestone(strings, 5, knownKilometers, Icons.terrain_rounded),
        _knownMilestone(strings, 10, knownKilometers, Icons.explore_rounded),
        _knownMilestone(strings, 20, knownKilometers, Icons.public_rounded),
        _coverageMilestone(strings, 20, primaryCoverage, Icons.grid_view_rounded),
        _coverageMilestone(strings, 40, primaryCoverage, Icons.hexagon_rounded),
        _coverageMilestone(strings, 65, primaryCoverage, Icons.hub_rounded),
        _todayMilestone(
          strings,
          5,
          traveledTodayKilometers,
          Icons.directions_walk_rounded,
        ),
        _todayMilestone(
          strings,
          10,
          traveledTodayKilometers,
          Icons.directions_run_rounded,
        ),
        _distanceMilestone(
          strings,
          15,
          totalDistanceKilometers,
          Icons.timeline_rounded,
        ),
        _distanceMilestone(
          strings,
          40,
          totalDistanceKilometers,
          Icons.alt_route_rounded,
        ),
        _distanceMilestone(
          strings,
          80,
          totalDistanceKilometers,
          Icons.route_rounded,
        ),
        _distanceMilestone(
          strings,
          160,
          totalDistanceKilometers,
          Icons.public_rounded,
        ),
        _stepsMilestone(
          strings,
          12000,
          dailySteps,
          Icons.local_fire_department_rounded,
        ),
        _stepsMilestone(strings, 20000, dailySteps, Icons.whatshot_rounded),
        _vehicleMilestone(
          strings,
          15,
          vehicleKilometers,
          Icons.directions_car_filled_rounded,
        ),
        _vehicleMilestone(
          strings,
          50,
          vehicleKilometers,
          Icons.airport_shuttle_rounded,
        ),
        _vehicleMilestone(
          strings,
          120,
          vehicleKilometers,
          Icons.local_shipping_rounded,
        ),
        _vehicleMilestone(
          strings,
          250,
          vehicleKilometers,
          Icons.route_rounded,
        ),
        _vehicleMilestone(
          strings,
          500,
          vehicleKilometers,
          Icons.travel_explore_rounded,
        ),
        _vehicleMilestone(
          strings,
          1000,
          vehicleKilometers,
          Icons.public_rounded,
        ),
        _streakMilestone(strings, 3, bestStreak, Icons.radar_rounded),
        _streakMilestone(strings, 7, bestStreak, Icons.local_fire_department_rounded),
        _streakMilestone(strings, 14, bestStreak, Icons.whatshot_rounded),
        _streakMilestone(strings, 30, bestStreak, Icons.bolt_rounded),
        _streakMilestone(strings, 60, bestStreak, Icons.workspace_premium_rounded),
        _streakMilestone(strings, 120, bestStreak, Icons.shield_moon_rounded),
        _zoneMilestone(strings, 3, zoneCount, Icons.place_rounded),
        _zoneMilestone(strings, 6, zoneCount, Icons.travel_explore_rounded),
        _zoneMilestone(strings, 10, zoneCount, Icons.map_rounded),
        ..._localZoneAchievements(
          strings: strings,
          zonesSnapshot: zonesSnapshot,
          zoneDisplayNames: zoneDisplayNames,
        ),
        ProgressionAchievement(
          title: strings.currentStreakLabel,
          description: strings.streakDaysValue(currentStreak),
          icon: Icons.radar_rounded,
          unlocked: currentStreak > 0,
        ),
      ],
    );
  }

  static int _levelFor(int points) {
    var level = 1;
    while (points >= _pointsForLevel(level + 1)) {
      level += 1;
    }
    return level;
  }

  static int _pointsForLevel(int level) {
    final safeLevel = level < 1 ? 1 : level;
    return ((safeLevel - 1) * (safeLevel - 1) * 420) + ((safeLevel - 1) * 180);
  }

  static String _titleFor(AppStrings strings, int level) {
    if (level >= 28) {
      return strings.rankUrbanLegend;
    }
    if (level >= 22) {
      return strings.rankUrbanLegend;
    }
    if (level >= 16) {
      return strings.rankCityCartographer;
    }
    if (level >= 11) {
      return strings.rankZoneHunter;
    }
    if (level >= 7) {
      return strings.rankOpenWorldWalker;
    }
    if (level >= 4) {
      return strings.rankStreetExplorer;
    }
    return strings.rankFirstSteps;
  }

  static ProgressionAchievement _pointsMilestone(
    AppStrings strings,
    int points,
    int totalPoints,
    IconData icon,
  ) {
    return ProgressionAchievement(
      title: strings.achievementPointsTitle(points),
      description: strings.achievementPointsBody(points),
      icon: icon,
      unlocked: totalPoints >= points,
    );
  }

  static ProgressionAchievement _knownMilestone(
    AppStrings strings,
    int kilometers,
    double knownKilometers,
    IconData icon,
  ) {
    return ProgressionAchievement(
      title: strings.achievementKnownKmTitle(kilometers),
      description: strings.achievementKnownKmBody(kilometers),
      icon: icon,
      unlocked: knownKilometers >= kilometers,
    );
  }

  static ProgressionAchievement _todayMilestone(
    AppStrings strings,
    int kilometers,
    double traveledTodayKilometers,
    IconData icon,
  ) {
    return ProgressionAchievement(
      title: strings.achievementTodayKmTitle(kilometers),
      description: strings.achievementTodayKmBody(kilometers),
      icon: icon,
      unlocked: traveledTodayKilometers >= kilometers,
    );
  }

  static ProgressionAchievement _distanceMilestone(
    AppStrings strings,
    int kilometers,
    double totalDistanceKilometers,
    IconData icon,
  ) {
    return ProgressionAchievement(
      title: strings.achievementTotalDistanceTitle(kilometers),
      description: strings.achievementTotalDistanceBody(kilometers),
      icon: icon,
      unlocked: totalDistanceKilometers >= kilometers,
    );
  }

  static ProgressionAchievement _stepsMilestone(
    AppStrings strings,
    int steps,
    int dailySteps,
    IconData icon,
  ) {
    return ProgressionAchievement(
      title: strings.achievementStepsTitle(steps),
      description: strings.achievementStepsBody(steps),
      icon: icon,
      unlocked: dailySteps >= steps,
    );
  }

  static ProgressionAchievement _zoneMilestone(
    AppStrings strings,
    int zones,
    int zoneCount,
    IconData icon,
  ) {
    return ProgressionAchievement(
      title: strings.achievementZonesTitle(zones),
      description: strings.achievementZonesBody(zones),
      icon: icon,
      unlocked: zoneCount >= zones,
    );
  }

  static ProgressionAchievement _coverageMilestone(
    AppStrings strings,
    int percent,
    double primaryCoverage,
    IconData icon,
  ) {
    return ProgressionAchievement(
      title: strings.achievementCoverageTitle(percent),
      description: strings.achievementCoverageBody(percent),
      icon: icon,
      unlocked: primaryCoverage >= (percent / 100),
    );
  }

  static ProgressionAchievement _vehicleMilestone(
    AppStrings strings,
    int kilometers,
    double vehicleKilometers,
    IconData icon,
  ) {
    return ProgressionAchievement(
      title: strings.achievementVehicleTitle(kilometers),
      description: strings.achievementVehicleBody(kilometers),
      icon: icon,
      unlocked: vehicleKilometers >= kilometers,
    );
  }

  static ProgressionAchievement _streakMilestone(
    AppStrings strings,
    int days,
    int bestStreak,
    IconData icon,
  ) {
    return ProgressionAchievement(
      title: strings.achievementStreakTitle(days),
      description: strings.achievementStreakBody(days),
      icon: icon,
      unlocked: bestStreak >= days,
    );
  }

  static List<ProgressionAchievement> _localZoneAchievements({
    required AppStrings strings,
    required FootprintZonesSnapshot zonesSnapshot,
    required Map<String, String> zoneDisplayNames,
  }) {
    final candidates = zonesSnapshot.zones
        .map((zone) {
          final resolved = (zoneDisplayNames[zone.zoneKey] ?? zone.title).trim();
          if (resolved.isEmpty ||
              ZoneNameService.looksTechnicalZoneTitle(resolved)) {
            return null;
          }
          return (zone: zone, name: resolved);
        })
        .whereType<({FootprintZone zone, String name})>()
        .toList(growable: false);

    final achievements = <ProgressionAchievement>[];
    for (final candidate in candidates.take(3)) {
      achievements.addAll([
        ProgressionAchievement(
          title: strings.achievementLocalZoneTitle(candidate.name, 35),
          description: strings.achievementLocalZoneBody(candidate.name, 35),
          icon: Icons.place_rounded,
          unlocked: candidate.zone.discoveredRatio >= 0.35,
        ),
        ProgressionAchievement(
          title: strings.achievementLocalZoneTitle(candidate.name, 60),
          description: strings.achievementLocalZoneBody(candidate.name, 60),
          icon: Icons.map_rounded,
          unlocked: candidate.zone.discoveredRatio >= 0.60,
        ),
        ProgressionAchievement(
          title: strings.achievementLocalZoneFullTitle(candidate.name),
          description: strings.achievementLocalZoneFullBody(candidate.name),
          icon: Icons.workspace_premium_rounded,
          unlocked: candidate.zone.discoveredRatio >= 0.90,
        ),
      ]);
    }
    return achievements;
  }
}
