import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'dart:io';

import '../models/experiment_settings.dart';
import '../models/gait_data.dart';
import 'database_service.dart';
import 'azure_storage_service.dart';

class ExperimentService {
  final DatabaseService _database;

  // 現在の実験セッション
  int? _currentSessionId;
  Timer? _phaseTimer;

  // データストリームコントローラー
  final _gaitDataController = StreamController<GaitRhythmData>.broadcast();

  // 実験データ
  final List<GaitRhythmData> _sessionGaitData = [];
  final List<ExperimentPhaseData> _sessionPhaseData = [];

  // 公開ストリーム
  Stream<GaitRhythmData> get gaitDataStream => _gaitDataController.stream;

  // コンストラクタ
  ExperimentService(this._database);

  // 実験セッション開始
  Future<int> startExperimentSession(ExperimentSettings settings) async {
    final sessionId = await _database.createExperimentSession(
      subjectId: settings.subjectId,
      startTime: DateTime.now(),
      settings: {
        'calibrationDuration': settings.calibrationDuration,
        'silentWalkingDuration': settings.silentWalkingDuration,
        'syncDuration': settings.syncDuration,
        'guidance1Duration': settings.guidance1Duration,
        'guidance2Duration': settings.guidance2Duration,
        'cooldownDuration': settings.cooldownDuration,
        'tempoIncrement': settings.tempoIncrement,
        'sensorPosition': settings.sensorPosition,
        'samplingRate': settings.samplingRate,
        'clickSoundType': settings.clickSoundType,
        'volume': settings.volume,
      },
    );

    _currentSessionId = sessionId;
    _sessionGaitData.clear();
    _sessionPhaseData.clear();

    return sessionId;
  }

  // 実験フェーズ開始
  void startPhase(ExperimentPhase phase, ExperimentSettings settings,
      Function onPhaseComplete) {
    // 現在のフェーズのデータを記録
    final phaseData = ExperimentPhaseData(
      name: phase.toString(),
      startTime: DateTime.now(),
      naturalTempo: settings.naturalTempo,
      targetTempo: settings.getCurrentTempo(),
    );

    _sessionPhaseData.add(phaseData);

    // フェーズの持続時間を取得
    int phaseDuration;
    switch (phase) {
      case ExperimentPhase.calibration:
        phaseDuration = settings.calibrationDuration;
        break;
      case ExperimentPhase.silentWalking:
        phaseDuration = settings.silentWalkingDuration;
        break;
      case ExperimentPhase.syncWithNaturalTempo:
        phaseDuration = settings.syncDuration;
        break;
      case ExperimentPhase.rhythmGuidance1:
        phaseDuration = settings.guidance1Duration;
        break;
      case ExperimentPhase.rhythmGuidance2:
        phaseDuration = settings.guidance2Duration;
        break;
      case ExperimentPhase.cooldown:
        phaseDuration = settings.cooldownDuration;
        break;
      default:
        phaseDuration = 0;
    }

    // フェーズタイマーをセット
    _phaseTimer?.cancel();
    if (phaseDuration > 0) {
      _phaseTimer = Timer(Duration(seconds: phaseDuration), () {
        // フェーズ終了処理
        final updatedPhaseData = _sessionPhaseData.last.copyWith(
          endTime: DateTime.now(),
        );
        _sessionPhaseData[_sessionPhaseData.length - 1] = updatedPhaseData;

        // フェーズ完了コールバック
        onPhaseComplete();
      });
    }
  }

  // フェーズキャンセル
  void cancelCurrentPhase() {
    _phaseTimer?.cancel();
    _phaseTimer = null;

    // 現在のフェーズのデータを更新
    if (_sessionPhaseData.isNotEmpty) {
      final updatedPhaseData = _sessionPhaseData.last.copyWith(
        endTime: DateTime.now(),
      );
      _sessionPhaseData[_sessionPhaseData.length - 1] = updatedPhaseData;
    }
  }

