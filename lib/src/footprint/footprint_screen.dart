import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';

import '../activity/daily_activity_tracker.dart';
import '../background/passive_tracking_service.dart';
import '../background/tracking_preferences.dart';
import '../i18n/app_strings.dart';
import 'footprint_backup_service.dart';
import 'footprint_cell.dart';
import 'footprint_fog_layer.dart';
import 'footprint_progress.dart';
import 'footprint_progression.dart';
import 'footprint_storage.dart';
import 'footprint_zones.dart';
import 'settings_screen.dart';

const _defaultCenter = LatLng(-34.6037, -58.3816);
const _revealMeters = 18.0;

class FootprintScreen extends StatefulWidget {
  const FootprintScreen({super.key});

  @override
  State<FootprintScreen> createState() => _FootprintScreenState();
}

class _FootprintScreenState extends State<FootprintScreen> {
  final MapController _mapController = MapController();
  final DailyActivityTracker _activityTracker = DailyActivityTracker();

  StreamSubscription<Map<String, dynamic>?>? _serviceSubscription;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _refreshTimer;

  bool _isBooting = true;
  bool _isLocating = false;
  bool _hasSeenOnboarding = false;
  bool _isTracking = false;
  bool _isFollowMode = true;
  bool _needsAlwaysPermission = false;

