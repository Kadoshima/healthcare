import 'package:flutter/material.dart';
// Remove unused import: import 'package:fl_chart/fl_chart.dart';
// Remove unused import: import 'dart:math' as math;

import '../models/gait_data.dart';
import '../services/sensor_service.dart'; // Add this import for CalibrationPoint class

/// 実験結果のサマリーを表示するウィジェット
///
/// 歩行リズムの計測精度に関する情報を含む改良版結果表示
class ExperimentResultsSummary extends StatelessWidget {
  final ExperimentSession session;
  final List<GaitRhythmData> rhythmData;
  final Map<String, dynamic> analysisResults;
  final List<CalibrationPoint>? calibrationPoints;

  const ExperimentResultsSummary({
    Key? key,
    required this.session,
    required this.rhythmData,
    required this.analysisResults,
    this.calibrationPoints,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '実験結果サマリー',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),

            // キャリブレーション情報
            if (calibrationPoints != null && calibrationPoints!.isNotEmpty) ...[
              _buildKeyValueText(
                context,
                '測定精度',
                _getCalibrationAccuracyText(),
                _getCalibrationAccuracyIcon(),
              ),
            ],

            if (analysisResults.containsKey('naturalTempo')) ...[
              _buildKeyValueText(
                context,
                '自然歩行リズム',
                '${analysisResults['naturalTempo'].toStringAsFixed(1)} BPM ± ${analysisResults['naturalTempoStdDev'].toStringAsFixed(1)}',
                Icons.directions_walk,
              ),
            ],

            if (analysisResults.containsKey('syncWithNaturalTempo_avgBpm')) ...[
              _buildKeyValueText(
                context,
                '同期フェーズ平均',
                '${analysisResults['syncWithNaturalTempo_avgBpm'].toStringAsFixed(1)} BPM',
                Icons.sync,
              ),
            ],

            if (analysisResults.containsKey('rhythmGuidance1_avgBpm')) ...[
              _buildKeyValueText(
                context,
                '誘導1フェーズ平均',
                '${analysisResults['rhythmGuidance1_avgBpm'].toStringAsFixed(1)} BPM',
                Icons.trending_up,
              ),
            ],

            if (analysisResults.containsKey('rhythmGuidance2_avgBpm')) ...[
              _buildKeyValueText(
                context,
                '誘導2フェーズ平均',
                '${analysisResults['rhythmGuidance2_avgBpm'].toStringAsFixed(1)} BPM',
                Icons.trending_up,
              ),
            ],

            if (analysisResults.containsKey('guidance1_adaptationAmount')) ...[
              _buildKeyValueText(
                context,
                '誘導フェーズでの適応量',
                '${analysisResults['guidance1_adaptationAmount'].toStringAsFixed(1)} BPM',
                Icons.show_chart,
              ),
            ],

            // フェーズ間の追従性評価
            if (analysisResults.containsKey('rhythmGuidance1_diffFromTarget') &&
                analysisResults
                    .containsKey('rhythmGuidance2_diffFromTarget')) ...[
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),

              // 追従性スコアの計算と表示
              _buildAdaptabilityScore(context),
            ],

            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),

            // 結論
            Text(
              '結論: ${_getConclusion()}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              _getConclusionDetails(),
              style: const TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: Colors.grey,
              ),
            ),

            // 測定精度の注釈
            if (calibrationPoints != null && calibrationPoints!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blueGrey
                      .withAlpha(26), // Changed from withOpacity to withAlpha
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: Colors.blueGrey.withAlpha(
                          77)), // Changed from withOpacity to withAlpha
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.blueGrey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'キャリブレーション済みセンサーによる高精度測定結果です。平均誤差は約${_getAverageCalibrationError().toStringAsFixed(1)}%です。',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.blueGrey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // キー・バリューのテキスト行を構築
  Widget _buildKeyValueText(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.blueGrey),
          const SizedBox(width: 8),
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

  // 追従性スコアの構築
  Widget _buildAdaptabilityScore(BuildContext context) {
    // 追従性スコアの計算
    final guidance1Diff =
        analysisResults['rhythmGuidance1_diffFromTarget'].abs();
    final guidance2Diff =
        analysisResults['rhythmGuidance2_diffFromTarget'].abs();
    final avgDiff = (guidance1Diff + guidance2Diff) / 2;

    // スコアの計算（差が小さいほど高スコア）
    double adaptabilityScore = (100 - (avgDiff * 10)).toDouble();
    if (adaptabilityScore < 0) adaptabilityScore = 0;
    if (adaptabilityScore > 100) adaptabilityScore = 100;

    // スコアに基づく色
    Color scoreColor;
    if (adaptabilityScore >= 80) {
      scoreColor = Colors.green;
    } else if (adaptabilityScore >= 60) {
      scoreColor = Colors.lightGreen;
    } else if (adaptabilityScore >= 40) {
      scoreColor = Colors.amber;
    } else if (adaptabilityScore >= 20) {
      scoreColor = Colors.orange;
    } else {
      scoreColor = Colors.red;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '誘導リズムへの追従性',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(width: 8),
            Expanded(
              child: LinearProgressIndicator(
                value: adaptabilityScore / 100,
                minHeight: 15,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${adaptabilityScore.toStringAsFixed(0)}%',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: scoreColor,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '平均誤差: ${avgDiff.toStringAsFixed(1)} BPM',
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 4),
        Text(
          '- 誘導1フェーズ誤差: ${guidance1Diff.toStringAsFixed(1)} BPM',
          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
        ),
        Text(
          '- 誘導2フェーズ誤差: ${guidance2Diff.toStringAsFixed(1)} BPM',
          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
        ),
      ],
    );
  }

  // キャリブレーション精度のテキスト
  String _getCalibrationAccuracyText() {
    if (calibrationPoints == null || calibrationPoints!.isEmpty) {
      return 'キャリブレーションなし';
    }

    final avgError = _getAverageCalibrationError();
    final accuracy = 100 - avgError;

    if (accuracy >= 95) {
      return '非常に高精度 (${accuracy.toStringAsFixed(1)}%)';
    } else if (accuracy >= 90) {
      return '高精度 (${accuracy.toStringAsFixed(1)}%)';
    } else if (accuracy >= 85) {
      return '良好 (${accuracy.toStringAsFixed(1)}%)';
    } else if (accuracy >= 80) {
      return '標準 (${accuracy.toStringAsFixed(1)}%)';
    } else {
      return '要改善 (${accuracy.toStringAsFixed(1)}%)';
    }
  }

  // キャリブレーション精度のアイコン
  IconData _getCalibrationAccuracyIcon() {
    if (calibrationPoints == null || calibrationPoints!.isEmpty) {
      return Icons.error_outline;
    }

    final avgError = _getAverageCalibrationError();
    final accuracy = 100 - avgError;

    if (accuracy >= 95) {
      return Icons.verified;
    } else if (accuracy >= 90) {
      return Icons.thumb_up;
    } else if (accuracy >= 85) {
      return Icons.check_circle;
    } else if (accuracy >= 80) {
      return Icons.check;
    } else {
      return Icons.warning;
    }
  }

  // 平均キャリブレーション誤差の計算
  double _getAverageCalibrationError() {
    if (calibrationPoints == null || calibrationPoints!.isEmpty) {
      return 0.0;
    }

    double totalErrorPercent = 0.0;
    for (final point in calibrationPoints!) {
      final errorPercent = (point.error.abs() / point.targetBpm) * 100;
      totalErrorPercent += errorPercent;
    }

    return totalErrorPercent / calibrationPoints!.length;
  }

  // 結論の生成
  String _getConclusion() {
    if (!analysisResults.containsKey('rhythmGuidance1_avgBpm') ||
        !analysisResults.containsKey('rhythmGuidance2_avgBpm') ||
        !analysisResults.containsKey('naturalTempo')) {
      return '十分なデータがありません';
    }

    final naturalTempo = analysisResults['naturalTempo'];
    final guidance1Avg = analysisResults['rhythmGuidance1_avgBpm'];
    final guidance2Avg = analysisResults['rhythmGuidance2_avgBpm'];

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

  // 結論の詳細
  String _getConclusionDetails() {
    if (!analysisResults.containsKey('rhythmGuidance1_avgBpm') ||
        !analysisResults.containsKey('rhythmGuidance2_avgBpm') ||
        !analysisResults.containsKey('naturalTempo')) {
      return '分析に必要なデータが不足しています。';
    }

    final naturalTempo = analysisResults['naturalTempo'];
    final guidance1Avg = analysisResults['rhythmGuidance1_avgBpm'];
    final guidance2Avg = analysisResults['rhythmGuidance2_avgBpm'];

    // 誘導効果の判定
    final guidance1Effect = guidance1Avg - naturalTempo;
    final guidance2Effect = guidance2Avg - naturalTempo;

    String details = '';

    if (guidance1Effect > 1.0 && guidance2Effect > 2.0) {
      details = '被験者は誘導音に対して高い追従性を示し、歩行リズムを効果的に変化させることができました。';
    } else if (guidance1Effect > 0.5 && guidance2Effect > 1.0) {
      details = '被験者は誘導音に対してある程度の追従性を示しましたが、完全には同期できていない可能性があります。';
    } else {
      details = '被験者の歩行リズムは誘導音による影響を受けにくい傾向がありました。';
    }

    return details;
  }
}
