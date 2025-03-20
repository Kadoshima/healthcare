import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../models/gait_data.dart';

/// 改良版SensorService - 歩行リズム測定の精度向上のための改良
class SensorService {
  // ストリームコントローラー
  final _accelerometerDataController =
      StreamController<AccelerometerData>.broadcast();
  final _gaitRhythmController = StreamController<double>.broadcast();

  // キャリブレーション結果用のコントローラー
  final _calibrationResultController =
      StreamController<CalibrationResult>.broadcast();

  // 購読管理
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;

  // 歩行リズム検出用パラメータ
  final List<AccelerometerData> _recentData = [];
  List<double> _filteredMagnitudes = [];

  // サンプリング関連
  final int _dataBufferSize = 500; // 約10秒分のデータ（50Hz想定）
  final double _samplingRate = 50.0; // Hz

  // 状態変数
  double _currentBpm = 0.0;
  bool _isWalking = false;

  // キャリブレーション状態
  bool _isCalibrating = false;
  double _targetCalibrationBpm = 0.0;
  List<CalibrationPoint> _calibrationPoints = [];

  // 精度メトリクス
  double _currentAccuracy = 0.0; // 推定精度（%）
  double _confidenceLevel = 0.0; // 信頼度レベル（0.0-1.0）

  // 歩行検出のパラメータ
  double _activityThreshold = 0.15; // 活動検出の閾値（加速度の標準偏差）
  final int _minConsecutiveSteps = 4; // 歩行と判断する最小連続ステップ数

  // フィルタリングパラメータ
  double _lowCutHz = 0.5; // ハイパスフィルタのカットオフ周波数（Hz）
  double _highCutHz = 3.0; // ローパスフィルタのカットオフ周波数（Hz）

  // センサー位置に基づくパラメータ調整
  final Map<String, Map<String, double>> _sensorPositionParams = {
    '腰部': {
      'lowCutHz': 0.5,
      'highCutHz': 3.0,
      'activityThreshold': 0.15,
      'peakThreshold': 0.5,
    },
    '足首': {
      'lowCutHz': 0.8,
      'highCutHz': 4.0,
      'activityThreshold': 0.25,
      'peakThreshold': 0.6,
    },
  };

  // 自己相関データ
  List<double> _autoCorrelation = [];

  // ピーク検出パラメータ
  double _peakThreshold = 0.5; // ピーク閾値（標準偏差の倍数）
  final int _minPeakDistance = 15; // ピーク間の最小サンプル数（約0.3秒）

  // 過去のBPM値を保存するキュー（平滑化用）
  final Queue<double> _recentBpms = Queue<double>();
  final int _bpmQueueSize = 5; // BPM平滑化のためのキューサイズ

  // アルゴリズム重み付け
  double _autocorrelationWeight = 0.6;
  double _peakDetectionWeight = 0.3;
  double _fftWeight = 0.1;

  // 補正係数（キャリブレーション後に設定）
  double _calibrationMultiplier = 1.0;
  double _calibrationOffset = 0.0;

  // 検証用パラメータ
  final List<double> _verificationErrors = [];
  double _avgVerificationError = 0.0;
  int _verificationCount = 0;

  // センサー状態
  bool _isRunning = false;

  // 公開ストリーム
  Stream<AccelerometerData> get accelerometerStream =>
      _accelerometerDataController.stream;
  Stream<double> get gaitRhythmStream => _gaitRhythmController.stream;
  Stream<CalibrationResult> get calibrationResultStream =>
      _calibrationResultController.stream;

  // 公開プロパティ
  double get currentBpm => _currentBpm;
  bool get isWalking => _isWalking;
  bool get isCalibrating => _isCalibrating;
  double get currentAccuracy => _currentAccuracy;
  double get confidenceLevel => _confidenceLevel;
  List<CalibrationPoint> get calibrationPoints =>
      List.unmodifiable(_calibrationPoints);
  double get avgVerificationError => _avgVerificationError;

