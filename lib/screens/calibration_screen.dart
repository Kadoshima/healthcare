import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';
import 'dart:math' as math;

import '../services/sensor_service.dart';
import '../services/improved_audio_service.dart';

/// 歩行リズムキャリブレーション画面
class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({Key? key}) : super(key: key);

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  // サービス
  late SensorService _sensorService;
  late ImprovedAudioService _audioService;

  // キャリブレーション状態
  final List<double> _calibrationBpms = [80, 100, 120]; // キャリブレーションする3つのBPM
  int _currentCalibrationStep = -1; // -1: 準備中, 0-2: キャリブレーション中, 3: 完了

  // UI状態
  bool _isPlaying = false;
  Timer? _calibrationTimer;
  int _countdownSeconds = 5;
  int _calibrationSeconds = 30;

  // 結果表示用
  List<CalibrationPoint> _calibrationPoints = [];
  double _calibrationMultiplier = 1.0;
  double _calibrationOffset = 0.0;

  // グラフデータ
  final List<FlSpot> _targetPoints = [];
  final List<FlSpot> _measuredPoints = [];

  // 購読
  StreamSubscription<double>? _bpmSubscription;
  StreamSubscription<CalibrationResult>? _calibrationResultSubscription;

  @override
  void initState() {
    super.initState();

    // サービスの取得
    _sensorService = Provider.of<SensorService>(context, listen: false);
    _audioService = Provider.of<ImprovedAudioService>(context, listen: false);

    // オーディオサービスの初期化
    _audioService.initialize().then((_) {
      // センサーサービスの初期化
      _sensorService.initialize().then((_) {
        // キャリブレーション結果の購読
        _calibrationResultSubscription = _sensorService.calibrationResultStream
            .listen(_handleCalibrationResult);

        // BPMデータの購読
        _bpmSubscription =
            _sensorService.gaitRhythmStream.listen(_handleBpmUpdate);

        // センサー開始
        _sensorService.startSensing();

        // 準備完了
        setState(() {
          _currentCalibrationStep = -1;
        });
      });
    });
  }

  @override
  void dispose() {
    // タイマーのキャンセル
    _calibrationTimer?.cancel();

    // メトロノームの停止
    if (_isPlaying) {
      _audioService.stopTempoCues();
    }

    // 購読のキャンセル
    _bpmSubscription?.cancel();
    _calibrationResultSubscription?.cancel();

    super.dispose();
  }

  // BPM更新のハンドラ
  void _handleBpmUpdate(double bpm) {
    // キャリブレーション中のみ処理
    if (_currentCalibrationStep >= 0 &&
        _currentCalibrationStep < _calibrationBpms.length) {
      // 現在のBPMを表示用に更新
      setState(() {});
    }
  }

  // キャリブレーション結果のハンドラ
  void _handleCalibrationResult(CalibrationResult result) {
    setState(() {
      _calibrationPoints = result.points;
      _calibrationMultiplier = result.calibrationMultiplier;
      _calibrationOffset = result.calibrationOffset;

      // グラフデータの更新
      _updateGraphData();
    });
  }

  // キャリブレーション開始
  void _startCalibration() {
    if (_currentCalibrationStep >= 0) return; // 既に開始している場合

    setState(() {
      _currentCalibrationStep = 0;
      _countdownSeconds = 5;
    });

    // カウントダウン開始
    _startCountdown();
  }

  // カウントダウン開始
  void _startCountdown() {
    _calibrationTimer?.cancel();

    _calibrationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _countdownSeconds--;
      });

      if (_countdownSeconds <= 0) {
        timer.cancel();
        _startCalibrationStep();
      }
    });
  }

  // 現在のキャリブレーションステップを開始
  void _startCalibrationStep() {
    if (_currentCalibrationStep >= _calibrationBpms.length) {
      // すべてのステップが完了
      _completeCalibration();
      return;
    }

    final targetBpm = _calibrationBpms[_currentCalibrationStep];

    // メトロノーム開始
    _audioService.loadClickSound('標準クリック').then((_) {
      _audioService.startTempoCues(targetBpm);
      _isPlaying = true;
    });

    // キャリブレーション開始
    _sensorService.startCalibration(targetBpm);

    // キャリブレーションタイマー設定
    _calibrationSeconds = 30;

    _calibrationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _calibrationSeconds--;
      });

      if (_calibrationSeconds <= 0) {
        timer.cancel();
        _finishCurrentStep();
      }
    });
  }

  // 現在のキャリブレーションステップを終了
  void _finishCurrentStep() {
    // メトロノーム停止
    _audioService.stopTempoCues();
    _isPlaying = false;

    // キャリブレーションデータ収集終了
    _sensorService.stopCalibration();

    // 次のステップへ
    setState(() {
      _currentCalibrationStep++;
      _countdownSeconds = 5;
    });

    if (_currentCalibrationStep < _calibrationBpms.length) {
      // 次のステップのカウントダウン開始
      _startCountdown();
    } else {
      // すべてのステップが完了
      _completeCalibration();
    }
  }

  // キャリブレーション完了
  void _completeCalibration() {
    setState(() {
      _currentCalibrationStep = _calibrationBpms.length; // 完了状態
    });

    // グラフデータの更新
    _updateGraphData();
  }

  // グラフデータの更新
  void _updateGraphData() {
    _targetPoints.clear();
    _measuredPoints.clear();

    for (int i = 0; i < _calibrationPoints.length; i++) {
      final point = _calibrationPoints[i];
      _targetPoints.add(FlSpot(point.measuredBpm, point.targetBpm));
      _measuredPoints.add(FlSpot(point.measuredBpm, point.measuredBpm));
    }

    // 理想線（y=x）の追加
    if (_calibrationPoints.isNotEmpty) {
      double minX = double.infinity;
      double maxX = -double.infinity;

      for (final point in _targetPoints) {
        minX = math.min(minX, point.x);
        maxX = math.max(maxX, point.x);
      }

      // 余裕を持たせる
      minX = math.max(0, minX - 10);
      maxX = maxX + 10;
    }
  }

  // キャリブレーションステップをスキップ
  void _skipStep() {
    _calibrationTimer?.cancel();

    // メトロノーム停止
    if (_isPlaying) {
      _audioService.stopTempoCues();
      _isPlaying = false;
    }

    // キャリブレーション停止
    if (_currentCalibrationStep >= 0 &&
        _currentCalibrationStep < _calibrationBpms.length) {
      _sensorService.stopCalibration();
    }

    // 次のステップへ
    setState(() {
      _currentCalibrationStep++;
      _countdownSeconds = 5;
    });

    if (_currentCalibrationStep < _calibrationBpms.length) {
      // 次のステップのカウントダウン開始
      _startCountdown();
    } else {
      // すべてのステップが完了
      _completeCalibration();
    }
  }

  // キャリブレーションをリセット
  void _resetCalibration() {
    _calibrationTimer?.cancel();

    // メトロノーム停止
    if (_isPlaying) {
      _audioService.stopTempoCues();
      _isPlaying = false;
    }

    setState(() {
      _currentCalibrationStep = -1;
      _countdownSeconds = 5;
      _calibrationSeconds = 30;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('歩行リズムキャリブレーション'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetCalibration,
            tooltip: 'リセット',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 説明カード
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'キャリブレーション手順',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '1. メトロノーム音に合わせて歩きます\n'
                        '2. 各BPM（80, 100, 120）で30秒間歩行します\n'
                        '3. キャリブレーション結果が自動的に適用されます',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '正確なキャリブレーションのため、メトロノームの音に合わせて一定のリズムで歩いてください。',
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ステータス表示
              _buildStatusCard(),

              const SizedBox(height: 16),

              // キャリブレーションボタン
              Center(
                child: _currentCalibrationStep == -1
                    ? ElevatedButton.icon(
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('キャリブレーション開始'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                        ),
                        onPressed: _startCalibration,
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_currentCalibrationStep < _calibrationBpms.length)
                            ElevatedButton.icon(
                              icon: const Icon(Icons.skip_next),
                              label: const Text('スキップ'),
                              onPressed: _skipStep,
                            ),
                          const SizedBox(width: 16),
                          if (_currentCalibrationStep ==
                              _calibrationBpms.length)
                            ElevatedButton.icon(
                              icon: const Icon(Icons.done),
                              label: const Text('完了'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                        ],
                      ),
              ),

              const SizedBox(height: 24),

              // 結果表示
              if (_calibrationPoints.isNotEmpty) ...[
                const Text(
                  'キャリブレーション結果',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                // 結果グラフ
                _buildCalibrationGraph(),

                const SizedBox(height: 16),

                // 補正係数
                Text(
                  '補正係数: ${_calibrationMultiplier.toStringAsFixed(3)} × BPM + ${_calibrationOffset.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ステータスカード
  Widget _buildStatusCard() {
    String statusText;
    IconData statusIcon;
    Color statusColor;

    if (_currentCalibrationStep == -1) {
      statusText = 'キャリブレーション待機中';
      statusIcon = Icons.hourglass_empty;
      statusColor = Colors.grey;
    } else if (_currentCalibrationStep < _calibrationBpms.length) {
      if (_countdownSeconds > 0) {
        statusText = 'カウントダウン: $_countdownSeconds秒';
        statusIcon = Icons.timer;
        statusColor = Colors.orange;
      } else {
        statusText =
            '${_calibrationBpms[_currentCalibrationStep]} BPMでキャリブレーション中: あと$_calibrationSeconds秒';
        statusIcon = Icons.directions_walk;
        statusColor = Colors.blue;
      }
    } else {
      statusText = 'キャリブレーション完了';
      statusIcon = Icons.check_circle;
      statusColor = Colors.green;
    }

    return Card(
      elevation: 4,
      color: statusColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 24,
        ),
        child: Row(
          children: [
            Icon(
              statusIcon,
              color: statusColor,
              size: 36,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                  if (_currentCalibrationStep >= 0 &&
                      _currentCalibrationStep < _calibrationBpms.length &&
                      _countdownSeconds <= 0)
                    const Text(
                      'メトロノーム音に合わせて歩いてください',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  if (_sensorService.isWalking &&
                      _currentCalibrationStep >= 0 &&
                      _currentCalibrationStep < _calibrationBpms.length)
                    Text(
                      '現在のBPM: ${_sensorService.currentBpm.toStringAsFixed(1)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
            if (_currentCalibrationStep >= 0 &&
                _currentCalibrationStep < _calibrationBpms.length &&
                _countdownSeconds <= 0)
              CircularProgressIndicator(
                value: 1 - (_calibrationSeconds / 30),
                color: statusColor,
              ),
          ],
        ),
      ),
    );
  }

  // キャリブレーショングラフ
  Widget _buildCalibrationGraph() {
    if (_calibrationPoints.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: Text('キャリブレーションデータがありません'),
        ),
      );
    }

    // データ範囲の計算
    double minX = 70.0;
    double maxX = 130.0;
    double minY = 70.0;
    double maxY = 130.0;

    for (final point in _calibrationPoints) {
      minX = math.min(minX, point.measuredBpm - 10);
      maxX = math.max(maxX, point.measuredBpm + 10);
      minY = math.min(minY, point.targetBpm - 10);
      maxY = math.max(maxY, point.targetBpm + 10);
    }

    // 補正ライン用のポイント
    final List<FlSpot> correctionLine = [];
    for (double x = minX; x <= maxX; x += 5) {
      correctionLine
          .add(FlSpot(x, x * _calibrationMultiplier + _calibrationOffset));
    }

    // 理想ライン用のポイント
    final List<FlSpot> idealLine = [];
    for (double x = minX; x <= maxX; x += 5) {
      idealLine.add(FlSpot(x, x));
    }

    return SizedBox(
      height: 250,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            horizontalInterval: 10,
            verticalInterval: 10,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.grey.withOpacity(0.3),
              strokeWidth: 1,
            ),
            getDrawingVerticalLine: (value) => FlLine(
              color: Colors.grey.withOpacity(0.3),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              axisNameWidget: const Text('実際のBPM'),
              sideTitles: SideTitles(
                showTitles: true,
                interval: 10,
                reservedSize: 40,
                getTitlesWidget: (value, meta) => Text(
                  value.toInt().toString(),
                  style: const TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              axisNameWidget: const Text('測定されたBPM'),
              sideTitles: SideTitles(
                showTitles: true,
                interval: 10,
                reservedSize: 30,
                getTitlesWidget: (value, meta) => Text(
                  value.toInt().toString(),
                  style: const TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            rightTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(color: Colors.grey.shade300, width: 1),
          ),
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          lineBarsData: [
            // 理想ライン（y = x）
            LineChartBarData(
              spots: idealLine,
              isCurved: false,
              color: Colors.grey.withOpacity(0.7),
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              dashArray: [5, 5],
            ),
            // 補正ライン
            LineChartBarData(
              spots: correctionLine,
              isCurved: false,
              color: Colors.green,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
            ),
            // キャリブレーションポイント
            LineChartBarData(
              spots: _calibrationPoints
                  .map((point) => FlSpot(point.measuredBpm, point.targetBpm))
                  .toList(),
              isCurved: false,
              color: Colors.transparent,
              barWidth: 0,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) =>
                    FlDotCirclePainter(
                  radius: 6,
                  color: Colors.blue,
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                ),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              tooltipBgColor: Colors.blueGrey.withOpacity(0.8),
              getTooltipItems: (List<LineBarSpot> touchedSpots) {
                return touchedSpots.map((barSpot) {
                  if (barSpot.barIndex == 2) {
                    // キャリブレーションポイント
                    final point = _calibrationPoints[barSpot.spotIndex];
                    return LineTooltipItem(
                      '目標: ${point.targetBpm.toStringAsFixed(1)} BPM\n'
                      '測定: ${point.measuredBpm.toStringAsFixed(1)} BPM\n'
                      '誤差: ${point.error.toStringAsFixed(1)} BPM',
                      const TextStyle(color: Colors.white),
                    );
                  }
                  return null;
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }
}
