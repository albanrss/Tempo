import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:tempo/constants/app_constants.dart';
import 'package:tempo/services/native_bridge.dart';
import 'package:tempo/services/app_cache.dart';
import 'package:tempo/services/password_service.dart';
import 'package:tempo/screens/app_limit_screen.dart';
import 'package:tempo/screens/pin_screen.dart';
import 'package:tempo/screens/active_limits_screen.dart';

class AppListerScreen extends StatefulWidget {
  const AppListerScreen({super.key});

  @override
  State<AppListerScreen> createState() => _AppListerScreenState();
}

class _AppListerScreenState extends State<AppListerScreen> with WidgetsBindingObserver {
  List<AppInfo> _apps = [];
  List<AppInfo> _filteredApps = [];
  Set<String> _appsWithLimits = {};
  Map<String, int> _appTimeLimits = {};
  bool _permissionGranted = false;
  bool _accessibilityEnabled = false;
  bool _notificationsEnabled = false;
  bool _isCheckingPermissions = true;
  bool _pinSet = false;
  final TextEditingController _searchBarController = TextEditingController();
  bool _isScrolled = false;
  final Set<String> _storedAppNamePackages = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAppsWithLimits();
    _checkAllPermissions();
    _checkPinStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchBarController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadAppsWithLimits();
      _checkAllPermissions();
      _checkPinStatus();
    }
  }

  Future<void> _checkPinStatus() async {
    final has = await PasswordService.hasPin();
    if (mounted) {
      setState(() {
        _pinSet = has;
      });
    }
  }

  Future<void> _checkAllPermissions() async {
    if (mounted) {
      setState(() {
        _isCheckingPermissions = true;
      });
    }
    await Future.wait([
      _checkAndRequestPermission(),
      _checkBlockingPermissions(),
      _checkNotificationPermission(),
    ]);
    if (mounted) {
      setState(() {
        _isCheckingPermissions = false;
      });
    }
  }

  Future<void> _loadAppsWithLimits() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final limitKeys = keys.where((k) => k.startsWith(StorageKeys.timeLimitPrefix));
    final limits = <String, int>{};
    for (final key in limitKeys) {
      final packageName = key.replaceFirst(StorageKeys.timeLimitPrefix, '');
      final value = prefs.getInt(key);
      if (value != null) {
        limits[packageName] = value;
      }
    }
    if (mounted) {
      setState(() {
        _appsWithLimits = limits.keys.toSet();
        _appTimeLimits = limits;
        _sortFilteredApps();
      });
    }
  }

  void _sortFilteredApps() {
    _filteredApps.sort((a, b) {
      final aHasLimit = _appsWithLimits.contains(a.packageName);
      final bHasLimit = _appsWithLimits.contains(b.packageName);
      if (aHasLimit && !bHasLimit) return -1;
      if (!aHasLimit && bHasLimit) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  Future<void> _checkBlockingPermissions() async {
    final accessibility = await NativeBridge.isAccessibilityServiceEnabled();
    if (mounted) {
      setState(() {
        _accessibilityEnabled = accessibility;
      });
    }
  }

  Future<void> _checkNotificationPermission() async {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final enabled = await androidPlugin?.areNotificationsEnabled() ?? false;
    if (mounted) {
      setState(() {
        _notificationsEnabled = enabled;
      });
    }
  }

  Future<void> _requestNotificationPermission() async {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
  }

  Future<void> _checkAndRequestPermission() async {
    final granted = await UsageStats.checkUsagePermission() ?? false;
    if (mounted) {
      setState(() {
        _permissionGranted = granted;
      });
    }
    if (granted) {
      _getInstalledApps();
    }
  }

  Future<void> _getInstalledApps() async {
    if (_apps.isNotEmpty) {
      _refreshAppsInBackground();
      return;
    }

    if (AppCache.appsWithIcons != null) {
      _setApps(AppCache.appsWithIcons!);
      return;
    }

    await AppCache.warmUp();
    final diskCached = AppCache.cachedApps;
    if (diskCached != null && diskCached.isNotEmpty) {
      _setApps(diskCached);
      _refreshAppsInBackground();
      return;
    }

    final appsWithIcons =
        await AppCache.loadAppsInBackground() ??
        await InstalledApps.getInstalledApps(withIcon: true);
    if (mounted) {
      _setApps(appsWithIcons);
    }
  }

  void _setApps(List<AppInfo> apps) {
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _applyFilter();
    });
    _storeAppNames(apps);
  }

  void _applyFilter() {
    final searchText = _searchBarController.text.toLowerCase().trim();
    if (searchText.isEmpty) {
      _filteredApps = List.from(_apps);
    } else {
      _filteredApps = _apps
          .where((elm) => elm.name.toLowerCase().contains(searchText))
          .toList();
    }
    _sortFilteredApps();
  }

  void _refreshAppsInBackground() {
    AppCache.loadAppsInBackground(forceRefresh: true).then((apps) {
      if (apps != null && mounted) {
        final newPackages = apps.map((a) => a.packageName).toSet();
        final oldPackages = _apps.map((a) => a.packageName).toSet();
        if (newPackages.length != oldPackages.length ||
            !newPackages.containsAll(oldPackages)) {
          _setApps(apps);
        } else {
          _storeAppNames(apps);
        }
      }
    });
  }

  Future<void> _storeAppNames(List<AppInfo> apps) async {
    final toStore = apps
        .where((app) => !_storedAppNamePackages.contains(app.packageName))
        .toList();
    if (toStore.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final futures = toStore.map(
      (app) => prefs.setString('${StorageKeys.appNamePrefix}${app.packageName}', app.name),
    );
    await Future.wait(futures);
    if (mounted) {
      for (final app in toStore) {
        _storedAppNamePackages.add(app.packageName);
      }
    }
  }

  Widget _buildPermissionCard({
    required String title,
    required String description,
    required bool granted,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: ListTile(
        leading: Icon(granted ? Icons.check_circle_outline : Icons.warning_amber_rounded),
        title: Text(title),
        subtitle: Text(granted ? Strings.permissionGranted : description),
        trailing: granted ? null : TextButton(onPressed: onAction, child: Text(actionLabel)),
      ),
    );
  }

  void _filterApps(String _) {
    setState(() {
      _applyFilter();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 64),

            Stack(
              alignment: Alignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        } else {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ActiveLimitsScreen(),
                            ),
                          );
                        }
                      },
                      child: Image.asset('assets/flower.png', height: 80, fit: BoxFit.contain),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 64),

            if (!_isCheckingPermissions &&
                (!_permissionGranted ||
                    !_accessibilityEnabled ||
                    !_notificationsEnabled ||
                    !_pinSet)) ...[
              const SizedBox(height: 16),

              _buildPermissionCard(
                title: Strings.usageAccessTitle,
                description: Strings.usageAccessDescription,
                granted: _permissionGranted,
                actionLabel: Strings.usageAccessAction,
                onAction: () => UsageStats.grantUsagePermission(),
              ),
              _buildPermissionCard(
                title: Strings.accessibilityServiceTitle,
                description: Strings.accessibilityServiceDescription,
                granted: _accessibilityEnabled,
                actionLabel: Strings.accessibilityServiceAction,
                onAction: () => NativeBridge.openAccessibilitySettings(),
              ),
              _buildPermissionCard(
                title: Strings.notificationsTitle,
                description: Strings.notificationsDescription,
                granted: _notificationsEnabled,
                actionLabel: Strings.notificationsAction,
                onAction: () async {
                  await _requestNotificationPermission();
                  _checkNotificationPermission();
                },
              ),
              _buildPermissionCard(
                title: Strings.pinSetupTitle,
                description: Strings.pinSetupDescription,
                granted: _pinSet,
                actionLabel: Strings.pinSetupAction,
                onAction: () async {
                  final success = await PinScreen.setupPin(context);
                  if (success) _checkPinStatus();
                },
              ),

              const SizedBox(height: 32),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [Text(Strings.permissionsSection)],
              ),
            ] else if (_apps.isNotEmpty) ...[
              Padding(
                padding: const .symmetric(horizontal: 16),
                child: SearchBar(
                  controller: _searchBarController,
                  leading: Padding(padding: const .only(left: 8), child: Icon(Icons.search)),
                  onChanged: _filterApps,
                  onSubmitted: _filterApps,
                  onTapOutside: (e) => FocusScope.of(context).unfocus(),
                ),
              ),

              const SizedBox(height: 32),

              Expanded(
                child: Stack(
                  children: [
                    NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        final isScrolled = notification.metrics.pixels > 0;
                        if (isScrolled != _isScrolled) {
                          setState(() => _isScrolled = isScrolled);
                        }
                        return false;
                      },
                      child: ListView.builder(
                        itemCount: _filteredApps.length,
                        itemBuilder: (context, index) {
                          final app = _filteredApps[index];
                          final hasLimit = _appsWithLimits.contains(app.packageName);

                          final isFirstWithoutLimit =
                              (!hasLimit &&
                              index > 0 &&
                              _appsWithLimits.contains(_filteredApps[index - 1].packageName));

                          final timeLimit = hasLimit ? _appTimeLimits[app.packageName] : null;

                          return Column(
                            key: ValueKey(app.packageName),
                            children: [
                              if (isFirstWithoutLimit) ...[
                                const Padding(
                                  padding: EdgeInsets.symmetric(
                                    vertical: 8.0,
                                    horizontal: 32.0,
                                  ),
                                  child: Divider(thickness: 1),
                                ),
                              ],

                              ListTile(
                                contentPadding: const .fromLTRB(16, 8, 16, 8),
                                leading: app.icon != null
                                    ? Image.memory(app.icon!, gaplessPlayback: true)
                                    : const Icon(Icons.apps),
                                title: Text(app.name),
                                trailing: hasLimit
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (timeLimit != null)
                                            Text(
                                              '${timeLimit}min',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.black,
                                              ),
                                            ),
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.timer_outlined,
                                            color: Colors.black,
                                          ),
                                        ],
                                      )
                                    : null,
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => AppLimitScreen(app: app),
                                    ),
                                  );
                                  _loadAppsWithLimits();
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ),

                    AnimatedContainer(
                      duration: Duration(milliseconds: 200),
                      height: _isScrolled ? 12 : 0,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black.withValues(alpha: 0.12), Colors.transparent],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const Expanded(child: Center(child: CircularProgressIndicator())),
            ],
          ],
        ),
      ),
    );
  }
}
