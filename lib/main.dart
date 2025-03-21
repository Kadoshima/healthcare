import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

// サービス
import 'services/database_service.dart';
import 'services/experiment_service.dart';
import 'services/sensor_service.dart';
import 'services/improved_audio_service.dart';
import 'services/azure_storage_service.dart';

// モデル
import 'models/experiment_settings.dart';

// 画面
import 'screens/home_screen.dart';
import 'screens/experiment_screen.dart';
import 'screens/improved_experiment_screen.dart'; // 改良版実験画面
import 'screens/calibration_screen.dart'; // キャリブレーション画面
import 'screens/results_screen.dart';
import 'screens/researcher_dashboard.dart';
import 'screens/metronome_settings_screen.dart';
import 'widgets/walking_rhythm_metrics.dart'; // 精度メトリクス表示ウィジェット
import 'widgets/experiment_results_summary.dart'; // 実験結果サマリーウィジェット

// デバッグモードフラグ（ロギングを有効化）
bool debugMode = true;

// デバッグログ出力関数
void debugLog(String message) {
  if (debugMode) {
    print('[DEBUG] $message');
  }
}

// グローバルインスタンス（アプリ全体でアクセス可能）
// これにより、画面間でのデータ共有が確実になります
final SensorService globalSensorService = SensorService();
final ImprovedAudioService globalAudioService = ImprovedAudioService();

void main() async {
  // Flutter初期化を確実に実行
  WidgetsFlutterBinding.ensureInitialized();

  debugLog('アプリケーション初期化開始');

  // キーボードの自動表示を防止
  SystemChannels.textInput.invokeMethod('TextInput.hide');

  // 画面がスリープしないように設定
  await WakelockPlus.enable();
  debugLog('Wakelockを有効化しました');

  // 環境変数の読み込み
  try {
    await dotenv.load(fileName: ".env");
    debugLog("環境変数を読み込みました");
  } catch (e) {
    debugLog("環境変数の読み込みに失敗しました: $e");
    // .envファイルがない場合でも続行できるようにする
  }

  // データベースサービスの初期化
  final databaseService = DatabaseService();
  await databaseService.initialize();
  debugLog('データベースサービスを初期化しました');

  // グローバルサービスの初期化
  await globalSensorService.initialize();
  await globalAudioService.initialize();
  debugLog('グローバルサービスを初期化しました');

  // Azure Storage設定
  final azureStorageService = AzureStorageService(
    accountName: 'hagiharatest', // 実際のAzureアカウント名
    accountKey:
        dotenv.env['AZURE_STORAGE_ACCOUNT_KEY'] ?? '', // Azure Storageアカウントキー
    containerName: 'healthcaredata', // コンテナ名
  );

  // 各種権限を要求
  await _requestPermissions();

  // アプリケーション起動
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ExperimentSettings()),
        Provider<DatabaseService>.value(value: databaseService),
        ProxyProvider<DatabaseService, ExperimentService>(
          update: (_, databaseService, __) =>
              ExperimentService(databaseService),
        ),
        // グローバルインスタンスを提供
        Provider<SensorService>.value(value: globalSensorService),
        Provider<ImprovedAudioService>.value(value: globalAudioService),
        Provider<AzureStorageService>.value(value: azureStorageService),
      ],
      child: const WalkingRhythmApp(),
    ),
  );

  debugLog('アプリケーション初期化完了');
}

// 必要な権限を要求する関数
Future<void> _requestPermissions() async {
  // 権限の実装...
  debugLog('アプリ権限をリクエストしました');
}

class WalkingRhythmApp extends StatefulWidget {
  const WalkingRhythmApp({Key? key}) : super(key: key);

  @override
  State<WalkingRhythmApp> createState() => _WalkingRhythmAppState();
}

class _WalkingRhythmAppState extends State<WalkingRhythmApp> {
  bool _servicesInitialized = false;
  String _initializationError = '';

  @override
  void initState() {
    super.initState();

    // グローバルサービスはすでに初期化されているので、
    // 状態を確認するだけで良い
    _checkServiceStatus();
  }

  // サービスの状態確認
  void _checkServiceStatus() {
    setState(() {
      _servicesInitialized =
          globalSensorService.isInitialized && globalAudioService.isInitialized;
      _initializationError = '';
    });

    if (!_servicesInitialized) {
      _initializeServices();
    }
  }

  // サービスの初期化（必要な場合のみ）
  Future<void> _initializeServices() async {
    try {
      debugLog('サービスの初期化を開始します');

      // SensorServiceの初期化が必要な場合
      if (!globalSensorService.isInitialized) {
        bool sensorInitialized = await globalSensorService.initialize();
        if (!sensorInitialized) {
          throw Exception("センサーサービスの初期化に失敗しました");
        }
        debugLog('センサーサービスを初期化しました');
      }

      // ImprovedAudioServiceの初期化が必要な場合
      if (!globalAudioService.isInitialized) {
        bool audioInitialized = await globalAudioService.initialize();
        if (!audioInitialized) {
          throw Exception("オーディオサービスの初期化に失敗しました");
        }
        debugLog('オーディオサービスを初期化しました');

        // 高精度モードを設定
        globalAudioService.setPrecisionMode(PrecisionMode.highPrecision);
        debugLog('オーディオサービスを高精度モードに設定しました');

        // 標準のクリック音を設定
        bool soundLoaded = await globalAudioService.loadClickSound('標準クリック');
        if (!soundLoaded) {
          throw Exception("クリック音のロードに失敗しました");
        }
        debugLog('標準クリック音をロードしました');
      }

      // 初期化完了を設定
      setState(() {
        _servicesInitialized = true;
        _initializationError = '';
      });

      debugLog('全てのサービスが正常に初期化されました');
    } catch (e) {
      debugLog('サービスの初期化に失敗しました: $e');
      setState(() {
        _servicesInitialized = false;
        _initializationError = e.toString();
      });

      // ユーザーに通知（必要に応じて）
      _showErrorDialog('初期化エラー', 'サービスの初期化に失敗しました: $e');
    }
  }

  // エラーダイアログを表示
  void _showErrorDialog(String title, String message) {
    // アプリが十分に初期化されている場合のみダイアログを表示
    if (mounted && context != null) {
      Future.delayed(Duration.zero, () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  // 再初期化を試みる
                  _initializeServices();
                },
                child: const Text('再試行'),
              ),
            ],
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Walking Rhythm App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),

      // デバッグバナーを非表示
      debugShowCheckedModeBanner: false,

      // 初期化状態に応じて初期画面を設定
      home: _servicesInitialized ? const HomeScreen() : _buildLoadingScreen(),

      // ルート定義
      routes: {
        '/home': (context) => const HomeScreen(),
        '/experiment': (context) => const ExperimentScreen(),
        '/improved_experiment': (context) =>
            const ImprovedExperimentScreen(), // 改良版実験画面
        '/calibration': (context) => const CalibrationScreen(), // キャリブレーション画面
        '/results': (context) => ResultsScreen(sessionId: 0),
        '/researcher_dashboard': (context) => const ResearcherDashboard(),
        '/metronome_settings': (context) => const MetronomeSettingsScreen(),
      },
    );
  }

  // 読み込み画面の構築
  Widget _buildLoadingScreen() {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            const Text('アプリケーションを初期化中...', style: TextStyle(fontSize: 18)),
            if (_initializationError.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'エラー: $_initializationError',
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _initializeServices,
                child: const Text('再試行'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
