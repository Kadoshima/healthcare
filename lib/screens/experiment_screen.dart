import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import '../models/experiment_settings.dart';
import '../models/gait_data.dart';
import '../services/sensor_service.dart';
// 以下のAudioServiceを使用する代わりに
// import '../services/audio_service.dart';
// ImprovedAudioServiceをインポート
import '../services/improved_audio_service.dart';
import '../services/experiment_service.dart';
import '../widgets/phase_timer.dart';
import '../widgets/tempo_display.dart';
import 'calibration_screen.dart';
import 'results_screen.dart';

// グローバルなデバッグロギング用（main.dartと合わせる）
bool debugMode = true;
void debugLog(String message) {
  if (debugMode) {
    print('[DEBUG] $message');
  }
}

class ExperimentScreen extends StatefulWidget {
  const ExperimentScreen({Key? key}) : super(key: key);

  @override
  State<ExperimentScreen> createState() => _ExperimentScreenState();
}

class _ExperimentScreenState extends State<ExperimentScreen> {
  // サービス
  late SensorService _sensorService;
  // AudioServiceの代わりにImprovedAudioServiceを使用
  late ImprovedAudioService _audioService;
  late ExperimentService _experimentService;

  // 購読
  StreamSubscription<double>? _gaitRhythmSubscription;
  StreamSubscription<GaitRhythmData>? _gaitDataSubscription;

  // 状態
  double _currentBpm = 0.0;
  double _targetBpm = 0.0;
  final List<FlSpot> _rhythmDataPoints = [];
  final int _maxDataPoints = 100; // グラフ表示用のデータポイント数

  // 初期化状態
  bool _isInitializing = true;
  String _initError = '';
  bool _servicesReady = false;

  // セッションID
  int? _sessionId;

  @override
  void initState() {
    super.initState();
    debugLog('実験画面を初期化します');

    // サービスの取得と初期化
    _initializeServices();
  }

