import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usage_stats/usage_stats.dart';

import 'package:tempo/constants/app_constants.dart';
import 'package:tempo/services/app_cache.dart';
import 'package:tempo/screens/pin_screen.dart';
import 'package:tempo/screens/app_lister_screen.dart';
import 'package:tempo/services/password_service.dart';

class ActiveLimitsScreen extends StatefulWidget {
  const ActiveLimitsScreen({super.key});

  @override
  State<ActiveLimitsScreen> createState() => _ActiveLimitsScreenState();
}

class _ActiveLimitsScreenState extends State<ActiveLimitsScreen> {
  List<_LimitedAppEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLimits();
  }

  Future<Map<String, int>> _getUsageInLastHour(Set<String> packages) async {
    final now = DateTime.now();
    final oneHourAgo = now.subtract(const Duration(hours: 1));

    final usageMap = <String, int>{};
    try {
      final events = await UsageStats.queryEvents(oneHourAgo, now);

      final lastForeground = <String, int>{};

      for (final event in events) {
        final pkg = event.packageName;
        if (pkg == null || !packages.contains(pkg)) continue;
        final timestamp = int.tryParse(event.timeStamp ?? '');
        if (timestamp == null) continue;
        final type = int.tryParse(event.eventType ?? '');
        if (type == null) continue;

        switch (type) {
          case 1: // MOVE_TO_FOREGROUND
          case 7: // ACTIVITY_RESUMED
            lastForeground[pkg] = timestamp;
            break;
          case 2: // MOVE_TO_BACKGROUND
          case 15: // ACTIVITY_PAUSED
            final start = lastForeground[pkg];
            if (start != null) {
              usageMap[pkg] = (usageMap[pkg] ?? 0) + (timestamp - start);
              lastForeground.remove(pkg);
            }
            break;
        }
      }

      final nowMs = now.millisecondsSinceEpoch;
      for (final entry in lastForeground.entries) {
        usageMap[entry.key] = (usageMap[entry.key] ?? 0) + (nowMs - entry.value);
      }
    } catch (_) {}

    return usageMap.map((k, v) => MapEntry(k, (v / 60000).round()));
  }

  Future<void> _loadLimits() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final limitKeys = keys.where((k) => k.startsWith(StorageKeys.timeLimitPrefix));

    final cachedApps = AppCache.cachedApps;
    final appsByPackage = <String, AppInfo>{};
    if (cachedApps != null) {
      for (final app in cachedApps) {
        appsByPackage[app.packageName] = app;
      }
    }

    final packageNames = <String>{};
    final limitsRaw = <String, int>{};
    for (final key in limitKeys) {
      final packageName = key.replaceFirst(StorageKeys.timeLimitPrefix, '');
      final minutes = prefs.getInt(key);
      if (minutes == null) continue;
      packageNames.add(packageName);
      limitsRaw[packageName] = minutes;
    }

    final usageMap = await _getUsageInLastHour(packageNames);

    final entries = <_LimitedAppEntry>[];
    for (final packageName in packageNames) {
      final minutes = limitsRaw[packageName]!;
      final cachedApp = appsByPackage[packageName];
      final appName =
          cachedApp?.name ??
          prefs.getString('${StorageKeys.appNamePrefix}$packageName') ??
          packageName;

      entries.add(
        _LimitedAppEntry(
          name: appName,
          packageName: packageName,
          minutes: minutes,
          usedMinutes: usageMap[packageName] ?? 0,
          icon: cachedApp?.icon,
        ),
      );
    }

    entries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (mounted) {
      setState(() {
        _entries = entries;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 48),

            Center(child: Image.asset('assets/flower.png', height: 80, fit: BoxFit.contain)),

            const SizedBox(height: 32),

            const Center(
              child: Text(
                Strings.activeLimitsTitle,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
            ),

            const SizedBox(height: 32),

            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: RefreshIndicator(
                  color: Colors.black,
                  onRefresh: _loadLimits,
                  child: _entries.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.4,
                              child: Center(
                                child: Text(
                                  Strings.noActiveLimits,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.black.withValues(alpha: 0.5),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          itemCount: _entries.length,
                          itemBuilder: (context, index) {
                            final entry = _entries[index];
                            final remaining = (entry.minutes - entry.usedMinutes).clamp(
                              0,
                              entry.minutes,
                            );
                            final isExhausted = remaining <= 0;
                            return ListTile(
                              contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                              leading: entry.icon != null
                                  ? Image.memory(
                                      entry.icon!,
                                      gaplessPlayback: true,
                                      width: 40,
                                      height: 40,
                                    )
                                  : const Icon(Icons.apps, size: 40),
                              title: Text(entry.name),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${entry.usedMinutes} / ${entry.minutes} min',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: isExhausted ? Colors.black : Colors.black,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        isExhausted
                                            ? Strings.limitExhausted
                                            : '$remaining minutes ${Strings.limitRemaining}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isExhausted
                                              ? Colors.black.withValues(alpha: 0.8)
                                              : Colors.black.withValues(alpha: 0.45),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    isExhausted ? Icons.block : Icons.timer_outlined,
                                    color: Colors.black,
                                    size: 20,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    bool ok = true;
                    final hasPin = await PasswordService.hasPin();
                    if (hasPin && context.mounted) {
                      ok = await PinScreen.promptPin(context);
                    }
                    if (ok && context.mounted) {
                      await Navigator.of(
                        context,
                      ).push(MaterialPageRoute(builder: (context) => const AppListerScreen()));
                      if (context.mounted) {
                        setState(() {
                          _loading = true;
                        });
                        _loadLimits();
                      }
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black,
                    side: const BorderSide(color: Colors.black),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    Strings.modifyLimitsAction,
                    style: TextStyle(fontSize: 15),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LimitedAppEntry {
  final String name;
  final String packageName;
  final int minutes;
  final int usedMinutes;
  final dynamic icon;

  _LimitedAppEntry({
    required this.name,
    required this.packageName,
    required this.minutes,
    required this.usedMinutes,
    this.icon,
  });
}
