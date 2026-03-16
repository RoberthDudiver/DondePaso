import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DailyActivitySnapshot {
  const DailyActivitySnapshot({
    required this.dailySteps,
    required this.sensorAvailable,
    required this.permissionGranted,
    required this.isWalking,
  });

  final int dailySteps;
  final bool sensorAvailable;
  final bool permissionGranted;
  final bool isWalking;
}

class DailyActivityTracker extends ChangeNotifier {
  StreamSubscription<StepCount>? _stepSubscription;
  StreamSubscription<PedestrianStatus>? _statusSubscription;

  int _dailySteps = 0;
  bool _sensorAvailable = true;
  bool _permissionGranted = true;
  bool _isWalking = false;

  int get dailySteps => _dailySteps;
  bool get sensorAvailable => _sensorAvailable;
  bool get permissionGranted => _permissionGranted;
  bool get isWalking => _isWalking;

  Future<void> start() async {
    await _loadPersisted();
    await _requestPermissionIfNeeded();
    if (!_permissionGranted) {
      notifyListeners();
      return;
    }

    _stepSubscription ??= Pedometer.stepCountStream.listen(
      _onStepCount,
      onError: (_) {
        _sensorAvailable = false;
        notifyListeners();
      },
      cancelOnError: false,
    );

    _statusSubscription ??= Pedometer.pedestrianStatusStream.listen(
      (status) {
        _isWalking = status.status == 'walking';
        notifyListeners();
      },
      onError: (_) {
        notifyListeners();
      },
      cancelOnError: false,
    );
  }

  Future<void> _requestPermissionIfNeeded() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final status = await Permission.activityRecognition.request();
      _permissionGranted = status.isGranted;
    }
  }

  Future<void> _loadPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    _dailySteps = prefs.getInt(_stepsKey) ?? 0;
  }

  Future<void> _onStepCount(StepCount event) async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    final storedDay = prefs.getString(_dayKey);
    final storedBase = prefs.getInt(_baseKey);

    var baseline = storedBase;

    if (storedDay != today || baseline == null || event.steps < baseline) {
      baseline = event.steps;
      await prefs.setString(_dayKey, today);
      await prefs.setInt(_baseKey, baseline);
    }

    _dailySteps = (event.steps - baseline).clamp(0, 999999);
    _sensorAvailable = true;

    await prefs.setInt(_stepsKey, _dailySteps);
    notifyListeners();
  }

  @override
  void dispose() {
    _stepSubscription?.cancel();
    _statusSubscription?.cancel();
    super.dispose();
  }

  static const _dayKey = 'activity_day_key';
  static const _baseKey = 'activity_base_steps';
  static const _stepsKey = 'activity_daily_steps';

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }
}
