import 'package:flutter/material.dart';

import '../background/tracking_preferences.dart';
import '../i18n/app_strings.dart';
import '../legal/legal_screen.dart';

class FootprintSettingsScreen extends StatelessWidget {
  const FootprintSettingsScreen({
    super.key,
    required this.totalPoints,
    required this.knownKilometers,
    required this.traveledTodayKilometers,
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
    required this.onClearMap,
  });

  final int totalPoints;
  final double knownKilometers;
  final double traveledTodayKilometers;
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
  final Future<void> Function() onClearMap;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Scaffold(
      appBar: AppBar(title: Text(strings.settings)),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _SettingsCard(
            title: strings.yourProgress,
            child: Row(
              children: [
                Expanded(
                  child: _MiniMetric(
                    label: strings.points,
                    value: '$totalPoints',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MiniMetric(
                    label: strings.totalKnownKm,
                    value: '${knownKilometers.toStringAsFixed(1)} km',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SettingsCard(
            title: strings.movement,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _MiniMetric(
                        label: strings.traveledTodayKm,
                        value: '${traveledTodayKilometers.toStringAsFixed(1)} km',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MiniMetric(
                        label: strings.todaySteps,
                        value: stepSensorAvailable
                            ? '$dailySteps'
                            : strings.stepSensorUnavailable,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MiniMetric(
                        label: strings.activityPulse,
                        value: activityLabel,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SettingsCard(
            title: strings.tracking,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoLine(
                  label: strings.status,
                  value: trackingActive ? strings.active : strings.off,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: trackingActive,
                  activeThumbColor: const Color(0xFFB8FF8C),
                  onChanged: (value) async {
                    await onTogglePassiveTracking(value);
                  },
                  title: Text(strings.passiveMode),
                  subtitle: Text(
                    trackingActive
                        ? strings.passiveModeBody
                        : strings.passiveModeOffBody,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _InfoLine(label: strings.fading, value: forgetAfterLabel),
                const SizedBox(height: 14),
                _TrackingProfileSection(
                  preferences: trackingPreferences,
                  onChanged: onUpdateTrackingPreferences,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: onRequestTracking,
                        child: Text(strings.restartTracking),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onOpenPermissions,
                        child: Text(strings.permissions),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SettingsCard(
            title: strings.privacy,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.localPrivacyBody,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  strings.experimentBody,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.78),
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const LegalScreen(),
                      ),
                    );
                  },
                  child: Text(strings.termsAndPrivacy),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SettingsCard(
            title: strings.map,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.mapFadesBody,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  strings.batteryHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.68),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.tonal(
                  onPressed: () async {
                    final approved =
                        await showDialog<bool>(
                          context: context,
                          builder: (context) {
                            return AlertDialog(
                              title: Text(strings.resetDialogTitle),
                              content: Text(strings.resetDialogBody),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: Text(strings.cancel),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  child: Text(strings.delete),
                                ),
                              ],
                            );
                          },
                        ) ??
                        false;

                    if (approved) {
                      await onClearMap();
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    }
                  },
                  child: Text(strings.resetProgress),
                ),
              ],
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
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        SegmentedButton<PassiveTrackingProfile>(
          segments: [
            ButtonSegment(
              value: PassiveTrackingProfile.batterySaver,
              label: Text(strings.profileBatterySaver),
            ),
            ButtonSegment(
              value: PassiveTrackingProfile.balanced,
              label: Text(strings.profileBalanced),
            ),
            ButtonSegment(
              value: PassiveTrackingProfile.precise,
              label: Text(strings.profilePrecise),
            ),
            ButtonSegment(
              value: PassiveTrackingProfile.custom,
              label: Text(strings.profileCustom),
            ),
          ],
          selected: {preferences.profile},
          onSelectionChanged: (selection) async {
            final selected = selection.first;
            await onChanged(preferences.copyWith(profile: selected));
          },
          multiSelectionEnabled: false,
          showSelectedIcon: false,
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: preferences.adaptiveModeEnabled,
          activeThumbColor: const Color(0xFFB8FF8C),
          onChanged: (value) async {
            await onChanged(
              preferences.copyWith(adaptiveModeEnabled: value),
            );
          },
          title: Text(strings.adaptiveTracking),
          subtitle: Text(
            strings.adaptiveTrackingBody,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
        ),
        if (preferences.profile == PassiveTrackingProfile.custom) ...[
          const SizedBox(height: 8),
          Text(
            '${strings.customDistance}: ${strings.customDistanceValue(preferences.customDistanceFilterMeters)}',
          ),
          Slider(
            value: preferences.customDistanceFilterMeters.toDouble(),
            min: 5,
            max: 60,
            divisions: 11,
            activeColor: const Color(0xFFB8FF8C),
            onChanged: (value) async {
              await onChanged(
                preferences.copyWith(
                  customDistanceFilterMeters: value.round(),
                ),
              );
            },
          ),
          Text(
            '${strings.customInterval}: ${strings.customIntervalValue(preferences.customIntervalSeconds)}',
          ),
          Slider(
            value: preferences.customIntervalSeconds.toDouble(),
            min: 5,
            max: 60,
            divisions: 11,
            activeColor: const Color(0xFFB8FF8C),
            onChanged: (value) async {
              await onChanged(
                preferences.copyWith(customIntervalSeconds: value.round()),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(label),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
        ),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