  int _totalPoints = 0;
  double _todayDistanceKilometers = 0;
  double _totalDistanceKilometers = 0;
  PassiveTrackingPreferences _trackingPreferences =
      PassiveTrackingPreferences.defaultPreferences;
  DateTime? _lastTrackedAt;
  LatLng? _currentLocation;
  List<FootprintCell> _cells = const [];
  FootprintZonesSnapshot _zonesSnapshot = const FootprintZonesSnapshot(
    primaryZone: null,
    zones: [],
  );
  ProgressionSnapshot? _progression;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    _activityTracker.addListener(_onActivityChanged);
    _activityTracker.start();

    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });

    try {
      _serviceSubscription = FlutterBackgroundService()
          .on('footprint_update')
          .listen((_) => _reloadFromStorage());
    } catch (_) {
      _serviceSubscription = null;
    }

    _restoreState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    _refreshTimer?.cancel();
    _serviceSubscription?.cancel();
    _positionSubscription?.cancel();
    _activityTracker
      ..removeListener(_onActivityChanged)
      ..dispose();
    super.dispose();
  }

  void _onActivityChanged() {
    if (mounted) {
      setState(() {
        _progression = FootprintProgression.build(
          strings: AppStrings.of(context),
          totalPoints: _totalPoints,
          knownKilometers: _knownKilometers,
          traveledTodayKilometers: _todayDistanceKilometers,
          dailySteps: _activityTracker.dailySteps,
          zonesSnapshot: _zonesSnapshot,
        );
      });
    }
  }

  late final WidgetsBindingObserver _lifecycleObserver =
      _FootprintLifecycleObserver(
        onResume: () async {
          await _refreshPermissionState();
          await _reloadFromStorage();
        },
      );

  Future<void> _restoreState() async {
    await _reloadFromStorage();
    await _refreshPermissionState();
    final running = await isPassiveTrackingServiceRunning();
    if (!mounted) {
      return;
    }

    setState(() {
      _isTracking = running;
      _isBooting = false;
    });

    await _startLiveLocationPreview();

    if (_hasSeenOnboarding && _currentLocation != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mapController.move(_currentLocation!, 16);
        }
      });
    }
  }

  Future<void> _reloadFromStorage() async {
    final snapshot = await FootprintProgress.loadSnapshot();
    if (!mounted) {
      return;
    }

    setState(() {
      _cells = snapshot.cells;
      _totalPoints = snapshot.totalPoints;
      _todayDistanceKilometers = FootprintProgress.todayKilometersFor(snapshot);
      _totalDistanceKilometers = FootprintProgress.totalDistanceKilometersFor(
        snapshot,
      );
      _trackingPreferences = snapshot.trackingPreferences;
      _hasSeenOnboarding = snapshot.onboardingSeen;
      _currentLocation = snapshot.lastLatLng;
      _lastTrackedAt = snapshot.lastTrackedAt;
      _zonesSnapshot = FootprintZones.build(
        cells: snapshot.cells,
        now: DateTime.now(),
      );
      _progression = FootprintProgression.build(
        strings: AppStrings.of(context),
        totalPoints: snapshot.totalPoints,
        knownKilometers: FootprintProgress.knownKilometersFor(
          snapshot.cells,
          DateTime.now(),
        ),
        traveledTodayKilometers: FootprintProgress.todayKilometersFor(snapshot),
        dailySteps: _activityTracker.dailySteps,
        zonesSnapshot: _zonesSnapshot,
      );
    });
  }

  Future<void> _refreshPermissionState() async {
    final permission = await Geolocator.checkPermission();
    if (!mounted) {
      return;
    }

    setState(() {
      _needsAlwaysPermission =
          _hasSeenOnboarding && permission != LocationPermission.always;
    });
  }

  Future<void> _startLiveLocationPreview() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      return;
    }

    await _positionSubscription?.cancel();

    final current = await _resolveBestPosition();
    if (current != null) {
      await _handleForegroundPosition(
        current,
        moveMap: _currentLocation == null,
      );
    }

    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 10,
          ),
        ).listen((position) {
          _handleForegroundPosition(position, moveMap: _isFollowMode);
        }, onError: (_) {
          if (mounted) {
            _showMessage(context.strings.locationStillLoading);
          }
        });

  }

  Future<Position?> _resolveBestPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> _handleForegroundPosition(
    Position position, {
    required bool moveMap,
  }) async {
    final point = LatLng(position.latitude, position.longitude);
    final snapshot = await FootprintProgress.recordVisit(point: point);
    if (!mounted) {
      return;
    }

    setState(() {
      _cells = snapshot.cells;
      _totalPoints = snapshot.totalPoints;
      _todayDistanceKilometers = FootprintProgress.todayKilometersFor(snapshot);
      _totalDistanceKilometers = FootprintProgress.totalDistanceKilometersFor(
        snapshot,
      );
      _currentLocation = point;
      _lastTrackedAt = snapshot.lastTrackedAt;
      _hasSeenOnboarding = snapshot.onboardingSeen;
      _zonesSnapshot = FootprintZones.build(
        cells: snapshot.cells,
        now: DateTime.now(),
      );
      _progression = FootprintProgression.build(
        strings: AppStrings.of(context),
        totalPoints: snapshot.totalPoints,
        knownKilometers: FootprintProgress.knownKilometersFor(
          snapshot.cells,
          DateTime.now(),
        ),
        traveledTodayKilometers: FootprintProgress.todayKilometersFor(snapshot),
        dailySteps: _activityTracker.dailySteps,
        zonesSnapshot: _zonesSnapshot,
      );
    });

    if (moveMap) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mapController.move(point, 16.5);
        }
      });
    }
  }

  Future<void> _activatePassiveTracking() async {
    final strings = context.strings;
    final result = await requestPassiveTrackingPermissions();
    if (!mounted) {
      return;
    }

    switch (result) {
      case PassiveTrackingPermissionResult.granted:
        await FootprintStorage().setOnboardingSeen();
        await ensurePassiveTrackingServiceRunning();
        await _reloadFromStorage();
        await _refreshPermissionState();
        await _startLiveLocationPreview();
        if (!mounted) {
          return;
        }
        setState(() {
          _hasSeenOnboarding = true;
          _isTracking = true;
        });
        break;
      case PassiveTrackingPermissionResult.locationServicesDisabled:
        await _showSimpleDialog(
          title: strings.gpsTitle,
          message: strings.gpsBody,
          primaryActionLabel: strings.openGps,
          onPrimaryAction: Geolocator.openLocationSettings,
        );
        break;
      case PassiveTrackingPermissionResult.foregroundDenied:
        await _showSimpleDialog(
          title: strings.locationNeededTitle,
          message: strings.locationNeededBody,
        );
        break;
      case PassiveTrackingPermissionResult.backgroundDenied:
        await _showSimpleDialog(
          title: strings.backgroundNeededTitle,
          message: strings.backgroundNeededBody,
        );
        break;
      case PassiveTrackingPermissionResult.permanentlyDenied:
        await _showSimpleDialog(
          title: strings.permissionBlockedTitle,
          message: strings.permissionBlockedBody,
          primaryActionLabel: strings.openSettings,
          onPrimaryAction: openAppSettings,
        );
        break;
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _centerOnCurrentLocation() async {
    final strings = context.strings;
    if (_isLocating) {
      return;
    }

    setState(() {
      _isFollowMode = true;
      _isLocating = true;
    });

    try {
      final servicesEnabled = await Geolocator.isLocationServiceEnabled();
      if (!servicesEnabled) {
        await _showSimpleDialog(
          title: strings.gpsTitle,
          message: strings.gpsBody,
          primaryActionLabel: strings.openGps,
          onPrimaryAction: Geolocator.openLocationSettings,
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        await _showSimpleDialog(
          title: strings.permissionBlockedTitle,
          message: strings.permissionBlockedBody,
          primaryActionLabel: strings.openSettings,
          onPrimaryAction: openAppSettings,
        );
        return;
      }

      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        _showMessage(strings.locationNeededBody);
        return;
      }

      _showMessage(strings.locatingYou);
      await _startLiveLocationPreview();

      final point = _currentLocation;
      if (point != null && mounted) {
        _mapController.move(point, 16.8);
        _showMessage(strings.locationCentered);
      } else {
        _showMessage(strings.locationStillLoading);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  Future<void> _showSimpleDialog({
    required String title,
    required String message,
    String? primaryActionLabel,
    Future<void> Function()? onPrimaryAction,
  }) async {
    final strings = context.strings;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.close),
            ),
            if (primaryActionLabel != null && onPrimaryAction != null)
              FilledButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await onPrimaryAction();
                },
                child: Text(primaryActionLabel),
              ),
          ],
        );
      },
    );
  }

  Future<void> _openPermissions() async {
    await openAppSettings();
  }

  Future<void> _exportBackup() async {
    final strings = context.strings;
    await FootprintProgress.flushPending();
    await FootprintBackupService.shareLatestBackup();
    _showMessage(strings.backupExported);
  }

  Future<void> _restoreLatestBackup() async {
    final strings = context.strings;
    final shouldRestore =
        await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text(strings.restoreBackupTitle),
              content: Text(
                '${strings.restoreBackupBody}\n\n${strings.backupWillRestart}',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(strings.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(strings.restore),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!shouldRestore) {
      return;
    }

    await FootprintProgress.flushPending();
    final backupState = await FootprintBackupService.loadLatestBackup();
    if (backupState == null) {
      _showMessage(strings.backupMissing);
      return;
    }

    await stopPassiveTrackingService();
    await FootprintStorage().overwriteState(backupState);
    FootprintProgress.invalidateCache();
    await _reloadFromStorage();
    await _refreshPermissionState();
    await _startLiveLocationPreview();

    if (backupState.passiveTrackingEnabled) {
      await ensurePassiveTrackingServiceRunning();
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isTracking = backupState.passiveTrackingEnabled;
    });
    _showMessage(strings.backupRestored);
  }

  Future<void> _requestAlwaysPermissionFromBanner() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always) {
      await _refreshPermissionState();
      return;
    }

    final requested = await Permission.locationAlways.request();
    if (requested.isGranted) {
      await _refreshPermissionState();
      if (_isTracking) {
        try {
          FlutterBackgroundService().invoke('refresh_stream');
        } catch (_) {
          await ensurePassiveTrackingServiceRunning();
        }
      }
      return;
    }

    await openAppSettings();
    await _refreshPermissionState();
  }

  Future<void> _setPassiveTracking(bool enabled) async {
    if (enabled) {
      await _activatePassiveTracking();
      return;
    }

    await stopPassiveTrackingService();
    if (!mounted) {
      return;
    }

    setState(() {
      _isTracking = false;
    });
  }

  Future<void> _updateTrackingPreferences(
    PassiveTrackingPreferences preferences,
  ) async {
    await FootprintStorage().saveTrackingPreferences(preferences);
    if (!mounted) {
      return;
    }

    setState(() {
      _trackingPreferences = preferences;
    });

    if (_isTracking) {
      try {
        FlutterBackgroundService().invoke('refresh_stream');
      } catch (_) {
        await ensurePassiveTrackingServiceRunning();
      }
    }
  }

  Future<void> _clearProgress() async {
    await stopPassiveTrackingService();
    await _positionSubscription?.cancel();
    await FootprintStorage().clear();
    FootprintProgress.invalidateCache();
    if (!mounted) {
      return;
    }

    setState(() {
      _cells = const [];
      _totalPoints = 0;
      _totalDistanceKilometers = 0;
      _currentLocation = null;
      _lastTrackedAt = null;
      _isTracking = false;
      _hasSeenOnboarding = false;
      _isFollowMode = true;
      _zonesSnapshot = const FootprintZonesSnapshot(primaryZone: null, zones: []);
      _progression = null;
    });
  }

  Future<void> _openSettingsScreen() async {
    final strings = context.strings;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) {
          return FootprintSettingsScreen(
            totalPoints: _totalPoints,
            knownKilometers: _knownKilometers,
            traveledTodayKilometers: _todayDistanceKilometers,
            totalDistanceKilometers: _totalDistanceKilometers,
            dailySteps: _activityTracker.dailySteps,
            activityLabel: _activityLabel(strings),
            stepSensorAvailable: _activityTracker.sensorAvailable,
            trackingActive: _isTracking,
            trackingPreferences: _trackingPreferences,
            forgetAfterLabel: strings.forgetAfterDays(
              footprintForgetAfter.inDays,
            ),
            onRequestTracking: _activatePassiveTracking,
            onTogglePassiveTracking: _setPassiveTracking,
            onUpdateTrackingPreferences: _updateTrackingPreferences,
            onOpenPermissions: _openPermissions,
            onExportBackup: _exportBackup,
            onRestoreBackup: _restoreLatestBackup,
            zonesSnapshot: _zonesSnapshot,
            progression: _progression,
            onClearMap: _clearProgress,
          );
        },
      ),
    );

    await _reloadFromStorage();
    final running = await isPassiveTrackingServiceRunning();
    if (mounted) {
      setState(() {
        _isTracking = running;
      });
    }
  }

  double get _knownKilometers {
    return FootprintProgress.knownKilometersFor(_cells, DateTime.now());
  }

  String get _pointsLabel =>
      AppStrings.of(context).formatCompactNumber(_totalPoints);

  String get _knownKilometersLabel =>
      '${_knownKilometers.toStringAsFixed(1)} km';

  String get _todayDistanceLabel =>
      '${_todayDistanceKilometers.toStringAsFixed(1)} km';

  String _activityLabel(AppStrings strings) {
    if (!_activityTracker.sensorAvailable ||
        !_activityTracker.permissionGranted) {
      return strings.stepSensorUnavailable;
    }

    if (_activityTracker.dailySteps >= 11000) {
      return strings.activityExplorer;
    }
    if (_activityTracker.dailySteps >= 7000 || _activityTracker.isWalking) {
      return strings.activityHigh;
    }
    if (_activityTracker.dailySteps >= 2500) {
      return strings.activityWarm;
    }
    return strings.activityLow;
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final now = DateTime.now();
    final compactHomeEnabled = now.microsecondsSinceEpoch >= 0;

    if (compactHomeEnabled) {
      return _buildCompactHome(context, strings, now);
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF030303), Color(0xFF0A0D07)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _currentLocation ?? _defaultCenter,
                  initialZoom: 15,
                  minZoom: 3,
                  maxZoom: 18.5,
                  onPositionChanged: (_, hasGesture) {
                    if (hasGesture && _isFollowMode) {
                      setState(() {
                        _isFollowMode = false;
                      });
                    }
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.dudiver.dondepaso',
                    tileBuilder: (context, child, tile) {
                      return ColorFiltered(
                        colorFilter: const ColorFilter.matrix([
                          0.88,
                          0,
                          0,
                          0,
                          0,
                          0,
                          0.93,
                          0,
                          0,
                          0,
                          0,
                          0,
                          0.93,
                          0,
                          0,
                          0,
                          0,
                          0,
                          1,
                          0,
                        ]),
                        child: child,
                      );
                    },
                  ),
                  FootprintFogLayer(
                    cells: _cells,
                    currentLocation: _currentLocation,
                    now: now,
                    forgetAfter: footprintForgetAfter,
                    revealMeters: _revealMeters,
                  ),
                  if (_currentLocation != null)
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: _currentLocation!,
                          radius: 12,
                          useRadiusInMeter: false,
                          color: const Color(0x33B8FF8C),
                          borderColor: const Color(0x66B8FF8C),
                          borderStrokeWidth: 1,
                        ),
                        CircleMarker(
                          point: _currentLocation!,
                          radius: 5,
                          useRadiusInMeter: false,
                          color: const Color(0xFFB8FF8C),
                          borderColor: Colors.black,
                          borderStrokeWidth: 1.6,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings.appTitle,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: _openSettingsScreen,
                        icon: const Icon(Icons.dashboard_customize_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_needsAlwaysPermission) ...[
                    _AlwaysPermissionBanner(
                      onPressed: _requestAlwaysPermissionFromBanner,
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: _MetricPill(
                          label: strings.points,
                          value: _pointsLabel,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MetricPill(
                          label: strings.traveledTodayKm,
                          value: _todayDistanceLabel,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _MetricPill(
                    label: strings.totalKnownKm,
                    value: _knownKilometersLabel,
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _TagChip(label: strings.localOnly),
                        _TagChip(label: strings.locked),
                        _TagChip(label: strings.noCloud),
                        if (_progression != null)
                          _TagChip(
                            label:
                                '${strings.levelValue(_progression!.level)} · ${_progression!.title}',
                          ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (!_isTracking)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: FilledButton.tonalIcon(
                            onPressed: _activatePassiveTracking,
                            icon: const Icon(Icons.radar_rounded),
                            label: Text(strings.passive),
                          ),
                        ),
                      FloatingActionButton.small(
                        heroTag: 'follow_me',
                        tooltip: strings.whereAmI,
                        onPressed: _centerOnCurrentLocation,
                        child: _isLocating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                ),
                              )
                            : Icon(
                                _isFollowMode
                                    ? Icons.navigation_rounded
                                    : Icons.my_location_rounded,
                              ),
                      ),
                    ],
                  ),
                  if (_lastTrackedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _timeLabel(strings, _lastTrackedAt!),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_isBooting)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0xEE030303),
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFFB8FF8C)),
                ),
              ),
            ),
          if (!_isBooting && !_hasSeenOnboarding)
            Positioned.fill(
              child: _OnboardingOverlay(onStart: _activatePassiveTracking),
            ),
        ],
      ),
    );
  }

  Widget _buildCompactHome(
    BuildContext context,
    AppStrings strings,
    DateTime now,
  ) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF030303), Color(0xFF0A0D07)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _currentLocation ?? _defaultCenter,
                  initialZoom: 15,
                  minZoom: 3,
                  maxZoom: 18.5,
                  onPositionChanged: (_, hasGesture) {
                    if (hasGesture && _isFollowMode) {
                      setState(() {
                        _isFollowMode = false;
                      });
                    }
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.dudiver.dondepaso',
                    tileBuilder: (context, child, tile) {
                      return ColorFiltered(
                        colorFilter: const ColorFilter.matrix([
                          0.88,
                          0,
                          0,
                          0,
                          0,
                          0,
                          0.93,
                          0,
                          0,
                          0,
                          0,
                          0,
                          0.93,
                          0,
                          0,
                          0,
                          0,
                          0,
                          1,
                          0,
                        ]),
                        child: child,
                      );
                    },
                  ),
                  FootprintFogLayer(
                    cells: _cells,
                    currentLocation: _currentLocation,
                    now: now,
                    forgetAfter: footprintForgetAfter,
                    revealMeters: _revealMeters,
                  ),
                  if (_currentLocation != null)
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: _currentLocation!,
                          radius: 12,
                          useRadiusInMeter: false,
                          color: const Color(0x33B8FF8C),
                          borderColor: const Color(0x66B8FF8C),
                          borderStrokeWidth: 1,
                        ),
                        CircleMarker(
                          point: _currentLocation!,
                          radius: 5,
                          useRadiusInMeter: false,
                          color: const Color(0xFFB8FF8C),
                          borderColor: Colors.black,
                          borderStrokeWidth: 1.6,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings.appTitle,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: _openSettingsScreen,
                        icon: const Icon(Icons.dashboard_customize_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_needsAlwaysPermission) ...[
                    _AlwaysPermissionBanner(
                      onPressed: _requestAlwaysPermissionFromBanner,
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: _MetricPill(
                          label: strings.points,
                          value: _pointsLabel,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MetricPill(
                          label: strings.traveledTodayKm,
                          value: _todayDistanceLabel,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _MetricPill(
                    label: strings.totalKnownKm,
                    value: _knownKilometersLabel,
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (!_isTracking)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: FilledButton.tonalIcon(
                            onPressed: _activatePassiveTracking,
                            icon: const Icon(Icons.radar_rounded),
                            label: Text(strings.passive),
                          ),
                        ),
                      FloatingActionButton.small(
                        heroTag: 'follow_me',
                        tooltip: strings.whereAmI,
                        onPressed: _centerOnCurrentLocation,
                        child: _isLocating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                ),
                              )
                            : Icon(
                                _isFollowMode
                                    ? Icons.navigation_rounded
                                    : Icons.my_location_rounded,
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_isBooting)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0xEE030303),
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFFB8FF8C)),
                ),
              ),
            ),
          if (!_isBooting && !_hasSeenOnboarding)
            Positioned.fill(
              child: _OnboardingOverlay(onStart: _activatePassiveTracking),
            ),
        ],
      ),
    );
  }

  String _timeLabel(AppStrings strings, DateTime timestamp) {
    final delta = DateTime.now().difference(timestamp);
    if (delta.inMinutes < 1) {
      return strings.lastCaptureJustNow;
    }
    if (delta.inHours < 1) {
      return strings.lastCaptureMinutes(delta.inMinutes);
    }
    return strings.lastCaptureHours(delta.inHours);
  }
}