  // センサーの初期化
  Future<bool> initialize({String sensorPosition = '腰部'}) async {
    try {
      // センサー位置に基づくパラメータ設定
      _adjustParametersForPosition(sensorPosition);

      // 初回キャリブレーションの設定
      _calibrationPoints = [
        CalibrationPoint(targetBpm: 80, measuredBpm: 80, error: 0),
        CalibrationPoint(targetBpm: 100, measuredBpm: 100, error: 0),
        CalibrationPoint(targetBpm: 120, measuredBpm: 120, error: 0),
      ];

      // デフォルトは補正なし
      _calibrationMultiplier = 1.0;
      _calibrationOffset = 0.0;

      return true;
    } catch (e) {
      debugPrint('センサー初期化エラー: $e');
      return false;
    }
  }

  // センサー位置に基づくパラメータ調整
  void _adjustParametersForPosition(String position) {
    if (_sensorPositionParams.containsKey(position)) {
      final params = _sensorPositionParams[position]!;
      _lowCutHz = params['lowCutHz']!;
      _highCutHz = params['highCutHz']!;
      _activityThreshold = params['activityThreshold']!;
      _peakThreshold = params['peakThreshold']!;

      debugPrint('センサー位置 $position に合わせてパラメータを調整しました');
      debugPrint('低周波カットオフ: $_lowCutHz, 高周波カットオフ: $_highCutHz');
      debugPrint('活動閾値: $_activityThreshold, ピーク閾値: $_peakThreshold');
    }
  }

  // センサー開始
  void startSensing() {
    if (_isRunning) return;

    _isRunning = true;
    _recentData.clear();
    _filteredMagnitudes.clear();
    _recentBpms.clear();
    _isWalking = false;

    // センサーデータの購読開始
    _accelerometerSubscription =
        accelerometerEvents.listen((AccelerometerEvent event) {
      final now = DateTime.now();
      final data = AccelerometerData(
        timestamp: now,
        x: event.x,
        y: event.y,
        z: event.z,
      );

      // データをストリームに送信
      _accelerometerDataController.add(data);

      // バッファにデータを追加
      _recentData.add(data);
      if (_recentData.length > _dataBufferSize) {
        _recentData.removeAt(0);
      }

      // 一定間隔でBPM計算（約2秒に1回）
      // サンプル数が200以上（約4秒分）たまったら初回計算、その後は100サンプル（約2秒）ごとに計算
      if ((_recentData.length >= 200 && _filteredMagnitudes.isEmpty) ||
          (_recentData.length % 100 == 0 && _recentData.length > 200)) {
        _processAccelerometerData();
      }
    });
  }

  // センサー停止
  void stopSensing() {
    _isRunning = false;
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
  }

  // キャリブレーション開始
  void startCalibration(double targetBpm) {
    _isCalibrating = true;
    _targetCalibrationBpm = targetBpm;
    _verificationErrors.clear();

    debugPrint('キャリブレーション開始: 目標 BPM = $_targetCalibrationBpm');
  }

