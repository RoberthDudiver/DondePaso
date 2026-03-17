import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../background/tracking_preferences.dart';
import 'footprint_cell.dart';
import 'footprint_storage.dart';

class FootprintBackupService {
  FootprintBackupService._();

  static const _schemaVersion = 1;
  static const _backupFileName = 'dondepaso_backup.json';

  static Future<File> writeAutomaticBackup(FootprintStorageState state) async {
    final file = await _backupFile();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(_encodeState(state)),
    );
    return file;
  }

  static Future<File?> latestBackupFile() async {
    final file = await _backupFile();
    return file.existsSync() ? file : null;
  }

  static Future<bool> hasBackup() async {
    final file = await latestBackupFile();
    return file != null;
  }

  static Future<void> shareLatestBackup() async {
    final storageState = await FootprintStorage().load();
    final file = await writeAutomaticBackup(storageState);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        text: 'DondePaso backup',
      ),
    );
  }

  static Future<FootprintStorageState?> loadLatestBackup() async {
    final file = await latestBackupFile();
    if (file == null) {
      return null;
    }

    final raw = await file.readAsString();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return _decodeState(json);
  }

  static Map<String, dynamic> _encodeState(FootprintStorageState state) {
    return <String, dynamic>{
      'schemaVersion': _schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'cells': state.cells.map((cell) => cell.toMap()).toList(),
      'legacyCells': state.legacyCells.map((cell) => cell.toMap()).toList(),
      'onboardingSeen': state.onboardingSeen,
      'lightMapMode': state.lightMapMode,
      'totalPoints': state.totalPoints,
      'totalDistanceMeters': state.totalDistanceMeters,
      'totalVehicleDistanceMeters': state.totalVehicleDistanceMeters,
      'todayDistanceMeters': state.todayDistanceMeters,
      'todayDistanceDayKey': state.todayDistanceDayKey,
      'passiveTrackingEnabled': state.passiveTrackingEnabled,
      'trackingPreferences': <String, dynamic>{
        'profile': state.trackingPreferences.profile.storageValue,
        'customDistanceFilterMeters':
            state.trackingPreferences.customDistanceFilterMeters,
        'customIntervalSeconds':
            state.trackingPreferences.customIntervalSeconds,
        'adaptiveModeEnabled': state.trackingPreferences.adaptiveModeEnabled,
      },
      'lastLatitude': state.lastLatitude,
      'lastLongitude': state.lastLongitude,
      'lastTrackedAt': state.lastTrackedAt?.toIso8601String(),
    };
  }

  static FootprintStorageState _decodeState(Map<String, dynamic> map) {
    final trackingMap =
        Map<String, dynamic>.from(
          (map['trackingPreferences'] as Map?) ?? const <String, dynamic>{},
        );

    return FootprintStorageState(
      cells: _decodeCells(map['cells']),
      legacyCells: _decodeCells(map['legacyCells']),
      onboardingSeen: map['onboardingSeen'] as bool? ?? false,
      lightMapMode: map['lightMapMode'] as bool? ?? false,
      totalPoints: (map['totalPoints'] as num?)?.toInt() ?? 0,
      totalDistanceMeters:
          (map['totalDistanceMeters'] as num?)?.toDouble() ?? 0,
      totalVehicleDistanceMeters:
          (map['totalVehicleDistanceMeters'] as num?)?.toDouble() ?? 0,
      todayDistanceMeters: (map['todayDistanceMeters'] as num?)?.toDouble() ?? 0,
      todayDistanceDayKey: map['todayDistanceDayKey'] as String?,
      passiveTrackingEnabled: map['passiveTrackingEnabled'] as bool? ?? true,
      trackingPreferences: PassiveTrackingPreferences(
        profile: PassiveTrackingProfileCodec.fromStorage(
          trackingMap['profile'] as String?,
        ),
        customDistanceFilterMeters:
            (trackingMap['customDistanceFilterMeters'] as num?)?.toInt() ??
            PassiveTrackingPreferences
                .defaultPreferences
                .customDistanceFilterMeters,
        customIntervalSeconds:
            (trackingMap['customIntervalSeconds'] as num?)?.toInt() ??
            PassiveTrackingPreferences.defaultPreferences.customIntervalSeconds,
        adaptiveModeEnabled:
            trackingMap['adaptiveModeEnabled'] as bool? ??
            PassiveTrackingPreferences.defaultPreferences.adaptiveModeEnabled,
      ),
      lastLatitude: (map['lastLatitude'] as num?)?.toDouble(),
      lastLongitude: (map['lastLongitude'] as num?)?.toDouble(),
      lastTrackedAt: map['lastTrackedAt'] == null
          ? null
          : DateTime.parse(map['lastTrackedAt'] as String),
    );
  }

  static List<FootprintCell> _decodeCells(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .map(
          (item) => FootprintCell.fromMap(
            Map<String, dynamic>.from(item as Map<dynamic, dynamic>),
          ),
        )
        .toList(growable: false);
  }

  static Future<File> _backupFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_backupFileName');
  }
}
