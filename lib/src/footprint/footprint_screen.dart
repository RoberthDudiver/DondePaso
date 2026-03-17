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
import 'zone_name_service.dart';

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
  final ZoneNameService _zoneNameService = ZoneNameService();

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
  final Map<String, String> _zoneNames = <String, String>{};
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

    final zonesSnapshot = FootprintZones.build(
      cells: snapshot.cells,
      now: DateTime.now(),
    );

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
      _zonesSnapshot = zonesSnapshot;
      _progression = FootprintProgression.build(
        strings: AppStrings.of(context),
        totalPoints: snapshot.totalPoints,
        knownKilometers: FootprintProgress.knownKilometersFor(
          snapshot.cells,
          DateTime.now(),
        ),
        traveledTodayKilometers: FootprintProgress.todayKilometersFor(snapshot),
        dailySteps: _activityTracker.dailySteps,
        zonesSnapshot: zonesSnapshot,
      );
    });

    unawaited(_loadZoneNames(zonesSnapshot));
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

    final zonesSnapshot = FootprintZones.build(
      cells: snapshot.cells,
      now: DateTime.now(),
    );

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
      _zonesSnapshot = zonesSnapshot;
      _progression = FootprintProgression.build(
        strings: AppStrings.of(context),
        totalPoints: snapshot.totalPoints,
        knownKilometers: FootprintProgress.knownKilometersFor(
          snapshot.cells,
          DateTime.now(),
        ),
        traveledTodayKilometers: FootprintProgress.todayKilometersFor(snapshot),
        dailySteps: _activityTracker.dailySteps,
        zonesSnapshot: zonesSnapshot,
      );
    });

    unawaited(_loadZoneNames(zonesSnapshot));

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

  Future<void> _loadZoneNames(FootprintZonesSnapshot snapshot) async {
    final resolved = <String, String>{};
    for (final zone in snapshot.zones) {
      final name = await _zoneNameService.resolveName(zone);
      resolved[zone.zoneKey] = name;
    }

    if (!mounted || resolved.isEmpty) {
      return;
    }

    setState(() {
      _zoneNames.addAll(resolved);
    });
  }

  String _displayZoneTitle(FootprintZone? zone, AppStrings strings) {
    if (zone == null) {
      return strings.cityExploration;
    }

    final cached = _zoneNames[zone.zoneKey]?.trim();
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    if (zone.title.startsWith('Area ')) {
      return strings.mainZone;
    }

    return zone.title;
  }

  int _zoneCountWhere(bool Function(FootprintZone zone) test) {
    final unique = <String>{};
    for (final zone in _zonesSnapshot.zones.where(test)) {
      final title = (_zoneNames[zone.zoneKey] ?? zone.title).trim();
      if (title.isEmpty || title.startsWith('Area ')) {
        unique.add(zone.zoneKey);
      } else {
        unique.add(title.toLowerCase());
      }
    }
    return unique.length;
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

  int get _frequentedZonesCount => _zoneCountWhere(
    (zone) => zone.totalVisits >= 8 || zone.averageFreshness >= 0.42,
  );

  int get _discoveredZonesCount => _zoneCountWhere((_) => true);

  double get _cityExplorationRatio {
    final totalDiscovered = _zonesSnapshot.zones.fold<int>(
      0,
      (sum, zone) => sum + zone.discoveredCells,
    );
    final totalEstimate = _zonesSnapshot.zones.fold<int>(
      0,
      (sum, zone) => sum + zone.totalCellsEstimate,
    );
    if (totalEstimate == 0) {
      return 0;
    }
    return (totalDiscovered / totalEstimate).clamp(0, 1).toDouble();
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
    final primaryZoneTitle = _displayZoneTitle(
      _zonesSnapshot.primaryZone,
      strings,
    );
    final explorationPercent = (_cityExplorationRatio * 100).round();

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF050608), Color(0xFF0A0C10), Color(0xFF040505)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
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
                            return Opacity(
                              opacity: 0.72,
                              child: ColorFiltered(
                                colorFilter: const ColorFilter.matrix([
                                  0.54, 0.20, 0.14, 0, 0,
                                  0.20, 0.50, 0.16, 0, 0,
                                  0.16, 0.18, 0.46, 0, 0,
                                  0, 0, 0, 1, 0,
                                ]),
                                child: child,
                              ),
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
                                radius: 22,
                                useRadiusInMeter: false,
                                color: const Color(0x18FFC76B),
                                borderColor: const Color(0x28FFC76B),
                                borderStrokeWidth: 1,
                              ),
                              CircleMarker(
                                point: _currentLocation!,
                                radius: 8,
                                useRadiusInMeter: false,
                                color: const Color(0xFFFFC963),
                                borderColor: Colors.black,
                                borderStrokeWidth: 1.6,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const Positioned.fill(
                    child: IgnorePointer(child: _MapAtmosphereOverlay()),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              child: Column(
                children: [
                  Row(
                    children: [
                      _GlassIconButton(
                        icon: Icons.menu_rounded,
                        onPressed: _openSettingsScreen,
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            strings.appTitle,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      _GlassIconButton(
                        icon: _isLocating
                            ? Icons.hourglass_top_rounded
                            : Icons.my_location_rounded,
                        onPressed: _centerOnCurrentLocation,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (_needsAlwaysPermission) ...[
                    _AlwaysPermissionBanner(
                      onPressed: _requestAlwaysPermissionFromBanner,
                    ),
                    const SizedBox(height: 14),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _HeroStatCard(
                          title: strings.frequentedLabel,
                          value: strings.zonesCount(_frequentedZonesCount),
                          accentColor: const Color(0xFF7CC8FF),
                          backgroundColor: const Color(0xAA10233A),
                          icon: Icons.place_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _HeroStatCard(
                          title: strings.discoveredLabel,
                          value: strings.zonesCount(_discoveredZonesCount),
                          accentColor: const Color(0xFFFFCB59),
                          backgroundColor: const Color(0xAA3A2A12),
                          icon: Icons.favorite_rounded,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  _ExplorationProgressCard(
                    title: primaryZoneTitle,
                    subtitle: strings.cityExploration,
                    percentLabel: '$explorationPercent%',
                    progress: _cityExplorationRatio,
                    footer: Row(
                      children: [
                        Expanded(
                          child: _MiniMetric(
                            label: strings.points,
                            value: _pointsLabel,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MiniMetric(
                            label: strings.traveledTodayKm,
                            value: _todayDistanceLabel,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MiniMetric(
                            label: strings.totalKnownKm,
                            value: _knownKilometersLabel,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _BottomCommandBar(
                    items: [
                      _BottomCommand(
                        icon: Icons.alt_route_rounded,
                        label: strings.trails,
                        onTap: () {
                          Navigator.of(context).push(
                            buildFootprintZonesRoute(
                              zonesSnapshot: _zonesSnapshot,
                            ),
                          );
                        },
                      ),
                      _BottomCommand(
                        icon: Icons.map_rounded,
                        label: strings.map,
                        isActive: true,
                        onTap: () {},
                      ),
                      _BottomCommand(
                        icon: Icons.shield_moon_rounded,
                        label: strings.achievements,
                        onTap: () {
                          Navigator.of(context).push(
                            buildFootprintAchievementsRoute(
                              progression: _progression,
                            ),
                          );
                        },
                      ),
                      _BottomCommand(
                        icon: Icons.bar_chart_rounded,
                        label: strings.data,
                        onTap: () {
                          Navigator.of(context).push(
                            buildFootprintProgressRoute(
                              totalPoints: _totalPoints,
                              knownKilometers: _knownKilometers,
                              traveledTodayKilometers:
                                  _todayDistanceKilometers,
                              totalDistanceKilometers:
                                  _totalDistanceKilometers,
                              dailySteps: _activityTracker.dailySteps,
                              activityLabel: _activityLabel(strings),
                              stepSensorAvailable:
                                  _activityTracker.sensorAvailable,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  if (!_isTracking)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: FilledButton.tonalIcon(
                        onPressed: _activatePassiveTracking,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0x33FFB84D),
                          foregroundColor: const Color(0xFFFFD37B),
                        ),
                        icon: const Icon(Icons.radar_rounded),
                        label: Text(strings.passive),
                      ),
                    ),
                  if (_lastTrackedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _timeLabel(strings, _lastTrackedAt!),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.54),
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
                  child: CircularProgressIndicator(color: Color(0xFFFFD37B)),
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

class _MapAtmosphereOverlay extends StatelessWidget {
  const _MapAtmosphereOverlay();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xBC090B10),
            Color(0x260D1015),
            Color(0xA607090D),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, 0.08),
                  radius: 0.74,
                  colors: [
                    const Color(0x00FFB84D),
                    const Color(0x12FFB84D),
                    Colors.black.withValues(alpha: 0.42),
                  ],
                ),
              ),
            ),
        ),
        const Positioned(
          left: -80,
          top: 86,
          child: _CloudBlob(width: 230, height: 180, alpha: 0.46),
        ),
        const Positioned(
          right: -96,
          top: 132,
          child: _CloudBlob(width: 260, height: 210, alpha: 0.52),
        ),
        const Positioned(
          left: -50,
          bottom: -6,
          child: _CloudBlob(width: 210, height: 150, alpha: 0.48),
        ),
        const Positioned(
          right: -40,
          bottom: 18,
          child: _CloudBlob(width: 240, height: 170, alpha: 0.56),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topCenter,
                radius: 1.12,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.10),
                  Colors.black.withValues(alpha: 0.34),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CloudBlob extends StatelessWidget {
  const _CloudBlob({
    required this.width,
    required this.height,
    required this.alpha,
  });

  final double width;
  final double height;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [
              Colors.black.withValues(alpha: alpha),
              Colors.black.withValues(alpha: alpha * 0.72),
              Colors.black.withValues(alpha: 0),
            ],
            stops: const [0.18, 0.54, 1],
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          onPressed();
        },
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _HeroStatCard extends StatelessWidget {
  const _HeroStatCard({
    required this.title,
    required this.value,
    required this.accentColor,
    required this.backgroundColor,
    required this.icon,
  });

  final String title;
  final String value;
  final Color accentColor;
  final Color backgroundColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accentColor, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExplorationProgressCard extends StatelessWidget {
  const _ExplorationProgressCard({
    required this.title,
    required this.subtitle,
    required this.percentLabel,
    required this.progress,
    required this.footer,
  });

  final String title;
  final String subtitle;
  final String percentLabel;
  final double progress;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.64),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                percentLabel,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFFFFD26E),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.10),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFFFC94E)),
            ),
          ),
          const SizedBox(height: 12),
          footer,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomCommand {
  const _BottomCommand({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;
}

class _BottomCommandBar extends StatelessWidget {
  const _BottomCommandBar({required this.items});

  final List<_BottomCommand> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: items
            .map(
              (item) => Expanded(
                child: _BottomCommandButton(item: item),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _BottomCommandButton extends StatelessWidget {
  const _BottomCommandButton({required this.item});

  final _BottomCommand item;

  @override
  Widget build(BuildContext context) {
    final activeColor = const Color(0xFFFFCF69);
    final inactiveColor = Colors.white.withValues(alpha: 0.72);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              item.icon,
              color: item.isActive ? activeColor : inactiveColor,
              size: 20,
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: item.isActive ? activeColor : inactiveColor,
                fontWeight: item.isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
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
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
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
