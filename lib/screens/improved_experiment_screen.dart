import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import '../models/experiment_settings.dart';
import '../models/gait_data.dart';
import '../services/sensor_service.dart';
import '../services/improved_audio_service.dart';
import '../services/experiment_service.dart';
import '../widgets/phase_timer.dart';
import '../widgets/tempo_display.dart';
import 'calibration_screen.dart';
import 'results_screen.dart';

// Global debug logging
bool debugMode = true;
void debugLog(String message) {
  if (debugMode) {
    print('[DEBUG] $message');
  }
}

class ImprovedExperimentScreen extends StatefulWidget {
  const ImprovedExperimentScreen({Key? key}) : super(key: key);

  @override
  State<ImprovedExperimentScreen> createState() =>
      _ImprovedExperimentScreenState();
}

class _ImprovedExperimentScreenState extends State<ImprovedExperimentScreen> {
  // Services
  late SensorService _sensorService;
  late ImprovedAudioService _audioService;
  late ExperimentService _experimentService;

  // Subscriptions
  StreamSubscription<double>? _gaitRhythmSubscription;
  StreamSubscription<GaitRhythmData>? _gaitDataSubscription;

  // State
  double _currentBpm = 0.0;
  double _targetBpm = 0.0;
  final List<FlSpot> _rhythmDataPoints = [];
  final int _maxDataPoints = 100; // Number of data points for graph display

  // Initialization state
  bool _isInitializing = true;
  String _initError = '';
  bool _servicesReady = false;

  // Session ID
  int? _sessionId;

  @override
  void initState() {
    super.initState();
    debugLog('Initializing experiment screen');

    // Initialize services
    _initializeServices();
  }

