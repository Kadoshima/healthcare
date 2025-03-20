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

void main() async {
  // Flutter初期化を確実に実行
  WidgetsFlutterBinding.ensureInitialized();

  // キーボードの自動表示を防止
  SystemChannels.textInput.invokeMethod('TextInput.hide');

  // 画面がスリープしないように設定
  await WakelockPlus.enable();

  // 環境変数の読み込み
  try {
    await dotenv.load(fileName: ".env");
    print("環境変数を読み込みました");
  } catch (e) {
    print("環境変数の読み込みに失敗しました: $e");
    // .envファイルがない場合でも続行できるようにする
  }

  // データベースサービスの初期化
  final databaseService = DatabaseService();
  await databaseService.initialize();

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
        Provider<SensorService>(
            create: (_) => SensorService()), // 改良版SensorService
        Provider<ImprovedAudioService>(create: (_) => ImprovedAudioService()),
        Provider<AzureStorageService>.value(value: azureStorageService),
      ],
      child: const WalkingRhythmApp(),
    ),
  );
}

// 必要な権限を要求する関数
Future<void> _requestPermissions() async {
  // 権限の実装...
}

class WalkingRhythmApp extends StatefulWidget {
  const WalkingRhythmApp({Key? key}) : super(key: key);

  @override
  State<WalkingRhythmApp> createState() => _WalkingRhythmAppState();
}

class _WalkingRhythmAppState extends State<WalkingRhythmApp> {
  @override
  void initState() {
    super.initState();

    // 各サービスの非同期初期化処理
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeServices();
    });
  }

  // サービスの初期化
  Future<void> _initializeServices() async {
    try {
      // ImprovedAudioServiceの初期化
      final improvedAudioService =
          Provider.of<ImprovedAudioService>(context, listen: false);
      await improvedAudioService.initialize();

      // 高精度モードを設定
      improvedAudioService.setPrecisionMode(PrecisionMode.highPrecision);

      // 標準のクリック音を設定
      await improvedAudioService.loadClickSound('標準クリック');

      // SensorServiceの初期化
      final sensorService = Provider.of<SensorService>(context, listen: false);
      await sensorService.initialize();

      print('All services initialized successfully');
    } catch (e) {
      print('Failed to initialize services: $e');
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

      // 初期画面の設定
      home: const HomeScreen(),

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
}
