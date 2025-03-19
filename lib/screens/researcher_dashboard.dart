import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/experiment_settings.dart';
import '../services/improved_audio_service.dart';
import 'metronome_settings_screen.dart';

class ResearcherDashboard extends StatefulWidget {
  const ResearcherDashboard({Key? key}) : super(key: key);

  @override
  State<ResearcherDashboard> createState() => _ResearcherDashboardState();
}

class _ResearcherDashboardState extends State<ResearcherDashboard> {
  // 設定のローカルコピー
  late int _calibrationDuration;
  late int _silentWalkingDuration;
  late int _syncDuration;
  late int _guidance1Duration;
  late int _guidance2Duration;
  late int _cooldownDuration;
  late double _tempoIncrement;
  late String _clickSoundType;
  late double _volume;
  late PrecisionMode _precisionMode;

  // 音声プレビュー用
  bool _isPreviewPlaying = false;
  double _previewTempo = 100.0;
  late ImprovedAudioService _audioService;

  @override
  void initState() {
    super.initState();

    // オーディオサービスの取得
    _audioService = Provider.of<ImprovedAudioService>(context, listen: false);
    _audioService.initialize();

    // 現在の設定を取得
    final settings = Provider.of<ExperimentSettings>(context, listen: false);
    _calibrationDuration = settings.calibrationDuration;
    _silentWalkingDuration = settings.silentWalkingDuration;
    _syncDuration = settings.syncDuration;
    _guidance1Duration = settings.guidance1Duration;
    _guidance2Duration = settings.guidance2Duration;
    _cooldownDuration = settings.cooldownDuration;
    _tempoIncrement = settings.tempoIncrement;
    _clickSoundType = settings.clickSoundType;
    _volume = settings.volume;
    _precisionMode = _audioService.precisionMode; // 現在の精度モードを取得
  }

  @override
  void dispose() {
    if (_isPreviewPlaying) {
      _audioService.stopTempoCues();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('研究者設定'),
        centerTitle: true,
        actions: [
          // メトロノーム詳細設定画面へのリンクを追加
          IconButton(
            icon: const Icon(Icons.music_note),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const MetronomeSettingsScreen(),
                ),
              );
            },
            tooltip: 'メトロノーム詳細設定',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // フェーズ時間設定
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'フェーズ時間設定',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),

                        // キャリブレーション時間
                        _buildDurationSlider(
                          title: 'キャリブレーション',
                          value: _calibrationDuration,
                          min: 10,
                          max: 60,
                          step: 5,
                          onChanged: (value) {
                            setState(() {
                              _calibrationDuration = value.toInt();
                            });
                          },
                        ),

                        // 無音歩行時間
                        _buildDurationSlider(
                          title: '無音歩行',
                          value: _silentWalkingDuration,
                          min: 60,
                          max: 300,
                          step: 30,
                          onChanged: (value) {
                            setState(() {
                              _silentWalkingDuration = value.toInt();
                            });
                          },
                        ),

                        // 同期フェーズ時間
                        _buildDurationSlider(
                          title: '自然リズム同期',
                          value: _syncDuration,
                          min: 60,
                          max: 600,
                          step: 30,
                          onChanged: (value) {
                            setState(() {
                              _syncDuration = value.toInt();
                            });
                          },
                        ),

                        // 誘導フェーズ1時間
                        _buildDurationSlider(
                          title: 'リズム誘導1',
                          value: _guidance1Duration,
                          min: 60,
                          max: 600,
                          step: 30,
                          onChanged: (value) {
                            setState(() {
                              _guidance1Duration = value.toInt();
                            });
                          },
                        ),

                        // 誘導フェーズ2時間
                        _buildDurationSlider(
                          title: 'リズム誘導2',
                          value: _guidance2Duration,
                          min: 60,
                          max: 600,
                          step: 30,
                          onChanged: (value) {
                            setState(() {
                              _guidance2Duration = value.toInt();
                            });
                          },
                        ),