  // キャリブレーション終了
  void stopCalibration() {
    if (!_isCalibrating) return;

    final List<double> measuredBpms = List.from(_recentBpms);
    if (measuredBpms.isEmpty) {
      debugPrint('キャリブレーション失敗: 測定データなし');
      _isCalibrating = false;
      return;
    }

    // 測定された平均BPM値
    measuredBpms.sort();
    final measuredBpm = measuredBpms[measuredBpms.length ~/ 2]; // 中央値
    final error = measuredBpm - _targetCalibrationBpm;

    // キャリブレーションポイントの追加・更新
    bool updated = false;
    for (int i = 0; i < _calibrationPoints.length; i++) {
      if ((_calibrationPoints[i].targetBpm - _targetCalibrationBpm).abs() < 5) {
        _calibrationPoints[i] = CalibrationPoint(
          targetBpm: _targetCalibrationBpm,
          measuredBpm: measuredBpm,
          error: error,
        );
        updated = true;
        break;
      }
    }

    if (!updated) {
      _calibrationPoints.add(CalibrationPoint(
        targetBpm: _targetCalibrationBpm,
        measuredBpm: measuredBpm,
        error: error,
      ));
    }

    // 補正係数の計算（線形回帰）
    _calculateCalibrationCoefficients();

    // 結果を送信
    final result = CalibrationResult(
      targetBpm: _targetCalibrationBpm,
      measuredBpm: measuredBpm,
      error: error,
      calibrationMultiplier: _calibrationMultiplier,
      calibrationOffset: _calibrationOffset,
      points: List.from(_calibrationPoints),
    );

    _calibrationResultController.add(result);

    debugPrint(
        'キャリブレーション完了: 目標=$_targetCalibrationBpm, 測定=$measuredBpm, 誤差=$error');
    debugPrint('補正係数: 乗数=$_calibrationMultiplier, オフセット=$_calibrationOffset');

    _isCalibrating = false;
  }

  // 補正係数の計算（線形回帰）
  void _calculateCalibrationCoefficients() {
    if (_calibrationPoints.length < 2) {
      // データ不足の場合はデフォルト値を使用
      _calibrationMultiplier = 1.0;
      _calibrationOffset = 0.0;
      return;
    }

    // 線形回帰のための変数
    double sumX = 0.0;
    double sumY = 0.0;
    double sumXY = 0.0;
    double sumX2 = 0.0;
    int n = _calibrationPoints.length;

    for (final point in _calibrationPoints) {
      sumX += point.measuredBpm;
      sumY += point.targetBpm;
      sumXY += point.measuredBpm * point.targetBpm;
      sumX2 += point.measuredBpm * point.measuredBpm;
    }

    // 傾きとオフセットの計算
    double denominator = n * sumX2 - sumX * sumX;
    if (denominator.abs() < 0.001) {
      // 分母がほぼ0の場合
      _calibrationMultiplier = 1.0;
      _calibrationOffset = 0.0;
    } else {
      _calibrationMultiplier = (n * sumXY - sumX * sumY) / denominator;
      _calibrationOffset = (sumY - _calibrationMultiplier * sumX) / n;

      // 異常値チェック（極端な補正を避ける）
      if (_calibrationMultiplier < 0.5 || _calibrationMultiplier > 2.0) {
        debugPrint('警告: 異常な補正係数が計算されました。デフォルト値を使用します。');
        _calibrationMultiplier = 1.0;
        _calibrationOffset = 0.0;
      }
    }
  }

  // 精度の検証
  void verifyAccuracy(double knownBpm) {
    if (!_isRunning || !_isWalking || _currentBpm <= 0) return;

    // 現在の測定値とknownBpmの差を計算
    final error = (_currentBpm - knownBpm).abs();
    final percentError = (error / knownBpm) * 100;

    _verificationErrors.add(percentError);
    _verificationCount++;

    // 平均誤差の更新
    double sum = 0.0;
    for (final err in _verificationErrors) {
      sum += err;
    }
    _avgVerificationError = sum / _verificationErrors.length;

    // 信頼度の更新
    _confidenceLevel = math.max(0.0, 1.0 - (_avgVerificationError / 20.0));
    if (_confidenceLevel > 1.0) _confidenceLevel = 1.0;

    // 精度の計算（100% - 平均誤差%）
    _currentAccuracy = 100.0 - _avgVerificationError;
    if (_currentAccuracy < 0.0) _currentAccuracy = 0.0;

    debugPrint(
        '精度検証: 既知=$knownBpm, 測定=$_currentBpm, 誤差=$error (${percentError.toStringAsFixed(1)}%)');
    debugPrint(
        '現在の推定精度: ${_currentAccuracy.toStringAsFixed(1)}%, 信頼度: ${(_confidenceLevel * 100).toStringAsFixed(1)}%');
  }