class _PrimaryZoneCard extends StatelessWidget {
  const _PrimaryZoneCard({required this.zone});

  final FootprintZone zone;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final coveragePercent = (zone.discoveredRatio * 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.mainZone,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            zone.title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: zone.discoveredRatio,
              minHeight: 9,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFB8FF8C)),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TagChip(label: strings.zoneCoverageLabel(coveragePercent)),
              _TagChip(label: strings.zoneCellsLabel(zone.discoveredCells)),
            ],
          ),
        ],
      ),
    );
  }
}

class _LevelBanner extends StatelessWidget {
  const _LevelBanner({required this.progression});

  final ProgressionSnapshot progression;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF141110), Color(0xFF172313)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFB8FF8C),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                '${progression.level}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  progression.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  strings.nextLevelLabel(
                    strings.formatCompactNumber(progression.nextLevelPoints),
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
          Text(
            strings.unlockedAchievementsLabel(
              progression.unlockedAchievements,
              progression.achievements.length,
            ),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
        ],
      ),
    );
  }
}

class _FootprintLifecycleObserver with WidgetsBindingObserver {
  _FootprintLifecycleObserver({required this.onResume});

  final Future<void> Function() onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResume();
    }
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.68),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.white.withValues(alpha: 0.76),
        ),
      ),
    );
  }
}

class _AlwaysPermissionBanner extends StatelessWidget {
  const _AlwaysPermissionBanner({required this.onPressed});

  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF611111),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFF7676), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.alwaysPermissionAlertTitle,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            strings.alwaysPermissionAlertBody,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.92),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF7A7A),
                foregroundColor: Colors.black,
              ),
              child: Text(strings.grantAlwaysPermission),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingOverlay extends StatelessWidget {
  const _OnboardingOverlay({required this.onStart});

  final Future<void> Function() onStart;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.86),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Text(
                strings.onboardingTitle,
                style: Theme.of(
                  context,
                ).textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  shadows: const [
                    Shadow(
                      color: Color(0xCC000000),
                      blurRadius: 14,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                strings.onboardingBody,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.8),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                strings.onboardingExperiment,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.68),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onStart,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB8FF8C),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: Text(strings.onboardingActivate),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
