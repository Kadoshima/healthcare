import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/sensor_service.dart';

/// 歩行リズム測定の精度メトリクスを表示するウィジェット
class WalkingRhythmMetrics extends StatelessWidget {
  final double fontSize;
  final bool showDetailed;
  final VoidCallback? onCalibrateTap;

  const WalkingRhythmMetrics({
    Key? key,
    this.fontSize = 14.0,
    this.showDetailed = false,
    this.onCalibrateTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final sensorService = Provider.of<SensorService>(context);

    // 現在の測定精度情報を取得
    final double accuracy = sensorService.currentAccuracy;
    final double confidence = sensorService.confidenceLevel;
    final double avgError = sensorService.avgVerificationError;

    // 精度に基づいた色の設定
    Color accuracyColor;
    if (accuracy >= 90) {
      accuracyColor = Colors.green;
    } else if (accuracy >= 80) {
      accuracyColor = Colors.lightGreen;
    } else if (accuracy >= 70) {
      accuracyColor = Colors.amber;
    } else if (accuracy >= 60) {
      accuracyColor = Colors.orange;
    } else {
      accuracyColor = Colors.red;
    }

    // 信頼度に基づいた色の設定
    Color confidenceColor;
    if (confidence >= 0.8) {
      confidenceColor = Colors.green;
    } else if (confidence >= 0.6) {
      confidenceColor = Colors.lightGreen;
    } else if (confidence >= 0.4) {
      confidenceColor = Colors.amber;
    } else if (confidence >= 0.2) {
      confidenceColor = Colors.orange;
    } else {
      confidenceColor = Colors.red;
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: accuracyColor),
                const SizedBox(width: 8),
                Text(
                  '歩行リズム測定精度',
                  style: TextStyle(
                    fontSize: fontSize + 2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 精度表示
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '測定精度',
                        style: TextStyle(
                          fontSize: fontSize,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: accuracy / 100,
                        backgroundColor: Colors.grey[200],
                        valueColor:
                            AlwaysStoppedAnimation<Color>(accuracyColor),
                        minHeight: 8,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${accuracy.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.bold,
                          color: accuracyColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '信頼度',
                        style: TextStyle(
                          fontSize: fontSize,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: confidence,
                        backgroundColor: Colors.grey[200],
                        valueColor:
                            AlwaysStoppedAnimation<Color>(confidenceColor),
                        minHeight: 8,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(confidence * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.bold,
                          color: confidenceColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // 詳細情報（オプション）
            if (showDetailed) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),

              // 平均誤差
              Row(
                children: [
                  const Icon(Icons.error_outline, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    '平均誤差: ${avgError.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: fontSize - 1,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // キャリブレーション状態
              Row(
                children: [
                  const Icon(Icons.settings_suggest,
                      size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    'キャリブレーション: ${sensorService.calibrationPoints.isEmpty ? "未実施" : "完了済"}',
                    style: TextStyle(
                      fontSize: fontSize - 1,
                      color: Colors.grey[700],
                    ),
                  ),
                  const Spacer(),
                  if (onCalibrateTap != null)
                    TextButton.icon(
                      icon: const Icon(Icons.tune, size: 16),
                      label: Text(
                        sensorService.calibrationPoints.isEmpty
                            ? 'キャリブレーション実行'
                            : '再キャリブレーション',
                        style: TextStyle(fontSize: fontSize - 1),
                      ),
                      onPressed: onCalibrateTap,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