  // 加速度データの処理（フィルタリングと歩行リズム検出）
  void _processAccelerometerData() {
    if (_recentData.length < 200) return; // 少なくとも4秒分のデータが必要

    try {
      // マグニチュードの抽出
      final magnitudes = _recentData.map((data) => data.magnitude).toList();

      // 1. 活動状態の検出（静止状態か歩行状態かを判断）
      final isActive = _detectActivity(magnitudes);

      if (!isActive) {
        // 活動が検出されない場合、歩行なしと判断
        _isWalking = false;

        // 歩行なしの場合は0 BPMを送信
        if (_currentBpm != 0.0) {
          _currentBpm = 0.0;
          _gaitRhythmController.add(_currentBpm);
        }
        return;
      }

      // 2. 信号前処理（フィルタリング）
      _filteredMagnitudes = _applyBandpassFilter(magnitudes);

      // 3. 複数の方法で歩行リズムを検出し、重み付けで統合
      double autocorrBpm = 0.0, peakBpm = 0.0, fftBpm = 0.0;

      // 3.1 自己相関法によるBPM検出
      autocorrBpm = _detectBpmByAutocorrelation();

      // 3.2 ピーク検出法によるBPM検出
      peakBpm = _detectBpmByPeakCounting();

      // 3.3 FFT法によるBPM検出
      fftBpm = _detectBpmBySimpleFFT();

      // 3.4 検出結果の統合（重み付け）
      double detectedBpm = 0.0;
      double totalWeight = 0.0;

      // 有効値のみ重み付け
      if (autocorrBpm >= 40 && autocorrBpm <= 160) {
        detectedBpm += autocorrBpm * _autocorrelationWeight;
        totalWeight += _autocorrelationWeight;
      }

      if (peakBpm >= 40 && peakBpm <= 160) {
        detectedBpm += peakBpm * _peakDetectionWeight;
        totalWeight += _peakDetectionWeight;
      }

      if (fftBpm >= 40 && fftBpm <= 160) {
        detectedBpm += fftBpm * _fftWeight;
        totalWeight += _fftWeight;
      }

      // 有効な重みがある場合のみ計算
      if (totalWeight > 0) {
        detectedBpm /= totalWeight;
      } else {
        // すべての方法が失敗した場合
        return;
      }

      // 4. キャリブレーション補正の適用
      final calibratedBpm =
          detectedBpm * _calibrationMultiplier + _calibrationOffset;

      // デバッグログ（詳細な検出結果）
      if (detectedBpm > 0) {
        debugPrint('BPM検出: 自己相関=$autocorrBpm, ピーク=$peakBpm, FFT=$fftBpm');
        debugPrint(
            '統合BPM=$detectedBpm, 補正後=${calibratedBpm.toStringAsFixed(1)}');
      }

      // 5. 平滑化（急激な変化を防止）
      _recentBpms.add(calibratedBpm);
      if (_recentBpms.length > _bpmQueueSize) {
        _recentBpms.removeFirst();
      }

      // 外れ値の影響を減らすために中央値フィルタリングを使用
      List<double> sortedBpms = List.from(_recentBpms)..sort();
      final smoothedBpm = sortedBpms[sortedBpms.length ~/ 2];

      // 歩行状態の更新と通知
      _isWalking = true;

      // 前回のBPMと大きく異なる場合のみ更新（ノイズ削減）
      if (_currentBpm == 0.0 || (_currentBpm - smoothedBpm).abs() > 2.0) {
        _currentBpm = smoothedBpm;
        _gaitRhythmController.add(_currentBpm);
      }
    } catch (e) {
      // エラーが発生した場合でも継続処理
      debugPrint('歩行リズム検出エラー: $e');
    }
  }

