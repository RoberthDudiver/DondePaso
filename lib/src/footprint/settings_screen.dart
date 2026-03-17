import 'package:flutter/material.dart';

import '../background/tracking_preferences.dart';
import '../community/community_screen.dart';
import '../i18n/app_strings.dart';
import '../legal/legal_screen.dart';
import 'footprint_progression.dart';
import 'footprint_zones.dart';
import 'zone_name_service.dart';

class FootprintSettingsScreen extends StatelessWidget {
  const FootprintSettingsScreen({
    super.key,
    required this.totalPoints,
    required this.knownKilometers,
    required this.traveledTodayKilometers,
    required this.totalDistanceKilometers,
    required this.dailySteps,
    required this.activityLabel,
    required this.stepSensorAvailable,
    required this.trackingActive,
    required this.trackingPreferences,
    required this.forgetAfterLabel,
    required this.onRequestTracking,
    required this.onTogglePassiveTracking,
    required this.onUpdateTrackingPreferences,
    required this.onOpenPermissions,
    required this.onExportBackup,
    required this.onRestoreBackup,
    required this.zonesSnapshot,
    required this.progression,
    required this.onClearMap,
  });

  final int totalPoints;
  final double knownKilometers;
  final double traveledTodayKilometers;
  final double totalDistanceKilometers;
  final int dailySteps;
  final String activityLabel;
  final bool stepSensorAvailable;
  final bool trackingActive;
  final PassiveTrackingPreferences trackingPreferences;
  final String forgetAfterLabel;
  final Future<void> Function() onRequestTracking;
  final Future<void> Function(bool enabled) onTogglePassiveTracking;
  final Future<void> Function(PassiveTrackingPreferences preferences)
  onUpdateTrackingPreferences;
  final Future<void> Function() onOpenPermissions;
  final Future<void> Function() onExportBackup;
  final Future<void> Function() onRestoreBackup;
  final FootprintZonesSnapshot zonesSnapshot;
  final ProgressionSnapshot? progression;
  final Future<void> Function() onClearMap;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Scaffold(
      appBar: AppBar(title: Text(strings.settings)),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _HubHero(
            points: strings.formatCompactNumber(totalPoints),
            knownKilometers: knownKilometers,
            traveledTodayKilometers: traveledTodayKilometers,
          ),
          const SizedBox(height: 14),
          _HubCard(
            title: strings.generalOverview,
            subtitle: strings.generalOverviewBody,
            icon: Icons.dashboard_rounded,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _OverviewScreen(
                    totalPoints: totalPoints,
                    knownKilometers: knownKilometers,
                    traveledTodayKilometers: traveledTodayKilometers,
                    totalDistanceKilometers: totalDistanceKilometers,
                    dailySteps: dailySteps,
                    activityLabel: activityLabel,
                    zonesSnapshot: zonesSnapshot,
                    progression: progression,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _HubCard(
            title: strings.achievementsAndLevels,
            subtitle: strings.achievementsAndLevelsBody,
            icon: Icons.military_tech_rounded,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _AchievementsScreen(
                    progression: progression,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _HubCard(
            title: strings.progressAndMovement,
            subtitle: strings.progressAndMovementBody,
            icon: Icons.insights_rounded,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _ProgressAndMovementScreen(
                    totalPoints: totalPoints,
                    knownKilometers: knownKilometers,
                    traveledTodayKilometers: traveledTodayKilometers,
                    totalDistanceKilometers: totalDistanceKilometers,
                    dailySteps: dailySteps,
                    activityLabel: activityLabel,
                    stepSensorAvailable: stepSensorAvailable,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _HubCard(
            title: strings.zones,
            subtitle: strings.zonesBody,
            icon: Icons.hexagon_rounded,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _ZonesScreen(zonesSnapshot: zonesSnapshot),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _HubCard(
            title: strings.mapAndBackup,
            subtitle: strings.mapAndBackupBody,
            icon: Icons.tune_rounded,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _MapAndBackupScreen(
                    trackingActive: trackingActive,
                    trackingPreferences: trackingPreferences,
                    forgetAfterLabel: forgetAfterLabel,
                    onRequestTracking: onRequestTracking,
                    onTogglePassiveTracking: onTogglePassiveTracking,
                    onUpdateTrackingPreferences: onUpdateTrackingPreferences,
                    onOpenPermissions: onOpenPermissions,
                    onExportBackup: onExportBackup,
                    onRestoreBackup: onRestoreBackup,
                    onClearMap: onClearMap,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _HubCard(
            title: strings.community,
            subtitle: strings.communityBody,
            icon: Icons.groups_rounded,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CommunityScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _HubCard(
            title: strings.legal,
            subtitle: strings.termsAndPrivacy,
            icon: Icons.policy_rounded,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LegalScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _OverviewScreen extends StatelessWidget {
  const _OverviewScreen({
    required this.totalPoints,
    required this.knownKilometers,
    required this.traveledTodayKilometers,
    required this.totalDistanceKilometers,
    required this.dailySteps,
    required this.activityLabel,
    required this.zonesSnapshot,
    required this.progression,
  });

  final int totalPoints;
  final double knownKilometers;
  final double traveledTodayKilometers;
  final double totalDistanceKilometers;
  final int dailySteps;
  final String activityLabel;
  final FootprintZonesSnapshot zonesSnapshot;
  final ProgressionSnapshot? progression;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final primaryZone = zonesSnapshot.primaryZone;

    return Scaffold(
      appBar: AppBar(title: Text(strings.generalOverview)),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _SectionPanel(
            title: progression?.title ?? strings.level,
            subtitle: progression == null
                ? strings.generalOverviewBody
                : strings.levelValue(progression!.level),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricCard(
                  label: strings.points,
                  value: strings.formatCompactNumber(totalPoints),
                ),
                _MetricCard(
                  label: strings.totalKnownKm,
                  value: '${knownKilometers.toStringAsFixed(1)} km',
                ),
                _MetricCard(
                  label: strings.traveledTodayKm,
                  value: '${traveledTodayKilometers.toStringAsFixed(1)} km',
                ),
                _MetricCard(
                  label: strings.totalDistance,
                  value: '${totalDistanceKilometers.toStringAsFixed(1)} km',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SectionPanel(
            title: strings.movement,
            subtitle: activityLabel,
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricCard(
                  label: strings.todaySteps,
                  value: strings.formatCompactNumber(dailySteps),
                ),
                _MetricCard(
                  label: strings.activeZones,
                  value: '${zonesSnapshot.zones.length}',
                ),
                _MetricCard(
                  label: strings.unlockedAchievements,
                  value: progression == null
                      ? '0'
                      : '${progression!.unlockedAchievements}',
                ),
                _MetricCard(
                  label: strings.level,
                  value: progression == null ? '1' : '${progression!.level}',
                ),
              ],
            ),
          ),
          if (primaryZone != null) ...[
            const SizedBox(height: 14),
            _SectionPanel(
              title: strings.mainZone,
              subtitle: strings.primaryZoneSummaryBody,
              child: _ZoneSummaryRow(zone: primaryZone),
            ),
          ],
        ],
      ),
    );
  }
}

class _AchievementsScreen extends StatelessWidget {
  const _AchievementsScreen({required this.progression});

  final ProgressionSnapshot? progression;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final data = progression;

    return Scaffold(
      appBar: AppBar(title: Text(strings.achievements)),
      body: data == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  strings.noAchievementsYet,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                _SectionPanel(
                  title: data.title,
                  subtitle: strings.levelValue(data.level),
                  child: Text(
                    strings.unlockedAchievementsLabel(
                      data.unlockedAchievements,
                      data.achievements.length,
                    ),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.82),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.95,
                  ),
                  itemCount: data.achievements.length,
                  itemBuilder: (context, index) {
                    final achievement = data.achievements[index];
                    return _AchievementTile(achievement: achievement);
                  },
                ),
              ],
            ),
    );
  }
}

class _ProgressAndMovementScreen extends StatelessWidget {
  const _ProgressAndMovementScreen({
    required this.totalPoints,
    required this.knownKilometers,
    required this.traveledTodayKilometers,
    required this.totalDistanceKilometers,
    required this.dailySteps,
    required this.activityLabel,
    required this.stepSensorAvailable,
  });

  final int totalPoints;
  final double knownKilometers;
  final double traveledTodayKilometers;
  final double totalDistanceKilometers;
  final int dailySteps;
  final String activityLabel;
  final bool stepSensorAvailable;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Scaffold(
      appBar: AppBar(title: Text(strings.progressAndMovement)),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _SectionPanel(
            title: strings.yourProgress,
            subtitle: strings.progressAndMovementBody,
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricCard(
                  label: strings.points,
                  value: strings.formatCompactNumber(totalPoints),
                ),
                _MetricCard(
                  label: strings.totalKnownKm,
                  value: '${knownKilometers.toStringAsFixed(1)} km',
                ),
                _MetricCard(
                  label: strings.traveledTodayKm,
                  value: '${traveledTodayKilometers.toStringAsFixed(1)} km',
                ),
                _MetricCard(
                  label: strings.totalDistance,
                  value: '${totalDistanceKilometers.toStringAsFixed(1)} km',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SectionPanel(
            title: strings.movement,
            subtitle: activityLabel,
            child: Column(
              children: [
                _InfoRow(
                  label: strings.todaySteps,
                  value: strings.formatCompactNumber(dailySteps),
                ),
                const SizedBox(height: 10),
                _InfoRow(
                  label: strings.activityPulse,
                  value: activityLabel,
                ),
                const SizedBox(height: 10),
                _InfoRow(
                  label: strings.stepSensorStatus,
                  value: stepSensorAvailable
                      ? strings.active
                      : strings.stepSensorUnavailable,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MapAndBackupScreen extends StatefulWidget {
  const _MapAndBackupScreen({
    required this.trackingActive,
    required this.trackingPreferences,
    required this.forgetAfterLabel,
    required this.onRequestTracking,
    required this.onTogglePassiveTracking,
    required this.onUpdateTrackingPreferences,
    required this.onOpenPermissions,
    required this.onExportBackup,
    required this.onRestoreBackup,
    required this.onClearMap,
  });

  final bool trackingActive;
  final PassiveTrackingPreferences trackingPreferences;
  final String forgetAfterLabel;
  final Future<void> Function() onRequestTracking;
  final Future<void> Function(bool enabled) onTogglePassiveTracking;
  final Future<void> Function(PassiveTrackingPreferences preferences)
  onUpdateTrackingPreferences;
  final Future<void> Function() onOpenPermissions;
  final Future<void> Function() onExportBackup;
  final Future<void> Function() onRestoreBackup;
  final Future<void> Function() onClearMap;

  @override
  State<_MapAndBackupScreen> createState() => _MapAndBackupScreenState();
}

class _MapAndBackupScreenState extends State<_MapAndBackupScreen> {
  late bool _trackingActive;
  late PassiveTrackingPreferences _preferences;

  @override
  void initState() {
    super.initState();
    _trackingActive = widget.trackingActive;
    _preferences = widget.trackingPreferences;
  }

  Future<void> _setPassiveTracking(bool enabled) async {
    if (enabled && !_trackingActive) {
      await widget.onRequestTracking();
      if (!mounted) {
        return;
      }
      setState(() {
        _trackingActive = true;
      });
      return;
    }

    await widget.onTogglePassiveTracking(enabled);
    if (!mounted) {
      return;
    }
    setState(() {
      _trackingActive = enabled;
    });
  }

  Future<void> _updatePreferences(PassiveTrackingPreferences preferences) async {
    setState(() {
      _preferences = preferences;
    });
    await widget.onUpdateTrackingPreferences(preferences);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Scaffold(
      appBar: AppBar(title: Text(strings.mapAndBackup)),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _SectionPanel(
            title: strings.updateSafetyTitle,
            subtitle: strings.updateSafetyBody,
            child: _ActionButtonRow(
              icon: Icons.security_update_good_rounded,
              label: strings.exportBackup,
              onPressed: widget.onExportBackup,
            ),
          ),
          const SizedBox(height: 14),
          _SectionPanel(
            title: strings.tracking,
            subtitle: strings.mapAndBackupBody,
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(strings.passiveMode),
                  subtitle: Text(
                    _trackingActive
                        ? strings.passiveModeBody
                        : strings.passiveModeOffBody,
                  ),
                  value: _trackingActive,
                  onChanged: _setPassiveTracking,
                ),
                const SizedBox(height: 8),
                _TrackingProfileSection(
                  preferences: _preferences,
                  onChanged: _updatePreferences,
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  label: strings.fading,
                  value: widget.forgetAfterLabel,
                ),
                const SizedBox(height: 10),
                _ActionButtonRow(
                  icon: Icons.shield_outlined,
                  label: strings.permissions,
                  onPressed: widget.onOpenPermissions,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SectionPanel(
            title: strings.backup,
            subtitle: strings.backupBody,
            child: Column(
              children: [
                _ActionButtonRow(
                  icon: Icons.upload_file_rounded,
                  label: strings.exportBackup,
                  onPressed: widget.onExportBackup,
                ),
                const SizedBox(height: 10),
                _ActionButtonRow(
                  icon: Icons.restore_rounded,
                  label: strings.restoreBackup,
                  onPressed: widget.onRestoreBackup,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SectionPanel(
            title: strings.map,
            subtitle: strings.mapControlBody,
            child: _ActionButtonRow(
              icon: Icons.delete_outline_rounded,
              label: strings.resetProgress,
              isDanger: true,
              onPressed: widget.onClearMap,
            ),
          ),
        ],
      ),
    );
  }
}

class _ZonesScreen extends StatefulWidget {
  const _ZonesScreen({required this.zonesSnapshot});

  final FootprintZonesSnapshot zonesSnapshot;

  @override
  State<_ZonesScreen> createState() => _ZonesScreenState();
}

class _ZonesScreenState extends State<_ZonesScreen> {
  final ZoneNameService _zoneNameService = ZoneNameService();
  final Map<String, String> _names = <String, String>{};

  @override
  void initState() {
    super.initState();
    _loadNames();
  }

  Future<void> _loadNames() async {
    for (final zone in widget.zonesSnapshot.zones) {
      final name = await _zoneNameService.resolveName(zone);
      if (!mounted) {
        return;
      }
      setState(() {
        _names[zone.zoneKey] = name;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final zones = _mergedZones(widget.zonesSnapshot.zones);

    return Scaffold(
      appBar: AppBar(title: Text(strings.zones)),
      body: zones.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  strings.noZonesYet,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(18),
              itemBuilder: (context, index) {
                final zone = zones[index];
                final displayName = _names[zone.zoneKey] ?? zone.title;
                return _SectionPanel(
                  title: displayName,
                  subtitle: strings.zoneCoverageLabel(
                    (zone.discoveredRatio * 100).round(),
                  ),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: zone.discoveredRatio,
                          minHeight: 10,
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          valueColor: const AlwaysStoppedAnimation(
                            Color(0xFFB8FF8C),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _MetricCard(
                            label: strings.zoneCellsLabel(zone.discoveredCells),
                            value: '${zone.discoveredCells}',
                          ),
                          _MetricCard(
                            label: strings.zoneVisitsLabel(zone.totalVisits),
                            value: '${zone.totalVisits}',
                          ),
                          _MetricCard(
                            label: strings.totalKnownKm,
                            value:
                                '${zone.knownKilometers.toStringAsFixed(1)} km',
                          ),
                          _MetricCard(
                            label: strings.zoneFreshness,
                            value:
                                '${(zone.averageFreshness * 100).round()}%',
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemCount: zones.length,
            ),
    );
  }

  List<FootprintZone> _mergedZones(List<FootprintZone> zones) {
    final merged = <String, _MergedZoneBucket>{};

    for (final zone in zones) {
      final displayName = (_names[zone.zoneKey] ?? zone.title).trim();
      final normalized = displayName.toLowerCase();
      merged.update(
        normalized,
        (bucket) {
          bucket.add(zone, displayName);
          return bucket;
        },
        ifAbsent: () => _MergedZoneBucket(displayName)..add(zone, displayName),
      );
    }

    return merged.values.map((bucket) => bucket.toZone()).toList()
      ..sort((a, b) {
        final ratioComparison = b.discoveredRatio.compareTo(a.discoveredRatio);
        if (ratioComparison != 0) {
          return ratioComparison;
        }
        return b.knownKilometers.compareTo(a.knownKilometers);
      });
  }
}

class _MergedZoneBucket {
  _MergedZoneBucket(this.displayName);

  final String displayName;
  double _centerLatitude = 0;
  double _centerLongitude = 0;
  int _zoneCount = 0;
  int _discoveredCells = 0;
  int _totalCellsEstimate = 0;
  double _knownKilometers = 0;
  double _freshnessWeighted = 0;
  int _totalVisits = 0;
  String _zoneKey = '';

  void add(FootprintZone zone, String name) {
    _zoneCount += 1;
    _centerLatitude += zone.centerLatitude;
    _centerLongitude += zone.centerLongitude;
    _discoveredCells += zone.discoveredCells;
    _totalCellsEstimate += zone.totalCellsEstimate;
    _knownKilometers += zone.knownKilometers;
    _freshnessWeighted += zone.averageFreshness * zone.discoveredCells;
    _totalVisits += zone.totalVisits;
    if (_zoneKey.isEmpty) {
      _zoneKey = zone.zoneKey;
    }
  }

  FootprintZone toZone() {
    return FootprintZone(
      title: displayName,
      centerLatitude: _centerLatitude / _zoneCount,
      centerLongitude: _centerLongitude / _zoneCount,
      zoneKey: _zoneKey,
      discoveredCells: _discoveredCells,
      totalCellsEstimate: _totalCellsEstimate,
      knownKilometers: _knownKilometers,
      averageFreshness: _discoveredCells == 0
          ? 0
          : _freshnessWeighted / _discoveredCells,
      totalVisits: _totalVisits,
    );
  }
}

class _HubHero extends StatelessWidget {
  const _HubHero({
    required this.points,
    required this.knownKilometers,
    required this.traveledTodayKilometers,
  });

  final String points;
  final double knownKilometers;
  final double traveledTodayKilometers;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        gradient: const LinearGradient(
          colors: [Color(0xFF121A10), Color(0xFF07161A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.settingsHubTitle,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            strings.settingsHubBody,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.8),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatBadge(label: strings.points, value: points),
              _StatBadge(
                label: strings.totalKnownKm,
                value: '${knownKilometers.toStringAsFixed(1)} km',
              ),
              _StatBadge(
                label: strings.traveledTodayKm,
                value: '${traveledTodayKilometers.toStringAsFixed(1)} km',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: const Color(0xFFB8FF8C)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.72),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right_rounded, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}

class _SectionPanel extends StatelessWidget {
  const _SectionPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.72),
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 132),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.24),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.62),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile({required this.achievement});

  final ProgressionAchievement achievement;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: achievement.unlocked
              ? const Color(0x55B8FF8C)
              : Colors.white.withValues(alpha: 0.06),
        ),
        gradient: achievement.unlocked
            ? const LinearGradient(
                colors: [Color(0xFF172313), Color(0xFF111315)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: achievement.unlocked
            ? null
            : Colors.white.withValues(alpha: 0.04),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: achievement.unlocked
                  ? const Color(0xFFB8FF8C)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              achievement.icon,
              color: achievement.unlocked ? Colors.black : Colors.white70,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            achievement.title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            achievement.description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackingProfileSection extends StatelessWidget {
  const _TrackingProfileSection({
    required this.preferences,
    required this.onChanged,
  });

  final PassiveTrackingPreferences preferences;
  final Future<void> Function(PassiveTrackingPreferences preferences) onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.trackingProfile,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ProfileChip(
              label: strings.profileBatterySaver,
              selected:
                  preferences.profile == PassiveTrackingProfile.batterySaver,
              onTap: () {
                onChanged(
                  preferences.copyWith(
                    profile: PassiveTrackingProfile.batterySaver,
                  ),
                );
              },
            ),
            _ProfileChip(
              label: strings.profileBalanced,
              selected: preferences.profile == PassiveTrackingProfile.balanced,
              onTap: () {
                onChanged(
                  preferences.copyWith(
                    profile: PassiveTrackingProfile.balanced,
                  ),
                );
              },
            ),
            _ProfileChip(
              label: strings.profilePrecise,
              selected: preferences.profile == PassiveTrackingProfile.precise,
              onTap: () {
                onChanged(
                  preferences.copyWith(
                    profile: PassiveTrackingProfile.precise,
                  ),
                );
              },
            ),
            _ProfileChip(
              label: strings.profileCustom,
              selected: preferences.profile == PassiveTrackingProfile.custom,
              onTap: () {
                onChanged(
                  preferences.copyWith(profile: PassiveTrackingProfile.custom),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(strings.adaptiveTracking),
          subtitle: Text(strings.adaptiveTrackingBody),
          value: preferences.adaptiveModeEnabled,
          onChanged: (value) {
            onChanged(preferences.copyWith(adaptiveModeEnabled: value));
          },
        ),
        if (preferences.profile == PassiveTrackingProfile.custom) ...[
          const SizedBox(height: 10),
          Text(
            strings.customDistanceValue(
              preferences.customDistanceFilterMeters,
            ),
          ),
          Slider(
            value: preferences.customDistanceFilterMeters.toDouble(),
            min: 5,
            max: 120,
            divisions: 23,
            label: strings.customDistanceValue(
              preferences.customDistanceFilterMeters,
            ),
            onChanged: (value) {
              onChanged(
                preferences.copyWith(
                  customDistanceFilterMeters: value.round(),
                ),
              );
            },
          ),
          Text(strings.customIntervalValue(preferences.customIntervalSeconds)),
          Slider(
            value: preferences.customIntervalSeconds.toDouble(),
            min: 5,
            max: 120,
            divisions: 23,
            label: strings.customIntervalValue(
              preferences.customIntervalSeconds,
            ),
            onChanged: (value) {
              onChanged(
                preferences.copyWith(customIntervalSeconds: value.round()),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: const Color(0xFFB8FF8C),
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: selected ? Colors.black : Colors.white,
        fontWeight: FontWeight.w700,
      ),
      backgroundColor: Colors.white.withValues(alpha: 0.06),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
    );
  }
}

class _ActionButtonRow extends StatelessWidget {
  const _ActionButtonRow({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isDanger = false,
  });

  final IconData icon;
  final String label;
  final Future<void> Function() onPressed;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: Icon(icon),
        style: FilledButton.styleFrom(
          foregroundColor: isDanger ? const Color(0xFFFF9D9D) : null,
        ),
        label: Text(label),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ZoneSummaryRow extends StatelessWidget {
  const _ZoneSummaryRow({required this.zone});

  final FootprintZone zone;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          zone.title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: zone.discoveredRatio,
            minHeight: 10,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            valueColor: const AlwaysStoppedAnimation(Color(0xFFB8FF8C)),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(
              label: strings.zoneCoverageLabel(
                (zone.discoveredRatio * 100).round(),
              ),
              value: '${(zone.discoveredRatio * 100).round()}%',
            ),
            _MetricCard(
              label: strings.zoneVisitsLabel(zone.totalVisits),
              value: '${zone.totalVisits}',
            ),
          ],
        ),
      ],
    );
  }
}
