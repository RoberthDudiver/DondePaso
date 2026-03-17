import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/app_strings.dart';
import 'footprint_zones.dart';

class ZoneNameService {
  static const _cachePrefix = 'zone_name_cache_v2_';
  static final RegExp _technicalZonePattern = RegExp(
    r'^(area|zone)\s*\d+$',
    caseSensitive: false,
  );

  static bool looksTechnicalZoneTitle(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) {
      return true;
    }
    return _technicalZonePattern.hasMatch(text);
  }

  static String fallbackDisplayName({AppStrings? strings}) {
    return (strings ?? AppStrings.fromSystem()).nearbyZone;
  }

  Future<String> resolveName(FootprintZone zone) async {
    final cacheKey = '$_cachePrefix${zone.zoneKey}';
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(cacheKey);
    if (cached != null &&
        cached.isNotEmpty &&
        !looksTechnicalZoneTitle(cached)) {
      return cached;
    }

    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': zone.centerLatitude.toStringAsFixed(6),
      'lon': zone.centerLongitude.toStringAsFixed(6),
      'zoom': '14',
      'addressdetails': '1',
    });

    try {
      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'DondePaso/1.0 (https://github.com/RoberthDudiver/DondePaso)',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        return zone.title;
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final address =
          Map<String, dynamic>.from(
            (payload['address'] as Map?) ?? const <String, dynamic>{},
          );

      final rawName = _bestAreaName(address, payload) ?? zone.title;
      final name = _cleanName(rawName) ?? zone.title;

      await prefs.setString(cacheKey, name);
      return name;
    } catch (_) {
      return zone.title;
    }
  }

  String? _bestAreaName(
    Map<String, dynamic> address,
    Map<String, dynamic> payload,
  ) {
    final quarter = _cleanName(address['quarter']?.toString());
    final neighbourhood = _cleanName(address['neighbourhood']?.toString());
    final suburb = _cleanName(address['suburb']?.toString());
    final cityDistrict = _cleanName(address['city_district']?.toString());
    final borough = _cleanName(address['borough']?.toString());
    final city = _cleanName(address['city']?.toString());
    final town = _cleanName(address['town']?.toString());
    final village = _cleanName(address['village']?.toString());

    final local = quarter ?? neighbourhood;
    final broader = suburb ?? cityDistrict ?? borough;

    if (local != null && broader != null && !_sameLabel(local, broader)) {
      return '$local · $broader';
    }

    return local ??
        broader ??
        _cleanName(payload['name']?.toString()) ??
        _cleanName(city) ??
        _cleanName(town) ??
        _cleanName(village) ??
        _cleanName(address['road']?.toString()) ??
        _cleanName(address['pedestrian']?.toString()) ??
        _cleanName(address['residential']?.toString()) ??
        _cleanName(address['commercial']?.toString()) ??
        _cleanName(payload['display_name']?.toString());
  }

  bool _sameLabel(String a, String b) {
    return a.trim().toLowerCase() == b.trim().toLowerCase();
  }

  String? _cleanName(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) {
      return null;
    }

    final firstSegment = text.split(',').first.trim();
    if (firstSegment.isEmpty) {
      return null;
    }

    if (looksTechnicalZoneTitle(firstSegment)) {
      return null;
    }

    return firstSegment;
  }
}