  // サービスの初期化とキャリブレーションチェック
  Future<void> _initializeServices() async {
    setState(() {
      _isInitializing = true;
      _initError = '';
    });

    try {
      // サービスの取得
      _sensorService = Provider.of<SensorService>(context, listen: false);
      _audioService = Provider.of<ImprovedAudioService>(context, listen: false);
      _experimentService =
          Provider.of<ExperimentService>(context, listen: false);

      debugLog('オーディオサービスの初期化を開始します');

      // オーディオサービスの初期化
      bool audioInitialized = await _audioService.initialize();
      if (!audioInitialized) {
        throw Exception('オーディオサービスの初期化に失敗しました');
      }

      debugLog('オーディオサービスの初期化が完了しました');

      // センサーサービスの初期化
      debugLog('センサーサービスの初期化を開始します');
      bool sensorInitialized = await _sensorService.initialize();
      if (!sensorInitialized) {
        throw Exception('センサーサービスの初期化に失敗しました');
      }

      debugLog('センサーサービスの初期化が完了しました');

      // 全サービスの準備完了
      setState(() {
        _servicesReady = true;
        _isInitializing = false;
      });

      debugLog('全サービスの初期化が完了しました');

      // キャリブレーションが必要かチェック
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkCalibrationAndProceed();
      });
    } catch (e) {
      debugLog('初期化エラー: $e');
      setState(() {
        _isInitializing = false;
        _servicesReady = false;
        _initError = e.toString();
      });

      // エラー表示
      _showError('初期化エラー', e.toString());
    }
  }

  // キャリブレーションチェックと実験開始
  Future<void> _checkCalibrationAndProceed() async {
    if (!_servicesReady) return;

    debugLog('キャリブレーションの状態を確認します');

    // キャリブレーションポイントをチェック
    if (_sensorService.calibrationPoints.isEmpty) {
      debugLog('キャリブレーションが未実施です');
      // キャリブレーションが必要なダイアログを表示
      _showCalibrationDialog();
    } else {
      debugLog(
          'キャリブレーションは既に完了しています: ${_sensorService.calibrationPoints.length}ポイント');
      // 実験を開始
      _startExperiment();
    }
  }

  // キャリブレーションダイアログの表示
  void _showCalibrationDialog() {
    debugLog('キャリブレーションダイアログを表示します');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('キャリブレーションが必要です'),
        content: const Text('正確な測定のためには、センサーのキャリブレーションが必要です。'
            'キャリブレーションを行うと、より高精度な歩行リズム測定が可能になります。'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // キャリブレーションなしで続行（精度が低下）
              debugLog('キャリブレーションをスキップします');
              _startExperiment();
            },
            child: const Text('スキップ'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _navigateToCalibration();
            },
            child: const Text('キャリブレーションを実行'),
          ),
        ],
      ),
    );
  }

  // キャリブレーション画面に遷移
  Future<void> _navigateToCalibration() async {
    debugLog('キャリブレーション画面に遷移します');

    // キャリブレーション画面に遷移
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const CalibrationScreen(),
      ),
    );

    debugLog('キャリブレーション画面から戻りました: $result');

    // キャリブレーション完了後、実験を開始
    _startExperiment();
  }

  // 実験開始
  Future<void> _startExperiment() async {
    debugLog('実験を開始します');

    final settings = Provider.of<ExperimentSettings>(context, listen: false);

    // 実験セッションの作成
    _sessionId = await _experimentService.startExperimentSession(settings);
    debugLog('実験セッションを作成しました: セッションID = $_sessionId');

    // センサーデータの購読開始
    _gaitRhythmSubscription = _sensorService.gaitRhythmStream.listen((bpm) {
      setState(() {
        _currentBpm = bpm;
      });

      // 実験データの記録
      _experimentService.addGaitRhythmData(
        bpm,
        settings.currentPhase,
        _targetBpm,
      );
    });
    debugLog('歩行リズムデータの購読を開始しました');

    // 実験データの購読開始
    _gaitDataSubscription = _experimentService.gaitDataStream.listen((data) {
      setState(() {
        // グラフ用のデータポイントを追加
        _rhythmDataPoints.add(FlSpot(
          _rhythmDataPoints.length.toDouble(),
          data.bpm,
        ));

        // 最大表示数を超えたら古いデータを削除
        if (_rhythmDataPoints.length > _maxDataPoints) {
          _rhythmDataPoints.removeAt(0);

          // X軸の値を調整
          for (var i = 0; i < _rhythmDataPoints.length; i++) {
            _rhythmDataPoints[i] = FlSpot(i.toDouble(), _rhythmDataPoints[i].y);
          }
        }
      });
    });
    debugLog('実験データの購読を開始しました');

    // センサー開始
    _sensorService.startSensing();
    debugLog('センサーを開始しました');

    // キャリブレーションから開始
    settings.startExperiment();
    _processPhaseChange(settings);
    debugLog('実験を開始しました: フェーズ = ${settings.currentPhase}');
  }

  // フェーズ変更処理
  void _processPhaseChange(ExperimentSettings settings) {
    debugLog('フェーズが変更されました: ${settings.currentPhase}');

    // 現在のフェーズに基づいて処理
    switch (settings.currentPhase) {
      case ExperimentPhase.calibration:
        _startCalibrationPhase(settings);
        break;
      case ExperimentPhase.silentWalking:
        _startSilentWalkingPhase(settings);
        break;
      case ExperimentPhase.syncWithNaturalTempo:
        _startSyncPhase(settings);
        break;
      case ExperimentPhase.rhythmGuidance1:
        _startGuidance1Phase(settings);
        break;
      case ExperimentPhase.rhythmGuidance2:
        _startGuidance2Phase(settings);
        break;
      case ExperimentPhase.cooldown:
        _startCooldownPhase(settings);
        break;
      case ExperimentPhase.completed:
        _completeExperiment();
        break;
      default:
        break;
    }
  }

  // キャリブレーションフェーズ
  void _startCalibrationPhase(ExperimentSettings settings) {
    debugLog('キャリブレーションフェーズを開始します');

    _targetBpm = 0.0;
    _audioService.stopTempoCues();

    // フェーズ開始
    _experimentService.startPhase(
      ExperimentPhase.calibration,
      settings,
      () {
        // フェーズ完了時：無音歩行フェーズへ
        settings.setPhase(ExperimentPhase.silentWalking);
        _processPhaseChange(settings);
      },
    );
  }

  // 無音歩行フェーズ
  void _startSilentWalkingPhase(ExperimentSettings settings) {
    debugLog('無音歩行フェーズを開始します');

    _targetBpm = 0.0;
    _audioService.stopTempoCues();

    // フェーズ開始
    _experimentService.startPhase(
      ExperimentPhase.silentWalking,
      settings,
      () {
        // フェーズ完了時：自然歩行リズムを設定
        final naturalTempo = _currentBpm;
        settings.setNaturalTempo(naturalTempo);
        debugLog('自然歩行リズムを設定しました: $naturalTempo BPM');

        // 同期フェーズへ
        settings.setPhase(ExperimentPhase.syncWithNaturalTempo);
        _processPhaseChange(settings);
      },
    );
  }

  // 同期フェーズ
  void _startSyncPhase(ExperimentSettings settings) {
    debugLog('同期フェーズを開始します');

    _targetBpm = settings.naturalTempo ?? 100.0;
    debugLog('目標テンポを設定: $_targetBpm BPM');

    _audioService.setVolume(settings.volume);

    // ImprovedAudioServiceでのロードと再生の方法に変更
    // 高精度モードを設定（こちらのほうがメトロノームの正確性が高い）
    _audioService.setPrecisionMode(PrecisionMode.highPrecision);
    debugLog('オーディオサービスを高精度モードに設定しました');

    // サウンドロードと再生
    _loadAndStartMetronome(settings.clickSoundType, _targetBpm);

    // フェーズ開始
    _experimentService.startPhase(
      ExperimentPhase.syncWithNaturalTempo,
      settings,
      () {
        // フェーズ完了時：誘導フェーズ1へ
        settings.setPhase(ExperimentPhase.rhythmGuidance1);
        _processPhaseChange(settings);
      },
    );
  }

  // メトロノームのロードと開始
  Future<void> _loadAndStartMetronome(
      String soundType, double targetBpm) async {
    try {
      // まず明示的にクリック音をロード
      debugLog('クリック音"$soundType"のロードを開始します');
      bool soundLoaded = await _audioService.loadClickSound(soundType);
      if (!soundLoaded) {
        debugLog('クリック音のロードに失敗しました');
        _showError('サウンドエラー', 'クリック音のロードに失敗しました');
        return;
      }

      debugLog('クリック音のロードに成功しました');

      // メトロノーム開始
      _audioService.startTempoCues(targetBpm);
      debugLog('メトロノームを開始しました: BPM = $targetBpm');
    } catch (e) {
      debugLog('メトロノーム開始エラー: $e');
      _showError('メトロノームエラー', 'メトロノームの開始に失敗しました: $e');
    }
  }

  // 誘導フェーズ1
  void _startGuidance1Phase(ExperimentSettings settings) {
    debugLog('誘導フェーズ1を開始します');

    _targetBpm = (settings.naturalTempo ?? 100.0) + settings.tempoIncrement;
    debugLog('目標テンポを更新: $_targetBpm BPM');

    _audioService.updateTempo(_targetBpm);
    debugLog('メトロノームのテンポを更新しました: $_targetBpm BPM');

    // フェーズ開始
    _experimentService.startPhase(
      ExperimentPhase.rhythmGuidance1,
      settings,
      () {
        // フェーズ完了時：誘導フェーズ2へ
        settings.setPhase(ExperimentPhase.rhythmGuidance2);
        _processPhaseChange(settings);
      },
    );
  }

  // 誘導フェーズ2
  void _startGuidance2Phase(ExperimentSettings settings) {
    debugLog('誘導フェーズ2を開始します');

    _targetBpm =
        (settings.naturalTempo ?? 100.0) + (settings.tempoIncrement * 2);
    debugLog('目標テンポを更新: $_targetBpm BPM');

    _audioService.updateTempo(_targetBpm);
    debugLog('メトロノームのテンポを更新しました: $_targetBpm BPM');

    // フェーズ開始
    _experimentService.startPhase(
      ExperimentPhase.rhythmGuidance2,
      settings,
      () {
        // フェーズ完了時：クールダウンフェーズへ
        settings.setPhase(ExperimentPhase.cooldown);
        _processPhaseChange(settings);
      },
    );
  }

  // クールダウンフェーズ
  void _startCooldownPhase(ExperimentSettings settings) {
    debugLog('クールダウンフェーズを開始します');

    _targetBpm = settings.naturalTempo ?? 100.0;
    debugLog('目標テンポを更新: $_targetBpm BPM');

    _audioService.updateTempo(_targetBpm);
    debugLog('メトロノームのテンポを更新しました: $_targetBpm BPM');

    // フェーズ開始
    _experimentService.startPhase(
      ExperimentPhase.cooldown,
      settings,
      () {
        // フェーズ完了時：実験完了
        settings.setPhase(ExperimentPhase.completed);
        _processPhaseChange(settings);
      },
    );
  }

  // 実験完了
  void _completeExperiment() async {
    debugLog('実験を完了します');

    // オーディオ停止
    _audioService.stopTempoCues();
    debugLog('オーディオを停止しました');

    // センサー停止
    _sensorService.stopSensing();
    debugLog('センサーを停止しました');

    // 実験セッション完了
    await _experimentService.completeExperimentSession();
    debugLog('実験セッションを完了しました');

    // 結果画面に遷移
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => ResultsScreen(sessionId: _sessionId!),
      ),
    );
    debugLog('結果画面に遷移します: セッションID = $_sessionId');
  }

  @override
  void dispose() {
    debugLog('実験画面のリソースを解放します');

    // 購読のキャンセル
    _gaitRhythmSubscription?.cancel();
    _gaitDataSubscription?.cancel();
    debugLog('購読をキャンセルしました');

    // フェーズタイマーのキャンセル
    _experimentService.cancelCurrentPhase();
    debugLog('フェーズタイマーをキャンセルしました');

    // オーディオ停止
    if (_audioService.isPlaying) {
      _audioService.stopTempoCues();
      debugLog('オーディオを停止しました');
    }

    super.dispose();
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
          const Text('実験を準備中...', style: TextStyle(fontSize: 18)),
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

  // フェーズ表示部分の改善
  Widget _buildPhaseDisplay(ExperimentSettings settings) {
    final phaseText = _getPhaseDisplayText(settings.currentPhase);
    final phaseIcon = _getPhaseIcon(settings.currentPhase);
    final phaseColor = _getPhaseColor(settings.currentPhase);

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: phaseColor.withOpacity(0.5), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(phaseIcon, color: phaseColor, size: 28),
                const SizedBox(width: 10),
                Text(
                  '現在のフェーズ: $phaseText',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: phaseColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            PhaseTimer(
              phase: settings.currentPhase,
              settings: settings,
            ),
            if (settings.currentPhase != ExperimentPhase.idle &&
                settings.currentPhase != ExperimentPhase.completed)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  _getPhaseInstructions(settings.currentPhase),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[700],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // リズム表示部分の改善
  Widget _buildRhythmDisplay(
      double currentBpm, double targetBpm, ExperimentSettings settings) {
    final bool showTarget =
        settings.currentPhase != ExperimentPhase.silentWalking &&
            settings.currentPhase != ExperimentPhase.calibration &&
            targetBpm > 0;

    final double diff = showTarget ? currentBpm - targetBpm : 0.0;
    final bool isInSync = showTarget && diff.abs() < 3.0;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              'リズム情報',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 現在のリズム
                TempoDisplay(
                  title: '現在の歩行リズム',
                  tempo: currentBpm,
                  color: Colors.blue,
                ),

                // 目標テンポ（無音時以外）
                if (showTarget)
                  TempoDisplay(
                    title: '目標テンポ',
                    tempo: targetBpm,
                    color: Colors.green,
                  ),
              ],
            ),

            // 同期状態の表示
            if (showTarget)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isInSync ? Icons.check_circle : Icons.info,
                      color: isInSync ? Colors.green : Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isInSync
                          ? 'リズムが同期しています'
                          : (diff > 0
                              ? '目標より ${diff.abs().toStringAsFixed(1)} BPM 速いです'
                              : '目標より ${diff.abs().toStringAsFixed(1)} BPM 遅いです'),
                      style: TextStyle(
                        color: isInSync ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // グラフ表示部分の改善
  Widget _buildRhythmGraph(
      List<FlSpot> dataPoints, double targetBpm, ExperimentSettings settings) {
    final bool showTarget =
        settings.currentPhase != ExperimentPhase.silentWalking &&
            settings.currentPhase != ExperimentPhase.calibration &&
            targetBpm > 0;

    // データが空の場合はロード中の表示
    if (dataPoints.isEmpty) {
      return Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          height: 300,
          padding: const EdgeInsets.all(16.0),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('データ収集中...'),
              ],
            ),
          ),
        ),
      );
    }

    // Y軸の最小値と最大値を計算
    final double minY =
        (dataPoints.map((p) => p.y).reduce((a, b) => a < b ? a : b) - 10)
            .clamp(0, double.infinity);
    final double maxY =
        dataPoints.map((p) => p.y).reduce((a, b) => a > b ? a : b) + 10;
    final double maxX = dataPoints.last.x + 0.5; // グラフの右端に余白を追加

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.show_chart, size: 20, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  '歩行リズム推移',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 250,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: 10,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: Colors.grey.withOpacity(0.3),
                        strokeWidth: 1,
                      );
                    },
                    getDrawingVerticalLine: (value) {
                      return FlLine(
                        color: Colors.grey.withOpacity(0.2),
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 20,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: false,
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
                    border: Border.all(color: Colors.grey.withOpacity(0.5)),
                  ),
                  minX: 0,
                  maxX: dataPoints.length.toDouble() - 1,
                  minY: minY,
                  maxY: maxY,
                  lineBarsData: [
                    // 実際の歩行リズム
                    LineChartBarData(
                      spots: dataPoints,
                      isCurved: true,
                      color: Colors.blue,
                      barWidth: 3,
                      dotData: FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.blue.withOpacity(0.1),
                      ),
                    ),
                    // 目標テンポ
                    if (showTarget)
                      LineChartBarData(
                        spots: [
                          FlSpot(0, targetBpm),
                          FlSpot(dataPoints.length.toDouble() - 1, targetBpm),
                        ],
                        isCurved: false,
                        color: Colors.green.withOpacity(0.7),
                        barWidth: 2,
                        dotData: FlDotData(show: false),
                        belowBarData: BarAreaData(show: false),
                        dashArray: [5, 5],
                      ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      tooltipBgColor: Colors.blueGrey.withOpacity(0.8),
                      getTooltipItems: (List<LineBarSpot> touchedSpots) {
                        return touchedSpots.map((barSpot) {
                          final flSpot = barSpot;
                          return LineTooltipItem(
                            '${flSpot.y.toStringAsFixed(1)} BPM',
                            const TextStyle(color: Colors.white),
                          );
                        }).toList();
                      },
                    ),
                    handleBuiltInTouches: true,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem('歩行リズム', Colors.blue),
                const SizedBox(width: 16),
                if (showTarget) _buildLegendItem('目標テンポ', Colors.green),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 凡例アイテムの構築
  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 3,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  // 実験中止の確認ダイアログ
  Future<void> _confirmAbortExperiment() async {
    debugLog('実験中止の確認ダイアログを表示します');

    final shouldAbort = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('実験中止'),
            content: const Text('実験を中止してもよろしいですか？\n\n中止した場合でもこれまでのデータは保存されます。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('キャンセル'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('中止する'),
              ),
            ],
          ),
        ) ??
        false;

    if (shouldAbort) {
      debugLog('実験を中止します');

      // オーディオ停止
      _audioService.stopTempoCues();
      debugLog('オーディオを停止しました');

      // センサー停止
      _sensorService.stopSensing();
      debugLog('センサーを停止しました');

      // 実験セッション完了
      if (_sessionId != null) {
        await _experimentService.completeExperimentSession();
        debugLog('実験セッションを完了しました: セッションID = $_sessionId');
      }

      // ホーム画面に戻る
      if (!mounted) return;
      Navigator.of(context).pop();
      debugLog('ホーム画面に戻ります');
    } else {
      debugLog('実験中止をキャンセルしました');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<ExperimentSettings>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('歩行リズム実験'),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          // キャリブレーションボタン
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'センサーキャリブレーション',
            onPressed: () {
              debugLog('キャリブレーションボタンがタップされました');
              _navigateToCalibration();
            },
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
                    // フェーズ表示
                    _buildPhaseDisplay(settings),

                    const SizedBox(height: 16),

                    // リズム表示
                    _buildRhythmDisplay(_currentBpm, _targetBpm, settings),

                    const SizedBox(height: 16),

                    // グラフ表示
                    Expanded(
                      child: _buildRhythmGraph(
                          _rhythmDataPoints, _targetBpm, settings),
                    ),

                    const SizedBox(height: 16),

                    // 実験中止ボタン
                    Align(
                      alignment: Alignment.center,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.stop),
                        label: const Text('実験中止'),
                        onPressed: _confirmAbortExperiment,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  // フェーズ表示テキスト
  String _getPhaseDisplayText(ExperimentPhase phase) {
    switch (phase) {
      case ExperimentPhase.calibration:
        return 'キャリブレーション';
      case ExperimentPhase.silentWalking:
        return '無音歩行';
      case ExperimentPhase.syncWithNaturalTempo:
        return '自然リズムと同期';
      case ExperimentPhase.rhythmGuidance1:
        return 'リズム誘導 1';
      case ExperimentPhase.rhythmGuidance2:
        return 'リズム誘導 2';
      case ExperimentPhase.cooldown:
        return 'クールダウン';
      case ExperimentPhase.completed:
        return '実験完了';
      default:
        return '準備中';
    }
  }

  // 各フェーズに対応するアイコンを取得
  IconData _getPhaseIcon(ExperimentPhase phase) {
    switch (phase) {
      case ExperimentPhase.calibration:
        return Icons.tune;
      case ExperimentPhase.silentWalking:
        return Icons.volume_off;
      case ExperimentPhase.syncWithNaturalTempo:
        return Icons.sync;
      case ExperimentPhase.rhythmGuidance1:
        return Icons.trending_up;
      case ExperimentPhase.rhythmGuidance2:
        return Icons.trending_up;
      case ExperimentPhase.cooldown:
        return Icons.arrow_downward;
      case ExperimentPhase.completed:
        return Icons.check_circle;
      default:
        return Icons.hourglass_empty;
    }
  }

  // 各フェーズに対応する色を取得
  Color _getPhaseColor(ExperimentPhase phase) {
    switch (phase) {
      case ExperimentPhase.calibration:
        return Colors.blue;
      case ExperimentPhase.silentWalking:
        return Colors.purple;
      case ExperimentPhase.syncWithNaturalTempo:
        return Colors.green;
      case ExperimentPhase.rhythmGuidance1:
        return Colors.orange;
      case ExperimentPhase.rhythmGuidance2:
        return Colors.deepOrange;
      case ExperimentPhase.cooldown:
        return Colors.teal;
      case ExperimentPhase.completed:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  // 各フェーズの説明テキストを取得
  String _getPhaseInstructions(ExperimentPhase phase) {
    switch (phase) {
      case ExperimentPhase.calibration:
        return 'センサーをキャリブレーションしています。自然に歩いてください。';
      case ExperimentPhase.silentWalking:
        return '無音状態で自然に歩いてください。あなたの自然な歩行リズムを測定します。';
      case ExperimentPhase.syncWithNaturalTempo:
        return '音に合わせて歩くようにしてください。この音はあなたの自然な歩行リズムです。';
      case ExperimentPhase.rhythmGuidance1:
        return '音に合わせて歩くようにしてください。テンポがわずかに上昇しています。';
      case ExperimentPhase.rhythmGuidance2:
        return '音に合わせて歩くようにしてください。テンポがさらに上昇しています。';
      case ExperimentPhase.cooldown:
        return '自然なリズムに戻ります。リラックスして歩いてください。';
      default:
        return '';
    }
  }
}
