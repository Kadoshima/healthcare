import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:sensors_plus/sensors_plus.dart';
import '../models/gait_data.dart';

class SensorService {
  // ストリームコントローラー
  final _accelerometerDataController =
      StreamController<AccelerometerData>.broadcast();
  final _gaitRhythmController = StreamController<double>.broadcast();

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

  // 歩行検出のパラメータ
  final double _activityThreshold = 0.15; // 活動検出の閾値（加速度の標準偏差）
  final int _minConsecutiveSteps = 4; // 歩行と判断する最小連続ステップ数

  // フィルタリングパラメータ
  final double _lowCutHz = 0.5; // ハイパスフィルタのカットオフ周波数（Hz）
  final double _highCutHz = 3.0; // ローパスフィルタのカットオフ周波数（Hz）

  // 自己相関データ
  List<double> _autoCorrelation = [];

  // ピーク検出パラメータ
  final double _peakThreshold = 0.5; // ピーク閾値（標準偏差の倍数）
  final int _minPeakDistance = 15; // ピーク間の最小サンプル数（約0.3秒）

  // 過去のBPM値を保存するキュー（平滑化用）
  final Queue<double> _recentBpms = Queue<double>();
  final int _bpmQueueSize = 5; // BPM平滑化のためのキューサイズ

  // センサー状態
  bool _isRunning = false;

  // 公開ストリーム
  Stream<AccelerometerData> get accelerometerStream =>
      _accelerometerDataController.stream;
  Stream<double> get gaitRhythmStream => _gaitRhythmController.stream;

  // 現在の歩行リズム
  double get currentBpm => _currentBpm;
  bool get isWalking => _isWalking;

  // センサーの初期化
  Future<bool> initialize() async {
    try {
      // センサーの有効性チェックなど、必要な初期化処理
      return true;
    } catch (e) {
      print('センサー初期化エラー: $e');
      return false;
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

      // 3. 歩行リズムの検出
      // 最も信頼性の高い方法で検出（自己相関法を優先）
      double detectedBpm = 0.0;

      // 3.1 自己相関法によるBPM検出（最も信頼性が高い）
      final autoCorrBpm = _detectBpmByAutocorrelation();

      if (autoCorrBpm > 40 && autoCorrBpm < 150) {
        // 有効な自己相関BPMが検出された場合はそれを使用
        detectedBpm = autoCorrBpm;
      } else {
        // 自己相関法が失敗した場合はピーク検出法を試す
        final peakBpm = _detectBpmByPeakCounting();

        if (peakBpm > 40 && peakBpm < 150) {
          detectedBpm = peakBpm;
        } else {
          // 最後の手段としてFFT法を使用
          final fftBpm = _detectBpmBySimpleFFT();
          if (fftBpm > 40 && fftBpm < 150) {
            detectedBpm = fftBpm;
          }
        }
      }

      // 有効なBPMが検出されなかった場合
      if (detectedBpm <= 0) return;

      // 5. 平滑化（急激な変化を防止）
      _recentBpms.add(detectedBpm);
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
      print('歩行リズム検出エラー: $e');
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
  }
}
