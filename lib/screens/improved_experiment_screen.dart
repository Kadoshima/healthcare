import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import '../models/experiment_settings.dart';
import '../models/gait_data.dart';
import '../services/sensor_service.dart';
import '../services/improved_audio_service.dart';
import '../services/experiment_service.dart';
import '../widgets/phase_timer.dart';
import '../widgets/tempo_display.dart';
import '../widgets/walking_rhythm_metrics.dart'; // 新しい精度メトリクス表示ウィジェット
import 'calibration_screen.dart'; // キャリブレーション画面
import 'results_screen.dart';

/// 改良版実験画面
///
/// 歩行リズム測定精度に関する情報を提供し、
/// キャリブレーション機能を統合
class ImprovedExperimentScreen extends StatefulWidget {
  const ImprovedExperimentScreen({Key? key}) : super(key: key);

  @override
  State<ImprovedExperimentScreen> createState() =>
      _ImprovedExperimentScreenState();
}

class _ImprovedExperimentScreenState extends State<ImprovedExperimentScreen> {
  // サービス
  late SensorService _sensorService;
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

  // 精度検証関連
  Timer? _verificationTimer;
  bool _isVerifying = false;
  int _verificationCount = 0;
  final int _maxVerifications = 3;

  // セッションID
  int? _sessionId;

  @override
  void initState() {
    super.initState();

    // サービスの取得
    _sensorService = Provider.of<SensorService>(context, listen: false);
    _audioService = Provider.of<ImprovedAudioService>(context, listen: false);
    _experimentService = Provider.of<ExperimentService>(context, listen: false);

    // オーディオサービスの初期化
    _audioService.initialize().then((_) {
      // 実験開始
      _startExperiment();
    });
  }

  // 実験開始
  Future<void> _startExperiment() async {
    final settings = Provider.of<ExperimentSettings>(context, listen: false);

    // 実験セッションの作成
    _sessionId = await _experimentService.startExperimentSession(settings);

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

    // センサー開始
    _sensorService.startSensing();

    // キャリブレーションから開始
    settings.startExperiment();
    _processPhaseChange(settings);

    // 精度検証のスケジュール
    _scheduleAccuracyVerification();
  }

