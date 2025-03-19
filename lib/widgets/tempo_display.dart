import 'package:flutter/material.dart';

class TempoDisplay extends StatelessWidget {
  final String title;
  final double tempo;
  final Color color;

  const TempoDisplay({
    Key? key,
    required this.title,
    required this.tempo,
    required this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // タイトル
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 8),

        // BPM表示
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: color,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              // BPM値
              Text(
                tempo.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),

              // BPM単位
              Text(
                'BPM',
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
