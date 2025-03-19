import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../models/gait_data.dart';
import '../services/database_service.dart';
import 'results_screen.dart';

class ExperimentHistoryScreen extends StatefulWidget {
  const ExperimentHistoryScreen({Key? key}) : super(key: key);

  @override
  State<ExperimentHistoryScreen> createState() =>
      _ExperimentHistoryScreenState();
}

class _ExperimentHistoryScreenState extends State<ExperimentHistoryScreen> {
  List<ExperimentSession> _sessions = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  // セッション一覧の読み込み
  Future<void> _loadSessions() async {
    try {
      final databaseService =
          Provider.of<DatabaseService>(context, listen: false);
      final sessions = await databaseService.getAllExperimentSessions();

      setState(() {
        _sessions = sessions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('実験履歴'),
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  // 画面本体の構築
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 60,
            ),
            const SizedBox(height: 16),
            Text(
              '履歴の読み込みに失敗しました',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(_error!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _loadSessions();
              },
              child: const Text('再読み込み'),
            ),
          ],
        ),
      );
    }

    if (_sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.history,
              color: Colors.grey,
              size: 60,
            ),
            const SizedBox(height: 16),
            Text(
              '実験履歴がありません',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text('実験を行うと、ここに履歴が表示されます'),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _sessions.length,
      itemBuilder: (context, index) {
        final session = _sessions[index];
        return _buildSessionCard(session);
      },
    );
  }

  // セッションカードの構築
  Widget _buildSessionCard(ExperimentSession session) {
    final dateFormat = DateFormat('yyyy/MM/dd HH:mm');
    final startTime = dateFormat.format(session.startTime);

    // 実験の所要時間
    String duration = '進行中';
    if (session.endTime != null) {
      final durationMinutes =
          session.endTime!.difference(session.startTime).inMinutes;
      duration = '$durationMinutes分';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ResultsScreen(sessionId: session.id),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 被験者ID
              Row(
                children: [
                  const Icon(Icons.person),
                  const SizedBox(width: 8),
                  Text(
                    '被験者: ${session.subjectId}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 実験日時
              Row(
                children: [
                  const Icon(Icons.access_time),
                  const SizedBox(width: 8),
                  Text('実施日時: $startTime'),
                ],
              ),
              const SizedBox(height: 4),

              // 所要時間
              Row(
                children: [
                  const Icon(Icons.timer),
                  const SizedBox(width: 8),
                  Text('所要時間: $duration'),
                ],
              ),
              const SizedBox(height: 4),

              // センサー位置
              Row(
                children: [
                  const Icon(Icons.sensors),
                  const SizedBox(width: 8),
                  Text('センサー位置: ${session.settings['sensorPosition'] ?? '不明'}'),
                ],
              ),
              const SizedBox(height: 8),

              // 詳細ボタン
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) =>
                            ResultsScreen(sessionId: session.id),
                      ),
                    );
                  },
                  child: const Text('詳細を表示'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
