// native_beep.dart
import 'package:flutter/services.dart';

class NativeBeep {
  static const platform = MethodChannel('com.example.healthcareApp/beep');

  static Future<void> playBeep(
      double frequency, double duration, double volume) async {
    try {
      await platform.invokeMethod('playBeep', {
        'frequency': frequency,
        'duration': duration,
        'volume': volume,
      });
    } on PlatformException catch (e) {
      print("Failed to play beep: '${e.message}'.");
    }
  }
}