  // 歩行リズムデータの追加
  void addGaitRhythmData(double bpm, ExperimentPhase phase, double targetBpm) {
    if (_currentSessionId == null) return;

    final data = GaitRhythmData(
      timestamp: DateTime.now(),
      bpm: bpm,
      phase: ExperimentPhaseData.fromString(phase.toString()),
      targetBpm: targetBpm,
    );

    _sessionGaitData.add(data);
    _gaitDataController.add(data);

    // 定期的にデータベースに保存（メモリ使用量削減のため）
    if (_sessionGaitData.length % 100 == 0) {
      _saveGaitDataBatch();
    }
  }

  // 歩行リズムデータのバッチ保存
  Future<void> _saveGaitDataBatch() async {
    if (_currentSessionId == null || _sessionGaitData.isEmpty) return;

    final batchData = List<GaitRhythmData>.from(_sessionGaitData);
    _sessionGaitData.clear();

    try {
      await _database.addGaitRhythmDataBatch(
        _currentSessionId!,
        batchData,
      );
    } catch (e) {
      debugPrint('歩行リズムデータ保存エラー: $e');
      // エラー発生時はデータを復元
      _sessionGaitData.insertAll(0, batchData);
    }
  }

  // 実験セッション完了
  Future<void> completeExperimentSession() async {
    if (_currentSessionId == null) return;

    // 残りのデータをデータベースに保存
    await _saveGaitDataBatch();

    // フェーズデータを保存
    for (var phaseData in _sessionPhaseData) {
      await _database.addPhaseData(_currentSessionId!, phaseData);
    }

    // セッションを完了状態に更新
    await _database.updateExperimentSession(
      _currentSessionId!,
      endTime: DateTime.now(),
    );

    _phaseTimer?.cancel();
    _phaseTimer = null;
    _currentSessionId = null;
  }

  // データのCSVエクスポート
  Future<String> exportSessionDataToCsv(int sessionId) async {
    try {
      // セッション情報の取得
      final session = await _database.getExperimentSession(sessionId);

      // 歩行リズムデータの取得
      final rhythmData = await _database.getGaitRhythmData(sessionId);

      // フェーズデータの取得
      final phaseData = await _database.getPhaseData(sessionId);

      // ドキュメントディレクトリの取得
      final directory = await getApplicationDocumentsDirectory();
      final path = directory.path;

      // セッション情報ファイル
      final sessionInfoFile = File('$path/session_${sessionId}_info.json');
      await sessionInfoFile.writeAsString(jsonEncode(session.toMap()));

      // 歩行リズムデータCSV
      final rhythmDataCsv = [
        ['timestamp', 'bpm', 'phase', 'targetBpm'], // ヘッダー
        ...rhythmData.map((data) => [
              data.timestamp.toIso8601String(),
              data.bpm,
              data.phase.toString(),
              data.targetBpm,
            ]),
      ];

      final rhythmDataString =
          const ListToCsvConverter().convert(rhythmDataCsv);
      final rhythmFile = File('$path/session_${sessionId}_rhythm_data.csv');
      await rhythmFile.writeAsString(rhythmDataString);

      // フェーズデータCSV
      final phaseDataCsv = [
        ['name', 'startTime', 'endTime', 'naturalTempo', 'targetTempo'], // ヘッダー
        ...phaseData.map((data) => [
              data.name,
              data.startTime.toIso8601String(),
              data.endTime?.toIso8601String() ?? '',
              data.naturalTempo ?? '',
              data.targetTempo ?? '',
            ]),
      ];

      final phaseDataString = const ListToCsvConverter().convert(phaseDataCsv);
      final phaseFile = File('$path/session_${sessionId}_phase_data.csv');
      await phaseFile.writeAsString(phaseDataString);

      // 分析結果のエクスポート
      await _exportAnalysisResults(sessionId, path, rhythmData, phaseData);

      return path;
    } catch (e) {
      debugPrint('データエクスポートエラー: $e');
      rethrow;
    }
  }

