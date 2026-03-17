import 'package:flutter/material.dart';

import '../i18n/app_strings.dart';
import 'footprint_zones.dart';

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
    required int dailySteps,
    required FootprintZonesSnapshot zonesSnapshot,
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
        ProgressionAchievement(
          title: strings.achievementMapStarterTitle,
          description: strings.achievementMapStarterBody,
          icon: Icons.map_rounded,
          unlocked: totalPoints >= 1000,
        ),
        ProgressionAchievement(
          title: strings.achievementNeighborhoodTitle,
          description: strings.achievementNeighborhoodBody,
          icon: Icons.route_rounded,
          unlocked: knownKilometers >= 1.0,
        ),
        ProgressionAchievement(
          title: strings.achievementRoutineBreakerTitle,
          description: strings.achievementRoutineBreakerBody,
          icon: Icons.alt_route_rounded,
          unlocked: knownKilometers >= 3.5,
        ),
        ProgressionAchievement(
          title: strings.achievementZoneKeeperTitle,
          description: strings.achievementZoneKeeperBody,
          icon: Icons.hexagon_rounded,
          unlocked: primaryCoverage >= 0.45,
        ),
        ProgressionAchievement(
          title: strings.achievementCityPulseTitle,
          description: strings.achievementCityPulseBody,
          icon: Icons.directions_walk_rounded,
          unlocked: traveledTodayKilometers >= 5,
        ),
        ProgressionAchievement(
          title: strings.achievementStepExplorerTitle,
          description: strings.achievementStepExplorerBody,
          icon: Icons.local_fire_department_rounded,
          unlocked: dailySteps >= 10000,
        ),
        ProgressionAchievement(
          title: strings.achievementMultiZoneTitle,
          description: strings.achievementMultiZoneBody,
          icon: Icons.public_rounded,
          unlocked: zoneCount >= 3,
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
    if (level >= 18) {
      return strings.rankUrbanLegend;
    }
    if (level >= 14) {
      return strings.rankCityCartographer;
    }
    if (level >= 10) {
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
}
