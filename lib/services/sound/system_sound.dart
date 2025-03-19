import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// システムサウンドの再生を担当するユーティリティクラス
class SystemSoundService {
  /// システムのクリック音を再生
  static Future<void> playClick() async {
    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (e) {
      debugPrint('システムサウンド再生エラー: $e');
    }
  }

  /// 触覚フィードバックを提供
  static Future<void> vibrate() async {
    try {
      await HapticFeedback.mediumImpact();
    } catch (e) {
      debugPrint('触覚フィードバックエラー: $e');
    }
  }

  /// 両方のフィードバックを提供
  static Future<void> playFeedback() async {
    try {
      await playClick();
      await vibrate();
    } catch (e) {
      debugPrint('フィードバックエラー: $e');
    }
  }
}
