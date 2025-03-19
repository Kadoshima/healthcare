import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

class AudioService {
  // オーディオプレーヤー
  AudioPlayer _player = AudioPlayer();

  // エラー状態の追跡
  bool _hasError = false;
  String _lastErrorMessage = '';

  // クリック音の種類とパス
  final Map<String, String> _clickSounds = {
    '標準クリック': 'assets/audio/100metronome.wav',
    '柔らかいクリック': 'assets/audio/90metronome.wav',
    '木製クリック': 'assets/audio/110metronome.wav',
    'ハイクリック': 'assets/audio/120metronome.wav',
  };

  // 再生状態
  bool _isPlaying = false;
  double _currentTempo = 100.0; // BPM
  String _currentSound = '標準クリック';
  Timer? _clickTimer;

  // 公開プロパティ
  bool get isPlaying => _isPlaying;
  double get currentTempo => _currentTempo;
  bool get hasError => _hasError;
  String get lastErrorMessage => _lastErrorMessage;

  // 初期化
  Future<bool> initialize() async {
    try {
      // オーディオセッションの設定
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.mixWithOthers,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ));

      // デフォルトのクリック音をロード
      final result = await loadClickSound(_currentSound);
      return result;
    } catch (e) {
      _setError('AudioService初期化エラー: $e');
      return false;
    }
  }

  // エラー設定
  void _setError(String message) {
    _hasError = true;
    _lastErrorMessage = message;
    debugPrint(message);
  }

  // エラーリセット
  void _resetError() {
    _hasError = false;
    _lastErrorMessage = '';
  }

  // クリック音ロード - 改善版
  Future<bool> loadClickSound(String soundType) async {
    try {
      _resetError();
      final soundPath = _clickSounds[soundType] ?? _clickSounds['標準クリック']!;

      // 既存の再生を停止
      await _player.stop();

      // 念のためエラーリスナーを追加
      _player.playbackEventStream.listen(
        (event) {},
        onError: (Object e, StackTrace stackTrace) {
          _setError('再生エラー: $e');
        },
      );

      // 音声ファイルのロード
      try {
        await _player.setAsset(soundPath);
        await _player.setLoopMode(LoopMode.off);
        _currentSound = soundType;
        return true;
      } catch (e) {
        _setError('音声ファイルロードエラー: $e');

        // 標準クリックに戻るフォールバック（指定したサウンドがロードできなかった場合）
        if (soundType != '標準クリック') {
          debugPrint('標準クリックにフォールバックします');
          return await loadClickSound('標準クリック');
        }
        return false;
      }
    } catch (e) {
      _setError('クリック音ロード全体エラー: $e');
      return false;
    }
  }

  // テンポに合わせたクリック音再生開始 - 改善版
  void startTempoCues(double bpm) {
    if (_isPlaying) {
      stopTempoCues();
    }

    // エラー状態のチェック
    if (_hasError) {
      debugPrint('エラーが発生しているため、テンポキューを開始できません: $_lastErrorMessage');
      return;
    }

    _isPlaying = true;
    _currentTempo = bpm;

    if (bpm <= 0) {
      // 無音モード
      return;
    }

    // BPMからインターバル（ミリ秒）を計算
    final interval = (60000 / bpm).round();

    // 正確なタイミングのためのオフセット調整
    final now = DateTime.now().millisecondsSinceEpoch;
    final delay = interval - (now % interval);

    // 最初のクリックを遅延実行し、その後は定期的に再生
    Future.delayed(Duration(milliseconds: delay), () {
      if (_isPlaying) {
        _safePlaySound();

        _clickTimer = Timer.periodic(Duration(milliseconds: interval), (timer) {
          if (_isPlaying) {
            _safePlaySound();
          } else {
            timer.cancel();
          }
        });
      }
    });
  }

  // 安全に音を再生するメソッド
  void _safePlaySound() {
    try {
      _player.seek(Duration.zero).then((_) {
        _player.play().catchError((error) {
          _setError('再生エラー: $error');
        });
      }).catchError((error) {
        _setError('シークエラー: $error');
      });
    } catch (e) {
      _setError('安全再生エラー: $e');
    }
  }

  // テンポの更新
  void updateTempo(double bpm) {
    if (!_isPlaying || _currentTempo == bpm) return;

    // 既存の再生を停止して新しいテンポで開始
    stopTempoCues();
    startTempoCues(bpm);
  }

  // クリック音の停止
  void stopTempoCues() {
    _isPlaying = false;
    _clickTimer?.cancel();
    _clickTimer = null;
    try {
      _player.stop().catchError((error) {
        _setError('停止エラー: $error');
      });
    } catch (e) {
      _setError('テンポキュー停止エラー: $e');
    }
  }

  // 音量設定
  void setVolume(double volume) {
    final clampedVolume = min(1.0, max(0.0, volume));
    try {
      _player.setVolume(clampedVolume).catchError((error) {
        _setError('音量設定エラー: $error');
      });
    } catch (e) {
      _setError('音量設定エラー: $e');
    }
  }

  // エラー状態をリセットして復旧を試みる
  Future<bool> recover() async {
    try {
      stopTempoCues();
      await _player.dispose();

      // プレーヤーを再作成
      _player = AudioPlayer();
      _resetError();

      // 再初期化
      return await initialize();
    } catch (e) {
      _setError('復旧中のエラー: $e');
      return false;
    }
  }

  // リソース解放
  void dispose() {
    stopTempoCues();
    _player.dispose();
  }
}
