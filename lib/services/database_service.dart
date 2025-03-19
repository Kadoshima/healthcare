import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import '../models/gait_data.dart';

class DatabaseService {
  static Database? _database;

  // データベース接続
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // データベース初期化
  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'walking_rhythm_guide.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDatabase,
    );
  }

  // データベース初期化
  Future<void> initialize() async {
    await database;
  }

  // データベースの作成
  Future<void> _createDatabase(Database db, int version) async {
    // 実験セッションテーブル
    await db.execute('''
      CREATE TABLE experiment_sessions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        subject_id TEXT NOT NULL,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        settings TEXT NOT NULL
      )
    ''');

    // 歩行リズムデータテーブル
    await db.execute('''
      CREATE TABLE gait_rhythm_data(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        timestamp INTEGER NOT NULL,
        bpm REAL NOT NULL,
        phase TEXT NOT NULL,
        target_bpm REAL NOT NULL,
        FOREIGN KEY (session_id) REFERENCES experiment_sessions (id) ON DELETE CASCADE
      )
    ''');

    // フェーズデータテーブル
    await db.execute('''
      CREATE TABLE phase_data(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        natural_tempo REAL,
        target_tempo REAL,
        FOREIGN KEY (session_id) REFERENCES experiment_sessions (id) ON DELETE CASCADE
      )
    ''');

    // インデックス作成
    await db.execute(
        'CREATE INDEX idx_gait_rhythm_session_id ON gait_rhythm_data (session_id)');
    await db.execute(
        'CREATE INDEX idx_phase_data_session_id ON phase_data (session_id)');
  }

  // 実験セッションの作成
  Future<int> createExperimentSession({
    required String subjectId,
    required DateTime startTime,
    required Map<String, dynamic> settings,
  }) async {
    final db = await database;

    return await db.insert(
      'experiment_sessions',
      {
        'subject_id': subjectId,
        'start_time': startTime.millisecondsSinceEpoch,
        'settings': jsonEncode(settings),
      },
    );
  }

  // 実験セッションの更新
  Future<void> updateExperimentSession(
    int sessionId, {
    DateTime? endTime,
    Map<String, dynamic>? settings,
  }) async {
    final db = await database;

    final updateData = <String, dynamic>{};
    if (endTime != null) {
      updateData['end_time'] = endTime.millisecondsSinceEpoch;
    }
    if (settings != null) {
      updateData['settings'] = jsonEncode(settings);
    }

    if (updateData.isEmpty) return;

    await db.update(
      'experiment_sessions',
      updateData,
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  // 歩行リズムデータの追加
  Future<void> addGaitRhythmData(
    int sessionId,
    GaitRhythmData data,
  ) async {
    final db = await database;

    await db.insert(
      'gait_rhythm_data',
      {
        'session_id': sessionId,
        'timestamp': data.timestamp.millisecondsSinceEpoch,
        'bpm': data.bpm,
        'phase': data.phase.toString(),
        'target_bpm': data.targetBpm,
      },
    );
  }

  // 歩行リズムデータのバッチ追加
  Future<void> addGaitRhythmDataBatch(
    int sessionId,
    List<GaitRhythmData> dataList,
  ) async {
    final db = await database;

    final batch = db.batch();

    for (var data in dataList) {
      batch.insert(
        'gait_rhythm_data',
        {
          'session_id': sessionId,
          'timestamp': data.timestamp.millisecondsSinceEpoch,
          'bpm': data.bpm,
          'phase': data.phase.toString(),
          'target_bpm': data.targetBpm,
        },
      );
    }

    await batch.commit(noResult: true);
  }

  // フェーズデータの追加
  Future<void> addPhaseData(
    int sessionId,
    ExperimentPhaseData data,
  ) async {
    final db = await database;

    await db.insert(
      'phase_data',
      {
        'session_id': sessionId,
        'name': data.name,
        'start_time': data.startTime.millisecondsSinceEpoch,
        'end_time': data.endTime?.millisecondsSinceEpoch,
        'natural_tempo': data.naturalTempo,
        'target_tempo': data.targetTempo,
      },
    );
  }

  // 実験セッションの取得
  Future<ExperimentSession> getExperimentSession(int sessionId) async {
    final db = await database;

    final List<Map<String, dynamic>> maps = await db.query(
      'experiment_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );

    if (maps.isEmpty) {
      throw Exception('セッションが見つかりません: $sessionId');
    }

    final map = maps.first;
    return ExperimentSession(
      id: map['id'],
      subjectId: map['subject_id'],
      startTime: DateTime.fromMillisecondsSinceEpoch(map['start_time']),
      endTime: map['end_time'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['end_time'])
          : null,
      settings: jsonDecode(map['settings']),
    );
  }

  // 全実験セッションの取得
  Future<List<ExperimentSession>> getAllExperimentSessions() async {
    final db = await database;

    final List<Map<String, dynamic>> maps = await db.query(
      'experiment_sessions',
      orderBy: 'start_time DESC',
    );

    return List.generate(maps.length, (i) {
      final map = maps[i];
      return ExperimentSession(
        id: map['id'],
        subjectId: map['subject_id'],
        startTime: DateTime.fromMillisecondsSinceEpoch(map['start_time']),
        endTime: map['end_time'] != null
            ? DateTime.fromMillisecondsSinceEpoch(map['end_time'])
            : null,
        settings: jsonDecode(map['settings']),
      );
    });
  }

  // 歩行リズムデータの取得
  Future<List<GaitRhythmData>> getGaitRhythmData(int sessionId) async {
    final db = await database;

    final List<Map<String, dynamic>> maps = await db.query(
      'gait_rhythm_data',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );

    return List.generate(maps.length, (i) {
      final map = maps[i];
      return GaitRhythmData(
        timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
        bpm: map['bpm'],
        phase: ExperimentPhaseData.fromString(map['phase']),
        targetBpm: map['target_bpm'],
      );
    });
  }

  // フェーズデータの取得
  Future<List<ExperimentPhaseData>> getPhaseData(int sessionId) async {
    final db = await database;

    final List<Map<String, dynamic>> maps = await db.query(
      'phase_data',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'start_time ASC',
    );

    return List.generate(maps.length, (i) {
      final map = maps[i];
      return ExperimentPhaseData(
        name: map['name'],
        startTime: DateTime.fromMillisecondsSinceEpoch(map['start_time']),
        endTime: map['end_time'] != null
            ? DateTime.fromMillisecondsSinceEpoch(map['end_time'])
            : null,
        naturalTempo: map['natural_tempo'],
        targetTempo: map['target_tempo'],
      );
    });
  }

  // 実験セッションの削除
  Future<void> deleteExperimentSession(int sessionId) async {
    final db = await database;

    await db.delete(
      'experiment_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }
}
