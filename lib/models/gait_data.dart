import 'dart:math' as math;

class AccelerometerData {
  final DateTime timestamp;
  final double x;
  final double y;
  final double z;
  final double magnitude;

  AccelerometerData({
    required this.timestamp,
    required this.x,
    required this.y,
    required this.z,
  }) : magnitude = _calculateMagnitude(x, y, z);

  static double _calculateMagnitude(double x, double y, double z) {
    return math.sqrt(x * x + y * y + z * z);
  }

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.millisecondsSinceEpoch,
      'x': x,
      'y': y,
      'z': z,
      'magnitude': magnitude,
    };
  }

  factory AccelerometerData.fromMap(Map<String, dynamic> map) {
    return AccelerometerData(
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      x: map['x'],
      y: map['y'],
      z: map['z'],
    );
  }
}

class GaitRhythmData {
  final DateTime timestamp;
  final double bpm;
  final ExperimentPhaseData phase;
  final double targetBpm;

  GaitRhythmData({
    required this.timestamp,
    required this.bpm,
    required this.phase,
    required this.targetBpm,
  });

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.millisecondsSinceEpoch,
      'bpm': bpm,
      'phase': phase.toString(),
      'targetBpm': targetBpm,
    };
  }

  factory GaitRhythmData.fromMap(Map<String, dynamic> map) {
    return GaitRhythmData(
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      bpm: map['bpm'],
      phase: ExperimentPhaseData.fromString(map['phase']),
      targetBpm: map['targetBpm'],
    );
  }
}

class ExperimentPhaseData {
  final String name;
  final DateTime startTime;
  final DateTime? endTime;
  final double? naturalTempo;
  final double? targetTempo;

  ExperimentPhaseData({
    required this.name,
    required this.startTime,
    this.endTime,
    this.naturalTempo,
    this.targetTempo,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime?.millisecondsSinceEpoch,
      'naturalTempo': naturalTempo,
      'targetTempo': targetTempo,
    };
  }

  factory ExperimentPhaseData.fromMap(Map<String, dynamic> map) {
    return ExperimentPhaseData(
      name: map['name'],
      startTime: DateTime.fromMillisecondsSinceEpoch(map['startTime']),
      endTime: map['endTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['endTime'])
          : null,
      naturalTempo: map['naturalTempo'],
      targetTempo: map['targetTempo'],
    );
  }

  static ExperimentPhaseData fromString(String phaseString) {
    // フェーズ名から適切なPhaseDataオブジェクトを作成
    final now = DateTime.now();
    return ExperimentPhaseData(
      name: phaseString,
      startTime: now,
    );
  }

  @override
  String toString() {
    return name;
  }
}

class ExperimentSession {
  final int id;
  final String subjectId;
  final DateTime startTime;
  final DateTime? endTime;
  final Map<String, dynamic> settings;
  final List<GaitRhythmData>? rhythmData;
  final List<ExperimentPhaseData>? phaseData;

  ExperimentSession({
    required this.id,
    required this.subjectId,
    required this.startTime,
    this.endTime,
    required this.settings,
    this.rhythmData,
    this.phaseData,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'subjectId': subjectId,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime?.millisecondsSinceEpoch,
      'settings': settings,
    };
  }

  factory ExperimentSession.fromMap(Map<String, dynamic> map) {
    return ExperimentSession(
      id: map['id'],
      subjectId: map['subjectId'],
      startTime: DateTime.fromMillisecondsSinceEpoch(map['startTime']),
      endTime: map['endTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['endTime'])
          : null,
      settings: map['settings'],
      rhythmData: null, // 別クエリで取得
      phaseData: null, // 別クエリで取得
    );
  }
}
