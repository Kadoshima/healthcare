import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';
import 'dart:math' as math;

import '../services/sensor_service.dart';
import '../services/improved_audio_service.dart';

// グローバルなデバッグロギング用（main.dartと合わせる）
bool debugMode = true;
void debugLog(String message) {
  if (debugMode) {
    print('[DEBUG] $message');
  }
}

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

  // 初期化状態
  bool _isInitializing = true;
  String _initError = '';

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
    debugLog('キャリブレーション画面を初期化します');

    // サービスの取得と初期化
    _initializeServices();
  }

  // サービスの初期化
  Future<void> _initializeServices() async {
    setState(() {
      _isInitializing = true;
      _initError = '';
    });

    try {
      // サービスの取得
      _sensorService = Provider.of<SensorService>(context, listen: false);
      _audioService = Provider.of<ImprovedAudioService>(context, listen: false);

      debugLog('オーディオサービスの初期化を開始します');

      // オーディオサービスの初期化
      bool audioInitialized = await _audioService.initialize();
      if (!audioInitialized) {
        throw Exception('オーディオサービスの初期化に失敗しました');
      }

      debugLog('オーディオサービスの初期化が完了しました');

      // 高精度モードを設定
      _audioService.setPrecisionMode(PrecisionMode.highPrecision);

      // 標準クリック音のロード
      bool soundLoaded = await _audioService.loadClickSound('標準クリック');
      if (!soundLoaded) {
        throw Exception('標準クリック音のロードに失敗しました');
      }

      debugLog('センサーサービスの初期化を開始します');

      // センサーサービスの初期化
      bool sensorInitialized = await _sensorService.initialize();
      if (!sensorInitialized) {
        throw Exception('センサーサービスの初期化に失敗しました');
      }

      debugLog('センサーサービスの初期化が完了しました');

      // キャリブレーション結果の購読
      _calibrationResultSubscription = _sensorService.calibrationResultStream
          .listen(_handleCalibrationResult);

      // BPMデータの購読
      _bpmSubscription =
          _sensorService.gaitRhythmStream.listen(_handleBpmUpdate);

      // センサー開始
      _sensorService.startSensing();
      debugLog('センサーの起動が完了しました');

      // 準備完了
      setState(() {
        _currentCalibrationStep = -1;
        _isInitializing = false;
      });

      debugLog('キャリブレーション画面の初期化が完了しました');
    } catch (e) {
      debugLog('初期化エラー: $e');
      setState(() {
        _isInitializing = false;
        _initError = e.toString();
      });

      // エラー表示
      _showError('初期化エラー', e.toString());
    }
  }

  @override
  void dispose() {
    debugLog('キャリブレーション画面のリソースを解放します');

    // タイマーのキャンセル
    _calibrationTimer?.cancel();

    // メトロノームの停止
    if (_isPlaying) {
      _audioService.stopTempoCues();
      debugLog('メトロノームを停止しました');
    }

    // 購読のキャンセル
    _bpmSubscription?.cancel();
    _calibrationResultSubscription?.cancel();
    debugLog('購読をキャンセルしました');

    super.dispose();
  }

  // BPM更新のハンドラ
  void _handleBpmUpdate(double bpm) {
    // キャリブレーション中のみ処理
    if (_currentCalibrationStep >= 0 &&
        _currentCalibrationStep < _calibrationBpms.length) {
      // 現在のBPMを表示用に更新
      setState(() {});
      debugLog('BPM更新: $bpm');
    }
  }

  // キャリブレーション結果のハンドラ
  void _handleCalibrationResult(CalibrationResult result) {
    debugLog('キャリブレーション結果を受信しました: '
        'targetBpm=${result.targetBpm}, measuredBpm=${result.measuredBpm}, '
        'error=${result.error}, multiplier=${result.calibrationMultiplier}, '
        'offset=${result.calibrationOffset}');

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

    debugLog('キャリブレーションを開始します');

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

    debugLog('カウントダウンを開始します: $_countdownSeconds秒');

    _calibrationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _countdownSeconds--;
      });

      if (_countdownSeconds <= 0) {
        debugLog('カウントダウンが完了しました');
        timer.cancel();
        _startCalibrationStep();
      }
    });
  }

  // 現在のキャリブレーションステップを開始
  void _startCalibrationStep() {
    if (_currentCalibrationStep >= _calibrationBpms.length) {
      // すべてのステップが完了
      debugLog('すべてのキャリブレーションステップが完了しました');
      _completeCalibration();
      return;
    }

    final targetBpm = _calibrationBpms[_currentCalibrationStep];
    debugLog('キャリブレーションステップ $_currentCalibrationStep を開始します: BPM = $targetBpm');

    // メトロノーム開始
    _loadAndStartMetronome(targetBpm);

    // キャリブレーション開始
    _sensorService.startCalibration(targetBpm);
    debugLog('センサーキャリブレーションを開始しました: BPM = $targetBpm');

    // キャリブレーションタイマー設定
    _calibrationSeconds = 30;

    _calibrationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _calibrationSeconds--;
      });

      if (_calibrationSeconds <= 0) {
        debugLog('キャリブレーションタイマーが完了しました');
        timer.cancel();
        _finishCurrentStep();
      }
    });
  }

  // メトロノームのロードと開始
  Future<void> _loadAndStartMetronome(double targetBpm) async {
    try {
      // まず明示的にクリック音をロード
      bool soundLoaded = await _audioService.loadClickSound('標準クリック');
      if (!soundLoaded) {
        debugLog('クリック音のロードに失敗しました');
        _showError('サウンドエラー', 'クリック音のロードに失敗しました');
        return;
      }

      debugLog('クリック音のロードに成功しました');

      // メトロノーム開始
      _audioService.startTempoCues(targetBpm);
      setState(() {
        _isPlaying = true;
      });

      debugLog('メトロノームを開始しました: BPM = $targetBpm');
    } catch (e) {
      debugLog('メトロノーム開始エラー: $e');
      _showError('メトロノームエラー', 'メトロノームの開始に失敗しました: $e');

      // エラーが発生した場合でもキャリブレーションは続行
      setState(() {
        _isPlaying = false;
      });
    }
  }

  // 現在のキャリブレーションステップを終了
  void _finishCurrentStep() {
    debugLog('キャリブレーションステップを終了します: ステップ $_currentCalibrationStep');

    // メトロノーム停止
    _audioService.stopTempoCues();
    setState(() {
      _isPlaying = false;
    });
    debugLog('メトロノームを停止しました');

    // キャリブレーションデータ収集終了
    _sensorService.stopCalibration();
    debugLog('センサーキャリブレーションを停止しました');

    // 次のステップへ
    setState(() {
      _currentCalibrationStep++;
      _countdownSeconds = 5;
    });

    if (_currentCalibrationStep < _calibrationBpms.length) {
      debugLog('次のキャリブレーションステップへ進みます: ステップ $_currentCalibrationStep');
      // 次のステップのカウントダウン開始
      _startCountdown();
    } else {
      debugLog('すべてのキャリブレーションステップが完了しました');
      // すべてのステップが完了
      _completeCalibration();
    }
  }

  // キャリブレーション完了
  void _completeCalibration() {
    debugLog('キャリブレーションを完了します');

    setState(() {
      _currentCalibrationStep = _calibrationBpms.length; // 完了状態
    });

    // グラフデータの更新
    _updateGraphData();

    // 結果をログに出力
    debugLog('キャリブレーション結果: '
        'ポイント数=${_calibrationPoints.length}, '
        '補正乗数=$_calibrationMultiplier, '
        '補正オフセット=$_calibrationOffset');
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
    debugLog('キャリブレーションステップをスキップします: ステップ $_currentCalibrationStep');

    _calibrationTimer?.cancel();

    // メトロノーム停止
    if (_isPlaying) {
      _audioService.stopTempoCues();
      setState(() {
        _isPlaying = false;
      });
      debugLog('メトロノームを停止しました（スキップ）');
    }

    // キャリブレーション停止
    if (_currentCalibrationStep >= 0 &&
        _currentCalibrationStep < _calibrationBpms.length) {
      _sensorService.stopCalibration();
      debugLog('センサーキャリブレーションを停止しました（スキップ）');
    }

    // 次のステップへ
    setState(() {
      _currentCalibrationStep++;
      _countdownSeconds = 5;
    });

    if (_currentCalibrationStep < _calibrationBpms.length) {
      debugLog('次のキャリブレーションステップへ進みます（スキップ後）: ステップ $_currentCalibrationStep');
      // 次のステップのカウントダウン開始
      _startCountdown();
    } else {
      debugLog('すべてのキャリブレーションステップが完了しました（スキップ後）');
      // すべてのステップが完了
      _completeCalibration();
    }
  }

  // キャリブレーションをリセット
  void _resetCalibration() {
    debugLog('キャリブレーションをリセットします');

    _calibrationTimer?.cancel();

    // メトロノーム停止
    if (_isPlaying) {
      _audioService.stopTempoCues();
      setState(() {
        _isPlaying = false;
      });
      debugLog('メトロノームを停止しました（リセット）');
    }

    setState(() {
      _currentCalibrationStep = -1;
      _countdownSeconds = 5;
      _calibrationSeconds = 30;
    });

    debugLog('キャリブレーションをリセットしました: 準備完了状態');
  }

  // エラー表示
  void _showError(String title, String message) {
    debugLog('エラー表示: $title - $message');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title: $message'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '閉じる',
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  // 読み込み中の表示
  Widget _buildLoadingScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          const Text('キャリブレーションを準備中...', style: TextStyle(fontSize: 18)),
          if (_initError.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'エラー: $_initError',
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _initializeServices,
              child: const Text('再試行'),
            ),
          ],
        ],
      ),
    );
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
        child: _isInitializing
            ? _buildLoadingScreen()
            : Padding(
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
                                if (_currentCalibrationStep <
                                    _calibrationBpms.length)
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
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
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
