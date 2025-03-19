import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../services/improved_audio_service.dart';

class MetronomeSettingsScreen extends StatefulWidget {
  const MetronomeSettingsScreen({Key? key}) : super(key: key);

  @override
  State<MetronomeSettingsScreen> createState() =>
      _MetronomeSettingsScreenState();
}

class _MetronomeSettingsScreenState extends State<MetronomeSettingsScreen> {
  late ImprovedAudioService _audioService;

  // 設定用の状態変数
  double _frequency = 800.0;
  double _duration = 0.02;
  double _volume = 0.7;
  WaveformType _waveformType = WaveformType.sine;
  PrecisionMode _precisionMode = PrecisionMode.highPrecision;

  // サウンドタイプのリスト
  final List<String> _soundTypes = [
    '標準クリック',
    '柔らかいクリック',
    '木製クリック',
    'ハイクリック',
  ];

  // 波形タイプのリスト
  final Map<WaveformType, String> _waveformNames = {
    WaveformType.sine: '正弦波',
    WaveformType.square: '矩形波',
    WaveformType.triangle: '三角波',
    WaveformType.sawtooth: 'のこぎり波',
  };

  // 精度モードのリスト
  final Map<PrecisionMode, String> _precisionModeNames = {
    PrecisionMode.basic: '基本',
    PrecisionMode.highPrecision: '高精度',
    PrecisionMode.synthesized: '合成',
  };

  String _currentSoundType = '標準クリック';
  bool _isTestPlaying = false;
  double _testTempo = 100.0;
  bool _isDiagnosticRunning = false;
  Map<String, dynamic>? _diagnosticResults;

