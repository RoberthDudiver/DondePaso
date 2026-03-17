import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'community_models.dart';

class CommunityService {
  static const _assetPath = 'assets/community/contributors.json';
  static const _remoteUrl =
      'https://raw.githubusercontent.com/RoberthDudiver/DondePaso/main/assets/community/contributors.json';
  static const _cacheKey = 'community_snapshot_cache_v1';
  static const _cacheFetchedAtKey = 'community_snapshot_fetched_at_v1';
  static const _staleAfter = Duration(hours: 24);

  Future<CommunitySnapshot> load({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = _readCachedSnapshot(prefs);
    final isCacheFresh = _isCacheFresh(prefs);

    if (!forceRefresh && cached != null && isCacheFresh) {
      return cached;
    }

    try {
      final remoteJson = await _loadRemoteJson();
      final remote = CommunitySnapshot.fromJson(remoteJson);
      await prefs.setString(_cacheKey, jsonEncode(remoteJson));
      await prefs.setString(
        _cacheFetchedAtKey,
        DateTime.now().toUtc().toIso8601String(),
      );
      return remote;
    } catch (_) {
      if (cached != null) {
        return cached;
      }
      return _loadBundledSnapshot();
    }
  }

  Future<Map<String, dynamic>> _loadRemoteJson() async {
    final response = await http
        .get(Uri.parse(_remoteUrl))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Failed to fetch contributors: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<CommunitySnapshot> _loadBundledSnapshot() async {
    final raw = await rootBundle.loadString(_assetPath);
    return CommunitySnapshot.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  CommunitySnapshot? _readCachedSnapshot(SharedPreferences prefs) {
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return CommunitySnapshot.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  bool _isCacheFresh(SharedPreferences prefs) {
    final fetchedAtRaw = prefs.getString(_cacheFetchedAtKey);
    if (fetchedAtRaw == null) {
      return false;
    }
    final fetchedAt = DateTime.tryParse(fetchedAtRaw);
    if (fetchedAt == null) {
      return false;
    }
    return DateTime.now().toUtc().difference(fetchedAt) < _staleAfter;
  }
}
