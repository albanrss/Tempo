class StorageKeys {
  StorageKeys._();

  static const String timeLimitPrefix = 'time_limit_';
  static const String appNamePrefix = 'app_name_';
  static const String forcedBgPrefix = 'forced_bg_';
}

class NotificationConfig {
  NotificationConfig._();

  static const String alertChannelId = 'app_limiter_channel';
  static const String alertChannelName = 'App Limiter';
  static const String alertChannelDescription = 'Notifications for app usage limits';
}

class Strings {
  Strings._();

  static const String appName = 'Tempo';

  static const String appTitle = 'App Limiter';

  static String setLimitTitle(String appName) {
    return 'Limit for $appName';
  }

  static const String limitDescription = 'Time limit in minutes per hour';
  static const String setLimitAction = 'Set Limit';
  static const String removeLimitAction = 'Remove Limit';

  static const String permissionsSection = 'Permissions Required';

  static const String usageAccessTitle = 'Usage Access';
  static const String usageAccessDescription = 'Tracks app usage to enforce time limits.';
  static const String usageAccessAction = 'Grant';

  static const String accessibilityServiceTitle = 'Accessibility Service';
  static const String accessibilityServiceDescription =
      'Block apps instantly when their limit is reached.';
  static const String accessibilityServiceAction = 'Enable';

  static const String notificationsTitle = 'Notifications';
  static const String notificationsDescription =
      'Alerts you when you have reached your app time limit.';
  static const String notificationsAction = 'Allow';

  static const String permissionGranted = 'Granted';

  static const String pinSetupTitle = 'Security PIN';
  static const String pinSetupDescription = 'Set a 4-digit PIN to protect access to the app.';
  static const String pinSetupAction = 'Set PIN';
  static const String pinSetupDone = 'PIN set';
  static const String pinDialogTitle = 'Enter your PIN';
  static const String pinSetupDialogTitle = 'Set a 4-digit PIN';
  static const String pinConfirmDialogTitle = 'Confirm your PIN';
  static const String pinChangeOldTitle = 'Enter current PIN';
  static const String pinChangeAction = 'Change PIN';
  static const String pinChangeSuccess = 'PIN successfully changed';
  static const String pinMismatchError = 'PINs do not match. Try again.';
  static const String pinWrongError = 'Wrong PIN.';
  static const String pinCancel = 'Cancel';
  static const String pinValidateAction = 'Validate';
  static const String pinNextAction = 'Next';

  static const String viewActiveLimits = 'View active limits';
  static const String activeLimitsTitle = 'Active Limits';
  static const String activeLimitsBack = 'Back';
  static const String modifyLimitsAction = 'Modify limits';
  static const String noActiveLimits = 'No active limits';
  static const String limitRemaining = 'remaining';
  static const String limitExhausted = 'Limit reached';
}
