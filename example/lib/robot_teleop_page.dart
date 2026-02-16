import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:zenoh_ffi/zenoh_ffi.dart';

import 'showcase_painters.dart';

/// Robot Teleoperation Control Panel
///
/// Demonstrates:
/// - Multiple publishers with different QoS/priorities simultaneously
///   (joystick at realTime+block+express, heartbeat at background, camera at dataHigh)
/// - Overlapping wildcard subscribers: robot/telemetry/* AND robot/telemetry/imu
/// - Liveliness token for robot online/offline
/// - Queryable serving robot state on demand
/// - Attachment on every command (operator ID, seq number)
/// - Timer-driven periodic publisher (heartbeat)
class RobotTeleopPage extends StatefulWidget {
  const RobotTeleopPage({super.key});

  @override
  State<RobotTeleopPage> createState() => _RobotTeleopPageState();
}

class _RobotTeleopPageState extends State<RobotTeleopPage>
    with TickerProviderStateMixin {
  ZenohSession? _session;
  bool _isDisposed = false;
  bool _isInitializing = true;
  String? _errorMessage;

  // Publishers with different QoS
  ZenohPublisher? _cmdPublisher; // realTime + block + express
  ZenohPublisher? _heartbeatPublisher; // background
  ZenohPublisher? _cameraPublisher; // dataHigh

  // Subscribers
  ZenohSubscriber? _telemetrySub; // robot/telemetry/*
  ZenohSubscriber? _imuSub; // robot/telemetry/imu (overlapping)

  // Queryable & Liveliness
  ZenohQueryable? _stateQueryable;
  ZenohLivelinessToken? _robotToken;

  // Joystick state
  Offset _joystickPosition = Offset.zero;
  bool _joystickActive = false;
  int _cmdSeqNum = 0;

  // Telemetry data
  double _speed = 0;
  double _battery = 0.85;
  double _signal = 0.72;
  double _imuRoll = 0;
  double _imuPitch = 0;
  int _telemetryCount = 0;
  int _imuCount = 0;
  bool _robotOnline = false;

  // Command log
  final List<_LogEntry> _log = [];

  // Animation
  late AnimationController _gaugeController;
  late AnimationController _pulseController;
  Timer? _heartbeatTimer;
  Timer? _simTimer;

  @override
  void initState() {
    super.initState();
    _gaugeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeZenoh());
  }

  @override
  void dispose() {
    _isDisposed = true;
    _gaugeController.dispose();
    _pulseController.dispose();
    _heartbeatTimer?.cancel();
    _simTimer?.cancel();
    _disposeZenoh();
    super.dispose();
  }

  void _disposeZenoh() {
    _robotToken?.undeclare();
    _cmdPublisher?.undeclare();
    _heartbeatPublisher?.undeclare();
    _cameraPublisher?.undeclare();
    _telemetrySub?.undeclare();
    _imuSub?.undeclare();
    _stateQueryable?.undeclare();
    _session?.close();
  }

  Future<void> _initializeZenoh() async {
    if (_isDisposed) return;
    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    try {
      _session = await ZenohSession.open(
        mode: 'peer',
        endpoints: [
          'tcp/localhost:7447',
          'tcp/127.0.0.1:7447',
          'tcp/10.81.29.92:7447',
          'tcp/10.0.0.2:7447',
        ],
      );

      // 1. Command publisher: realTime + block + express
      _cmdPublisher = await _session!.declarePublisher(
        'robot/cmd/velocity',
        options: const ZenohPublisherOptions(
          priority: ZenohPriority.realTime,
          congestionControl: ZenohCongestionControl.block,
          encoding: ZenohEncoding.applicationJson,
          express: true,
        ),
      );

      // 2. Heartbeat publisher: background
      _heartbeatPublisher = await _session!.declarePublisher(
        'robot/heartbeat',
        options: const ZenohPublisherOptions(
          priority: ZenohPriority.background,
          congestionControl: ZenohCongestionControl.drop,
          encoding: ZenohEncoding.textPlain,
        ),
      );

      // 3. Camera request publisher: dataHigh
      _cameraPublisher = await _session!.declarePublisher(
        'robot/cmd/camera',
        options: const ZenohPublisherOptions(
          priority: ZenohPriority.dataHigh,
          congestionControl: ZenohCongestionControl.drop,
          encoding: ZenohEncoding.applicationJson,
        ),
      );

      // 4. Telemetry subscriber (wildcard)
      _telemetrySub = await _session!.declareSubscriber('robot/telemetry/*');
      _telemetrySub!.stream.listen((sample) {
        if (!mounted || _isDisposed) return;
        _telemetryCount++;
        try {
          final data = jsonDecode(sample.payloadString);
          setState(() {
            if (data['speed'] != null) {
              _speed = (data['speed'] as num).toDouble();
            }
            if (data['battery'] != null) {
              _battery = (data['battery'] as num).toDouble();
            }
            if (data['signal'] != null) {
              _signal = (data['signal'] as num).toDouble();
            }
          });
          _gaugeController.forward(from: 0);
        } catch (_) {}
      });

      // 5. IMU subscriber (overlapping — also matches robot/telemetry/imu)
      _imuSub = await _session!.declareSubscriber('robot/telemetry/imu');
      _imuSub!.stream.listen((sample) {
        if (!mounted || _isDisposed) return;
        _imuCount++;
        try {
          final data = jsonDecode(sample.payloadString);
          setState(() {
            _imuRoll = (data['roll'] as num?)?.toDouble() ?? 0;
            _imuPitch = (data['pitch'] as num?)?.toDouble() ?? 0;
          });
        } catch (_) {}
      });

      // 6. Robot state queryable
      _stateQueryable = await _session!.declareQueryable(
        'robot/state',
        (query) {
          query.replyJson(query.key, {
            'speed': _speed,
            'battery': _battery,
            'signal': _signal,
            'imu': {'roll': _imuRoll, 'pitch': _imuPitch},
            'online': _robotOnline,
            'telemetryCount': _telemetryCount,
            'cmdSeq': _cmdSeqNum,
          });
        },
      );

      // 7. Liveliness token
      _robotToken = await _session!.declareLivelinessToken('robot/operator/flutter');
      _robotOnline = true;

      // 8. Start heartbeat timer
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _heartbeatPublisher?.putString(
          'alive:${DateTime.now().millisecondsSinceEpoch}',
          options: const ZenohPutOptions(
            encoding: ZenohEncoding.textPlain,
          ),
        );
      });

      // 9. Start telemetry simulator (self-publish for demo)
      _simTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        _simulateTelemetry();
      });

      if (!_isDisposed && mounted) {
        setState(() => _isInitializing = false);
        _addLog('System', 'Robot operator connected');
      }
    } catch (e) {
      if (!_isDisposed && mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _simulateTelemetry() {
    if (_session == null || _isDisposed) return;
    final rand = Random();

    // Simulated speed based on joystick
    final targetSpeed = _joystickPosition.distance * 100;
    _speed = _speed + (targetSpeed - _speed) * 0.3;

    // Publish telemetry
    _session!.putJson('robot/telemetry/speed', {
      'speed': _speed,
      'battery': _battery - 0.0001,
      'signal': 0.6 + rand.nextDouble() * 0.4,
    });

    // Publish IMU (also caught by robot/telemetry/* subscriber)
    _session!.putJson('robot/telemetry/imu', {
      'roll': _joystickPosition.dx * 15 + rand.nextDouble() * 2 - 1,
      'pitch': _joystickPosition.dy * 15 + rand.nextDouble() * 2 - 1,
    });

    // Drain battery
    if (mounted && !_isDisposed) {
      setState(() {
        _battery = (_battery - 0.0001).clamp(0.0, 1.0);
      });
    }
  }

  Future<void> _publishCommand(Offset position) async {
    if (_cmdPublisher == null) return;
    _cmdSeqNum++;

    final cmd = {
      'linear_x': -position.dy, // forward/back
      'angular_z': -position.dx, // left/right
      'seq': _cmdSeqNum,
    };

    try {
      await _cmdPublisher!.putJson(cmd,
          attachment: Uint8List.fromList(
              utf8.encode('op=flutter;seq=$_cmdSeqNum')));
      _addLog('CMD',
          'vel=(${(-position.dy).toStringAsFixed(2)}, ${(-position.dx).toStringAsFixed(2)}) seq=$_cmdSeqNum');
    } catch (_) {}
  }

  void _addLog(String tag, String message) {
    if (!mounted || _isDisposed) return;
    setState(() {
      _log.insert(0, _LogEntry(
        tag: tag,
        message: message,
        timestamp: DateTime.now(),
      ));
      if (_log.length > 100) _log.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        appBar: AppBar(title: const Text('Robot Teleop')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Robot Teleop')),
        body: _buildErrorWidget(),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              const Text('Robot Teleop'),
              const SizedBox(width: 8),
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) => Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _robotOnline
                        ? Colors.green.withAlpha(
                            (100 + _pulseController.value * 155).toInt())
                        : Colors.red,
                    boxShadow: _robotOnline
                        ? [
                            BoxShadow(
                              color: Colors.green.withAlpha(
                                  (_pulseController.value * 100).toInt()),
                              blurRadius: 6,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ],
          ),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.gamepad), text: 'Control'),
              Tab(icon: Icon(Icons.speed), text: 'Telemetry'),
              Tab(icon: Icon(Icons.list_alt), text: 'Log'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildControlTab(),
            _buildTelemetryTab(),
            _buildLogTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildControlTab() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D1B2A), Color(0xFF1B2838)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // Status bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _statusChip('Speed', '${_speed.toStringAsFixed(1)} m/s',
                    Icons.speed, Colors.cyan),
                _statusChip('Battery', '${(_battery * 100).toStringAsFixed(0)}%',
                    Icons.battery_std,
                    _battery > 0.3 ? Colors.green : Colors.red),
                _statusChip('Signal', '${(_signal * 100).toStringAsFixed(0)}%',
                    Icons.wifi, Colors.amber),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Joystick
          Expanded(
            child: Center(
              child: GestureDetector(
                onPanStart: (_) {
                  setState(() => _joystickActive = true);
                },
                onPanUpdate: (details) {
                  final box = context.findRenderObject() as RenderBox?;
                  if (box == null) return;
                  final size = 200.0;
                  final center = Offset(size / 2, size / 2);
                  final localPos = details.localPosition - center;
                  final clamped = Offset(
                    (localPos.dx / (size / 2)).clamp(-1.0, 1.0),
                    (localPos.dy / (size / 2)).clamp(-1.0, 1.0),
                  );
                  setState(() => _joystickPosition = clamped);
                  _publishCommand(clamped);
                },
                onPanEnd: (_) {
                  setState(() {
                    _joystickPosition = Offset.zero;
                    _joystickActive = false;
                  });
                  _publishCommand(Offset.zero);
                  _addLog('CMD', 'STOP (joystick released)');
                },
                child: SizedBox(
                  width: 220,
                  height: 220,
                  child: CustomPaint(
                    painter: JoystickPainter(
                      thumbPosition: _joystickPosition,
                      isActive: _joystickActive,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Quick commands
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _cmdButton('STOP', Icons.stop, Colors.red, () {
                  _publishCommand(Offset.zero);
                  _addLog('CMD', 'EMERGENCY STOP');
                }),
                _cmdButton('FWD', Icons.arrow_upward, Colors.blue, () {
                  _publishCommand(const Offset(0, -0.5));
                }),
                _cmdButton('Photo', Icons.camera, Colors.orange, () {
                  _cameraPublisher?.putJson({'action': 'capture'});
                  _addLog('CAM', 'Photo capture requested (dataHigh)');
                }),
              ],
            ),
          ),

          // QoS info
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                _qosBadge('CMD', 'realTime', Colors.red),
                const SizedBox(width: 6),
                _qosBadge('Heartbeat', 'background', Colors.grey),
                const SizedBox(width: 6),
                _qosBadge('Camera', 'dataHigh', Colors.orange),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryTab() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D1B2A), Color(0xFF1B2838)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Gauges row
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 160,
                    child: CustomPaint(
                      painter: GaugePainter(
                        value: (_speed / 100).clamp(0, 1),
                        startColor: Colors.cyan,
                        endColor: Colors.red,
                        label: 'SPEED',
                        unit: 'm/s',
                        displayValue: _speed,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: 160,
                    child: CustomPaint(
                      painter: GaugePainter(
                        value: _battery,
                        startColor: Colors.red,
                        endColor: Colors.green,
                        label: 'BATTERY',
                        unit: '%',
                        displayValue: _battery * 100,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: 160,
                    child: CustomPaint(
                      painter: GaugePainter(
                        value: _signal,
                        startColor: Colors.grey,
                        endColor: Colors.amber,
                        label: 'SIGNAL',
                        unit: '%',
                        displayValue: _signal * 100,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // IMU section
            GradientCard(
              colors: const [Color(0xFF1A237E), Color(0xFF283593)],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('IMU Data',
                      style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _imuMetric('Roll', _imuRoll),
                      ),
                      Expanded(
                        child: _imuMetric('Pitch', _imuPitch),
                      ),
                      Expanded(
                        child: Transform.rotate(
                          angle: _imuRoll * pi / 180,
                          child: const Icon(Icons.navigation,
                              color: Colors.cyan, size: 40),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Statistics
            GradientCard(
              colors: const [Color(0xFF004D40), Color(0xFF00695C)],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Subscriber Statistics',
                      style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _statItem('Telemetry', '$_telemetryCount',
                          'robot/telemetry/*'),
                      _statItem(
                          'IMU', '$_imuCount', 'robot/telemetry/imu'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'IMU messages are received by BOTH subscribers (overlapping wildcards)',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogTab() {
    return Container(
      color: const Color(0xFF0D1117),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.terminal, color: Colors.green, size: 18),
                const SizedBox(width: 8),
                const Text('Command Log',
                    style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace')),
                const Spacer(),
                Text('${_log.length} entries',
                    style: const TextStyle(
                        color: Colors.grey, fontSize: 12)),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_sweep,
                      color: Colors.grey, size: 18),
                  onPressed: () => setState(() => _log.clear()),
                  tooltip: 'Clear log',
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _log.length,
              itemBuilder: (context, index) {
                final entry = _log[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                      children: [
                        TextSpan(
                          text:
                              '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
                              '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
                              '${entry.timestamp.second.toString().padLeft(2, '0')} ',
                          style: const TextStyle(color: Colors.grey),
                        ),
                        TextSpan(
                          text: '[${entry.tag}] ',
                          style: TextStyle(
                            color: _tagColor(entry.tag),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextSpan(
                          text: entry.message,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _cmdButton(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        height: 60,
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(80)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            Text(label,
                style: TextStyle(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _qosBadge(String label, String priority, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label: $priority',
        style: TextStyle(color: color, fontSize: 10, fontFamily: 'monospace'),
      ),
    );
  }

  Widget _imuMetric(String label, double value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 4),
        AnimatedCounter(
          value: value.round(),
          suffix: '°',
          style: const TextStyle(
            color: Colors.cyan,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _statItem(String label, String value, String key) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace')),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Text(key,
            style: const TextStyle(
                color: Colors.white38,
                fontSize: 9,
                fontFamily: 'monospace')),
      ],
    );
  }

  Color _tagColor(String tag) {
    switch (tag) {
      case 'CMD':
        return Colors.red;
      case 'CAM':
        return Colors.orange;
      case 'System':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            const Text('Connection Failed',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_errorMessage ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: const SelectableText(
                'zenohd -l tcp/0.0.0.0:7447',
                style: TextStyle(fontFamily: 'monospace', fontSize: 14),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _initializeZenoh,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogEntry {
  final String tag;
  final String message;
  final DateTime timestamp;

  _LogEntry({required this.tag, required this.message, required this.timestamp});
}
