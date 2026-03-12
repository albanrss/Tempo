import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:tempo/constants/app_constants.dart';
import 'package:tempo/constants/app_theme.dart';
import 'package:tempo/screens/spinning_logo_screen.dart';
import 'package:tempo/services/app_cache.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppCache.warmUp();
  runApp(const MyApp());
}

Future<void> initNotifications() async {
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  const androidInitializationSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const initializationSettings = InitializationSettings(
    android: androidInitializationSettings,
  );
  await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings
  );

  final androidPlugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  const alertChannel = AndroidNotificationChannel(
    NotificationConfig.alertChannelId,
    NotificationConfig.alertChannelName,
    description: NotificationConfig.alertChannelDescription,
    importance: Importance.max,
  );
  await androidPlugin?.createNotificationChannel(alertChannel);
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      initNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Strings.appName,
      themeMode: ThemeMode.light,
      theme: AppTheme.theme,
      darkTheme: AppTheme.theme,
      home: const SpinningLogoScreen(),
    );
  }
}
