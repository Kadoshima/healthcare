import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'dart:math' as math;

import '../models/gait_data.dart';
import '../services/database_service.dart';
import '../services/experiment_service.dart';

class ResultsScreen extends StatefulWidget {
  final int sessionId;

  const ResultsScreen({
    Key? key,
    required this.sessionId,
  }) : super(key: key);

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  // データ
  ExperimentSession? _session;
  final List<GaitRhythmData> _rhythmData = [];
  final List<ExperimentPhaseData> _phaseData = [];

  // 分析結果
  Map<String, dynamic> _analysisResults = {};

  // 読み込み状態
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // データ読み込み
  Future<void> _loadData() async {
    try {
      final databaseService =
          Provider.of<DatabaseService>(context, listen: false);

      // セッション情報の取得
      final session =
          await databaseService.getExperimentSession(widget.sessionId);

      // 歩行リズムデータの取得
      final rhythmData =
          await databaseService.getGaitRhythmData(widget.sessionId);

      // フェーズデータの取得
      final phaseData = await databaseService.getPhaseData(widget.sessionId);

      // データ分析
      final analysisResults = _analyzeData(rhythmData, phaseData);

      setState(() {
        _session = session;
        _rhythmData.addAll(rhythmData);
        _phaseData.addAll(phaseData);
        _analysisResults = analysisResults;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // 分析結果
  Map<String, dynamic> _analyzeData(
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('実験結果'),
        centerTitle: true,
        actions: [
          if (!_isLoading && _error == null)
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: _exportAndShareData,
              tooltip: 'データをエクスポート',
            ),
        ],
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
              'データの読み込みに失敗しました',
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
                _loadData();
              },
              child: const Text('再読み込み'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 基本情報
          _buildSessionInfoCard(),

          const SizedBox(height: 16),

          // 分析結果サマリー
          _buildAnalysisSummaryCard(),

          const SizedBox(height: 16),

          // 歩行リズムグラフ
          _buildRhythmGraphCard(),

          const SizedBox(height: 16),

          // フェーズごとの詳細分析
          _buildPhaseAnalysisCard(),

          const SizedBox(height: 16),

          // 追従性分析
          _buildAdaptationAnalysisCard(),

          const SizedBox(height: 24),

          // ホーム画面に戻るボタン
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text(
                'ホーム画面に戻る',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // セッション情報カード
  Widget _buildSessionInfoCard() {
    if (_session == null) return const SizedBox.shrink();

    final dateFormat = DateFormat('yyyy/MM/dd HH:mm');
    final startTime = dateFormat.format(_session!.startTime);
    final endTime =
        _session!.endTime != null ? dateFormat.format(_session!.endTime!) : '-';

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '実験セッション情報',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _buildInfoRow('被験者ID', _session!.subjectId),
            _buildInfoRow('開始時間', startTime),
            _buildInfoRow('終了時間', endTime),
            _buildInfoRow(
                'センサー位置', _session!.settings['sensorPosition'] ?? '-'),
            if (_analysisResults.containsKey('naturalTempo'))
              _buildInfoRow(
                '自然歩行リズム',
                '${_analysisResults['naturalTempo'].toStringAsFixed(1)} BPM',
              ),
          ],
        ),
      ),
    );
  }

  // 分析結果サマリーカード
  Widget _buildAnalysisSummaryCard() {
    if (_analysisResults.isEmpty) {
      return const Card(
        elevation: 4,
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('分析結果がありません'),
        ),
      );
    }

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '分析結果サマリー',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (_analysisResults.containsKey('naturalTempo')) ...[
              _buildInfoRow(
                '自然歩行リズム',
                '${_analysisResults['naturalTempo'].toStringAsFixed(1)} BPM ± ${_analysisResults['naturalTempoStdDev'].toStringAsFixed(1)}',
              ),
            ],
            if (_analysisResults
                .containsKey('syncWithNaturalTempo_avgBpm')) ...[
              _buildInfoRow(
                '同期フェーズ平均',
                '${_analysisResults['syncWithNaturalTempo_avgBpm'].toStringAsFixed(1)} BPM',
              ),
            ],
            if (_analysisResults.containsKey('rhythmGuidance1_avgBpm')) ...[
              _buildInfoRow(
                '誘導1フェーズ平均',
                '${_analysisResults['rhythmGuidance1_avgBpm'].toStringAsFixed(1)} BPM',
              ),
            ],
            if (_analysisResults.containsKey('rhythmGuidance2_avgBpm')) ...[
              _buildInfoRow(
                '誘導2フェーズ平均',
                '${_analysisResults['rhythmGuidance2_avgBpm'].toStringAsFixed(1)} BPM',
              ),
            ],
            if (_analysisResults.containsKey('guidance1_adaptationAmount')) ...[
              _buildInfoRow(
                '誘導フェーズでの適応量',
                '${_analysisResults['guidance1_adaptationAmount'].toStringAsFixed(1)} BPM',
              ),
            ],
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              '結論: ${_getConclusion()}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  // 歩行リズムグラフカード - 改善版
  Widget _buildRhythmGraphCard() {
    if (_rhythmData.isEmpty) {
      return const Card(
        elevation: 4,
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('グラフデータがありません'),
        ),
      );
    }

    // グラフデータの準備
    final List<FlSpot> spotData = [];
    final List<FlSpot> targetData = [];
    final List<String> phaseMarkers = [];
    final List<double> phaseMarkerPositions = [];

    // 開始時刻
    final startTime = _rhythmData.first.timestamp.millisecondsSinceEpoch;

    // データポイントの作成 - データの間引きを改善
    final int dataStep =
        math.max(1, (_rhythmData.length / 300).ceil()); // 最大300ポイントに制限
    for (var i = 0; i < _rhythmData.length; i += dataStep) {
      final data = _rhythmData[i];
      final xPos = (data.timestamp.millisecondsSinceEpoch - startTime) /
          1000 /
          60; // 分単位
      spotData.add(FlSpot(xPos, data.bpm));

      if (data.targetBpm > 0) {
        targetData.add(FlSpot(xPos, data.targetBpm));
      }
    }

    // フェーズマーカーの作成
    for (final phase in _phaseData) {
      final xPos = (phase.startTime.millisecondsSinceEpoch - startTime) /
          1000 /
          60; // 分単位
      phaseMarkerPositions.add(xPos);

      // フェーズ名の短縮表示
      String shortName;
      if (phase.name.contains('silentWalking')) {
        shortName = '無音';
      } else if (phase.name.contains('syncWithNaturalTempo')) {
        shortName = '同期';
      } else if (phase.name.contains('rhythmGuidance1')) {
        shortName = '誘導1';
      } else if (phase.name.contains('rhythmGuidance2')) {
        shortName = '誘導2';
      } else if (phase.name.contains('cooldown')) {
        shortName = 'ｸｰﾙﾀﾞｳﾝ';
      } else {
        shortName = 'その他';
      }
      phaseMarkers.add(shortName);
    }

    // データの範囲を計算
    final double minY = math.max(
        0, (spotData.map((p) => p.y).reduce((a, b) => a < b ? a : b) - 10));
    final double maxY =
        spotData.map((p) => p.y).reduce((a, b) => a > b ? a : b) + 10;
    final double maxX = spotData.last.x + 0.5; // グラフの右端に余白を追加

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
                const Icon(Icons.show_chart, size: 24, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  '歩行リズム推移',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '各フェーズでの歩行リズム（BPM）の変化を表示しています。縦線はフェーズの変わり目を示します。',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: 10,
                    verticalInterval: 1,
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
                      axisNameWidget: const Text('BPM',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      axisNameSize: 20,
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
                      axisNameWidget: const Text('経過時間（分）',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      axisNameSize: 20,
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 2, // 2分ごとに表示
                        reservedSize: 30,
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
                  minY: minY,
                  maxY: maxY,
                  minX: 0,
                  maxX: maxX,
                  lineBarsData: [
                    // 実際の歩行リズム
                    LineChartBarData(
                      spots: spotData,
                      isCurved: true,
                      color: Colors.blue,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: false,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 2,
                            color: Colors.blue,
                            strokeWidth: 1,
                            strokeColor: Colors.blue,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.blue.withOpacity(0.1),
                      ),
                    ),
                    // 目標テンポ
                    if (targetData.isNotEmpty)
                      LineChartBarData(
                        spots: targetData,
                        isCurved: false,
                        color: Colors.green.withOpacity(0.7),
                        barWidth: 2,
                        isStrokeCapRound: true,
                        dotData: FlDotData(show: false),
                        belowBarData: BarAreaData(show: false),
                        dashArray: [5, 5],
                      ),
                  ],
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      if (_analysisResults.containsKey('naturalTempo'))
                        HorizontalLine(
                          y: _analysisResults['naturalTempo'],
                          color: Colors.purpleAccent.withOpacity(0.7),
                          strokeWidth: 2,
                          dashArray: [5, 5],
                          label: HorizontalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            padding: const EdgeInsets.only(right: 5, bottom: 5),
                            style: const TextStyle(
                              color: Colors.purpleAccent,
                              fontWeight: FontWeight.bold,
                            ),
                            labelResolver: (line) =>
                                '自然テンポ: ${line.y.toStringAsFixed(1)}',
                          ),
                        ),
                    ],
                    verticalLines: [
                      for (var i = 0; i < phaseMarkerPositions.length; i++)
                        VerticalLine(
                          x: phaseMarkerPositions[i],
                          color: Colors.red.withOpacity(0.7),
                          strokeWidth: 1,
                          label: VerticalLineLabel(
                            show: true,
                            alignment: Alignment.topCenter,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                            labelResolver: (line) => phaseMarkers[i],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Wrap(
                spacing: 20,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _buildLegendItem('歩行リズム', Colors.blue),
                  _buildLegendItem('目標テンポ', Colors.green),
                  _buildLegendItem('フェーズ境界', Colors.red),
                  _buildLegendItem('自然テンポ', Colors.purpleAccent),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // フェーズごとの詳細分析カード
  Widget _buildPhaseAnalysisCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'フェーズごとの詳細分析',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            // フェーズごとの分析テーブル
            Table(
              border: TableBorder.all(
                color: Colors.grey.shade300,
                width: 1,
              ),
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(2),
                3: FlexColumnWidth(2),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                // ヘッダー行
                TableRow(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                  ),
                  children: [
                    _buildTableHeader('フェーズ'),
                    _buildTableHeader('平均 BPM'),
                    _buildTableHeader('標準偏差'),
                    _buildTableHeader('目標との差'),
                  ],
                ),

                // 無音フェーズ
                if (_analysisResults.containsKey('silentWalking_avgBpm'))
                  _buildPhaseAnalysisRow(
                    '無音歩行',
                    _analysisResults['silentWalking_avgBpm'],
                    _analysisResults['silentWalking_stdDev'],
                    null,
                  ),

                // 同期フェーズ
                if (_analysisResults.containsKey('syncWithNaturalTempo_avgBpm'))
                  _buildPhaseAnalysisRow(
                    '自然リズム同期',
                    _analysisResults['syncWithNaturalTempo_avgBpm'],
                    _analysisResults['syncWithNaturalTempo_stdDev'],
                    _analysisResults['syncWithNaturalTempo_diffFromTarget'],
                  ),

                // 誘導フェーズ1
                if (_analysisResults.containsKey('rhythmGuidance1_avgBpm'))
                  _buildPhaseAnalysisRow(
                    'リズム誘導1',
                    _analysisResults['rhythmGuidance1_avgBpm'],
                    _analysisResults['rhythmGuidance1_stdDev'],
                    _analysisResults['rhythmGuidance1_diffFromTarget'],
                  ),

                // 誘導フェーズ2
                if (_analysisResults.containsKey('rhythmGuidance2_avgBpm'))
                  _buildPhaseAnalysisRow(
                    'リズム誘導2',
                    _analysisResults['rhythmGuidance2_avgBpm'],
                    _analysisResults['rhythmGuidance2_stdDev'],
                    _analysisResults['rhythmGuidance2_diffFromTarget'],
                  ),

                // クールダウンフェーズ
                if (_analysisResults.containsKey('cooldown_avgBpm'))
                  _buildPhaseAnalysisRow(
                    'クールダウン',
                    _analysisResults['cooldown_avgBpm'],
                    _analysisResults['cooldown_stdDev'],
                    _analysisResults['cooldown_diffFromTarget'],
                  ),
              ],
            ),

            const SizedBox(height: 16),
            const Text(
              '* 標準偏差は値が小さいほど歩行リズムが安定していることを示します。',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
            const Text(
              '* 目標との差がマイナスの場合、目標テンポより遅いことを示します。',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  // 追従性分析カード - 改善版
  Widget _buildAdaptationAnalysisCard() {
    if (!_analysisResults.containsKey('guidance1_timeTrend')) {
      return const SizedBox.shrink();
    }

    final timeTrend =
        _analysisResults['guidance1_timeTrend'] as Map<int, double>;

    if (timeTrend.isEmpty) {
      return const SizedBox.shrink();
    }

    // トレンドグラフ用のスポット
    final trendSpots = <FlSpot>[];

    for (final entry in timeTrend.entries) {
      trendSpots.add(FlSpot(entry.key * 30, entry.value));
    }

    trendSpots.sort((a, b) => a.x.compareTo(b.x));

    // ターゲットBPMラインのY値を取得
    double targetBpm = 0.0;
    if (_analysisResults.containsKey('rhythmGuidance1_targetBpm')) {
      targetBpm = _analysisResults['rhythmGuidance1_targetBpm'];
    }

    // 適応スコアの計算
    double adaptationScore = 0.0;
    if (_analysisResults.containsKey('guidance1_adaptationAmount')) {
      final adaptationAmount = _analysisResults['guidance1_adaptationAmount'];
      // 正の適応量（目標に近づいた場合）に対してスコアを高く
      if (adaptationAmount > 0) {
        adaptationScore = math.min(100, adaptationAmount * 20); // 最大100%
      }
    }

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
                const Icon(Icons.trending_up,
                    size: 24, color: Colors.deepPurple),
                const SizedBox(width: 8),
                Text(
                  'テンポ誘導への追従性分析',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '誘導フェーズ1における歩行リズムの時間的変化を分析します。'
              'グラフは30秒ごとの平均値を示しています。',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: 5,
                    verticalInterval: 60,
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
                      axisNameWidget: const Text('BPM',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      axisNameSize: 20,
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 5,
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
                      axisNameWidget: const Text('経過時間（秒）',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      axisNameSize: 20,
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 60,
                        reservedSize: 30,
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
                  lineBarsData: [
                    LineChartBarData(
                      spots: trendSpots,
                      isCurved: true,
                      color: Colors.deepPurple,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.deepPurple.withOpacity(0.1),
                      ),
                    ),
                    if (targetBpm > 0)
                      LineChartBarData(
                        spots: [
                          FlSpot(0, targetBpm),
                          FlSpot(trendSpots.last.x, targetBpm),
                        ],
                        isCurved: false,
                        color: Colors.orange.withOpacity(0.7),
                        barWidth: 2,
                        dotData: FlDotData(show: false),
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
                            '${flSpot.x.toInt()}秒: ${flSpot.y.toStringAsFixed(1)} BPM',
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
            const SizedBox(height: 16),

            // 適応量の表示
            if (_analysisResults.containsKey('guidance1_adaptationAmount')) ...[
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                '適応能力の分析:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),

              // 適応スコアの視覚化
              Row(
                children: [
                  const SizedBox(width: 8),
                  const Text('適応スコア: ',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: adaptationScore / 100,
                      minHeight: 15,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _getAdaptationColor(adaptationScore),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${adaptationScore.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _getAdaptationColor(adaptationScore),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),

              const SizedBox(height: 16),
              Text(
                '誘導フェーズ開始時と終了時の歩行リズム差: ${_analysisResults['guidance1_adaptationAmount'].toStringAsFixed(1)} BPM',
              ),
              const SizedBox(height: 8),
              Text(
                _getAdaptationConclusion(),
                style: const TextStyle(
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),

              // 追加の説明
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: const Text(
                  '適応スコアは、被験者が誘導テンポに従う能力を示します。スコアが高いほど、実験中に歩行リズムを目標テンポに合わせる能力が高いことを示します。',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 情報行の構築
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  // テーブルヘッダーの構築
  Widget _buildTableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  // フェーズ分析行の構築
  TableRow _buildPhaseAnalysisRow(
    String phaseName,
    double avgBpm,
    double stdDev,
    double? diffFromTarget,
  ) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(phaseName),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            avgBpm.toStringAsFixed(1),
            textAlign: TextAlign.center,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            stdDev.toStringAsFixed(2),
            textAlign: TextAlign.center,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: diffFromTarget != null
              ? Text(
                  diffFromTarget.toStringAsFixed(1),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: diffFromTarget.abs() < 1.0
                        ? Colors.green
                        : (diffFromTarget.abs() < 3.0
                            ? Colors.orange
                            : Colors.red),
                  ),
                )
              : const Text('-', textAlign: TextAlign.center),
        ),
      ],
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

  // 結論の生成
  String _getConclusion() {
    if (!_analysisResults.containsKey('rhythmGuidance1_avgBpm') ||
        !_analysisResults.containsKey('rhythmGuidance2_avgBpm') ||
        !_analysisResults.containsKey('naturalTempo')) {
      return '十分なデータがありません';
    }

    final naturalTempo = _analysisResults['naturalTempo'];
    final guidance1Avg = _analysisResults['rhythmGuidance1_avgBpm'];
    final guidance2Avg = _analysisResults['rhythmGuidance2_avgBpm'];

    // 誘導効果の判定
    final guidance1Effect = guidance1Avg - naturalTempo;
    final guidance2Effect = guidance2Avg - naturalTempo;

    if (guidance1Effect > 1.0 && guidance2Effect > 2.0) {
      return 'テンポ誘導が効果的に歩行リズムを変化させています';
    } else if (guidance1Effect > 0.5 && guidance2Effect > 1.0) {
      return 'テンポ誘導がある程度歩行リズムに影響を与えています';
    } else {
      return 'テンポ誘導の効果は限定的でした';
    }
  }

  // 適応性の結論生成
  String _getAdaptationConclusion() {
    if (!_analysisResults.containsKey('guidance1_adaptationAmount')) {
      return '';
    }

    final adaptationAmount = _analysisResults['guidance1_adaptationAmount'];

    if (adaptationAmount > 3.0) {
      return '被験者は誘導音に対して高い追従性を示しました。';
    } else if (adaptationAmount > 1.0) {
      return '被験者は誘導音に対して中程度の追従性を示しました。';
    } else if (adaptationAmount > 0) {
      return '被験者は誘導音に対してわずかな追従性を示しました。';
    } else {
      return '被験者は誘導音に対する明確な追従性を示しませんでした。';
    }
  }

  // 適応スコアに基づく色を取得
  Color _getAdaptationColor(double score) {
    if (score >= 80) {
      return Colors.green;
    } else if (score >= 50) {
      return Colors.amber;
    } else if (score >= 20) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  // データのエクスポートと共有
  Future<void> _exportAndShareData() async {
    try {
      final experimentService =
          Provider.of<ExperimentService>(context, listen: false);

      // プログレスダイアログを表示
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('データをエクスポート中...'),
            ],
          ),
        ),
      );

      // データをエクスポート
      final exportPath =
          await experimentService.exportSessionDataToCsv(widget.sessionId);

      // ダイアログを閉じる
      if (!mounted) return;
      Navigator.of(context).pop();

      // 共有
      final directory = Directory(exportPath);
      final files = directory
          .listSync()
          .where((e) =>
              e is File &&
              e.path.contains('session_${widget.sessionId}') &&
              (e.path.endsWith('.csv') || e.path.endsWith('.json')))
          .map((e) => XFile(e.path))
          .toList();

      if (files.isEmpty) {
        throw Exception('エクスポートファイルが見つかりません');
      }

      await Share.shareXFiles(
        files,
        subject:
            '歩行リズム実験データ - ${_session?.subjectId} - ${DateFormat('yyyy-MM-dd').format(_session!.startTime)}',
      );
    } catch (e) {
      if (!mounted) return;

      // エラーダイアログを表示
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('エクスポートエラー'),
          content: Text(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }
}
