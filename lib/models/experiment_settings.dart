import 'package:flutter/foundation.dart';

enum ExperimentPhase {
  idle,
  calibration,
  silentWalking,
  syncWithNaturalTempo,
  rhythmGuidance1,
  rhythmGuidance2,
  cooldown,
  completed
}

class ExperimentSettings extends ChangeNotifier {
  // 被験者情報
  String subjectId = '';
  int? subjectAge;
  String subjectGender = '';

  // 実験フェーズ設定
  int calibrationDuration = 30; // 秒
  int silentWalkingDuration = 180; // 3分間
  int syncDuration = 300; // 5分間
  int guidance1Duration = 300; // 5分間
  int guidance2Duration = 300; // 5分間
  int cooldownDuration = 120; // 2分間

  // テンポ設定
  double? naturalTempo; // 自然歩行リズム（bpm）
  double tempoIncrement = 5.0; // テンポ上昇幅（bpm）

  // 計測設定
  String sensorPosition = '腰部'; // センサー装着位置
  int samplingRate = 50; // Hz

  // 音設定
  String clickSoundType = '標準クリック';
  double volume = 0.7; // 0.0 〜 1.0
  bool useImprovedAudio = true; // 改良版オーディオエンジンを使用するか

  // 実験状態
  ExperimentPhase currentPhase = ExperimentPhase.idle;
  DateTime? experimentStartTime;
  DateTime? currentPhaseStartTime;

  // 自然歩行リズム設定
  void setNaturalTempo(double tempo) {
    naturalTempo = tempo;
    notifyListeners();
  }

  // フェーズ変更
  void setPhase(ExperimentPhase phase) {
    currentPhase = phase;
    currentPhaseStartTime = DateTime.now();
    notifyListeners();
  }

  // 被験者情報設定
  void setSubjectInfo({required String id, int? age, required String gender}) {
    subjectId = id;
    subjectAge = age;
    subjectGender = gender;
    notifyListeners();
  }

  // 実験設定更新
  void updateExperimentDurations({
    int? calibration,
    int? silentWalking,
    int? sync,
    int? guidance1,
    int? guidance2,
    int? cooldown,
  }) {
    if (calibration != null) calibrationDuration = calibration;
    if (silentWalking != null) silentWalkingDuration = silentWalking;
    if (sync != null) syncDuration = sync;
    if (guidance1 != null) guidance1Duration = guidance1;
    if (guidance2 != null) guidance2Duration = guidance2;
    if (cooldown != null) cooldownDuration = cooldown;
    notifyListeners();
  }

  // テンポ設定更新
  void updateTempoSettings({double? increment}) {
    if (increment != null) tempoIncrement = increment;
    notifyListeners();
  }

  // 音設定更新
  void updateSoundSettings(
      {String? soundType, double? newVolume, bool? useImprovedAudio}) {
    if (soundType != null) clickSoundType = soundType;
    if (newVolume != null) volume = newVolume;
    if (useImprovedAudio != null) this.useImprovedAudio = useImprovedAudio;
    notifyListeners();
  }

  // 現在のフェーズでのテンポ取得
  double getCurrentTempo() {
    if (naturalTempo == null) return 100.0; // デフォルト値

    switch (currentPhase) {
      case ExperimentPhase.silentWalking:
        return 0.0; // 無音
      case ExperimentPhase.syncWithNaturalTempo:
        return naturalTempo!;
      case ExperimentPhase.rhythmGuidance1:
        return naturalTempo! + tempoIncrement;
      case ExperimentPhase.rhythmGuidance2:
        return naturalTempo! + (tempoIncrement * 2);
      case ExperimentPhase.cooldown:
        return naturalTempo!;
      default:
        return 0.0;
    }
  }

  // 実験開始
  void startExperiment() {
    experimentStartTime = DateTime.now();
    setPhase(ExperimentPhase.calibration);
  }

  // 実験終了
  void completeExperiment() {
    setPhase(ExperimentPhase.completed);
  }

  // 実験リセット
  void resetExperiment() {
    currentPhase = ExperimentPhase.idle;
    experimentStartTime = null;
    currentPhaseStartTime = null;
    naturalTempo = null;
    notifyListeners();
  }
}
