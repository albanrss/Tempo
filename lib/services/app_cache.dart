import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_category.dart';
import 'package:installed_apps/platform_type.dart';
import 'package:path_provider/path_provider.dart';
import 'package:usage_stats/usage_stats.dart';

class AppCache {
  static List<AppInfo>? appsWithIcons;
  static Future<List<AppInfo>>? _loadingFuture;

  static List<AppInfo>? _diskCachedApps;
  static Future<void>? _warmUpFuture;
  static const String _cacheFileName = 'apps_cache.json';

  static Future<void> warmUp() {
    _warmUpFuture ??= _loadFromDisk();
    return _warmUpFuture!;
  }

  static List<AppInfo>? get cachedApps => appsWithIcons ?? _diskCachedApps;

  static Future<void> _loadFromDisk() async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$_cacheFileName');
      if (!file.existsSync()) return;
      final content = await file.readAsString();
      _diskCachedApps = await compute(_deserializeApps, content);
    } catch (_) {
      // Cache miss / corrupt file — not critical, will be regenerated
    }
  }

  static List<AppInfo> _deserializeApps(String json) {
    final List<dynamic> list = jsonDecode(json);
    return list.map((item) {
      final map = item as Map<String, dynamic>;
      final iconBase64 = map['icon'] as String?;
      return AppInfo(
        name: map['name'] as String,
        icon: iconBase64 != null ? base64Decode(iconBase64) : null,
        packageName: map['package_name'] as String,
        versionName: map['version_name'] as String,
        versionCode: map['version_code'] as int,
        platformType: PlatformType.parse(map['platform_type'] as String?),
        installedTimestamp: map['installed_timestamp'] as int,
        isSystemApp: map['is_system_app'] as bool,
        isLaunchableApp: map['is_launchable_app'] as bool,
        category: AppCategory.fromValue(map['category'] as int?),
      );
    }).toList();
  }

  static String _serializeApps(List<AppInfo> apps) {
    final list = apps.map((app) => {
      'name': app.name,
      'package_name': app.packageName,
      'icon': app.icon != null ? base64Encode(app.icon!) : null,
      'version_name': app.versionName,
      'version_code': app.versionCode,
      'platform_type': app.platformType.slug,
      'installed_timestamp': app.installedTimestamp,
      'is_system_app': app.isSystemApp,
      'is_launchable_app': app.isLaunchableApp,
      'category': app.category.value,
    }).toList();
    return jsonEncode(list);
  }

  static Future<void> _saveToDisk(List<AppInfo> apps) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$_cacheFileName');
      final json = await compute(_serializeApps, apps);
      await file.writeAsString(json);
    } catch (_) {}
  }

  static Future<List<AppInfo>?> loadAppsInBackground({bool forceRefresh = false}) async {
    if (forceRefresh) {
      appsWithIcons = null;
      _loadingFuture = null;
    }

    if (appsWithIcons != null) return appsWithIcons;
    if (_loadingFuture != null) return _loadingFuture;

    final granted = await UsageStats.checkUsagePermission() ?? false;
    if (!granted) return null;

    final future = _fetchAndCacheApps();
    _loadingFuture = future;
    try {
      final result = await future;
      if (_loadingFuture == future) {
        appsWithIcons = result;
        _diskCachedApps = result;
      }
      return result;
    } catch (e) {
      return null;
    } finally {
      if (_loadingFuture == future) {
        _loadingFuture = null;
      }
    }
  }

  static Future<List<AppInfo>> _fetchAndCacheApps() async {
    final apps = await InstalledApps.getInstalledApps(
      withIcon: true,
      excludeSystemApps: false,
    );
    _saveToDisk(apps);
    return apps;
  }
}
