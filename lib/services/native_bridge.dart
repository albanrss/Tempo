import 'package:flutter/services.dart';

class NativeBridge {
  static const _channel = MethodChannel('albanrss.tempo/app_blocker');

  static Future<bool> isAccessibilityServiceEnabled() async {
    return await _channel.invokeMethod<bool>('isAccessibilityServiceEnabled') ??
        false;
  }

  static Future<void> openAccessibilitySettings() async {
    await _channel.invokeMethod('openAccessibilitySettings');
  }
}
