import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:zenoh_ffi/zenoh_ffi.dart';

import 'showcase_painters.dart';

/// Smart Agriculture Monitor
///
/// Demonstrates:
/// - ZenohConfigBuilder.custom('timestamping', {'enabled': true}) + openWithConfig()
/// - ZenohEncoding.textCsv and ZenohEncoding.applicationYaml (novel encodings)
/// - Queryable with attachment in reply - zone status queryable at 'farm/zone/*/status'
/// - All 7 ZenohPriority levels - background for periodic metrics, data for readings, realTime for critical alerts
/// - session.delete() for clearing zone alerts
/// - ZenohRetry.execute wrapping getCollect
/// - get() stream for progressive zone loading
/// - Wildcard subscriber on 'farm/zone/**'
class AgricultureMonitorPage extends StatefulWidget {
  const AgricultureMonitorPage({super.key});

  @override
  State<AgricultureMonitorPage> createState() =>
      _AgricultureMonitorPageState();
}

class _AgricultureMonitorPageState extends State<AgricultureMonitorPage>
    with TickerProviderStateMixin {
  ZenohSession? _session;
  bool _isDisposed = false;
  bool _isInitializing = true;
  String? _errorMessage;

  // Tab controller
  late TabController _tabController;

  // Zone data
  final Map<String, _ZoneData> _zones = {};
  String? _selectedZoneId;

  // Zone history for sparklines (last 20 readings per zone)
  final Map<String, List<_ZoneSensorReading>> _zoneHistory = {};

  // Subscriber
  ZenohSubscriber? _wildcardSubscriber;

  // Queryable
  ZenohQueryable? _statusQueryable;

  // Simulation timer
  Timer? _simulationTimer;

  // Alerts
  final List<_FarmAlert> _alerts = [];

  // Thresholds
  double _tempThresholdHigh = 35.0;
  double _humidityThresholdLow = 30.0;
  double _moistureThresholdLow = 20.0;

  // Zone definitions: 12 zones in a 3x4 grid
  static const List<String> _zoneIds = [
    'A1', 'A2', 'A3', 'A4',
    'B1', 'B2', 'B3', 'B4',
    'C1', 'C2', 'C3', 'C4',
  ];

  // Encoding assignments per zone
  static final Map<String, ZenohEncoding> _zoneEncodings = {
    'A1': ZenohEncoding.applicationJson,
    'A2': ZenohEncoding.applicationJson,
    'A3': ZenohEncoding.textCsv,
    'A4': ZenohEncoding.textCsv,
    'B1': ZenohEncoding.applicationYaml,
    'B2': ZenohEncoding.applicationYaml,
    'B3': ZenohEncoding.applicationJson,
    'B4': ZenohEncoding.textCsv,
    'C1': ZenohEncoding.applicationYaml,
    'C2': ZenohEncoding.applicationJson,
    'C3': ZenohEncoding.textCsv,
    'C4': ZenohEncoding.applicationYaml,
  };

  // Priority assignments per zone (demonstrate all 7 levels)
  static final Map<String, ZenohPriority> _zonePriorities = {
    'A1': ZenohPriority.realTime,
    'A2': ZenohPriority.interactiveHigh,
    'A3': ZenohPriority.interactiveLow,
    'A4': ZenohPriority.dataHigh,
    'B1': ZenohPriority.data,
    'B2': ZenohPriority.dataLow,
    'B3': ZenohPriority.background,
    'B4': ZenohPriority.realTime,
    'C1': ZenohPriority.interactiveHigh,
    'C2': ZenohPriority.data,
    'C3': ZenohPriority.dataLow,
    'C4': ZenohPriority.background,
  };

  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Initialize zone data
    for (final id in _zoneIds) {
      _zones[id] = _ZoneData(
        id: id,
        temperature: 20.0 + _random.nextDouble() * 10,
        humidity: 40.0 + _random.nextDouble() * 30,
        soilMoisture: 30.0 + _random.nextDouble() * 40,
        encoding: _zoneEncodings[id]!,
        priority: _zonePriorities[id]!,
        lastUpdate: DateTime.now(),
      );
      _zoneHistory[id] = [];
    }
    _selectedZoneId = 'A1';

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeZenoh();
    });
  }

  Future<void> _initializeZenoh() async {
    if (_isDisposed) return;

    try {
      // Use ZenohConfigBuilder with custom timestamping config
      final config = ZenohConfigBuilder()
          .mode('peer')
          .connect([
            'tcp/localhost:7447',
            'tcp/127.0.0.1:7447',
            'tcp/10.81.29.92:7447',
            'tcp/10.0.0.2:7447',
          ])
          .custom('timestamping', {'enabled': true});

      _session = await ZenohSession.openWithConfig(config);

      // Declare wildcard subscriber on 'farm/zone/**'
      _wildcardSubscriber =
          await _session!.declareSubscriber('farm/zone/**');
      _wildcardSubscriber!.stream.listen((sample) {
        if (mounted && !_isDisposed) {
          _handleZoneSample(sample);
        }
      });

      // Declare queryable for zone status at 'farm/zone/*/status'
      _statusQueryable = await _session!.declareQueryable(
        'farm/zone/*/status',
        (query) {
          _handleStatusQuery(query);
        },
      );

      // Start simulation timer
      _simulationTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _simulateAndPublish(),
      );

      if (!_isDisposed && mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = null;
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

  void _handleZoneSample(ZenohSample sample) {
    // Parse zone ID from key: farm/zone/{id}/sensors
    final parts = sample.key.split('/');
    if (parts.length < 3) return;
    final zoneId = parts[2];
    if (!_zoneIds.contains(zoneId)) return;

    try {
      double temp = 0;
      double humidity = 0;
      double moisture = 0;

      final payload = sample.payloadString;
      final encoding = _zoneEncodings[zoneId] ?? ZenohEncoding.applicationJson;

      if (encoding == ZenohEncoding.applicationJson) {
        final data = jsonDecode(payload) as Map<String, dynamic>;
        temp = (data['temperature'] as num).toDouble();
        humidity = (data['humidity'] as num).toDouble();
        moisture = (data['soil_moisture'] as num).toDouble();
      } else if (encoding == ZenohEncoding.textCsv) {
        // Semicolon-separated: temperature;humidity;soil_moisture
        final fields = payload.split(';');
        if (fields.length >= 3) {
          temp = double.tryParse(fields[0]) ?? 0;
          humidity = double.tryParse(fields[1]) ?? 0;
          moisture = double.tryParse(fields[2]) ?? 0;
        }
      } else if (encoding == ZenohEncoding.applicationYaml) {
        // Simple YAML-like parsing: key: value per line
        final lines = payload.split('\n');
        for (final line in lines) {
          final kv = line.split(':');
          if (kv.length >= 2) {
            final key = kv[0].trim();
            final value = double.tryParse(kv[1].trim()) ?? 0;
            if (key == 'temperature') temp = value;
            if (key == 'humidity') humidity = value;
            if (key == 'soil_moisture') moisture = value;
          }
        }
      }

      setState(() {
        _zones[zoneId] = _ZoneData(
          id: zoneId,
          temperature: temp,
          humidity: humidity,
          soilMoisture: moisture,
          encoding: encoding,
          priority: _zonePriorities[zoneId] ?? ZenohPriority.data,
          lastUpdate: DateTime.now(),
        );

        // Append to history
        _zoneHistory[zoneId] ??= [];
        _zoneHistory[zoneId]!.add(_ZoneSensorReading(
          temperature: temp,
          humidity: humidity,
          soilMoisture: moisture,
          timestamp: DateTime.now(),
        ));
        if (_zoneHistory[zoneId]!.length > 20) {
          _zoneHistory[zoneId]!.removeAt(0);
        }

        // Check thresholds and generate alerts
        _checkThresholds(zoneId, temp, humidity, moisture);
      });
    } catch (e) {
      print('Error parsing zone sample: $e');
    }
  }

  void _checkThresholds(
      String zoneId, double temp, double humidity, double moisture) {
    if (temp > _tempThresholdHigh) {
      _addAlert(
        zoneId,
        'High temperature: ${temp.toStringAsFixed(1)} C',
        ZenohPriority.realTime,
      );
    }
    if (humidity < _humidityThresholdLow) {
      _addAlert(
        zoneId,
        'Low humidity: ${humidity.toStringAsFixed(1)}%',
        ZenohPriority.interactiveHigh,
      );
    }
    if (moisture < _moistureThresholdLow) {
      _addAlert(
        zoneId,
        'Low soil moisture: ${moisture.toStringAsFixed(1)}%',
        ZenohPriority.dataHigh,
      );
    }
  }

  void _addAlert(String zoneId, String message, ZenohPriority priority) {
    _alerts.insert(
      0,
      _FarmAlert(
        zoneId: zoneId,
        message: message,
        priority: priority,
        timestamp: DateTime.now(),
      ),
    );
    if (_alerts.length > 100) _alerts.removeLast();

    // Publish alert via zenoh with appropriate priority
    _session?.putString(
      'farm/alerts/$zoneId',
      jsonEncode({
        'zone': zoneId,
        'message': message,
        'priority': priority.name,
        'ts': DateTime.now().toIso8601String(),
      }),
      options: ZenohPutOptions(
        encoding: ZenohEncoding.applicationJson,
        priority: priority,
      ),
    );
  }

  void _handleStatusQuery(ZenohQuery query) {
    // Extract zone ID from selector, e.g. farm/zone/A1/status
    final parts = query.selector.split('/');
    String? zoneId;
    for (int i = 0; i < parts.length; i++) {
      if (parts[i] == 'zone' && i + 1 < parts.length) {
        zoneId = parts[i + 1];
        break;
      }
    }

    if (zoneId != null && _zones.containsKey(zoneId)) {
      final zone = _zones[zoneId]!;
      final statusData = {
        'zone': zoneId,
        'temperature': zone.temperature,
        'humidity': zone.humidity,
        'soil_moisture': zone.soilMoisture,
        'health_score': zone.healthScore,
        'encoding': zone.encoding.mimeType,
        'priority': zone.priority.name,
        'last_update': zone.lastUpdate.toIso8601String(),
      };

      // Reply with attachment containing zone metadata
      query.replyJson(
        'farm/zone/$zoneId/status',
        statusData,
        attachment: 'zone=$zoneId;type=status;format=json',
      );
    } else {
      query.replyJson(
        query.key,
        {'error': 'Zone not found', 'requested': zoneId},
      );
    }
  }

  void _simulateAndPublish() {
    if (_session == null || _isDisposed) return;

    for (final zoneId in _zoneIds) {
      final zone = _zones[zoneId];
      if (zone == null) continue;

      // Simulate sensor drift
      final newTemp = (zone.temperature + (_random.nextDouble() - 0.5) * 2)
          .clamp(15.0, 40.0);
      final newHumidity =
          (zone.humidity + (_random.nextDouble() - 0.5) * 3).clamp(20.0, 90.0);
      final newMoisture = (zone.soilMoisture + (_random.nextDouble() - 0.5) * 4)
          .clamp(0.0, 100.0);

      final encoding = _zoneEncodings[zoneId]!;
      final priority = _zonePriorities[zoneId]!;
      String payload;

      if (encoding == ZenohEncoding.applicationJson) {
        payload = jsonEncode({
          'temperature': double.parse(newTemp.toStringAsFixed(1)),
          'humidity': double.parse(newHumidity.toStringAsFixed(1)),
          'soil_moisture': double.parse(newMoisture.toStringAsFixed(1)),
        });
      } else if (encoding == ZenohEncoding.textCsv) {
        // Semicolon-separated CSV
        payload =
            '${newTemp.toStringAsFixed(1)};${newHumidity.toStringAsFixed(1)};${newMoisture.toStringAsFixed(1)}';
      } else {
        // applicationYaml
        payload =
            'temperature: ${newTemp.toStringAsFixed(1)}\nhumidity: ${newHumidity.toStringAsFixed(1)}\nsoil_moisture: ${newMoisture.toStringAsFixed(1)}';
      }

      _session!.putString(
        'farm/zone/$zoneId/sensors',
        payload,
        options: ZenohPutOptions(
          encoding: encoding,
          priority: priority,
        ),
      );
    }
  }

  Future<void> _fetchZoneStatus(String zoneId) async {
    if (_session == null) return;

    try {
      const retry = ZenohRetry(
        maxAttempts: 3,
        initialDelay: Duration(milliseconds: 300),
      );

      final replies = await retry.execute(
        () => _session!.getCollect(
          'farm/zone/$zoneId/status',
          options: const ZenohGetOptions(
            timeout: Duration(seconds: 5),
          ),
        ),
      );

      if (mounted && !_isDisposed) {
        if (replies.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Status for $zoneId: ${replies.first.payloadString}'),
              backgroundColor: Colors.green[700],
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No status reply for Zone $zoneId'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fetch status error: $e')),
        );
      }
    }
  }

  Future<void> _progressiveLoadZones() async {
    if (_session == null) return;

    try {
      // Use get() stream for progressive zone loading
      final stream = _session!.get(
        'farm/zone/*/status',
        options: const ZenohGetOptions(
          timeout: Duration(seconds: 5),
        ),
      );

      int count = 0;
      await for (final reply in stream) {
        count++;
        if (mounted && !_isDisposed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Loaded zone $count: ${reply.key}'),
              duration: const Duration(milliseconds: 800),
              backgroundColor: Colors.blue[700],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Progressive load error: $e')),
        );
      }
    }
  }

  Future<void> _clearAllAlerts() async {
    if (_session == null) return;

    try {
      // Use session.delete() for clearing zone alerts
      await _session!.delete('farm/alerts/**');

      if (mounted && !_isDisposed) {
        setState(() {
          _alerts.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All alerts cleared'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Clear alerts error: $e')),
        );
      }
    }
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Agriculture Monitor'),
        bottom: _isInitializing || _errorMessage != null
            ? null
            : TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(Icons.grid_view), text: 'Farm Overview'),
                  Tab(icon: Icon(Icons.info_outline), text: 'Zone Detail'),
                  Tab(
                      icon: Icon(Icons.notification_important),
                      text: 'Alerts'),
                ],
              ),
        actions: [
          if (!_isInitializing && _errorMessage == null)
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'Progressive load all zones',
              onPressed: _progressiveLoadZones,
            ),
        ],
      ),
      body: _isInitializing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Connecting to Zenoh...'),
                ],
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_off,
                            color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        const Text(
                          'Connection Failed',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$_errorMessage',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: const Column(
                            children: [
                              Text(
                                'Make sure a Zenoh router is running:',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              SizedBox(height: 4),
                              SelectableText(
                                'zenohd -l tcp/0.0.0.0:7447',
                                style: TextStyle(
                                    fontFamily: 'monospace', fontSize: 13),
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
                        ),
                      ],
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildFarmOverviewTab(),
                    _buildZoneDetailTab(),
                    _buildAlertsTab(),
                  ],
                ),
    );
  }

  // ------------------------------------------------------------------
  // Tab 1: Farm Overview
  // ------------------------------------------------------------------

  Widget _buildFarmOverviewTab() {
    // Compute averages
    double avgTemp = 0;
    double avgHumidity = 0;
    double avgMoisture = 0;
    if (_zones.isNotEmpty) {
      for (final z in _zones.values) {
        avgTemp += z.temperature;
        avgHumidity += z.humidity;
        avgMoisture += z.soilMoisture;
      }
      avgTemp /= _zones.length;
      avgHumidity /= _zones.length;
      avgMoisture /= _zones.length;
    }

    return Column(
      children: [
        // Farm stats header
        GradientCard(
          colors: const [Color(0xFF1B5E20), Color(0xFF2E7D32)],
          margin: const EdgeInsets.all(8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statColumn('Avg Temp',
                  '${avgTemp.toStringAsFixed(1)} C', Icons.thermostat),
              _statColumn('Avg Humidity',
                  '${avgHumidity.toStringAsFixed(1)}%', Icons.water_drop),
              _statColumn('Avg Moisture',
                  '${avgMoisture.toStringAsFixed(1)}%', Icons.grass),
            ],
          ),
        ),

        // Zone grid (3 columns x 4 rows)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                childAspectRatio: 0.9,
              ),
              itemCount: _zoneIds.length,
              itemBuilder: (context, index) {
                final zoneId = _zoneIds[index];
                final zone = _zones[zoneId]!;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedZoneId = zoneId;
                    });
                    _tabController.animateTo(1);
                  },
                  child: CustomPaint(
                    painter: HeatmapCellPainter(
                      value: zone.healthScore,
                      label: 'Zone $zoneId',
                      sublabel:
                          '${zone.temperature.toStringAsFixed(0)} C | ${zone.humidity.toStringAsFixed(0)}%',
                      isSelected: _selectedZoneId == zoneId,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _statColumn(String label, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(color: Colors.white60, fontSize: 11)),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Tab 2: Zone Detail
  // ------------------------------------------------------------------

  Widget _buildZoneDetailTab() {
    final zoneId = _selectedZoneId ?? 'A1';
    final zone = _zones[zoneId];
    if (zone == null) {
      return const Center(child: Text('Select a zone from Farm Overview'));
    }

    final history = _zoneHistory[zoneId] ?? [];
    final tempHistory = history.map((r) => r.temperature).toList();
    final humidityHistory = history.map((r) => r.humidity).toList();
    final moistureHistory = history.map((r) => r.soilMoisture).toList();

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        // Zone header
        GradientCard(
          colors: const [Color(0xFF0D47A1), Color(0xFF1565C0)],
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Zone $zoneId',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Last update: ${_formatTime(zone.lastUpdate)}',
                      style:
                          const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Encoding badge
              _encodingBadge(zone.encoding),
              const SizedBox(width: 8),
              // Priority badge
              _priorityBadgeWidget(zone.priority),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Gauge widgets for temp, humidity, moisture
        SizedBox(
          height: 170,
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: CustomPaint(
                    painter: GaugePainter(
                      value: ((zone.temperature - 15) / 25).clamp(0, 1),
                      startColor: Colors.blue,
                      endColor: Colors.red,
                      label: 'Temperature',
                      unit: 'C',
                      displayValue: zone.temperature,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: CustomPaint(
                    painter: GaugePainter(
                      value: (zone.humidity / 100).clamp(0, 1),
                      startColor: Colors.orange,
                      endColor: Colors.cyan,
                      label: 'Humidity',
                      unit: '%',
                      displayValue: zone.humidity,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: CustomPaint(
                    painter: GaugePainter(
                      value: (zone.soilMoisture / 100).clamp(0, 1),
                      startColor: Colors.brown,
                      endColor: Colors.green,
                      label: 'Moisture',
                      unit: '%',
                      displayValue: zone.soilMoisture,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Sparkline charts
        if (tempHistory.length >= 2) ...[
          const Text('Temperature History',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(8),
            child: CustomPaint(
              size: const Size(double.infinity, 64),
              painter: SparklinePainter(
                data: tempHistory,
                lineColor: Colors.redAccent,
                minValue: 15,
                maxValue: 40,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Humidity History',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(8),
            child: CustomPaint(
              size: const Size(double.infinity, 64),
              painter: SparklinePainter(
                data: humidityHistory,
                lineColor: Colors.cyanAccent,
                minValue: 20,
                maxValue: 90,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Soil Moisture History',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(8),
            child: CustomPaint(
              size: const Size(double.infinity, 64),
              painter: SparklinePainter(
                data: moistureHistory,
                lineColor: Colors.lightGreenAccent,
                minValue: 0,
                maxValue: 100,
              ),
            ),
          ),
        ] else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text('Waiting for sensor data...',
                  style: TextStyle(color: Colors.grey)),
            ),
          ),

        const SizedBox(height: 12),

        // Threshold controls
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Alert Thresholds',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(
                        width: 100,
                        child: Text('Temp High:', style: TextStyle(fontSize: 12))),
                    Expanded(
                      child: Slider(
                        value: _tempThresholdHigh,
                        min: 25,
                        max: 45,
                        divisions: 20,
                        label: '${_tempThresholdHigh.toStringAsFixed(0)} C',
                        activeColor: Colors.red,
                        onChanged: (v) =>
                            setState(() => _tempThresholdHigh = v),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text('${_tempThresholdHigh.toStringAsFixed(0)} C',
                          style: const TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const SizedBox(
                        width: 100,
                        child:
                            Text('Humidity Low:', style: TextStyle(fontSize: 12))),
                    Expanded(
                      child: Slider(
                        value: _humidityThresholdLow,
                        min: 10,
                        max: 50,
                        divisions: 20,
                        label: '${_humidityThresholdLow.toStringAsFixed(0)}%',
                        activeColor: Colors.blue,
                        onChanged: (v) =>
                            setState(() => _humidityThresholdLow = v),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text('${_humidityThresholdLow.toStringAsFixed(0)}%',
                          style: const TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const SizedBox(
                        width: 100,
                        child:
                            Text('Moisture Low:', style: TextStyle(fontSize: 12))),
                    Expanded(
                      child: Slider(
                        value: _moistureThresholdLow,
                        min: 5,
                        max: 40,
                        divisions: 14,
                        label: '${_moistureThresholdLow.toStringAsFixed(0)}%',
                        activeColor: Colors.green,
                        onChanged: (v) =>
                            setState(() => _moistureThresholdLow = v),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text('${_moistureThresholdLow.toStringAsFixed(0)}%',
                          style: const TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Fetch Status button using ZenohRetry
        ElevatedButton.icon(
          onPressed: () => _fetchZoneStatus(zoneId),
          icon: const Icon(Icons.download, size: 18),
          label: Text('Fetch Status (Zone $zoneId with Retry)'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),

        const SizedBox(height: 16),
      ],
    );
  }

  Widget _encodingBadge(ZenohEncoding encoding) {
    Color bgColor;
    switch (encoding) {
      case ZenohEncoding.applicationJson:
        bgColor = Colors.blue;
        break;
      case ZenohEncoding.textCsv:
        bgColor = Colors.teal;
        break;
      case ZenohEncoding.applicationYaml:
        bgColor = Colors.purple;
        break;
      default:
        bgColor = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor.withAlpha(180),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        encoding.mimeType,
        style: const TextStyle(
            color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _priorityBadgeWidget(ZenohPriority priority) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _priorityColor(priority).withAlpha(180),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        priority.name,
        style: const TextStyle(
            color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Tab 3: Alerts
  // ------------------------------------------------------------------

  Widget _buildAlertsTab() {
    // Sort alerts by priority (lower value = higher priority)
    final sortedAlerts = List<_FarmAlert>.from(_alerts)
      ..sort((a, b) => a.priority.value.compareTo(b.priority.value));

    return Column(
      children: [
        // Header
        GradientCard(
          colors: const [Color(0xFFB71C1C), Color(0xFFD32F2F)],
          margin: const EdgeInsets.all(8),
          child: Row(
            children: [
              const Icon(Icons.warning_amber, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Farm Alerts',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    Text('${_alerts.length} active alert(s)',
                        style:
                            const TextStyle(color: Colors.white60, fontSize: 12)),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _alerts.isNotEmpty ? _clearAllAlerts : null,
                icon: const Icon(Icons.delete_sweep, size: 18),
                label: const Text('Clear All'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red,
                ),
              ),
            ],
          ),
        ),

        // Alert list
        Expanded(
          child: sortedAlerts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle,
                          size: 64, color: Colors.green[300]),
                      const SizedBox(height: 12),
                      const Text('No active alerts',
                          style: TextStyle(color: Colors.grey, fontSize: 16)),
                      const Text('All zones within thresholds',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: sortedAlerts.length,
                  itemBuilder: (context, index) {
                    final alert = sortedAlerts[index];
                    return _AlertCard(
                      alert: alert,
                      priorityColor: _priorityColor(alert.priority),
                      onTap: () {
                        setState(() {
                          _selectedZoneId = alert.zoneId;
                        });
                        _tabController.animateTo(1);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  Color _priorityColor(ZenohPriority priority) {
    switch (priority) {
      case ZenohPriority.realTime:
        return Colors.red;
      case ZenohPriority.interactiveHigh:
        return Colors.deepOrange;
      case ZenohPriority.interactiveLow:
        return Colors.orange;
      case ZenohPriority.dataHigh:
        return Colors.amber.shade800;
      case ZenohPriority.data:
        return Colors.blue;
      case ZenohPriority.dataLow:
        return Colors.indigo;
      case ZenohPriority.background:
        return Colors.grey;
    }
  }

  String _formatTime(DateTime dt) => '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _isDisposed = true;
    _simulationTimer?.cancel();
    _tabController.dispose();
    _disposeResources();
    super.dispose();
  }

  Future<void> _disposeResources() async {
    await _wildcardSubscriber?.undeclare();
    await _statusQueryable?.undeclare();
    await _session?.close();
  }
}

// ============================================================================
// Alert Card with AnimatedSize
// ============================================================================

class _AlertCard extends StatefulWidget {
  final _FarmAlert alert;
  final Color priorityColor;
  final VoidCallback onTap;

  const _AlertCard({
    required this.alert,
    required this.priorityColor,
    required this.onTap,
  });

  @override
  State<_AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<_AlertCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        child: Card(
          margin: const EdgeInsets.symmetric(vertical: 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: widget.priorityColor,
                  width: 5,
                ),
              ),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber,
                      color: widget.priorityColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Zone ${widget.alert.zoneId}: ${widget.alert.message}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: widget.priorityColor.withAlpha(40),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        widget.alert.priority.name,
                        style: TextStyle(
                          fontSize: 9,
                          color: widget.priorityColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_expanded) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Time: ${_formatTime(widget.alert.timestamp)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                  Text(
                    'Priority Value: ${widget.alert.priority.value} (lower = higher priority)',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: widget.onTap,
                      child: const Text('Go to Zone'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) => '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';
}

// ============================================================================
// Data Models
// ============================================================================

class _ZoneData {
  final String id;
  final double temperature;
  final double humidity;
  final double soilMoisture;
  final ZenohEncoding encoding;
  final ZenohPriority priority;
  final DateTime lastUpdate;

  _ZoneData({
    required this.id,
    required this.temperature,
    required this.humidity,
    required this.soilMoisture,
    required this.encoding,
    required this.priority,
    required this.lastUpdate,
  });

  /// Health score: 0.0 (healthy/green) to 1.0 (critical/red)
  /// Based on how far values stray from ideal ranges
  double get healthScore {
    // Ideal: temp 20-28, humidity 50-70, moisture 40-70
    double tempScore = 0;
    if (temperature < 18) {
      tempScore = ((18 - temperature) / 10).clamp(0, 1);
    } else if (temperature > 30) {
      tempScore = ((temperature - 30) / 10).clamp(0, 1);
    }

    double humidScore = 0;
    if (humidity < 40) {
      humidScore = ((40 - humidity) / 30).clamp(0, 1);
    } else if (humidity > 75) {
      humidScore = ((humidity - 75) / 20).clamp(0, 1);
    }

    double moistScore = 0;
    if (soilMoisture < 30) {
      moistScore = ((30 - soilMoisture) / 30).clamp(0, 1);
    } else if (soilMoisture > 80) {
      moistScore = ((soilMoisture - 80) / 20).clamp(0, 1);
    }

    return ((tempScore + humidScore + moistScore) / 3).clamp(0.0, 1.0);
  }
}

class _ZoneSensorReading {
  final double temperature;
  final double humidity;
  final double soilMoisture;
  final DateTime timestamp;

  _ZoneSensorReading({
    required this.temperature,
    required this.humidity,
    required this.soilMoisture,
    required this.timestamp,
  });
}

class _FarmAlert {
  final String zoneId;
  final String message;
  final ZenohPriority priority;
  final DateTime timestamp;

  _FarmAlert({
    required this.zoneId,
    required this.message,
    required this.priority,
    required this.timestamp,
  });
}
