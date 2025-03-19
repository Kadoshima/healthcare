import 'dart:async';
import 'package:flutter/material.dart';
import '../models/experiment_settings.dart';

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

  @override
  void initState() {
    super.initState();
    _initTimer();
  }

  @override
  void didUpdateWidget(PhaseTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) {
      _timer?.cancel();
      _initTimer();
    }
  }

  // タイマーの初期化
  void _initTimer() {
    if (widget.phase == ExperimentPhase.idle ||
        widget.phase == ExperimentPhase.completed) {
      setState(() {
        _remainingSeconds = 0;
        _progress = 0.0;
      });
      return;
    }

    // 現在のフェーズの持続時間を取得
    int phaseDuration;
    switch (widget.phase) {
      case ExperimentPhase.calibration:
        phaseDuration = widget.settings.calibrationDuration;
        break;
      case ExperimentPhase.silentWalking:
        phaseDuration = widget.settings.silentWalkingDuration;
        break;
      case ExperimentPhase.syncWithNaturalTempo:
        phaseDuration = widget.settings.syncDuration;
        break;
      case ExperimentPhase.rhythmGuidance1:
        phaseDuration = widget.settings.guidance1Duration;
        break;
      case ExperimentPhase.rhythmGuidance2:
        phaseDuration = widget.settings.guidance2Duration;
        break;
      case ExperimentPhase.cooldown:
        phaseDuration = widget.settings.cooldownDuration;
        break;
      default:
        phaseDuration = 0;
    }

    // フェーズ開始時間から経過時間を計算
    final phaseStartTime = widget.settings.currentPhaseStartTime;
    if (phaseStartTime == null) {
      setState(() {
        _remainingSeconds = phaseDuration;
        _progress = 0.0;
      });
    } else {
      final elapsedSeconds =
          DateTime.now().difference(phaseStartTime).inSeconds;
      final remaining = phaseDuration - elapsedSeconds;

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
      if (_remainingSeconds <= 0) {
        timer.cancel();
        return;
      }

      setState(() {
        _remainingSeconds--;
        _progress = 1.0 - (_remainingSeconds / phaseDuration);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // フェーズが待機中または完了の場合は表示しない
    if (widget.phase == ExperimentPhase.idle ||
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
        Text(
          '残り時間: $timeText',
          style: const TextStyle(fontWeight: FontWeight.bold),
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
