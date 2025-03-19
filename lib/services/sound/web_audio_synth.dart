// web_audio_synth.dart
import 'dart:js' as js;
import 'package:flutter/foundation.dart';

class WebAudioSynth {
  bool _isInitialized = false;

  // Web Audio APIの初期化
  Future<bool> initialize() async {
    if (!kIsWeb) return false;

    try {
      js.context.callMethod('eval', [
        '''
        // Web Audio APIのセットアップ
        window.audioContext = new (window.AudioContext || window.webkitAudioContext)();
        window.playTone = function(frequency, duration, volume) {
          // オシレーターの作成
          var oscillator = audioContext.createOscillator();
          var gainNode = audioContext.createGain();
          
          // 設定
          oscillator.type = 'sine';
          oscillator.frequency.value = frequency;
          gainNode.gain.value = volume;
          
          // 接続
          oscillator.connect(gainNode);
          gainNode.connect(audioContext.destination);
          
          // 再生
          oscillator.start();
          
          // 指定された長さ後に停止
          setTimeout(function() {
            oscillator.stop();
          }, duration * 1000);
        };
      '''
      ]);

      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('Web Audio初期化エラー: $e');
      return false;
    }
  }

  // トーン再生
  void playTone(double frequency, double duration, double volume) {
    if (!_isInitialized || !kIsWeb) return;

    try {
      js.context.callMethod('playTone', [frequency, duration, volume]);
    } catch (e) {
      debugPrint('Web Audio再生エラー: $e');
    }
  }
}
