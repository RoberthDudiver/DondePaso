import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'footprint_zones.dart';

class ZoneNameService {
  static const _cachePrefix = 'zone_name_cache_';

  Future<String> resolveName(FootprintZone zone) async {
    final cacheKey = '$_cachePrefix${zone.zoneKey}';
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': zone.centerLatitude.toStringAsFixed(6),
      'lon': zone.centerLongitude.toStringAsFixed(6),
      'zoom': '15',
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

      final rawName =
          _firstNonEmpty(
            address['suburb'],
            address['neighbourhood'],
            address['quarter'],
            address['city_district'],
            address['borough'],
            address['town'],
            address['village'],
            address['city'],
            payload['name'],
            payload['display_name'],
          ) ??
          zone.title;
      final name = _cleanName(rawName) ?? zone.title;

      await prefs.setString(cacheKey, name);
      return name;
    } catch (_) {
      return zone.title;
    }
  }

  String? _firstNonEmpty(Object? a, [
    Object? b,
    Object? c,
    Object? d,
    Object? e,
    Object? f,
    Object? g,
    Object? h,
    Object? i,
    Object? j,
  ]) {
    final values = [a, b, c, d, e, f, g, h, i, j];
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) {
        return text;
      }
    }
    return null;
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

    return firstSegment;
  }
}
