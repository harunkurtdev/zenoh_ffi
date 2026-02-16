import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:zenoh_ffi/zenoh_ffi.dart';

import 'showcase_painters.dart';

// ============================================================================
// Performance Benchmark Dashboard
//
// Demonstrates:
// - Systematic comparison of ZenohPriority levels
// - ZenohCongestionControl modes comparison
// - Express mode on/off comparison
// - Timed publish bursts with Stopwatch for msgs/sec
// - Round-trip latency: publisher -> queryable echo -> back via getCollect
// - Configurable binary payload sizes
// - sessionId displayed during benchmarks
// - Multiple concurrent publishers (stress test)
// ============================================================================

class BenchmarkPage extends StatefulWidget {
  const BenchmarkPage({super.key});

  @override
  State<BenchmarkPage> createState() => _BenchmarkPageState();
}

class _BenchmarkPageState extends State<BenchmarkPage>
    with TickerProviderStateMixin {
  // Session state
  ZenohSession? _session;
  bool _isDisposed = false;
  bool _isInitializing = true;
  String? _errorMessage;
  String? _sessionId;

  // Tab controller
  late TabController _tabController;

  // ---- Throughput tab state ----
  ZenohPriority _selectedPriority = ZenohPriority.data;
  ZenohCongestionControl _selectedCongestion = ZenohCongestionControl.drop;
  bool _selectedExpress = false;
  double _payloadSizeIndex = 2; // index into _payloadSizes
  double _messageCount = 1000;
  bool _throughputRunning = false;
  double _throughputProgress = 0.0;
  int _liveMsgsPerSec = 0;
  final List<_ThroughputResult> _throughputResults = [];

  // Animation for throughput bar chart
  late AnimationController _barChartAnim;

  static const List<int> _payloadSizes = [64, 256, 1024, 4096];

  // ---- Latency tab state ----
  bool _latencyRunning = false;
  double _latencyProgress = 0.0;
  final List<double> _latencies = [];
  double _latencyMin = 0;
  double _latencyMax = 0;
  double _latencyAvg = 0;
  double _latencyP95 = 0;
  double _latencyP99 = 0;

  // Animation for histogram
  late AnimationController _histogramAnim;

  // ---- Results tab state ----
  final List<_BenchmarkResultEntry> _allResults = [];
  bool _showComparison = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _barChartAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _histogramAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeZenoh();
    });
  }

  Future<void> _initializeZenoh() async {
    if (_isDisposed) return;

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

      final sid = _session!.sessionId;

      if (!_isDisposed && mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = null;
          _sessionId = sid;
        });
      }
    } catch (e) {
      if (mounted && !_isDisposed) {
        setState(() {
          _isInitializing = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  // =========================================================================
  // Throughput Benchmark
  // =========================================================================

  Future<void> _runThroughputBenchmark() async {
    if (_session == null || _throughputRunning) return;

    setState(() {
      _throughputRunning = true;
      _throughputProgress = 0.0;
      _liveMsgsPerSec = 0;
    });

    final payloadSize = _payloadSizes[_payloadSizeIndex.toInt()];
    final count = _messageCount.toInt();
    final priority = _selectedPriority;
    final congestion = _selectedCongestion;
    final express = _selectedExpress;

    ZenohPublisher? pub;
    try {
      pub = await _session!.declarePublisher(
        'bench/throughput/test',
        options: ZenohPublisherOptions(
          priority: priority,
          congestionControl: congestion,
          express: express,
        ),
      );

      final payload = Uint8List(payloadSize);
      // Fill with non-zero pattern
      for (int i = 0; i < payloadSize; i++) {
        payload[i] = i % 256;
      }

      final sw = Stopwatch()..start();
      int lastUpdate = 0;

      for (int i = 0; i < count; i++) {
        await pub.put(payload);

        // Update progress and live rate periodically
        final elapsed = sw.elapsedMilliseconds;
        if (elapsed - lastUpdate > 100 || i == count - 1) {
          lastUpdate = elapsed;
          final progress = (i + 1) / count;
          final rate =
              elapsed > 0 ? ((i + 1) / (elapsed / 1000)).round() : 0;
          if (mounted && !_isDisposed) {
            setState(() {
              _throughputProgress = progress;
              _liveMsgsPerSec = rate;
            });
          }
        }
      }
      sw.stop();

      final rate = count / (sw.elapsedMilliseconds / 1000);

      await pub.undeclare();
      pub = null;

      final result = _ThroughputResult(
        priority: priority,
        congestion: congestion,
        express: express,
        payloadSize: payloadSize,
        messageCount: count,
        msgsPerSec: rate,
        elapsedMs: sw.elapsedMilliseconds,
      );

      if (mounted && !_isDisposed) {
        setState(() {
          _throughputResults.add(result);
          _throughputRunning = false;
          _throughputProgress = 1.0;
          _liveMsgsPerSec = rate.round();

          // Also add to all-results
          _allResults.add(_BenchmarkResultEntry(
            type: 'Throughput',
            priority: priority,
            congestion: congestion,
            express: express,
            payloadSize: payloadSize,
            msgsPerSec: rate,
            avgLatencyMs: null,
            timestamp: DateTime.now(),
          ));
        });

        _barChartAnim.forward(from: 0);
      }
    } catch (e) {
      await pub?.undeclare();
      if (mounted && !_isDisposed) {
        setState(() {
          _throughputRunning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Throughput benchmark error: $e')),
        );
      }
    }
  }

  // =========================================================================
  // Latency Benchmark
  // =========================================================================

  Future<void> _runLatencyBenchmark() async {
    if (_session == null || _latencyRunning) return;

    setState(() {
      _latencyRunning = true;
      _latencyProgress = 0.0;
      _latencies.clear();
      _latencyMin = 0;
      _latencyMax = 0;
      _latencyAvg = 0;
      _latencyP95 = 0;
      _latencyP99 = 0;
    });

    ZenohQueryable? queryable;
    try {
      // Declare a queryable echo service
      queryable = await _session!.declareQueryable(
        'bench/echo',
        (query) {
          query.reply('bench/echo', query.value ?? Uint8List(0));
        },
      );

      const iterations = 50;
      final latencies = <double>[];

      for (int i = 0; i < iterations; i++) {
        final sw = Stopwatch()..start();
        await _session!.getCollect(
          'bench/echo',
          options: const ZenohGetOptions(
            timeout: Duration(seconds: 2),
          ),
        );
        sw.stop();

        final latencyMs = sw.elapsedMicroseconds / 1000.0;
        latencies.add(latencyMs);

        if (mounted && !_isDisposed) {
          setState(() {
            _latencyProgress = (i + 1) / iterations;
            _latencies.add(latencyMs);
          });
        }
      }

      await queryable.undeclare();
      queryable = null;

      // Compute statistics
      latencies.sort();
      final minVal = latencies.first;
      final maxVal = latencies.last;
      final avgVal = latencies.reduce((a, b) => a + b) / latencies.length;
      final p95Index = ((latencies.length - 1) * 0.95).round();
      final p99Index = ((latencies.length - 1) * 0.99).round();
      final p95Val = latencies[p95Index];
      final p99Val = latencies[p99Index];

      if (mounted && !_isDisposed) {
        setState(() {
          _latencyRunning = false;
          _latencyMin = minVal;
          _latencyMax = maxVal;
          _latencyAvg = avgVal;
          _latencyP95 = p95Val;
          _latencyP99 = p99Val;

          // Add to all-results
          _allResults.add(_BenchmarkResultEntry(
            type: 'Latency',
            priority: ZenohPriority.data,
            congestion: ZenohCongestionControl.drop,
            express: false,
            payloadSize: 0,
            msgsPerSec: null,
            avgLatencyMs: avgVal,
            timestamp: DateTime.now(),
          ));
        });

        _histogramAnim.forward(from: 0);
      }
    } catch (e) {
      await queryable?.undeclare();
      if (mounted && !_isDisposed) {
        setState(() {
          _latencyRunning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Latency benchmark error: $e')),
        );
      }
    }
  }

  // =========================================================================
  // UI
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance Benchmark'),
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        bottom: _isInitializing || _errorMessage != null
            ? null
            : TabBar(
                controller: _tabController,
                indicatorColor: Colors.cyanAccent,
                labelColor: Colors.cyanAccent,
                unselectedLabelColor: Colors.white60,
                tabs: const [
                  Tab(icon: Icon(Icons.speed), text: 'Throughput'),
                  Tab(icon: Icon(Icons.timer), text: 'Latency'),
                  Tab(icon: Icon(Icons.assessment), text: 'Results'),
                ],
              ),
      ),
      backgroundColor: const Color(0xFF0F0F23),
      body: _isInitializing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.cyanAccent),
                  SizedBox(height: 16),
                  Text(
                    'Connecting to Zenoh...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            )
          : _errorMessage != null
              ? _buildErrorWidget()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildThroughputTab(),
                    _buildLatencyTab(),
                    _buildResultsTab(),
                  ],
                ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Connection Failed',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$_errorMessage',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withAlpha(80)),
              ),
              child: const Column(
                children: [
                  Text(
                    'Make sure a Zenoh router is running:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.amber,
                    ),
                  ),
                  SizedBox(height: 4),
                  SelectableText(
                    'zenohd -l tcp/0.0.0.0:7447',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _isInitializing = true;
                  _errorMessage = null;
                });
                _initializeZenoh();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // Throughput Tab
  // =========================================================================

  Widget _buildThroughputTab() {
    final payloadSize = _payloadSizes[_payloadSizeIndex.toInt()];

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Session ID
        if (_sessionId != null)
          GradientCard(
            colors: const [Color(0xFF1A237E), Color(0xFF283593)],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.fingerprint, color: Colors.white60, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Session: ',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                Expanded(
                  child: Text(
                    _sessionId!,
                    style: const TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 8),

        // Config panel
        _buildDarkCard(
          title: 'Configuration',
          icon: Icons.tune,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Payload size slider
              Row(
                children: [
                  const Text(
                    'Payload Size: ',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  Text(
                    '$payloadSize bytes',
                    style: const TextStyle(
                      color: Colors.cyanAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _payloadSizeIndex,
                min: 0,
                max: (_payloadSizes.length - 1).toDouble(),
                divisions: _payloadSizes.length - 1,
                activeColor: Colors.cyanAccent,
                inactiveColor: Colors.white12,
                label: '$payloadSize B',
                onChanged: _throughputRunning
                    ? null
                    : (v) => setState(() => _payloadSizeIndex = v),
              ),

              // Message count slider
              Row(
                children: [
                  const Text(
                    'Message Count: ',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  Text(
                    '${_messageCount.toInt()}',
                    style: const TextStyle(
                      color: Colors.cyanAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _messageCount,
                min: 100,
                max: 5000,
                divisions: 49,
                activeColor: Colors.cyanAccent,
                inactiveColor: Colors.white12,
                label: '${_messageCount.toInt()}',
                onChanged: _throughputRunning
                    ? null
                    : (v) => setState(() => _messageCount = v),
              ),

              // Priority dropdown
              Row(
                children: [
                  Expanded(
                    child: _buildDropdown<ZenohPriority>(
                      label: 'Priority',
                      value: _selectedPriority,
                      items: ZenohPriority.values,
                      nameOf: (p) => p.name,
                      colorOf: _priorityColor,
                      onChanged: _throughputRunning
                          ? null
                          : (v) {
                              if (v != null) {
                                setState(() => _selectedPriority = v);
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildDropdown<ZenohCongestionControl>(
                      label: 'Congestion',
                      value: _selectedCongestion,
                      items: ZenohCongestionControl.values,
                      nameOf: (c) => c.name,
                      colorOf: (_) => Colors.teal,
                      onChanged: _throughputRunning
                          ? null
                          : (v) {
                              if (v != null) {
                                setState(() => _selectedCongestion = v);
                              }
                            },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Express toggle
              Row(
                children: [
                  const Text(
                    'Express Mode',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const Spacer(),
                  Switch(
                    value: _selectedExpress,
                    activeTrackColor: Colors.cyanAccent,
                    onChanged: _throughputRunning
                        ? null
                        : (v) => setState(() => _selectedExpress = v),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Progress ring and live counter
        if (_throughputRunning || _throughputProgress > 0)
          _buildDarkCard(
            title: 'Live Metrics',
            icon: Icons.show_chart,
            child: Row(
              children: [
                // Progress ring
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CustomPaint(
                    painter: ProgressRingPainter(
                      progress: _throughputProgress,
                      startColor: Colors.cyanAccent,
                      endColor: Colors.blueAccent,
                      strokeWidth: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                // Live msgs/sec counter
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Messages / sec',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    AnimatedCounter(
                      value: _liveMsgsPerSec,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        color: Colors.cyanAccent,
                      ),
                      suffix: ' msg/s',
                    ),
                  ],
                ),
              ],
            ),
          ),

        const SizedBox(height: 8),

        // Run button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ElevatedButton.icon(
            onPressed: _throughputRunning ? null : _runThroughputBenchmark,
            icon: _throughputRunning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(
                _throughputRunning ? 'Running...' : 'Run Throughput Benchmark'),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _throughputRunning ? Colors.grey[800] : Colors.cyanAccent,
              foregroundColor:
                  _throughputRunning ? Colors.white54 : Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Bar chart of results
        if (_throughputResults.isNotEmpty)
          _buildDarkCard(
            title: 'Throughput Results',
            icon: Icons.bar_chart,
            child: SizedBox(
              height: max(100.0, _throughputResults.length * 44.0),
              child: AnimatedBuilder(
                animation: _barChartAnim,
                builder: (context, _) {
                  return CustomPaint(
                    size: Size.infinite,
                    painter: BarChartPainter(
                      animationValue: _barChartAnim.value,
                      items: _throughputResults.map((r) {
                        final label =
                            '${r.priority.name}/${r.congestion.name}${r.express ? "/exp" : ""}';
                        return BarChartItem(
                          label: label,
                          value: r.msgsPerSec,
                          color: _priorityColor(r.priority),
                          valueLabel: '${r.msgsPerSec.round()} msg/s',
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  // =========================================================================
  // Latency Tab
  // =========================================================================

  Widget _buildLatencyTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Session ID
        if (_sessionId != null)
          GradientCard(
            colors: const [Color(0xFF1A237E), Color(0xFF283593)],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.fingerprint, color: Colors.white60, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Session: ',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                Expanded(
                  child: Text(
                    _sessionId!,
                    style: const TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 8),

        _buildDarkCard(
          title: 'Latency Test',
          icon: Icons.timer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Measures round-trip time: session.getCollect() to a local '
                'queryable echo on bench/echo (50 iterations).',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 12),

              // Progress ring
              if (_latencyRunning || _latencyProgress > 0)
                Center(
                  child: SizedBox(
                    width: 90,
                    height: 90,
                    child: CustomPaint(
                      painter: ProgressRingPainter(
                        progress: _latencyProgress,
                        startColor: Colors.greenAccent,
                        endColor: Colors.redAccent,
                        strokeWidth: 6,
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 12),

              // Run button
              ElevatedButton.icon(
                onPressed: _latencyRunning ? null : _runLatencyBenchmark,
                icon: _latencyRunning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(
                    _latencyRunning ? 'Running...' : 'Run Latency Benchmark'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _latencyRunning ? Colors.grey[800] : Colors.greenAccent,
                  foregroundColor:
                      _latencyRunning ? Colors.white54 : Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Statistics
        if (_latencies.isNotEmpty && !_latencyRunning)
          _buildDarkCard(
            title: 'Statistics',
            icon: Icons.analytics,
            child: Column(
              children: [
                _buildStatRow('Min', '${_latencyMin.toStringAsFixed(3)} ms',
                    _latencyColorForMs(_latencyMin)),
                _buildStatRow('Avg', '${_latencyAvg.toStringAsFixed(3)} ms',
                    _latencyColorForMs(_latencyAvg)),
                _buildStatRow('Max', '${_latencyMax.toStringAsFixed(3)} ms',
                    _latencyColorForMs(_latencyMax)),
                const Divider(color: Colors.white12),
                _buildStatRow('P95', '${_latencyP95.toStringAsFixed(3)} ms',
                    _latencyColorForMs(_latencyP95)),
                _buildStatRow('P99', '${_latencyP99.toStringAsFixed(3)} ms',
                    _latencyColorForMs(_latencyP99)),
              ],
            ),
          ),

        const SizedBox(height: 8),

        // Histogram
        if (_latencies.isNotEmpty && !_latencyRunning)
          _buildDarkCard(
            title: 'Latency Distribution',
            icon: Icons.equalizer,
            child: SizedBox(
              height: 180,
              child: AnimatedBuilder(
                animation: _histogramAnim,
                builder: (context, _) {
                  final histData = _computeHistogramData();
                  return CustomPaint(
                    size: Size.infinite,
                    painter: HistogramPainter(
                      buckets: histData.buckets,
                      bucketColors: histData.colors,
                      bucketLabels: histData.labels,
                      animationValue: _histogramAnim.value,
                      meanValue: histData.meanIndex,
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  // =========================================================================
  // Results Tab
  // =========================================================================

  Widget _buildResultsTab() {
    // Find best/worst for comparison
    int? bestThroughputIdx;
    int? worstThroughputIdx;
    int? bestLatencyIdx;
    int? worstLatencyIdx;

    if (_showComparison && _allResults.length >= 2) {
      double bestRate = -1;
      double worstRate = double.infinity;
      double bestLat = double.infinity;
      double worstLat = -1;

      for (int i = 0; i < _allResults.length; i++) {
        final r = _allResults[i];
        if (r.msgsPerSec != null) {
          if (r.msgsPerSec! > bestRate) {
            bestRate = r.msgsPerSec!;
            bestThroughputIdx = i;
          }
          if (r.msgsPerSec! < worstRate) {
            worstRate = r.msgsPerSec!;
            worstThroughputIdx = i;
          }
        }
        if (r.avgLatencyMs != null) {
          if (r.avgLatencyMs! < bestLat) {
            bestLat = r.avgLatencyMs!;
            bestLatencyIdx = i;
          }
          if (r.avgLatencyMs! > worstLat) {
            worstLat = r.avgLatencyMs!;
            worstLatencyIdx = i;
          }
        }
      }
    }

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: GradientCard(
            colors: const [Color(0xFF1A237E), Color(0xFF283593)],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_sessionId != null)
                  Row(
                    children: [
                      const Icon(Icons.fingerprint,
                          color: Colors.white60, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Session: $_sessionId',
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '${_allResults.length} test(s) completed',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const Spacer(),
                    if (_allResults.length >= 2)
                      TextButton(
                        onPressed: () {
                          setState(
                              () => _showComparison = !_showComparison);
                        },
                        child: Text(
                          _showComparison ? 'Hide Compare' : 'Compare',
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (_allResults.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _allResults.clear();
                            _throughputResults.clear();
                            _showComparison = false;
                          });
                        },
                        child: const Text(
                          'Clear Results',
                          style: TextStyle(color: Colors.redAccent, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Results list
        Expanded(
          child: _allResults.isEmpty
              ? const Center(
                  child: Text(
                    'Run benchmarks to see results here',
                    style: TextStyle(color: Colors.white38),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _allResults.length,
                  itemBuilder: (context, index) {
                    final r = _allResults[index];
                    final isBestThroughput =
                        _showComparison && index == bestThroughputIdx;
                    final isWorstThroughput =
                        _showComparison && index == worstThroughputIdx;
                    final isBestLatency =
                        _showComparison && index == bestLatencyIdx;
                    final isWorstLatency =
                        _showComparison && index == worstLatencyIdx;

                    Color? borderColor;
                    String? badge;
                    if (isBestThroughput || isBestLatency) {
                      borderColor = Colors.greenAccent;
                      badge = 'BEST';
                    } else if (isWorstThroughput || isWorstLatency) {
                      borderColor = Colors.redAccent;
                      badge = 'WORST';
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: borderColor ?? Colors.white10,
                          width: borderColor != null ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                r.type == 'Throughput'
                                    ? Icons.speed
                                    : Icons.timer,
                                color: r.type == 'Throughput'
                                    ? Colors.cyanAccent
                                    : Colors.greenAccent,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                r.type,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const Spacer(),
                              if (badge != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: borderColor!.withAlpha(40),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    badge,
                                    style: TextStyle(
                                      color: borderColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 6),
                              Text(
                                _formatTimestamp(r.timestamp),
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _resultBadge(
                                r.priority.name,
                                _priorityColor(r.priority),
                              ),
                              _resultBadge(r.congestion.name, Colors.teal),
                              if (r.express)
                                _resultBadge('express', Colors.amber),
                              if (r.payloadSize > 0)
                                _resultBadge(
                                    '${r.payloadSize}B', Colors.blueGrey),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (r.msgsPerSec != null)
                            Text(
                              '${r.msgsPerSec!.round()} msgs/sec',
                              style: const TextStyle(
                                color: Colors.cyanAccent,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                          if (r.avgLatencyMs != null)
                            Text(
                              '${r.avgLatencyMs!.toStringAsFixed(3)} ms avg',
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // =========================================================================
  // Helper widgets and methods
  // =========================================================================

  Widget _buildDarkCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white60, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) nameOf,
    required Color Function(T) colorOf,
    required ValueChanged<T?>? onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      dropdownColor: const Color(0xFF1A1A2E),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      items: items
          .map((item) => DropdownMenuItem<T>(
                value: item,
                child: Text(
                  nameOf(item),
                  style: TextStyle(
                    color: colorOf(item),
                    fontSize: 12,
                  ),
                ),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildStatRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _priorityColor(ZenohPriority priority) {
    switch (priority) {
      case ZenohPriority.realTime:
        return Colors.red;
      case ZenohPriority.interactiveHigh:
        return Colors.deepOrange;
      case ZenohPriority.interactiveLow:
        return Colors.orange;
      case ZenohPriority.dataHigh:
        return Colors.amber;
      case ZenohPriority.data:
        return Colors.blue;
      case ZenohPriority.dataLow:
        return Colors.indigo;
      case ZenohPriority.background:
        return Colors.grey;
    }
  }

  Color _latencyColorForMs(double ms) {
    if (ms < 1.0) return Colors.greenAccent;
    if (ms < 5.0) return Colors.yellowAccent;
    return Colors.redAccent;
  }

  _HistogramData _computeHistogramData() {
    if (_latencies.isEmpty) {
      return const _HistogramData(
        buckets: [],
        colors: [],
        labels: [],
        meanIndex: null,
      );
    }

    // Build buckets: <0.5ms, 0.5-1, 1-2, 2-5, 5-10, 10-20, >20ms
    final boundaries = [0.5, 1.0, 2.0, 5.0, 10.0, 20.0];
    final bucketCounts = List<double>.filled(boundaries.length + 1, 0);
    final bucketLabels = [
      '<0.5',
      '0.5-1',
      '1-2',
      '2-5',
      '5-10',
      '10-20',
      '>20',
    ];

    for (final lat in _latencies) {
      bool placed = false;
      for (int b = 0; b < boundaries.length; b++) {
        if (lat < boundaries[b]) {
          bucketCounts[b]++;
          placed = true;
          break;
        }
      }
      if (!placed) bucketCounts[boundaries.length]++;
    }

    // Colors: green for low, yellow for mid, red for high
    final colors = <Color>[
      Colors.greenAccent, // <0.5
      Colors.green, // 0.5-1
      Colors.yellowAccent, // 1-2
      Colors.yellow, // 2-5
      Colors.orange, // 5-10
      Colors.deepOrange, // 10-20
      Colors.redAccent, // >20
    ];

    // Mean bucket index
    final meanMs = _latencyAvg;
    double meanIdx = 0;
    for (int b = 0; b < boundaries.length; b++) {
      if (meanMs < boundaries[b]) {
        // Interpolate within this bucket
        final low = b == 0 ? 0.0 : boundaries[b - 1];
        final high = boundaries[b];
        final fraction = (meanMs - low) / (high - low);
        meanIdx = b + fraction.clamp(0.0, 1.0) * 0.8;
        break;
      }
      if (b == boundaries.length - 1) {
        meanIdx = boundaries.length.toDouble();
      }
    }

    return _HistogramData(
      buckets: bucketCounts,
      colors: colors,
      labels: bucketLabels,
      meanIndex: meanIdx,
    );
  }

  String _formatTimestamp(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _isDisposed = true;
    _tabController.dispose();
    _barChartAnim.dispose();
    _histogramAnim.dispose();
    _disposeResources();
    super.dispose();
  }

  Future<void> _disposeResources() async {
    await _session?.close();
  }
}

// ============================================================================
// Data models
// ============================================================================

class _ThroughputResult {
  final ZenohPriority priority;
  final ZenohCongestionControl congestion;
  final bool express;
  final int payloadSize;
  final int messageCount;
  final double msgsPerSec;
  final int elapsedMs;

  const _ThroughputResult({
    required this.priority,
    required this.congestion,
    required this.express,
    required this.payloadSize,
    required this.messageCount,
    required this.msgsPerSec,
    required this.elapsedMs,
  });
}

class _BenchmarkResultEntry {
  final String type;
  final ZenohPriority priority;
  final ZenohCongestionControl congestion;
  final bool express;
  final int payloadSize;
  final double? msgsPerSec;
  final double? avgLatencyMs;
  final DateTime timestamp;

  const _BenchmarkResultEntry({
    required this.type,
    required this.priority,
    required this.congestion,
    required this.express,
    required this.payloadSize,
    this.msgsPerSec,
    this.avgLatencyMs,
    required this.timestamp,
  });
}

class _HistogramData {
  final List<double> buckets;
  final List<Color> colors;
  final List<String> labels;
  final double? meanIndex;

  const _HistogramData({
    required this.buckets,
    required this.colors,
    required this.labels,
    this.meanIndex,
  });
}
