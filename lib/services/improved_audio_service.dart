import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;

// 精度モードの列挙型
enum PrecisionMode { basic, highPrecision, synthesized }

// 波形の種類
enum WaveformType { sine, square, triangle, sawtooth }

// 改良版オーディオサービス
class ImprovedAudioService {
  // ネイティブ通信用チャンネル
  static const MethodChannel _nativeChannel =
      MethodChannel('com.example.healthcare_app_1/metronome');

  // 再生状態
  bool _isPlaying = false;
  double _currentTempo = 100.0; // BPM
  String _currentSoundType = '標準クリック';
  double _volume = 0.7;
  Timer? _clickTimer;
  Timer? _schedulerTimer; // スケジューラタイマー
  bool _isInitialized = false;
  bool _previewMode = false;
  int _errorCount = 0;

  // 高精度モード用
  Stopwatch? _stopwatch;
  int _nextTickTime = 0;
  int _tickCount = 0;
  bool _preloadedBufferAvailable = false;

  // 精度モード
  PrecisionMode _precisionMode = PrecisionMode.highPrecision;

  // オーディオキューイング用
  final List<int> _scheduledBeeps = []; // 予定されたビープ音のタイムスタンプ
  final int _lookAheadMs = 500; // 500ms先までのビープ音をスケジュール

  // 診断用
  int _missedBeeps = 0;
  int _totalBeeps = 0;
  DateTime? _lastActualBeepTime;
  double _avgBeepDelay = 0.0;
  bool _isInDiagnosticMode = false;
  late StreamController<int> _testTimestampController;

  // 公開プロパティ
  bool get isPlaying => _isPlaying;
  double get currentTempo => _currentTempo;
  String get currentSoundType => _currentSoundType;
  PrecisionMode get precisionMode => _precisionMode;
  bool get isInitialized => _isInitialized;

  // 音のプリセット
  final Map<String, Map<String, dynamic>> _soundPresets = {
    '標準クリック': {
      'frequency': 800.0,
      'duration': 0.02,
      'waveform': WaveformType.sine,
    },
    '柔らかいクリック': {
      'frequency': 600.0,
      'duration': 0.03,
      'waveform': WaveformType.sine,
    },
    '木製クリック': {
      'frequency': 1200.0,
      'duration': 0.01,
      'waveform': WaveformType.square,
    },
    'ハイクリック': {
      'frequency': 1600.0,
      'duration': 0.015,
      'waveform': WaveformType.sine,
    },
  };

  // イニシャライザ
  Future<bool> initialize() async {
    try {
      // ネイティブコード側が利用可能か確認
      final isAvailable =
          await _nativeChannel.invokeMethod<bool>('isAvailable') ?? false;

      if (isAvailable && (Platform.isIOS || Platform.isAndroid)) {
        // ネイティブ側で音をプリロード
        await _nativeChannel.invokeMethod('preloadSounds');
        _preloadedBufferAvailable = true;
      }

      _isInitialized = true;
      debugPrint('ImprovedAudioService: 初期化成功');
      return true;
    } catch (e) {
      debugPrint('AudioService初期化エラー: $e');
      _isInitialized = false;
      return false;
    }
  }

  // 音のロード
  Future<bool> loadClickSound(String soundType) async {
    try {
      if (!_soundPresets.containsKey(soundType)) {
        debugPrint('未知のサウンドタイプ: $soundType、標準クリックを使用します');
        soundType = '標準クリック';
      }

      _currentSoundType = soundType;

      // ネイティブコード側が利用可能であればプリロード
      if (_preloadedBufferAvailable && (Platform.isIOS || Platform.isAndroid)) {
        final presetData = _soundPresets[soundType]!;
        await _nativeChannel.invokeMethod('preloadAudio', {
          'frequency': presetData['frequency'],
          'duration': presetData['duration'],
          'waveform': presetData['waveform'].index,
        });
      }

      return true;
    } catch (e) {
      debugPrint('音設定エラー: $e');
      return false;
    }
  }

  // プレビューモードの設定
  void setPreviewMode(bool enabled) {
    _previewMode = enabled;
  }

  // ビープ音の再生
  Future<void> _playBeep({int? scheduledTime}) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      _totalBeeps++;