  @override
  void initState() {
    super.initState();
    _audioService = Provider.of<ImprovedAudioService>(context, listen: false);
    _currentSoundType = _audioService.currentSoundType;
    _precisionMode = _audioService.precisionMode;

    // 必要に応じてサービスの初期化を待つ
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _audioService.initialize();
      setState(() {
        // 設定値を更新
      });
    });
  }

  @override
  void dispose() {
    // テスト再生中なら停止
    if (_isTestPlaying) {
      _audioService.stopTempoCues();
    }
    super.dispose();
  }

  // テスト再生の切り替え
  void _toggleTestPlay() {
    setState(() {
      if (_isTestPlaying) {
        _audioService.stopTempoCues();
        _isTestPlaying = false;
      } else {
        // オーディオサービスが初期化されているか確認
        if (!_audioService.isInitialized) {
          _showLoading(context);
          _audioService.initialize().then((_) {
            Navigator.of(context).pop(); // ローディング表示を閉じる
            _startPreview();
          }).catchError((error) {
            Navigator.of(context).pop(); // ローディング表示を閉じる
            _showError('オーディオの初期化に失敗しました: $error');
          });
        } else {
          _startPreview();
        }
      }
    });
  }

  void _startPreview() {
    // まずサウンドがロードされていることを確認
    _audioService.loadClickSound(_currentSoundType).then((success) {
      if (success) {
        // 軽量プレビューモードを使用
        _audioService.setPreviewMode(true);
        _audioService.startTempoCues(_testTempo);
        setState(() {
          _isTestPlaying = true;
        });
      } else {
        _showError('サウンドのロードに失敗しました');
      }
    });
  }

  // ローディング表示
  void _showLoading(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text("オーディオを準備中..."),
              ],
            ),
          ),
        );
      },
    );
  }

  // エラー表示
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  // 音色の適用
  void _applySoundSettings() {
    _audioService.setFrequency(_frequency);
    _audioService.setClickDuration(_duration);
    _audioService.setWaveform(_waveformType);
    _audioService.setVolume(_volume);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('メトロノーム設定を適用しました')),
    );

    // 再生中なら一度停止して再開
    if (_isTestPlaying) {
      _audioService.stopTempoCues();
      _audioService.setPreviewMode(true); // プレビューモードを維持
      _audioService.startTempoCues(_testTempo);
    }
  }

  // 診断テスト実行
  void _runDiagnosticTest() async {
    setState(() {
      _isDiagnosticRunning = true;
    });

    final results = await _audioService.runDiagnostics();

    setState(() {
      _isDiagnosticRunning = false;
      _diagnosticResults = results;
    });

    _showDiagnosticResults(results);
  }

  // 診断結果表示
  void _showDiagnosticResults(Map<String, dynamic> results) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('メトロノーム診断結果'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '基本タイミングテスト: ${_getStatusIcon(results['basicTimingTest']['status'])}'),
            SizedBox(height: 8),
            if (results['basicTimingTest']['status'] == 'success') ...[
              Text(
                  '平均間隔: ${results['basicTimingTest']['avgInterval'].toStringAsFixed(2)}ms'),
              Text(
                  '標準偏差: ${results['basicTimingTest']['stdDev'].toStringAsFixed(2)}ms'),
              Text('最大ジッター: ${results['basicTimingTest']['maxJitter']}ms'),
              Text(
                  '品質評価: ${_getQualityText(results['basicTimingTest']['quality'])}'),
            ],
            Divider(),
            Text(
                'システム負荷テスト: ${_getStatusIcon(results['systemLoadTest']['status'])}'),
            Text(
                'オーディオセッション: ${_getStatusIcon(results['audioSessionCheck']['status'])}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('閉じる'),
          ),
        ],
      ),
    );
  }

  // ステータスアイコン取得
  Widget _getStatusIcon(String status) {
    if (status == 'success') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: 16),
          SizedBox(width: 4),
          Text('成功'),
        ],
      );
    } else {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error, color: Colors.red, size: 16),
          SizedBox(width: 4),
          Text('失敗'),
        ],
      );
    }
  }

  // 品質テキスト取得
  String _getQualityText(String quality) {
    switch (quality) {
      case 'excellent':
        return '優秀 ✓✓✓';
      case 'good':
        return '良好 ✓✓';
      case 'acceptable':
        return '許容範囲 ✓';
      case 'poor':
        return '改善が必要 ✗';
      default:
        return quality;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('メトロノーム設定'),
        actions: [
          // 診断ツールボタン追加
          IconButton(
            icon: Icon(Icons.bug_report),
            onPressed: _isDiagnosticRunning ? null : _runDiagnosticTest,
            tooltip: 'メトロノーム診断',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // プリセット音色選択
            const Text('プリセット音色',
                style: TextStyle(fontWeight: FontWeight.bold)),
            DropdownButton<String>(
              value: _currentSoundType,
              isExpanded: true,
              onChanged: (value) async {
                if (value != null) {
                  setState(() {
                    _currentSoundType = value;
                  });
                  await _audioService.loadClickSound(value);

                  // テスト再生中なら一度停止して再開
                  if (_isTestPlaying) {
                    _audioService.stopTempoCues();
                    _audioService.setPreviewMode(true); // プレビューモードを設定
                    _audioService.startTempoCues(_testTempo);
                  }
                }
              },
              items: _soundTypes.map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // 精度モード選択
            const Text('精度モード', style: TextStyle(fontWeight: FontWeight.bold)),
            DropdownButton<PrecisionMode>(
              value: _precisionMode,
              isExpanded: true,
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _precisionMode = value;
                  });
                  _audioService.setPrecisionMode(value);
                }
              },
              items: _precisionModeNames.entries
                  .map<DropdownMenuItem<PrecisionMode>>((entry) {
                return DropdownMenuItem<PrecisionMode>(
                  value: entry.key,
                  child: Text(entry.value),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // カスタム設定
            const Text('カスタム設定', style: TextStyle(fontWeight: FontWeight.bold)),

            // 周波数設定
            const Text('周波数 (Hz)'),
            Slider(
              value: _frequency,
              min: 200.0,
              max: 2000.0,
              divisions: 36,
              label: '${_frequency.round()} Hz',
              onChanged: (value) {
                setState(() {
                  _frequency = value;
                });
              },
            ),

            // 音の長さ設定
            const Text('音の長さ (秒)'),
            Slider(
              value: _duration,
              min: 0.005,
              max: 0.1,
              divisions: 19,
              label: '${(_duration * 1000).round()} ms',
              onChanged: (value) {
                setState(() {
                  _duration = value;
                });
              },
            ),

            // 音量設定
            const Text('音量'),
            Slider(
              value: _volume,
              min: 0.1,
              max: 1.0,
              divisions: 9,
              label: '${(_volume * 100).round()}%',
              onChanged: (value) {
                setState(() {
                  _volume = value;
                });
                _audioService.setVolume(value);
              },
            ),

            // 波形タイプ選択
            const Text('波形'),
            DropdownButton<WaveformType>(
              value: _waveformType,
              isExpanded: true,
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _waveformType = value;
                  });
                }
              },
              items: _waveformNames.entries
                  .map<DropdownMenuItem<WaveformType>>((entry) {
                return DropdownMenuItem<WaveformType>(
                  value: entry.key,
                  child: Text(entry.value),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // 設定適用ボタン
            ElevatedButton(
              onPressed: _applySoundSettings,
              child: const Text('設定を適用'),
            ),

            const SizedBox(height: 24),

            // テスト再生設定
            const Text('テスト再生', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _testTempo,
                    min: 40.0,
                    max: 240.0,
                    divisions: 200,
                    label: '${_testTempo.round()} BPM',
                    onChanged: (value) {
                      setState(() {
                        _testTempo = value;
                        if (_isTestPlaying) {
                          _audioService.updateTempo(value);
                        }
                      });
                    },
                  ),
                ),
                ElevatedButton(
                  onPressed: _toggleTestPlay,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isTestPlaying ? Colors.red : Colors.green,
                  ),
                  child: Text(_isTestPlaying ? '停止' : '再生'),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 精度テスト（開発用）
            if (kDebugMode) // デバッグモードでのみ表示
              ElevatedButton(
                onPressed: () {
                  _audioService.checkTempoAccuracy(10); // 10秒間テスト
                },
                child: const Text('精度テスト (10秒)'),
              ),

            const SizedBox(height: 24),

            // サポート情報
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'メトロノーム使用のヒント',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('・高精度モードは最も正確ですが、低バッテリー状態では使用を避けてください。'),
                    Text('・合成モードは長時間の使用に最適化されています。'),
                    Text('・標準クリックは最もシャープな音で、柔らかいクリックは長い練習に適しています。'),
                    Text('・システム音量も適切に設定してください。'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