  // 活動状態の検出（静止しているか動いているかを判断）- 最適化バージョン
  bool _detectActivity(List<double> magnitudes) {
    // 短い区間（最新の1秒程度）を使用
    final recentSection =
        magnitudes.sublist(math.max(0, magnitudes.length - 50));

    // 分散または標準偏差の計算 - 最適化
    double sum = 0.0;
    for (final value in recentSection) {
      sum += value;
    }
    final mean = sum / recentSection.length;

    double sumSquares = 0.0;
    int crossings = 0;
    double prevValue = recentSection[0];

    // 一回のループで標準偏差と交差回数を同時に計算
    for (int i = 0; i < recentSection.length; i++) {
      final value = recentSection[i];
      sumSquares += (value - mean) * (value - mean);

      // 平均交差のチェック (i > 0 の場合のみ)
      if (i > 0) {
        if ((value > mean && prevValue < mean) ||
            (value < mean && prevValue > mean)) {
          crossings++;
        }
      }

      prevValue = value;
    }

    final stdDev = math.sqrt(sumSquares / recentSection.length);

    // 少なくとも3回の交差が必要（約1.5歩に相当）
    if (crossings < 3) {
      return false;
    }

    // 標準偏差が閾値以上なら活動中と判断
    return stdDev > _activityThreshold;
  }

  // バンドパスフィルタの適用（歩行に関連する周波数帯域のみを抽出）
  List<double> _applyBandpassFilter(List<double> data) {
    final result = List<double>.filled(data.length, 0.0);

    // 移動平均（移動窓）フィルタを使用した簡易ローパスフィルタ
    final lowPassWindow = (_samplingRate / _highCutHz).round(); // ウィンドウサイズ
    final List<double> lowPassFiltered = List<double>.filled(data.length, 0.0);

    // ローパスフィルタの適用
    for (int i = 0; i < data.length; i++) {
      double sum = 0.0;
      int count = 0;

      for (int j = math.max(0, i - lowPassWindow ~/ 2);
          j < math.min(data.length, i + lowPassWindow ~/ 2);
          j++) {
        sum += data[j];
        count++;
      }

      if (count > 0) {
        lowPassFiltered[i] = sum / count;
      }
    }

    // 差分を取ることで簡易ハイパスフィルタを適用
    // ハイパスフィルタのウィンドウサイズ
    final highPassWindow = (_samplingRate / _lowCutHz).round();

    for (int i = 0; i < data.length; i++) {
      double sum = 0.0;
      int count = 0;

      for (int j = math.max(0, i - highPassWindow ~/ 2);
          j < math.min(data.length, i + highPassWindow ~/ 2);
          j++) {
        sum += lowPassFiltered[j];
        count++;
      }

      double baseline = (count > 0) ? sum / count : 0.0;

      // 原信号から低周波成分（ベースライン）を引く = ハイパス効果
      result[i] = data[i] - baseline;
    }

    return result;
  }