  // Initialize services and check calibration
  Future<void> _initializeServices() async {
    setState(() {
      _isInitializing = true;
      _initError = '';
    });

    try {
      // Get services
      _sensorService = Provider.of<SensorService>(context, listen: false);
      _audioService = Provider.of<ImprovedAudioService>(context, listen: false);
      _experimentService =
          Provider.of<ExperimentService>(context, listen: false);

      debugLog('Initializing audio service');

      // Initialize audio service
      bool audioInitialized = await _audioService.initialize();
      if (!audioInitialized) {
        throw Exception('Failed to initialize audio service');
      }

      debugLog('Audio service initialized');

      // Initialize sensor service
      debugLog('Initializing sensor service');
      bool sensorInitialized = await _sensorService.initialize();
      if (!sensorInitialized) {
        throw Exception('Failed to initialize sensor service');
      }

      debugLog('Sensor service initialized');

      // All services ready
      setState(() {
        _servicesReady = true;
        _isInitializing = false;
      });

      debugLog('All services initialized');

      // Check calibration status
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkCalibrationAndProceed();
      });
    } catch (e) {
      debugLog('Initialization error: $e');
      setState(() {
        _isInitializing = false;
        _servicesReady = false;
        _initError = e.toString();
      });

      // Show error
      _showError('Initialization Error', e.toString());
    }
  }

  // Check calibration and start experiment
  Future<void> _checkCalibrationAndProceed() async {
    if (!_servicesReady) return;

    debugLog('Checking calibration status');

    // Check calibration points
    if (_sensorService.calibrationPoints.isEmpty) {
      debugLog('Calibration not performed');
      // Show dialog for calibration
      _showCalibrationDialog();
    } else {
      debugLog(
          'Calibration already completed: ${_sensorService.calibrationPoints.length} points');
      // Start experiment
      _startExperiment();
    }
  }

  // Show calibration dialog
  void _showCalibrationDialog() {
    debugLog('Showing calibration dialog');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Calibration Required'),
        content: const Text(
            'For accurate measurements, sensor calibration is needed. '
            'Calibration allows for more precise walking rhythm measurement.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Continue without calibration (reduced accuracy)
              debugLog('Skipping calibration');
              _startExperiment();
            },
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _navigateToCalibration();
            },
            child: const Text('Perform Calibration'),
          ),
        ],
      ),
    );
  }

  // Navigate to calibration screen
  Future<void> _navigateToCalibration() async {
    debugLog('Navigating to calibration screen');

    // Navigate to calibration screen
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const CalibrationScreen(),
      ),
    );

    debugLog('Returned from calibration screen: $result');

    // Start experiment after calibration
    _startExperiment();
  }

  // Start experiment
  Future<void> _startExperiment() async {
    debugLog('Starting experiment');

    final settings = Provider.of<ExperimentSettings>(context, listen: false);

    // Create experiment session
    _sessionId = await _experimentService.startExperimentSession(settings);
    debugLog('Created experiment session: session ID = $_sessionId');

    // Subscribe to sensor data
    _gaitRhythmSubscription = _sensorService.gaitRhythmStream.listen((bpm) {
      setState(() {
        _currentBpm = bpm;
      });

      // Record experiment data
      _experimentService.addGaitRhythmData(
        bpm,
        settings.currentPhase,
        _targetBpm,
      );
    });
    debugLog('Subscribed to gait rhythm data');

    // Subscribe to experiment data
    _gaitDataSubscription = _experimentService.gaitDataStream.listen((data) {
      setState(() {
        // Add data point for graph
        _rhythmDataPoints.add(FlSpot(
          _rhythmDataPoints.length.toDouble(),
          data.bpm,
        ));

        // Remove old data points if exceeding max
        if (_rhythmDataPoints.length > _maxDataPoints) {
          _rhythmDataPoints.removeAt(0);

          // Adjust X values
          for (var i = 0; i < _rhythmDataPoints.length; i++) {
            _rhythmDataPoints[i] = FlSpot(i.toDouble(), _rhythmDataPoints[i].y);
          }
        }
      });
    });
    debugLog('Subscribed to experiment data');

    // Start sensor
    _sensorService.startSensing();
    debugLog('Started sensor');

    // Start from calibration
    settings.startExperiment();
    _processPhaseChange(settings);
    debugLog('Started experiment: phase = ${settings.currentPhase}');
  }

  // Process phase change
  void _processPhaseChange(ExperimentSettings settings) {
    debugLog('Phase changed: ${settings.currentPhase}');

    // Process based on current phase
    switch (settings.currentPhase) {
      case ExperimentPhase.calibration:
        _startCalibrationPhase(settings);
        break;
      case ExperimentPhase.silentWalking:
        _startSilentWalkingPhase(settings);
        break;
      case ExperimentPhase.syncWithNaturalTempo:
        _startSyncPhase(settings);
        break;
      case ExperimentPhase.rhythmGuidance1:
        _startGuidance1Phase(settings);
        break;
      case ExperimentPhase.rhythmGuidance2:
        _startGuidance2Phase(settings);
        break;
      case ExperimentPhase.cooldown:
        _startCooldownPhase(settings);
        break;
      case ExperimentPhase.completed:
        _completeExperiment();
        break;
      default:
        break;
    }
  }

  // Calibration phase
  void _startCalibrationPhase(ExperimentSettings settings) {
    debugLog('Starting calibration phase');

    _targetBpm = 0.0;
    _audioService.stopTempoCues();

    // Start phase
    _experimentService.startPhase(
      ExperimentPhase.calibration,
      settings,
      () {
        // When phase completes: move to silent walking phase
        settings.setPhase(ExperimentPhase.silentWalking);
        _processPhaseChange(settings);
      },
    );
  }

  // Silent walking phase
  void _startSilentWalkingPhase(ExperimentSettings settings) {
    debugLog('Starting silent walking phase');

    _targetBpm = 0.0;
    _audioService.stopTempoCues();

    // Start phase
    _experimentService.startPhase(
      ExperimentPhase.silentWalking,
      settings,
      () {
        // When phase completes: set natural walking rhythm
        final naturalTempo = _currentBpm;
        settings.setNaturalTempo(naturalTempo);
        debugLog('Set natural walking rhythm: $naturalTempo BPM');

        // Move to sync phase
        settings.setPhase(ExperimentPhase.syncWithNaturalTempo);
        _processPhaseChange(settings);
      },
    );
  }

  // Sync phase
  void _startSyncPhase(ExperimentSettings settings) {
    debugLog('Starting sync phase');

    _targetBpm = settings.naturalTempo ?? 100.0;
    debugLog('Set target tempo: $_targetBpm BPM');

    _audioService.setVolume(settings.volume);

    // Set high precision mode
    _audioService.setPrecisionMode(PrecisionMode.highPrecision);
    debugLog('Set audio service to high precision mode');

    // Load and play sound
    _loadAndStartMetronome(settings.clickSoundType, _targetBpm);

    // Start phase
    _experimentService.startPhase(
      ExperimentPhase.syncWithNaturalTempo,
      settings,
      () {
        // When phase completes: move to guidance phase 1
        settings.setPhase(ExperimentPhase.rhythmGuidance1);
        _processPhaseChange(settings);
      },
    );
  }

  // Load and start metronome
  Future<void> _loadAndStartMetronome(
      String soundType, double targetBpm) async {
    try {
      // Explicitly load click sound
      debugLog('Loading click sound "$soundType"');
      bool soundLoaded = await _audioService.loadClickSound(soundType);
      if (!soundLoaded) {
        debugLog('Failed to load click sound');
        _showError('Sound Error', 'Failed to load click sound');
        return;
      }

      debugLog('Successfully loaded click sound');

      // Start metronome
      _audioService.startTempoCues(targetBpm);
      debugLog('Started metronome: BPM = $targetBpm');
    } catch (e) {
      debugLog('Metronome start error: $e');
      _showError('Metronome Error', 'Failed to start metronome: $e');
    }
  }

  // Guidance phase 1
  void _startGuidance1Phase(ExperimentSettings settings) {
    debugLog('Starting guidance phase 1');

    _targetBpm = (settings.naturalTempo ?? 100.0) + settings.tempoIncrement;
    debugLog('Updated target tempo: $_targetBpm BPM');

    _audioService.updateTempo(_targetBpm);
    debugLog('Updated metronome tempo: $_targetBpm BPM');

    // Start phase
    _experimentService.startPhase(
      ExperimentPhase.rhythmGuidance1,
      settings,
      () {
        // When phase completes: move to guidance phase 2
        settings.setPhase(ExperimentPhase.rhythmGuidance2);
        _processPhaseChange(settings);
      },
    );
  }

  // Guidance phase 2
  void _startGuidance2Phase(ExperimentSettings settings) {
    debugLog('Starting guidance phase 2');

    _targetBpm =
        (settings.naturalTempo ?? 100.0) + (settings.tempoIncrement * 2);
    debugLog('Updated target tempo: $_targetBpm BPM');

    _audioService.updateTempo(_targetBpm);
    debugLog('Updated metronome tempo: $_targetBpm BPM');

    // Start phase
    _experimentService.startPhase(
      ExperimentPhase.rhythmGuidance2,
      settings,
      () {
        // When phase completes: move to cooldown phase
        settings.setPhase(ExperimentPhase.cooldown);
        _processPhaseChange(settings);
      },
    );
  }

  // Cooldown phase
  void _startCooldownPhase(ExperimentSettings settings) {
    debugLog('Starting cooldown phase');

    _targetBpm = settings.naturalTempo ?? 100.0;
    debugLog('Updated target tempo: $_targetBpm BPM');

    _audioService.updateTempo(_targetBpm);
    debugLog('Updated metronome tempo: $_targetBpm BPM');

    // Start phase
    _experimentService.startPhase(
      ExperimentPhase.cooldown,
      settings,
      () {
        // When phase completes: complete experiment
        settings.setPhase(ExperimentPhase.completed);
        _processPhaseChange(settings);
      },
    );
  }

  // Complete experiment
  void _completeExperiment() async {
    debugLog('Completing experiment');

    // Stop audio
    _audioService.stopTempoCues();
    debugLog('Stopped audio');

    // Stop sensor
    _sensorService.stopSensing();
    debugLog('Stopped sensor');

    // Complete experiment session
    await _experimentService.completeExperimentSession();
    debugLog('Completed experiment session');

    // Navigate to results screen
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => ResultsScreen(sessionId: _sessionId!),
      ),
    );
    debugLog('Navigating to results screen: session ID = $_sessionId');
  }

  @override
  void dispose() {
    debugLog('Disposing experiment screen resources');

    // Cancel subscriptions
    _gaitRhythmSubscription?.cancel();
    _gaitDataSubscription?.cancel();
    debugLog('Cancelled subscriptions');

    // Cancel phase timer
    _experimentService.cancelCurrentPhase();
    debugLog('Cancelled phase timer');

    // Stop audio
    if (_audioService.isPlaying) {
      _audioService.stopTempoCues();
      debugLog('Stopped audio');
    }

    super.dispose();
  }

  // Show error
  void _showError(String title, String message) {
    debugLog('Showing error: $title - $message');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title: $message'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Close',
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  // Loading screen display
  Widget _buildLoadingScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          const Text('Preparing experiment...', style: TextStyle(fontSize: 18)),
          if (_initError.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Error: $_initError',
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _initializeServices,
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }

  // Phase display section
  Widget _buildPhaseDisplay(ExperimentSettings settings) {
    final phaseText = _getPhaseDisplayText(settings.currentPhase);
    final phaseIcon = _getPhaseIcon(settings.currentPhase);
    final phaseColor = _getPhaseColor(settings.currentPhase);

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: phaseColor.withOpacity(0.5), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(phaseIcon, color: phaseColor, size: 28),
                const SizedBox(width: 10),
                Text(
                  'Current Phase: $phaseText',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: phaseColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            PhaseTimer(
              phase: settings.currentPhase,
              settings: settings,
            ),
            if (settings.currentPhase != ExperimentPhase.idle &&
                settings.currentPhase != ExperimentPhase.completed)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  _getPhaseInstructions(settings.currentPhase),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[700],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Rhythm display section
  Widget _buildRhythmDisplay(
      double currentBpm, double targetBpm, ExperimentSettings settings) {
    final bool showTarget =
        settings.currentPhase != ExperimentPhase.silentWalking &&
            settings.currentPhase != ExperimentPhase.calibration &&
            targetBpm > 0;

    final double diff = showTarget ? currentBpm - targetBpm : 0.0;
    final bool isInSync = showTarget && diff.abs() < 3.0;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              'Rhythm Information',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Current rhythm
                TempoDisplay(
                  title: 'Current Walking Rhythm',
                  tempo: currentBpm,
                  color: Colors.blue,
                ),

                // Target tempo (not in silent mode)
                if (showTarget)
                  TempoDisplay(
                    title: 'Target Tempo',
                    tempo: targetBpm,
                    color: Colors.green,
                  ),
              ],
            ),

            // Sync status display
            if (showTarget)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isInSync ? Icons.check_circle : Icons.info,
                      color: isInSync ? Colors.green : Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isInSync
                          ? 'Rhythm is synchronized'
                          : (diff > 0
                              ? '${diff.abs().toStringAsFixed(1)} BPM faster than target'
                              : '${diff.abs().toStringAsFixed(1)} BPM slower than target'),
                      style: TextStyle(
                        color: isInSync ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Rhythm graph display
  Widget _buildRhythmGraph(
      List<FlSpot> dataPoints, double targetBpm, ExperimentSettings settings) {
    final bool showTarget =
        settings.currentPhase != ExperimentPhase.silentWalking &&
            settings.currentPhase != ExperimentPhase.calibration &&
            targetBpm > 0;

    // If data is empty, show loading display
    if (dataPoints.isEmpty) {
      return Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          height: 300,
          padding: const EdgeInsets.all(16.0),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Collecting data...'),
              ],
            ),
          ),
        ),
      );
    }

    // Calculate Y-axis min and max values
    final double minY =
        (dataPoints.map((p) => p.y).reduce((a, b) => a < b ? a : b) - 10)
            .clamp(0, double.infinity);
    final double maxY =
        dataPoints.map((p) => p.y).reduce((a, b) => a > b ? a : b) + 10;

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
                const Icon(Icons.show_chart, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Walking Rhythm Trend',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 250,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: 20,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: Colors.grey.withOpacity(0.3),
                        strokeWidth: 1,
                      );
                    },
                    getDrawingVerticalLine: (value) {
                      return FlLine(
                        color: Colors.grey.withOpacity(0.3),
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
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
                      sideTitles: SideTitles(
                        showTitles: false,
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
                    border: Border.all(color: Colors.grey.withOpacity(0.5)),
                  ),
                  minX: 0,
                  maxX: dataPoints.length.toDouble() - 1,
                  minY: minY,
                  maxY: maxY,
                  lineBarsData: [
                    // Actual walking rhythm
                    LineChartBarData(
                      spots: dataPoints,
                      isCurved: true,
                      color: Colors.blue,
                      barWidth: 3,
                      dotData: FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.blue.withOpacity(0.1),
                      ),
                    ),
                    // Target tempo
                    if (showTarget)
                      LineChartBarData(
                        spots: [
                          FlSpot(0, targetBpm),
                          FlSpot(dataPoints.length.toDouble() - 1, targetBpm),
                        ],
                        isCurved: false,
                        color: Colors.green.withOpacity(0.7),
                        barWidth: 2,
                        dotData: FlDotData(show: false),
                        belowBarData: BarAreaData(show: false),
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
                            '${flSpot.y.toStringAsFixed(1)} BPM',
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
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem('Walking Rhythm', Colors.blue),
                const SizedBox(width: 16),
                if (showTarget) _buildLegendItem('Target Tempo', Colors.green),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Legend item builder
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

  // Experiment abort confirmation dialog
  Future<void> _confirmAbortExperiment() async {
    debugLog('Showing experiment abort confirmation dialog');

    final shouldAbort = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Abort Experiment'),
            content: const Text(
                'Are you sure you want to abort the experiment?\n\nData collected so far will still be saved.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Abort'),
              ),
            ],
          ),
        ) ??
        false;

    if (shouldAbort) {
      debugLog('Aborting experiment');

      // Stop audio
      _audioService.stopTempoCues();
      debugLog('Stopped audio');

      // Stop sensor
      _sensorService.stopSensing();
      debugLog('Stopped sensor');

      // Complete experiment session
      if (_sessionId != null) {
        await _experimentService.completeExperimentSession();
        debugLog('Completed experiment session: session ID = $_sessionId');
      }

      // Return to home screen
      if (!mounted) return;
      Navigator.of(context).pop();
      debugLog('Returning to home screen');
    } else {
      debugLog('Cancelled experiment abort');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<ExperimentSettings>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Walking Rhythm Experiment'),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          // Calibration button
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Sensor Calibration',
            onPressed: () {
              debugLog('Calibration button tapped');
              _navigateToCalibration();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: _isInitializing
            ? _buildLoadingScreen()
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Phase display
                    _buildPhaseDisplay(settings),

                    const SizedBox(height: 16),

                    // Rhythm display
                    _buildRhythmDisplay(_currentBpm, _targetBpm, settings),

                    const SizedBox(height: 16),

                    // Graph display
                    Expanded(
                      child: _buildRhythmGraph(
                          _rhythmDataPoints, _targetBpm, settings),
                    ),

                    const SizedBox(height: 16),

                    // Abort experiment button
                    Align(
                      alignment: Alignment.center,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.stop),
                        label: const Text('Abort Experiment'),
                        onPressed: _confirmAbortExperiment,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  // Phase display text
  String _getPhaseDisplayText(ExperimentPhase phase) {
    switch (phase) {
      case ExperimentPhase.calibration:
        return 'Calibration';
      case ExperimentPhase.silentWalking:
        return 'Silent Walking';
      case ExperimentPhase.syncWithNaturalTempo:
        return 'Sync with Natural Rhythm';
      case ExperimentPhase.rhythmGuidance1:
        return 'Rhythm Guidance 1';
      case ExperimentPhase.rhythmGuidance2:
        return 'Rhythm Guidance 2';
      case ExperimentPhase.cooldown:
        return 'Cooldown';
      case ExperimentPhase.completed:
        return 'Experiment Completed';
      default:
        return 'Preparing';
    }
  }

  // Get icon for each phase
  IconData _getPhaseIcon(ExperimentPhase phase) {
    switch (phase) {
      case ExperimentPhase.calibration:
        return Icons.tune;
      case ExperimentPhase.silentWalking:
        return Icons.volume_off;
      case ExperimentPhase.syncWithNaturalTempo:
        return Icons.sync;
      case ExperimentPhase.rhythmGuidance1:
        return Icons.trending_up;
      case ExperimentPhase.rhythmGuidance2:
        return Icons.trending_up;
      case ExperimentPhase.cooldown:
        return Icons.arrow_downward;
      case ExperimentPhase.completed:
        return Icons.check_circle;
      default:
        return Icons.hourglass_empty;
    }
  }

  // Get color for each phase
  Color _getPhaseColor(ExperimentPhase phase) {
    switch (phase) {
      case ExperimentPhase.calibration:
        return Colors.blue;
      case ExperimentPhase.silentWalking:
        return Colors.purple;
      case ExperimentPhase.syncWithNaturalTempo:
        return Colors.green;
      case ExperimentPhase.rhythmGuidance1:
        return Colors.orange;
      case ExperimentPhase.rhythmGuidance2:
        return Colors.deepOrange;
      case ExperimentPhase.cooldown:
        return Colors.teal;
      case ExperimentPhase.completed:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  // Get instructions text for each phase
  String _getPhaseInstructions(ExperimentPhase phase) {
    switch (phase) {
      case ExperimentPhase.calibration:
        return 'Calibrating the sensor. Please walk naturally.';
      case ExperimentPhase.silentWalking:
        return 'Please walk naturally in silence. We are measuring your natural walking rhythm.';
      case ExperimentPhase.syncWithNaturalTempo:
        return 'Please try to walk in sync with the sound. This is your natural walking rhythm.';
      case ExperimentPhase.rhythmGuidance1:
        return 'Please try to walk in sync with the sound. The tempo has slightly increased.';
      case ExperimentPhase.rhythmGuidance2:
        return 'Please try to walk in sync with the sound. The tempo has further increased.';
      case ExperimentPhase.cooldown:
        return 'Returning to natural rhythm. Please relax and walk comfortably.';
      default:
        return '';
    }
  }
}
