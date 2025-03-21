import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/experiment_settings.dart';
import '../services/sensor_service.dart'; // SensorService をインポート
import 'experiment_screen.dart';
import 'researcher_dashboard.dart';
import 'experiment_history_screen.dart';
import 'calibration_screen.dart'; // キャリブレーション画面をインポート

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _formKey = GlobalKey<FormState>();

  // 被験者情報
  final _subjectIdController = TextEditingController();
  int? _subjectAge;
  String _subjectGender = '男性';

  // 装着位置
  String _sensorPosition = '腰部';

  // 権限状態
  bool _hasPermissions = false;

  // キャリブレーション状態を追跡
  bool _isCalibrated = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _checkCalibrationStatus();

    // フォーカスを強制的に解除し、キーボードを非表示にする
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  // 権限チェック
  Future<void> _checkPermissions() async {
    // センサー使用権限は特に必要ないが、オーディオとストレージの権限は確認
    final storageStatus = await Permission.storage.status;
    setState(() {
      _hasPermissions = storageStatus.isGranted;
    });
  }

  // キャリブレーション状態のチェック
  void _checkCalibrationStatus() {
    // SensorServiceのキャリブレーション状態を確認
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sensorService = Provider.of<SensorService>(context, listen: false);
      setState(() {
        _isCalibrated = sensorService.calibrationPoints.isNotEmpty;
      });
    });
  }

  // 権限リクエスト
  Future<void> _requestPermissions() async {
    final storageStatus = await Permission.storage.request();

    setState(() {
      _hasPermissions = storageStatus.isGranted;
    });
  }

  @override
  void dispose() {
    _subjectIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 画面サイズを取得
    final screenSize = MediaQuery.of(context).size;

    return GestureDetector(
      // タップでフォーカスを外し、キーボードを閉じる
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('歩行リズム誘導アプリ'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const ResearcherDashboard(),
                  ),
                );
              },
            ),
          ],
        ),
        // スクロール可能な領域にする
        body: SingleChildScrollView(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 権限チェック
                  if (!_hasPermissions)
                    Card(
                      color: Colors.amber.shade100,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '必要な権限が許可されていません',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'アプリの実行には権限の許可が必要です。「権限を許可」をタップして必要な権限を許可してください。',
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _requestPermissions,
                              child: const Text('権限を許可'),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // キャリブレーション状態表示とボタン
                  Card(
                    color: _isCalibrated
                        ? Colors.green.shade50
                        : Colors.amber.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _isCalibrated
                                    ? Icons.check_circle
                                    : Icons.warning,
                                color:
                                    _isCalibrated ? Colors.green : Colors.amber,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'センサーキャリブレーション',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isCalibrated
                                ? 'センサーはキャリブレーション済みです。必要に応じて再キャリブレーションを行ってください。'
                                : '高精度な測定のため、実験前にセンサーのキャリブレーションを行ってください。',
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.tune),
                              label: Text(_isCalibrated
                                  ? 'センサーを再キャリブレーション'
                                  : 'センサーをキャリブレーション'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    _isCalibrated ? Colors.green : Colors.amber,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () {
                                _navigateToCalibration(context);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 実験説明
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '実験の概要',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          // 説明文をスクロール可能な領域に配置
                          Container(
                            constraints: BoxConstraints(
                              maxHeight:
                                  screenSize.height * 0.25, // 画面の25%の高さ制限
                            ),
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text(
                                    'この実験では、歩行リズムと音のテンポの関係を調査します。実験中はスマートフォンを所定の位置に装着し、'
                                    '指示に従って歩行してください。途中でテンポが変化することがありますが、自然に歩き続けてください。',
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    '実験の流れ:',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  SizedBox(height: 4),
                                  Text('1. キャリブレーション (30秒)'),
                                  Text('2. 無音状態での歩行 (3分間)'),
                                  Text('3. 自然リズムと同じテンポの音を提示 (5分間)'),
                                  Text('4. テンポを段階的に上昇 (5分ずつ)'),
                                  Text('5. クールダウン (2分間)'),
                                  SizedBox(height: 8),
                                  Text(
                                    '実験時間は約20分です。いつでも実験を中止することができます。',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 被験者情報入力フォーム
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '被験者情報',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),

                            // 被験者ID
                            TextFormField(
                              controller: _subjectIdController,
                              decoration: const InputDecoration(
                                labelText: '被験者ID *',
                                border: OutlineInputBorder(),
                                hintText: '例: S001',
                              ),
                              // 自動フォーカスを無効化
                              autofocus: false,
                              // キーボードタイプを制限
                              keyboardType: TextInputType.text,
                              // エンターキーの種類を変更
                              textInputAction: TextInputAction.next,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return '被験者IDを入力してください';
                                }
                                return null;
                              },
                            ),

                            const SizedBox(height: 16),

                            // 年齢
                            TextFormField(
                              decoration: const InputDecoration(
                                labelText: '年齢',
                                border: OutlineInputBorder(),
                                hintText: '例: 25',
                              ),
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                              autofocus: false,
                              onChanged: (value) {
                                if (value.isNotEmpty) {
                                  setState(() {
                                    _subjectAge = int.tryParse(value);
                                  });
                                }
                              },
                            ),

                            const SizedBox(height: 16),

                            // 性別
                            DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                labelText: '性別',
                                border: OutlineInputBorder(),
                              ),
                              value: _subjectGender,
                              items: const [
                                DropdownMenuItem(
                                  value: '男性',
                                  child: Text('男性'),
                                ),
                                DropdownMenuItem(
                                  value: '女性',
                                  child: Text('女性'),
                                ),
                                DropdownMenuItem(
                                  value: 'その他',
                                  child: Text('その他'),
                                ),
                                DropdownMenuItem(
                                  value: '回答しない',
                                  child: Text('回答しない'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    _subjectGender = value;
                                  });
                                }
                              },
                            ),

                            const SizedBox(height: 16),

                            // センサー装着位置
                            DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                labelText: 'センサー装着位置',
                                border: OutlineInputBorder(),
                              ),
                              value: _sensorPosition,
                              items: const [
                                DropdownMenuItem(
                                  value: '腰部',
                                  child: Text('腰部'),
                                ),
                                DropdownMenuItem(
                                  value: '足首',
                                  child: Text('足首'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    _sensorPosition = value;
                                  });
                                }
                              },
                            ),

                            const SizedBox(height: 24),

                            // 実験開始ボタン
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed:
                                    _hasPermissions ? _startExperiment : null,
                                style: ElevatedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                ),
                                child: const Text(
                                  '実験を開始',
                                  style: TextStyle(fontSize: 18),
                                ),
                              ),
                            ),

                            const SizedBox(height: 8),

                            // 実験履歴ボタン
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const ExperimentHistoryScreen(),
                                    ),
                                  );
                                },
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                ),
                                child: const Text(
                                  '実験履歴を表示',
                                  style: TextStyle(fontSize: 18),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 画面下部の余白を確保
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // キャリブレーション画面への遷移
  Future<void> _navigateToCalibration(BuildContext context) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const CalibrationScreen(),
      ),
    );

    // キャリブレーション画面から戻ってきたら状態を更新
    if (mounted) {
      _checkCalibrationStatus();
    }
  }

  // 実験開始
  void _startExperiment() {
    if (!_formKey.currentState!.validate()) return;

    // 被験者情報を設定
    final settings = Provider.of<ExperimentSettings>(context, listen: false);
    settings.setSubjectInfo(
      id: _subjectIdController.text,
      age: _subjectAge,
      gender: _subjectGender,
    );

    // センサー設定を更新
    settings.sensorPosition = _sensorPosition;

    // 実験画面に遷移
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ExperimentScreen(),
      ),
    );
  }
}