  // 自己相関によるBPM検出 - 最適化バージョン
  double _detectBpmByAutocorrelation() {
    if (_filteredMagnitudes.length < 100) return 0.0;

    // 計算効率向上のため、データサイズを制限
    final centralData = _filteredMagnitudes.sublist(
        _filteredMagnitudes.length ~/ 4,
        math.min(_filteredMagnitudes.length * 3 ~/ 4,
            _filteredMagnitudes.length ~/ 4 + 250));

    // 自己相関の計算用パラメータ
    final int maxLag =
        math.min((_samplingRate * 2).round(), centralData.length ~/ 2);
    _autoCorrelation = List<double>.filled(maxLag, 0.0);

    // 信号の正規化（平均0、分散1）- 効率化
    double sum = 0.0;
    for (final value in centralData) {
      sum += value;
    }
    final double mean = sum / centralData.length;

    final List<double> normalizedData =
        List<double>.filled(centralData.length, 0.0);
    double sumSquares = 0.0;

    for (int i = 0; i < centralData.length; i++) {
      normalizedData[i] = centralData[i] - mean;
      sumSquares += normalizedData[i] * normalizedData[i];
    }

    final double variance = sumSquares / centralData.length;
    final double stdDev = math.sqrt(variance);

    if (stdDev < 0.001) return 0.0; // 分散が非常に小さい場合は計算しない

    // 各データポイントを標準化
    for (int i = 0; i < normalizedData.length; i++) {
      normalizedData[i] = normalizedData[i] / stdDev;
    }

    // 自己相関の計算 - 効率化
    for (int lag = 0; lag < maxLag; lag++) {
      double sum = 0.0;
      for (int i = 0; i < normalizedData.length - lag; i++) {
        sum += normalizedData[i] * normalizedData[i + lag];
      }
      _autoCorrelation[lag] = sum / (normalizedData.length - lag);
    }

    // 自己相関の最初のピークを検出（歩行周期）
    final int minLag = (_samplingRate * 0.25).round();
    List<int> acPeaks = _findPeaks(_autoCorrelation.sublist(minLag));

    // ピークのインデックスを補正（sublistによるオフセットを考慮）
    acPeaks = acPeaks.map((p) => p + minLag).toList();

    if (acPeaks.isEmpty) return 0.0;

    // 最初のピーク（自己相関は対称的なので、最初のピークが最も重要）
    final int firstPeakLag = acPeaks.first;

    // ラグからステップ頻度（BPM）を計算
    final double stepFrequencyHz = _samplingRate / firstPeakLag;
    final double bpm = stepFrequencyHz * 60.0;

    return bpm;
  }

  // ピーク検出に基づくBPM検出
  double _detectBpmByPeakCounting() {
    if (_filteredMagnitudes.length < 100) return 0.0;

    // 最近の部分のみを使用（過去4秒程度）
    final recentData = _filteredMagnitudes
        .sublist(math.max(0, _filteredMagnitudes.length - 200));

    // ピーク検出
    final List<int> peaks = _findPeaks(recentData);

    if (peaks.length < _minConsecutiveSteps) {
      return 0.0; // 十分なピークがない場合
    }

    // ピーク間の間隔を計算
    final List<int> intervals = [];
    for (int i = 1; i < peaks.length; i++) {
      intervals.add(peaks[i] - peaks[i - 1]);
    }

    // 極端な間隔を除外（中央値の±50%の範囲外）
    intervals.sort();
    final int medianInterval = intervals[intervals.length ~/ 2];
    final List<int> validIntervals = intervals
        .where((interval) =>
            interval >= medianInterval * 0.5 &&
            interval <= medianInterval * 1.5)
        .toList();

    if (validIntervals.isEmpty) return 0.0;

    // 平均間隔を計算
    final double avgInterval =
        validIntervals.reduce((a, b) => a + b) / validIntervals.length;

    // BPMを計算
    final double stepFrequencyHz = _samplingRate / avgInterval;
    final double bpm = stepFrequencyHz * 60.0;

    return bpm;
  }