  // 分析結果のエクスポート
  Future<void> _exportAnalysisResults(
      int sessionId,
      String exportPath,
      List<GaitRhythmData> rhythmData,
      List<ExperimentPhaseData> phaseData) async {
    try {
      // 分析を実行
      final analysisResults = _analyzeExperimentData(rhythmData, phaseData);

      // 分析結果をJSONで保存
      final analysisFile =
          File('$exportPath/session_${sessionId}_analysis.json');
      await analysisFile.writeAsString(jsonEncode(analysisResults));

      // 分析サマリーをCSVで保存
      final summaryCsv = [
        ['metric', 'value', 'unit', 'description'], // ヘッダー
      ];

      // 分析結果をCSVに変換
      analysisResults.forEach((key, value) {
        String unit = '';
        String description = '';

        // メトリクスの単位と説明を設定
        if (key.contains('bpm') || key.contains('Tempo')) {
          unit = 'BPM';
          description = '歩行リズム';
        } else if (key.contains('stdDev')) {
          unit = 'BPM';
          description = '標準偏差';
        } else if (key.contains('diff')) {
          unit = 'BPM';
          description = '目標テンポとの差';
        } else if (key.contains('Percentage')) {
          unit = '%';
          description = 'パーセンテージ';
        } else if (key.contains('cv')) {
          unit = '';
          description = '変動係数';
        }

        summaryCsv.add([key, value.toString(), unit, description]);
      });

      final summaryString = const ListToCsvConverter().convert(summaryCsv);
      final summaryFile = File('$exportPath/session_${sessionId}_summary.csv');
      await summaryFile.writeAsString(summaryString);
    } catch (e) {
      debugPrint('分析結果エクスポートエラー: $e');
    }
  }

