import 'dart:async';
import 'package:flutter/material.dart';
import '../models/experiment_settings.dart';

// グローバルなデバッグロギング用（main.dartと合わせる）
bool debugMode = true;
void debugLog(String message) {
  if (debugMode) {
    print('[DEBUG] $message');
  }
}

class PhaseTimer extends StatefulWidget {
  final ExperimentPhase phase;
  final ExperimentSettings settings;

  const PhaseTimer({
    Key? key,
    required this.phase,
    required this.settings,
  }) : super(key: key);

  @override
  State<PhaseTimer> createState() => _PhaseTimerState();
}

class _PhaseTimerState extends State<PhaseTimer> {
  Timer? _timer;
  int _remainingSeconds = 0;
  double _progress = 0.0;
  bool _isActive = false;

  @override
  void initState() {
    super.initState();
    debugLog('PhaseTimer: タイマーを初期化します。フェーズ: ${widget.phase}');
    _initTimer();
  }

  @override
  void didUpdateWidget(PhaseTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) {
      debugLog(
          'PhaseTimer: フェーズが変更されました: ${oldWidget.phase} -> ${widget.phase}');
      _timer?.cancel();
      _initTimer();
    }
  }

  // タイマーの初期化 - 改良版
  void _initTimer() {
    if (widget.phase == ExperimentPhase.idle ||
        widget.phase == ExperimentPhase.completed) {
      debugLog('PhaseTimer: フェーズが idle または completed のため、タイマーを開始しません');
      setState(() {
        _remainingSeconds = 0;
        _progress = 0.0;
        _isActive = false;
      });
      return;
    }

    debugLog('PhaseTimer: タイマーを初期化します: フェーズ ${widget.phase}');
    setState(() {
      _isActive = true;
    });

    // 現在のフェーズの持続時間を取得
    int phaseDuration = _getPhaseDuration(widget.phase, widget.settings);
    debugLog('PhaseTimer: フェーズ持続時間: $phaseDuration 秒');

    // フェーズ開始時間から経過時間を計算
    final phaseStartTime = widget.settings.currentPhaseStartTime;
    if (phaseStartTime == null) {
      debugLog('PhaseTimer: フェーズ開始時間が設定されていません。フル持続時間を使用します');
      setState(() {
        _remainingSeconds = phaseDuration;
        _progress = 0.0;
      });
    } else {
      final elapsedSeconds =
          DateTime.now().difference(phaseStartTime).inSeconds;
      final remaining = phaseDuration - elapsedSeconds;

      debugLog('PhaseTimer: 経過時間: $elapsedSeconds 秒, 残り時間: $remaining 秒');

      setState(() {
        _remainingSeconds = remaining > 0 ? remaining : 0;
        _progress = elapsedSeconds / phaseDuration;
        if (_progress > 1.0) _progress = 1.0;
        if (_progress < 0.0) _progress = 0.0;
      });
    }

    // タイマーの開始
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      debugLog(
          'PhaseTimer: タイマーカウントダウン: $_remainingSeconds -> ${_remainingSeconds - 1} 秒');
      if (_remainingSeconds <= 0) {
        debugLog('PhaseTimer: タイマー終了');
        timer.cancel();
        return;
      }

      setState(() {
        _remainingSeconds--;
        _progress = 1.0 - (_remainingSeconds / phaseDuration);
      });
    });
  }

  // フェーズに応じた持続時間を取得
  int _getPhaseDuration(ExperimentPhase phase, ExperimentSettings settings) {
    switch (phase) {
      case ExperimentPhase.calibration:
        return settings.calibrationDuration;
      case ExperimentPhase.silentWalking:
        return settings.silentWalkingDuration;
      case ExperimentPhase.syncWithNaturalTempo:
        return settings.syncDuration;
      case ExperimentPhase.rhythmGuidance1:
        return settings.guidance1Duration;
      case ExperimentPhase.rhythmGuidance2:
        return settings.guidance2Duration;
      case ExperimentPhase.cooldown:
        return settings.cooldownDuration;
      default:
        return 0;
    }
  }

  @override
  void dispose() {
    debugLog('PhaseTimer: リソースを解放します');
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // フェーズが待機中または完了の場合は表示しない
    if (!_isActive ||
        widget.phase == ExperimentPhase.idle ||
        widget.phase == ExperimentPhase.completed) {
      return const SizedBox.shrink();
    }

    // 残り時間の表示形式
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    final timeText =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Column(
      children: [
        // プログレスバー
        LinearProgressIndicator(
          value: _progress,
          minHeight: 10,
          backgroundColor: Colors.grey.shade200,
          valueColor: AlwaysStoppedAnimation<Color>(
            _getProgressColor(_progress),
          ),
        ),

        const SizedBox(height: 8),

        // 残り時間
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.timer, size: 16),
            const SizedBox(width: 4),
            Text(
              '残り時間: $timeText',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }

  // 進行状況に基づいた色の取得
  Color _getProgressColor(double progress) {
    if (progress < 0.5) {
      return Colors.green;
    } else if (progress < 0.8) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }
}