  // 精度検証のスケジュール
  void _scheduleAccuracyVerification() {
    // 60秒ごとに精度検証を実行
    _verificationTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      // 精度検証回数の制限
      if (_verificationCount >= _maxVerifications) {
        timer.cancel();
        return;
      }

      final settings = Provider.of<ExperimentSettings>(context, listen: false);

      // 実験フェーズ中のみ検証
      if (settings.currentPhase == ExperimentPhase.syncWithNaturalTempo ||
          settings.currentPhase == ExperimentPhase.rhythmGuidance1 ||
          settings.currentPhase == ExperimentPhase.rhythmGuidance2) {
        // 精度検証実行
        _verifyMeasurementAccuracy();
        _verificationCount++;
      }
    });
  }

  // 測定精度の検証
  void _verifyMeasurementAccuracy() {
    final settings = Provider.of<ExperimentSettings>(context, listen: false);

    // 既知のBPM（現在の目標テンポ）
    final knownBpm = settings.getCurrentTempo();

    if (knownBpm <= 0) return; // テンポが無効な場合

    setState(() {
      _isVerifying = true;
    });

    // センサー精度の検証
    _sensorService.verifyAccuracy(knownBpm);

    // 検証状態の表示を3秒間表示
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _isVerifying = false;
        });
      }
    });
  }

  // フェーズ変更処理
  void _processPhaseChange(ExperimentSettings settings) {
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

        // 同期フェーズへ
        settings.setPhase(ExperimentPhase.syncWithNaturalTempo);
        _processPhaseChange(settings);
      },
    );
  }

  // 同期フェーズ
  void _startSyncPhase(ExperimentSettings settings) {
    _targetBpm = settings.naturalTempo ?? 100.0;
    _audioService.setVolume(settings.volume);

    // ImprovedAudioServiceでのロードと再生の方法に変更
    // 高精度モードを設定（こちらのほうがメトロノームの正確性が高い）
    _audioService.setPrecisionMode(PrecisionMode.highPrecision);

    _audioService.loadClickSound(settings.clickSoundType).then((_) {
      _audioService.startTempoCues(_targetBpm);
    });

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

  // 誘導フェーズ1
  void _startGuidance1Phase(ExperimentSettings settings) {
    _targetBpm = (settings.naturalTempo ?? 100.0) + settings.tempoIncrement;
    _audioService.updateTempo(_targetBpm);

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
    _targetBpm =
        (settings.naturalTempo ?? 100.0) + (settings.tempoIncrement * 2);
    _audioService.updateTempo(_targetBpm);

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
    _targetBpm = settings.naturalTempo ?? 100.0;
    _audioService.updateTempo(_targetBpm);

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
    // オーディオ停止
    _audioService.stopTempoCues();

    // センサー停止
    _sensorService.stopSensing();

    // 実験セッション完了
    await _experimentService.completeExperimentSession();

    // 結果画面に遷移
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => ResultsScreen(sessionId: _sessionId!),
      ),
    );
  }

  @override
  void dispose() {
    // 購読のキャンセル
    _gaitRhythmSubscription?.cancel();
    _gaitDataSubscription?.cancel();

    // フェーズタイマーのキャンセル
    _experimentService.cancelCurrentPhase();

    // 検証タイマーのキャンセル
    _verificationTimer?.cancel();

    super.dispose();
  }

  // キャリブレーション画面に遷移
  void _navigateToCalibration() async {
    final settings = Provider.of<ExperimentSettings>(context, listen: false);

    // 現在のフェーズを一時保存
    final currentPhase = settings.currentPhase;

    // メトロノームを一時停止
    final wasPlaying = _targetBpm > 0;
    if (wasPlaying) {
      _audioService.stopTempoCues();
    }

    // キャリブレーション画面に遷移
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const CalibrationScreen(),
      ),
    );

    // 戻ってきたらメトロノームを再開
    if (wasPlaying && mounted) {
      _audioService.startTempoCues(_targetBpm);
    }

    // 更新を反映させる
    setState(() {});
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

  // 測定精度メトリクス表示
  Widget _buildAccuracyMetrics() {
    return WalkingRhythmMetrics(
      showDetailed: true,
      onCalibrateTap: _navigateToCalibration,
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
                const Icon(Icons.show_chart, size: 20),
                const SizedBox(width: 8),
                Text(
                  '歩行リズム推移',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                // 精度検証中の表示
                if (_isVerifying)
                  Chip(
                    label: const Text('精度検証中'),
                    avatar: const Icon(Icons.analytics, size: 16),
                    backgroundColor: Colors.lightBlue.withOpacity(0.2),
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
                    horizontalInterval: 20,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: Colors.grey.withOpacity(0.3),
                        strokeWidth: 1,
                      );
                    },
                    getDrawingVerticalLine: (value) {
                      return FlLine(
                        color: Colors.grey.withOpacity(0.3),
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
      // オーディオ停止
      _audioService.stopTempoCues();

      // センサー停止
      _sensorService.stopSensing();

      // 実験セッション完了
      if (_sessionId != null) {
        await _experimentService.completeExperimentSession();
      }

      // ホーム画面に戻る
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<ExperimentSettings>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('歩行リズム実験 (改良版)'),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          // キャリブレーションボタン
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'センサーキャリブレーション',
            onPressed: _navigateToCalibration,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // フェーズ表示
              _buildPhaseDisplay(settings),

              const SizedBox(height: 16),

              // 測定精度メトリクス
              _buildAccuracyMetrics(),

              const SizedBox(height: 16),

              // リズム表示
              _buildRhythmDisplay(_currentBpm, _targetBpm, settings),

              const SizedBox(height: 16),

              // グラフ表示
              Expanded(
                child:
                    _buildRhythmGraph(_rhythmDataPoints, _targetBpm, settings),
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