  // 簡易FFTを使用したBPM検出
  double _detectBpmBySimpleFFT() {
    if (_filteredMagnitudes.length < 128) return 0.0;

    // 2のべき乗のサンプル数を使用（FFTの効率のため）
    // 256サンプル ≈ 5秒（50Hzサンプリング）
    final int fftSize = 256;
    final List<double> fftInput = List<double>.filled(fftSize, 0.0);

    // 最新のデータをコピー
    for (int i = 0; i < fftSize; i++) {
      if (i < _filteredMagnitudes.length) {
        fftInput[fftSize - 1 - i] =
            _filteredMagnitudes[_filteredMagnitudes.length - 1 - i];
      }
    }

    // ウィンドウ関数を適用（ハミングウィンドウ）
    for (int i = 0; i < fftSize; i++) {
      double windowCoef =
          0.54 - 0.46 * math.cos(2 * math.pi * i / (fftSize - 1));
      fftInput[i] *= windowCoef;
    }

    // パワースペクトル計算（簡易版、実際のFFTの代わりに）
    // 注: 実際のアプリではFFTライブラリを使用することを推奨
    final List<double> powerSpectrum = List<double>.filled(fftSize ~/ 2, 0.0);

    // 歩行リズムに関連する周波数帯域のみを調査（約0.5Hz～3Hz）
    final int minBin = (0.5 * fftSize / _samplingRate).round();
    final int maxBin = (3.0 * fftSize / _samplingRate).round();

    // 最もパワーの大きい周波数を見つける代わりに、自己相関を使った簡易法
    for (int freq = minBin; freq <= maxBin; freq++) {
      // 対応する周期でのサイン波との相関を計算
      double sumSin = 0.0, sumCos = 0.0;
      for (int i = 0; i < fftSize; i++) {
        double phase = 2 * math.pi * freq * i / fftSize;
        sumSin += fftInput[i] * math.sin(phase);
        sumCos += fftInput[i] * math.cos(phase);
      }

      // パワースペクトル計算
      powerSpectrum[freq] = sumSin * sumSin + sumCos * sumCos;
    }

    // 最大パワーを持つ周波数ビンを見つける
    int maxPowerBin = minBin;
    double maxPower = powerSpectrum[minBin];

    for (int bin = minBin + 1; bin <= maxBin; bin++) {
      if (powerSpectrum[bin] > maxPower) {
        maxPower = powerSpectrum[bin];
        maxPowerBin = bin;
      }
    }

    // 周波数からBPMを計算
    final double domFreq = maxPowerBin * _samplingRate / fftSize;
    final double bpm = domFreq * 60.0;

    return bpm;
  }

  // ピーク検出（改良版）
  List<int> _findPeaks(List<double> data) {
    final peaks = <int>[];

    if (data.length < 3) return peaks;

    // 分散（または標準偏差）の計算
    final mean = data.reduce((a, b) => a + b) / data.length;
    final sumSquaredDiffs =
        data.map((x) => math.pow(x - mean, 2)).reduce((a, b) => a + b);
    final stdDev = math.sqrt(sumSquaredDiffs / data.length);

    // 閾値（標準偏差の一定倍）
    final threshold = stdDev * _peakThreshold;

    // ピーク検出
    for (int i = 1; i < data.length - 1; i++) {
      // 前後のデータよりも大きく、かつ閾値より大きい場合にピークとみなす
      if (data[i] > data[i - 1] &&
          data[i] > data[i + 1] &&
          data[i] > threshold) {
        // 最小距離条件のチェック
        if (peaks.isEmpty || i - peaks.last >= _minPeakDistance) {
          peaks.add(i);
        } else if (data[i] > data[peaks.last]) {
          // より大きなピークで置き換え
          peaks[peaks.length - 1] = i;
        }
      }
    }

    return peaks;
  }

  // リソース解放
  void dispose() {
    stopSensing();
    _accelerometerDataController.close();
    _gaitRhythmController.close();
    _calibrationResultController.close();
  }
}

/// キャリブレーションポイント（目標BPMと測定BPMの対応）
class CalibrationPoint {
  final double targetBpm; // 目標BPM
  final double measuredBpm; // 測定されたBPM
  final double error; // 誤差

  CalibrationPoint({
    required this.targetBpm,
    required this.measuredBpm,
    required this.error,
  });
}

/// キャリブレーション結果
class CalibrationResult {
  final double targetBpm;
  final double measuredBpm;
  final double error;
  final double calibrationMultiplier;
  final double calibrationOffset;
  final List<CalibrationPoint> points;

  CalibrationResult({
    required this.targetBpm,
    required this.measuredBpm,
    required this.error,
    required this.calibrationMultiplier,
    required this.calibrationOffset,
    required this.points,
  });
}