  // 実験データの分析
  Map<String, dynamic> _analyzeExperimentData(
    List<GaitRhythmData> rhythmData,
    List<ExperimentPhaseData> phaseData,
  ) {
    final results = <String, dynamic>{};

    if (rhythmData.isEmpty || phaseData.isEmpty) {
      return results;
    }

    // 自然歩行リズム（無音フェーズの平均）
    final silentPhaseData = rhythmData
        .where((data) => data.phase.name.contains('silentWalking'))
        .toList();

    if (silentPhaseData.isNotEmpty) {
      final silentBpms = silentPhaseData.map((data) => data.bpm).toList();
      final naturalTempo =
          silentBpms.reduce((a, b) => a + b) / silentBpms.length;
      results['naturalTempo'] = naturalTempo;

      // 標準偏差
      final sumSquaredDiffs = silentBpms
          .map((bpm) => (bpm - naturalTempo) * (bpm - naturalTempo))
          .reduce((a, b) => a + b);
      final stdDev = math.sqrt(sumSquaredDiffs / silentBpms.length);
      results['naturalTempoStdDev'] = stdDev;
    }

    // 各フェーズの平均と標準偏差
    for (final phase in phaseData) {
      final phaseRhythmData =
          rhythmData.where((data) => data.phase.name == phase.name).toList();

      if (phaseRhythmData.isNotEmpty) {
        final bpms = phaseRhythmData.map((data) => data.bpm).toList();
        final avgBpm = bpms.reduce((a, b) => a + b) / bpms.length;

        // 標準偏差
        final sumSquaredDiffs = bpms
            .map((bpm) => (bpm - avgBpm) * (bpm - avgBpm))
            .reduce((a, b) => a + b);
        final stdDev = math.sqrt(sumSquaredDiffs / bpms.length);

        results['${phase.name}_avgBpm'] = avgBpm;
        results['${phase.name}_stdDev'] = stdDev;
        results['${phase.name}_targetBpm'] = phaseRhythmData.first.targetBpm;

        // 目標テンポとの差
        if (phaseRhythmData.first.targetBpm > 0) {
          final targetBpm = phaseRhythmData.first.targetBpm;
          final diff = avgBpm - targetBpm;
          results['${phase.name}_diffFromTarget'] = diff;
          results['${phase.name}_diffPercentage'] = (diff / targetBpm) * 100;
        }
      }
    }

    // 同期フェーズでの安定度（変動係数）
    final syncPhaseData = rhythmData
        .where((data) => data.phase.name.contains('syncWithNaturalTempo'))
        .toList();

    if (syncPhaseData.isNotEmpty) {
      final syncBpms = syncPhaseData.map((data) => data.bpm).toList();
      final avgBpm = syncBpms.reduce((a, b) => a + b) / syncBpms.length;

      // 標準偏差
      final sumSquaredDiffs = syncBpms
          .map((bpm) => (bpm - avgBpm) * (bpm - avgBpm))
          .reduce((a, b) => a + b);
      final stdDev = math.sqrt(sumSquaredDiffs / syncBpms.length);

      // 変動係数
      final cv = stdDev / avgBpm;
      results['syncPhase_cv'] = cv;
    }

    // 誘導フェーズでの追従度
    final guidance1Data = rhythmData
        .where((data) => data.phase.name.contains('rhythmGuidance1'))
        .toList();

    if (guidance1Data.isNotEmpty) {
      // フェーズ内での時間経過と歩行リズムの関係を分析
      final firstTimestamp =
          guidance1Data.first.timestamp.millisecondsSinceEpoch;
      final normGuidance1Data = guidance1Data.map((data) {
        final timeDiff =
            (data.timestamp.millisecondsSinceEpoch - firstTimestamp) /
                1000; // 秒単位
        return MapEntry(timeDiff, data.bpm);
      }).toList();

      // 30秒ごとの平均値を計算
      final timeFrames = <int, List<double>>{};
      for (final entry in normGuidance1Data) {
        final timeFrame = (entry.key / 30).floor();
        timeFrames.putIfAbsent(timeFrame, () => []);
        timeFrames[timeFrame]!.add(entry.value);
      }

      final timeTrend = <int, double>{};
      for (final entry in timeFrames.entries) {
        final avgBpm = entry.value.reduce((a, b) => a + b) / entry.value.length;
        timeTrend[entry.key] = avgBpm;
      }

      results['guidance1_timeTrend'] = timeTrend;

      // 開始時と終了時の差
      if (timeTrend.isNotEmpty) {
        final keys = timeTrend.keys.toList()..sort();
        if (keys.length >= 2) {
          final startBpm = timeTrend[keys.first] ?? 0;
          final endBpm = timeTrend[keys.last] ?? 0;
          results['guidance1_adaptationAmount'] = endBpm - startBpm;
        }
      }
    }

    return results;
  }

  // Azureへのデータアップロード
  Future<bool> uploadSessionDataToAzure(
      int sessionId, AzureStorageService azureStorage,
      {Function(double)? progressCallback}) async {
    try {
      // まずデータをエクスポート
      final exportPath = await exportSessionDataToCsv(sessionId);

      // セッション情報の取得
      final session = await _database.getExperimentSession(sessionId);

      // Azureへのアップロード
      final result = await azureStorage.uploadSessionData(sessionId, exportPath,
          subjectId: session.subjectId, progressCallback: progressCallback);

      return result;
    } catch (e) {
      debugPrint('Azureアップロードエラー: $e');
      return false;
    }
  }

  // リソース解放
  void dispose() {
    _phaseTimer?.cancel();
    _gaitDataController.close();
  }
}

// ExperimentPhaseDataの拡張
extension ExperimentPhaseDataExtension on ExperimentPhaseData {
  ExperimentPhaseData copyWith({
    String? name,
    DateTime? startTime,
    DateTime? endTime,
    double? naturalTempo,
    double? targetTempo,
  }) {
    return ExperimentPhaseData(
      name: name ?? this.name,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      naturalTempo: naturalTempo ?? this.naturalTempo,
      targetTempo: targetTempo ?? this.targetTempo,
    );
  }
}