                        // クールダウン時間
                        _buildDurationSlider(
                          title: 'クールダウン',
                          value: _cooldownDuration,
                          min: 0,
                          max: 300,
                          step: 30,
                          onChanged: (value) {
                            setState(() {
                              _cooldownDuration = value.toInt();
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // テンポ設定
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'テンポ設定',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),

                        // テンポ増加幅
                        Row(
                          children: [
                            const Text('テンポ増加幅:'),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Slider(
                                value: _tempoIncrement,
                                min: 1.0,
                                max: 10.0,
                                divisions: 9,
                                label:
                                    '${_tempoIncrement.toStringAsFixed(1)} BPM',
                                onChanged: (value) {
                                  setState(() {
                                    _tempoIncrement = value;
                                  });
                                },
                              ),
                            ),
                            Text('${_tempoIncrement.toStringAsFixed(1)} BPM'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // 音設定
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '音設定',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),

                        // クリック音の種類
                        DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: 'クリック音の種類',
                            border: OutlineInputBorder(),
                          ),
                          value: _clickSoundType,
                          items: const [
                            DropdownMenuItem(
                              value: '標準クリック',
                              child: Text('標準クリック'),
                            ),
                            DropdownMenuItem(
                              value: '柔らかいクリック',
                              child: Text('柔らかいクリック'),
                            ),
                            DropdownMenuItem(
                              value: '木製クリック',
                              child: Text('木製クリック'),
                            ),
                            DropdownMenuItem(
                              value: 'ハイクリック',
                              child: Text('ハイクリック'),
                            ),
                          ],
                          onChanged: (value) async {
                            if (value != null) {
                              setState(() {
                                _clickSoundType = value;
                              });

                              // プレビュー中の場合は音を変更
                              if (_isPreviewPlaying) {
                                await _audioService
                                    .loadClickSound(_clickSoundType);
                                _audioService.startTempoCues(_previewTempo);
                              }
                            }
                          },
                        ),

                        const SizedBox(height: 16),

                        // 精度モード
                        DropdownButtonFormField<PrecisionMode>(
                          decoration: const InputDecoration(
                            labelText: '精度モード',
                            border: OutlineInputBorder(),
                            helperText: '高精度モードほど正確なタイミングで音を再生します',
                          ),
                          value: _precisionMode,
                          items: [
                            DropdownMenuItem(
                              value: PrecisionMode.basic,
                              child: Row(
                                children: const [
                                  Icon(Icons.speed, size: 16),
                                  SizedBox(width: 8),
                                  Text('標準'),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: PrecisionMode.highPrecision,
                              child: Row(
                                children: const [
                                  Icon(Icons.high_quality, size: 16),
                                  SizedBox(width: 8),
                                  Text('高精度'),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: PrecisionMode.synthesized,
                              child: Row(
                                children: const [
                                  Icon(Icons.music_note, size: 16),
                                  SizedBox(width: 8),
                                  Text('合成音'),
                                ],
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _precisionMode = value;
                              });
                              _audioService.setPrecisionMode(value);

                              // プレビュー中の場合は再起動
                              if (_isPreviewPlaying) {
                                _audioService.stopTempoCues();
                                _audioService.startTempoCues(_previewTempo);
                              }
                            }
                          },
                        ),

                        const SizedBox(height: 16),

                        // 音量
                        Row(
                          children: [
                            const Icon(Icons.volume_down),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Slider(
                                value: _volume,
                                min: 0.0,
                                max: 1.0,
                                onChanged: (value) {
                                  setState(() {
                                    _volume = value;
                                  });
                                  _audioService.setVolume(_volume);
                                },
                              ),
                            ),
                            const Icon(Icons.volume_up),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // プレビュー
                        Row(
                          children: [
                            const Text('テンポ:'),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Slider(
                                value: _previewTempo,
                                min: 60.0,
                                max: 160.0,
                                divisions: 20,
                                label: '${_previewTempo.toInt()} BPM',
                                onChanged: (value) {
                                  setState(() {
                                    _previewTempo = value;
                                  });
                                  if (_isPreviewPlaying) {
                                    _audioService.updateTempo(_previewTempo);
                                  }
                                },
                              ),
                            ),
                            Text('${_previewTempo.toInt()} BPM'),
                          ],
                        ),

                        const SizedBox(height: 8),

                        Center(
                          child: ElevatedButton.icon(
                            icon: Icon(_isPreviewPlaying
                                ? Icons.stop
                                : Icons.play_arrow),
                            label: Text(_isPreviewPlaying ? '停止' : 'プレビュー'),
                            onPressed: () async {
                              if (_isPreviewPlaying) {
                                _audioService.stopTempoCues();
                              } else {
                                await _audioService
                                    .loadClickSound(_clickSoundType);
                                _audioService.setPrecisionMode(_precisionMode);
                                _audioService.setVolume(_volume);
                                _audioService.startTempoCues(_previewTempo);
                              }

                              setState(() {
                                _isPreviewPlaying = !_isPreviewPlaying;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // 保存ボタン
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveSettings,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      '設定を保存',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // リセットボタン
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _resetSettings,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      'デフォルト設定に戻す',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 時間設定スライダー
  Widget _buildDurationSlider({
    required String title,
    required int value,
    required double min,
    required double max,
    required double step,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title),
        Row(
          children: [
            Text('${value}秒'),
            Expanded(
              child: Slider(
                value: value.toDouble(),
                min: min,
                max: max,
                divisions: ((max - min) / step).floor(),
                label: '${value}秒',
                onChanged: onChanged,
              ),
            ),
            Text('${value ~/ 60}分${value % 60}秒'),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // 設定保存
  void _saveSettings() {
    final settings = Provider.of<ExperimentSettings>(context, listen: false);

    // フェーズ時間設定を更新
    settings.updateExperimentDurations(
      calibration: _calibrationDuration,
      silentWalking: _silentWalkingDuration,
      sync: _syncDuration,
      guidance1: _guidance1Duration,
      guidance2: _guidance2Duration,
      cooldown: _cooldownDuration,
    );

    // テンポ設定を更新
    settings.updateTempoSettings(
      increment: _tempoIncrement,
    );

    // 音設定を更新
    settings.updateSoundSettings(
      soundType: _clickSoundType,
      newVolume: _volume,
      useImprovedAudio: true, // 常にImprovedAudioServiceを使用
    );

    // 精度モードの保存
    _audioService.setPrecisionMode(_precisionMode);

    // 完了メッセージ
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('設定を保存しました'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // 設定リセット
  void _resetSettings() {
    setState(() {
      _calibrationDuration = 30;
      _silentWalkingDuration = 180;
      _syncDuration = 300;
      _guidance1Duration = 300;
      _guidance2Duration = 300;
      _cooldownDuration = 120;
      _tempoIncrement = 5.0;
      _clickSoundType = '標準クリック';
      _volume = 0.7;
      _precisionMode = PrecisionMode.highPrecision;
    });

    // 音声設定も初期化
    _audioService.setPrecisionMode(PrecisionMode.highPrecision);
    _audioService.setVolume(_volume);
    _audioService.loadClickSound(_clickSoundType);

    // 完了メッセージ
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('設定をデフォルトに戻しました'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