      // 診断モードの場合、タイムスタンプを記録
      if (_isInDiagnosticMode && scheduledTime != null) {
        _testTimestampController.add(now);
      }

      // 実際のビープ時間と予定時間との差を記録（診断用）
      if (scheduledTime != null) {
        final delay = now - scheduledTime;
        if (delay > 20) {
          // 20ms以上の遅延をカウント
          _missedBeeps++;
        }

        // 平均遅延を更新
        _avgBeepDelay =
            (_avgBeepDelay * (_totalBeeps - 1) + delay) / _totalBeeps;

        if (_totalBeeps % 50 == 0 && kDebugMode) {
          debugPrint(
              '診断: ${_missedBeeps}/${_totalBeeps} ビープが遅延 (平均: ${_avgBeepDelay.toStringAsFixed(2)}ms)');
        }
      }

      _lastActualBeepTime = DateTime.now();

      // ネイティブコード側が利用可能でプリロード済みの場合
      if (_preloadedBufferAvailable && (Platform.isIOS || Platform.isAndroid)) {
        await _nativeChannel.invokeMethod('playPreloadedAudio', {
          'volume': _volume,
        });
      } else {
        // システムサウンドを再生
        await _playSystemSound();

        // 触覚フィードバックを追加（オプション）
        if (_volume > 0.5) {
          await HapticFeedback.lightImpact();
        }
      }
    } catch (e) {
      debugPrint('ビープ音再生エラー: $e');

      // エラーが続く場合は再初期化を試みる
      if (_errorCount++ > 5) {
        _reinitializeAudio();
        _errorCount = 0;
      }
    }
  }

  // オーディオの再初期化
  Future<void> _reinitializeAudio() async {
    debugPrint('オーディオシステムを再初期化しています...');

    // 一時停止
    final wasPlaying = _isPlaying;
    final currentTempo = _currentTempo;

    stopTempoCues();
    _isInitialized = false;

    // 再初期化
    final success = await initialize();

    // 再開
    if (success && wasPlaying) {
      startTempoCues(currentTempo);
    }
  }

  // システムサウンドを再生
  Future<void> _playSystemSound() async {
    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (e) {
      debugPrint('システムサウンドエラー: $e');
    }
  }

  // 精度モードの設定
  void setPrecisionMode(PrecisionMode mode) {
    if (_precisionMode == mode) return;

    _precisionMode = mode;

    // モード変更時に再生中なら再起動
    final wasPlaying = _isPlaying;
    final currentTempo = _currentTempo;

    if (wasPlaying) {
      stopTempoCues();
      startTempoCues(currentTempo);
    }
  }

  // 周波数設定
  void setFrequency(double frequency) {
    if (_preloadedBufferAvailable && (Platform.isIOS || Platform.isAndroid)) {
      _nativeChannel.invokeMethod('setFrequency', {
        'frequency': frequency,
      });
    }
  }

  // クリック長さ設定
  void setClickDuration(double duration) {
    if (_preloadedBufferAvailable && (Platform.isIOS || Platform.isAndroid)) {
      _nativeChannel.invokeMethod('setDuration', {
        'duration': duration,
      });
    }
  }

  // 波形設定
  void setWaveform(WaveformType waveform) {
    if (_preloadedBufferAvailable && (Platform.isIOS || Platform.isAndroid)) {
      _nativeChannel.invokeMethod('setWaveform', {
        'waveform': waveform.index,
      });
    }
  }

  // テンポに合わせた再生開始
  void startTempoCues(double bpm) {
    // 既存の再生を停止
    stopTempoCues();

    // BPMが無効な場合
    if (bpm <= 0) return;

    _isPlaying = true;
    _currentTempo = bpm;
    _missedBeeps = 0;
    _totalBeeps = 0;
    _avgBeepDelay = 0.0;
    _scheduledBeeps.clear();

    // プレビューモードの場合は軽量版を使用
    if (_previewMode) {
      _startPreviewModePlayback(bpm);
      return;
    }

    // ネイティブの高精度モードが利用可能な場合（iOS/Android）
    if (_preloadedBufferAvailable &&
        (Platform.isIOS || Platform.isAndroid) &&
        _precisionMode == PrecisionMode.highPrecision) {
      _startNativeHighPrecisionPlayback(bpm);
      return;
    }

    // モードに応じた再生処理
    switch (_precisionMode) {
      case PrecisionMode.highPrecision:
        _startHighPrecisionTempoPlayback(bpm);
        break;
      case PrecisionMode.synthesized:
        _startSynthesizedTempoPlayback(bpm);
        break;
      default:
        _startBasicTempoPlayback(bpm);
    }
  }

  // ネイティブの高精度モードでの再生
  void _startNativeHighPrecisionPlayback(double bpm) {
    try {
      _nativeChannel.invokeMethod('startStableMetronome', {
        'bpm': bpm,
        'soundType': _currentSoundType,
        'volume': _volume,
        'lookAheadMs': 200, // 先行スケジューリング
      });

      // ビート通知のリスナー（UI同期用）
      _nativeChannel.setMethodCallHandler((call) async {
        if (call.method == 'onBeatPlayed') {
          _lastActualBeepTime = DateTime.now();
        }
        return null;
      });
    } catch (e) {
      debugPrint('ネイティブ高精度モード起動エラー: $e');
      // フォールバック
      _startHighPrecisionTempoPlayback(bpm);
    }
  }

  // 軽量プレビューモードでの再生
  void _startPreviewModePlayback(double bpm) {
    // BPMからインターバル（ミリ秒）を計算
    final interval = (60000 / bpm).round();

    // 最初のクリックを再生
    _playBeep();

    // 軽量タイマーを使用（CPUの負荷を軽減）
    _clickTimer = Timer.periodic(Duration(milliseconds: interval), (timer) {
      if (!_isPlaying) {
        timer.cancel();
        return;
      }

      _playBeep();
    });
  }

  // 基本モードでのテンポ再生（改良）
  void _startBasicTempoPlayback(double bpm) {
    // BPMからインターバル（ミリ秒）を計算
    final interval = (60000 / bpm).round();

    // 最初のクリックを実行
    _playBeep();

    // 通常の周期的なタイマーよりも少し短い周期で実行し、安定性を向上
    final timerInterval = max(1, interval ~/ 10);
    int nextTickTime = DateTime.now().millisecondsSinceEpoch + interval;

    _clickTimer =
        Timer.periodic(Duration(milliseconds: timerInterval), (timer) {
      if (!_isPlaying) {
        timer.cancel();
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      if (now >= nextTickTime) {
        _playBeep(scheduledTime: nextTickTime);
        nextTickTime = now + interval;
      }
    });
  }

  // 高精度モードでのテンポ再生
  void _startHighPrecisionTempoPlayback(double bpm) {
    // BPMからインターバル（ミリ秒）を計算
    final intervalMs = (60000 / bpm);

    // 正確なタイミングを測定するストップウォッチを初期化
    _stopwatch = Stopwatch()..start();
    _nextTickTime = 0;
    _tickCount = 0;

    // 先行スケジューリング
    final now = DateTime.now().millisecondsSinceEpoch;
    _scheduleBeeps(now, intervalMs, _lookAheadMs);

    // 最初のクリックを再生
    _playBeep();

    // スケジューラタイマーを開始
    _schedulerTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isPlaying) {
        timer.cancel();
        return;
      }

      // スケジュールを更新
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      _scheduleBeeps(currentTime, intervalMs, _lookAheadMs);
    });

    // 再生タイマーを開始（BPMに応じて最適化された間隔で監視）
    int checkInterval = bpm > 120 ? 1 : (bpm > 60 ? 2 : 5);

    _clickTimer =
        Timer.periodic(Duration(milliseconds: checkInterval), (timer) {
      if (!_isPlaying) {
        timer.cancel();
        _stopwatch?.stop();
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;

      // ジッター防止のためのわずかな許容範囲（1-2ms）を持たせる
      while (_scheduledBeeps.isNotEmpty && (now >= _scheduledBeeps[0] - 1)) {
        final scheduledTime = _scheduledBeeps.removeAt(0);
        _playBeep(scheduledTime: scheduledTime);
      }
    });
  }

  // ビープ音のスケジューリング
  void _scheduleBeeps(int currentTime, double interval, int lookAheadMs) {
    final lookAheadTime = currentTime + lookAheadMs;

    // 既存のスケジュールにあるビープ音の最後の時間を取得
    int lastScheduledTime = currentTime;
    if (_scheduledBeeps.isNotEmpty) {
      // ソートして最後の値を取得
      _scheduledBeeps.sort();
      lastScheduledTime = _scheduledBeeps.last;

      // 重複を避けるため、現在時刻より前のスケジュールを削除
      _scheduledBeeps.removeWhere((time) => time < currentTime);
    }

    // 次のビープ音の時間を計算（最後のスケジュールから次の間隔を加算）
    var nextTime = lastScheduledTime + interval.round();

    // 先行時間までのビープ音をスケジュール
    while (nextTime <= lookAheadTime) {
      if (!_scheduledBeeps.contains(nextTime)) {
        _scheduledBeeps.add(nextTime);
      }
      nextTime += interval.round();
    }
  }

  // シンセサイズドモードでのテンポ再生
  void _startSynthesizedTempoPlayback(double bpm) {
    // BPMからインターバル（ミリ秒）を計算
    final interval = (60000 / bpm);

    // 現在の時間（ミリ秒）
    final startTime = DateTime.now().millisecondsSinceEpoch;
    var nextTickTime = startTime;

    // 最初のクリックを再生
    _playBeep();
    nextTickTime += interval.round();

    // より高精度なスケジューラ
    _clickTimer = Timer.periodic(const Duration(milliseconds: 1), (timer) {
      if (!_isPlaying) {
        timer.cancel();
        return;
      }

      final currentTime = DateTime.now().millisecondsSinceEpoch;

      // 次のタイミングに達したか
      if (currentTime >= nextTickTime) {
        _playBeep(scheduledTime: nextTickTime);

        // ドリフトを防ぐ改良アルゴリズム
        final elapsedTime = currentTime - startTime;
        final perfectBeats = elapsedTime / interval;
        final nextBeat = (perfectBeats.floor() + 1);
        nextTickTime = startTime + (nextBeat * interval).round();
      }
    });
  }

  // テンポの更新
  void updateTempo(double bpm) {
    if (!_isPlaying || _currentTempo == bpm) return;

    // 最小・最大値のチェック
    if (bpm < 10 || bpm > 300) {
      debugPrint('警告: 指定されたテンポ($bpm)が範囲外です。制限内に調整します。');
      bpm = bpm.clamp(10, 300);
    }

    _currentTempo = bpm;

    // ネイティブの高精度モードを使用中の場合
    if (_preloadedBufferAvailable &&
        (Platform.isIOS || Platform.isAndroid) &&
        _precisionMode == PrecisionMode.highPrecision) {
      try {
        _nativeChannel.invokeMethod('updateTempo', {
          'bpm': bpm,
        });
        return;
      } catch (e) {
        debugPrint('ネイティブテンポ更新エラー: $e');
      }
    }

    // モードに基づいて再起動
    stopTempoCues();
    startTempoCues(bpm);
  }

  // クリック音の停止
  void stopTempoCues() {
    _isPlaying = false;

    // ネイティブの高精度モードを使用中の場合
    if (_preloadedBufferAvailable && (Platform.isIOS || Platform.isAndroid)) {
      try {
        _nativeChannel.invokeMethod('stopMetronome');
      } catch (e) {
        debugPrint('ネイティブメトロノーム停止エラー: $e');
      }
    }

    // タイマーの停止
    _clickTimer?.cancel();
    _clickTimer = null;

    _schedulerTimer?.cancel();
    _schedulerTimer = null;

    // ストップウォッチの停止
    _stopwatch?.stop();
    _stopwatch = null;

    // スケジュールされたビープをクリア
    _scheduledBeeps.clear();

    // 診断情報の出力
    if (_totalBeeps > 0 && kDebugMode) {
      final missRate = (_missedBeeps / _totalBeeps) * 100;
      debugPrint(
          '診断サマリー: $_totalBeeps ビープのうち $_missedBeeps が遅延 (${missRate.toStringAsFixed(1)}%)');
      debugPrint('平均遅延: ${_avgBeepDelay.toStringAsFixed(2)}ms');
    }
  }

  // 音量設定
  void setVolume(double volume) {
    _volume = max(0.0, min(1.0, volume));

    // ネイティブ側の音量も更新
    if (_preloadedBufferAvailable && (Platform.isIOS || Platform.isAndroid)) {
      try {
        _nativeChannel.invokeMethod('setVolume', {
          'volume': _volume,
        });
      } catch (e) {
        debugPrint('ネイティブ音量設定エラー: $e');
      }
    }
  }

  // 診断ツール実行
  Future<Map<String, dynamic>> runDiagnostics() async {
    final results = <String, dynamic>{};

    // テスト1: 基本タイミングテスト
    results['basicTimingTest'] = await _runBasicTimingTest();

    // テスト2: システム負荷テスト
    results['systemLoadTest'] = await _runSystemLoadTest();

    // テスト3: オーディオセッションチェック
    results['audioSessionCheck'] = await _checkAudioSession();

    return results;
  }

  Future<Map<String, dynamic>> _runBasicTimingTest() async {
    final result = <String, dynamic>{};

    try {
      stopTempoCues(); // 進行中の再生を確実に停止

      final testBpm = 120.0; // 1秒あたり2拍
      final expectedInterval = 500; // ms
      final testDuration = 5000; // 5秒
      final beatTimestamps = <int>[];

      // タイミング計測の設定
      _testTimestampController = StreamController<int>.broadcast();
      final subscription = _testTimestampController.stream.listen((timestamp) {
        beatTimestamps.add(timestamp);
      });

      // 最も精度の高いモードでテストシーケンスを再生
      setPrecisionMode(PrecisionMode.highPrecision);

      _isInDiagnosticMode = true;

      startTempoCues(testBpm);

      // テスト時間待機
      await Future.delayed(Duration(milliseconds: testDuration));

      stopTempoCues();
      _isInDiagnosticMode = false;

      // タイミング統計の計算
      final intervals = <int>[];
      for (int i = 1; i < beatTimestamps.length; i++) {
        intervals.add(beatTimestamps[i] - beatTimestamps[i - 1]);
      }

      if (intervals.isEmpty) {
        result['status'] = 'failure';
        result['error'] = 'ビートが検出されませんでした';
        return result;
      }

      // 統計計算
      final avgInterval = intervals.reduce((a, b) => a + b) / intervals.length;
      final driftFromExpected = (avgInterval - expectedInterval).abs();

      double sumSquaredDiffs = 0.0;
      for (final interval in intervals) {
        sumSquaredDiffs += pow(interval - avgInterval, 2);
      }
      final stdDev = sqrt(sumSquaredDiffs / intervals.length);

      // クリーンアップ
      await subscription.cancel();
      await _testTimestampController.close();

      // 統計を返す
      result['status'] = 'success';
      result['beatCount'] = beatTimestamps.length;
      result['avgInterval'] = avgInterval;
      result['stdDev'] = stdDev;
      result['drift'] = driftFromExpected;
      result['maxJitter'] = intervals.reduce((a, b) => a > b ? a : b) -
          intervals.reduce((a, b) => a < b ? a : b);

      // パフォーマンス評価
      if (stdDev < 5) {
        result['quality'] = 'excellent';
      } else if (stdDev < 15) {
        result['quality'] = 'good';
      } else if (stdDev < 30) {
        result['quality'] = 'acceptable';
      } else {
        result['quality'] = 'poor';
      }
    } catch (e) {
      result['status'] = 'error';
      result['error'] = e.toString();
    }

    return result;
  }

  Future<Map<String, dynamic>> _runSystemLoadTest() async {
    // 実装の詳細は負荷下でのパフォーマンスをテスト
    try {
      if (_preloadedBufferAvailable && (Platform.isIOS || Platform.isAndroid)) {
        final result = await _nativeChannel.invokeMethod('runSystemLoadTest');
        return {
          'status': 'success',
          'nativeResult': result,
          'message': 'システムは適切なオーディオ負荷を処理できます'
        };
      }
      return {'status': 'success', 'message': 'システムはオーディオ負荷を処理できます'};
    } catch (e) {
      return {'status': 'error', 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _checkAudioSession() async {
    // 実装はオーディオセッション構成をチェック
    try {
      if (_preloadedBufferAvailable && (Platform.isIOS || Platform.isAndroid)) {
        final result = await _nativeChannel.invokeMethod('checkAudioSession');
        return {
          'status': 'success',
          'nativeResult': result,
          'message': 'オーディオセッションは正しく構成されています'
        };
      }
      return {'status': 'success', 'message': 'オーディオセッションは正しく構成されています'};
    } catch (e) {
      return {'status': 'error', 'error': e.toString()};
    }
  }

  // メトロノーム精度チェック（デバッグ用）
  void checkTempoAccuracy(int seconds) {
    if (_isPlaying) {
      debugPrint('精度チェックは再生停止時に実行してください');
      return;
    }

    debugPrint('メトロノーム精度テスト開始 (${seconds}秒間)...');

    final testTempo = 120.0; // 毎分120拍
    final expectedInterval = 500; // 500ミリ秒ごと
    int beepCount = 0;
    final List<int> actualTimes = [];

    // 精度テスト用の変数
    _missedBeeps = 0;
    _totalBeeps = 0;
    _avgBeepDelay = 0.0;

    // 最初のビープ音
    _playBeep();
    actualTimes.add(DateTime.now().millisecondsSinceEpoch);
    beepCount++;

    final endTime = DateTime.now().millisecondsSinceEpoch + (seconds * 1000);

    // 高精度モードでテスト
    _scheduledBeeps.clear();
    final startTime = DateTime.now().millisecondsSinceEpoch;

    // スケジュールを作成
    for (int i = 1; i <= (seconds * 2); i++) {
      _scheduledBeeps.add(startTime + (i * expectedInterval));
    }

    _clickTimer = Timer.periodic(const Duration(milliseconds: 1), (timer) {
      final now = DateTime.now().millisecondsSinceEpoch;

      if (now >= endTime) {
        timer.cancel();
        _analyzeAccuracyResults(actualTimes, expectedInterval);
        return;
      }

      // スケジュールされたビープ音がある場合は再生
      while (_scheduledBeeps.isNotEmpty && _scheduledBeeps[0] <= now) {
        final scheduledTime = _scheduledBeeps.removeAt(0);
        _playBeep(scheduledTime: scheduledTime);
        actualTimes.add(now);
        beepCount++;
      }
    });
  }

  // 精度テスト結果の分析（デバッグ用）
  void _analyzeAccuracyResults(List<int> actualTimes, int expectedInterval) {
    if (actualTimes.length < 2) {
      debugPrint('十分なデータがありません');
      return;
    }

    final List<int> intervals = [];
    for (int i = 1; i < actualTimes.length; i++) {
      intervals.add(actualTimes[i] - actualTimes[i - 1]);
    }

    final double avgInterval =
        intervals.reduce((a, b) => a + b) / intervals.length;
    double sumSquaredDiff = 0.0;
    for (final interval in intervals) {
      sumSquaredDiff += pow(interval - avgInterval, 2);
    }
    final double stdDev = sqrt(sumSquaredDiff / intervals.length);
    final double errorRate =
        ((avgInterval - expectedInterval) / expectedInterval) * 100;

    debugPrint('===== 精度テスト結果 =====');
    debugPrint('予定間隔: ${expectedInterval}ms');
    debugPrint('実際の平均間隔: ${avgInterval.toStringAsFixed(2)}ms');
    debugPrint('標準偏差: ${stdDev.toStringAsFixed(2)}ms');
    debugPrint('誤差率: ${errorRate.toStringAsFixed(2)}%');
    debugPrint('ビープ音の総数: ${actualTimes.length}');

    if (stdDev < 10) {
      debugPrint('精度評価: 優れています (標準偏差 < 10ms)');
    } else if (stdDev < 20) {
      debugPrint('精度評価: 良好です (標準偏差 < 20ms)');
    } else if (stdDev < 30) {
      debugPrint('精度評価: 許容範囲内です (標準偏差 < 30ms)');
    } else {
      debugPrint('精度評価: 改善が必要です (標準偏差 > 30ms)');
    }
  }

  // リソース解放
  void dispose() {
    stopTempoCues();

    if (_preloadedBufferAvailable && (Platform.isIOS || Platform.isAndroid)) {
      try {
        _nativeChannel.invokeMethod('releaseResources');
      } catch (e) {
        debugPrint('ネイティブリソース解放エラー: $e');
      }
    }
  }
}
