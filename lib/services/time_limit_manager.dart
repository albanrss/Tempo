import 'package:shared_preferences/shared_preferences.dart';
import 'package:tempo/constants/app_constants.dart';

class TimeLimitManager {
  static Future<void> setTimeLimit(String appPackageName, int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('${StorageKeys.timeLimitPrefix}$appPackageName', minutes);
  }

  static Future<int?> getTimeLimit(String appPackageName) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('${StorageKeys.timeLimitPrefix}$appPackageName');
  }

  static Future<void> removeTimeLimit(String appPackageName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${StorageKeys.timeLimitPrefix}$appPackageName');
  }
}
