import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:zenoh_ffi/zenoh_ffi.dart';

/// Sensor Dashboard - Industrial IoT
///
/// Demonstrates:
/// - declarePublisher() with ZenohPublisherOptions
/// - ZenohPriority enum (realTime, data, background, etc.)
/// - ZenohCongestionControl enum (block, drop, dropFirst)
/// - ZenohEncoding types (json, textPlain, bytes)
/// - ZenohPutOptions with attachment metadata
/// - Publisher putJson(), putString(), delete()
/// - Express mode
/// - Subscriber showing received messages with QoS info
class SensorDashboardPage extends StatefulWidget {
  const SensorDashboardPage({super.key});

  @override
  State<SensorDashboardPage> createState() => _SensorDashboardPageState();
}

class _SensorDashboardPageState extends State<SensorDashboardPage> {
  ZenohSession? _session;
  bool _isDisposed = false;
  bool _isInitializing = true;
  String? _errorMessage;

  // Publishers for different sensors
  ZenohPublisher? _tempPublisher;
  ZenohPublisher? _humidityPublisher;
  ZenohPublisher? _statusPublisher;

  // Subscriber for receiving all sensor data
  ZenohSubscriber? _subscriber;

  // Configurable QoS per publisher
  ZenohPriority _tempPriority = ZenohPriority.realTime;
  ZenohCongestionControl _tempCongestion = ZenohCongestionControl.block;
  bool _tempExpress = true;

  ZenohPriority _humidityPriority = ZenohPriority.data;
  ZenohCongestionControl _humidityCongestion = ZenohCongestionControl.drop;

  ZenohPriority _statusPriority = ZenohPriority.background;
  ZenohCongestionControl _statusCongestion = ZenohCongestionControl.drop;

  // Simulated sensor values
  double _temperature = 22.5;
  double _humidity = 55.0;
  String _statusText = 'nominal';

  // Attachment metadata
  final TextEditingController _attachmentController =
      TextEditingController(text: 'source=sensor-01;floor=3');

  // Received messages
  final List<_SensorMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeZenoh();
    });
  }

  Future<void> _initializeZenoh() async {
    if (_isDisposed) return;

    try {
      _session = await ZenohSession.open(
        mode: 'peer',
        endpoints: ['tcp/localhost:7447', 'tcp/127.0.0.1:7447'],
      );

      // Declare publishers with different QoS
      await _recreatePublishers();

      // Subscribe to all sensor topics
      _subscriber = await _session!.declareSubscriber('sensor/**');
      _subscriber!.stream.listen((sample) {
        if (mounted && !_isDisposed) {
          setState(() {
            _messages.insert(
              0,
              _SensorMessage(
                key: sample.key,
                payload: sample.payloadString,
                encoding: sample.encoding,
                priority: sample.priority,
                congestion: sample.congestionControl,
                attachment: sample.attachmentString,
                kind: sample.kind,
                receivedAt: DateTime.now(),
              ),
            );
            if (_messages.length > 100) _messages.removeLast();
          });
        }
      });

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

  Future<void> _recreatePublishers() async {
    // Undeclare existing publishers
    await _tempPublisher?.undeclare();
    await _humidityPublisher?.undeclare();
    await _statusPublisher?.undeclare();

    _tempPublisher = await _session!.declarePublisher(
      'sensor/temperature',
      options: ZenohPublisherOptions(
        priority: _tempPriority,
        congestionControl: _tempCongestion,
        encoding: ZenohEncoding.applicationJson,
        express: _tempExpress,
      ),
    );

    _humidityPublisher = await _session!.declarePublisher(
      'sensor/humidity',
      options: ZenohPublisherOptions(
        priority: _humidityPriority,
        congestionControl: _humidityCongestion,
        encoding: ZenohEncoding.applicationJson,
      ),
    );

    _statusPublisher = await _session!.declarePublisher(
      'sensor/status',
      options: ZenohPublisherOptions(
        priority: _statusPriority,
        congestionControl: _statusCongestion,
        encoding: ZenohEncoding.textPlain,
      ),
    );
  }

  Future<void> _publishTemperature() async {
    if (_tempPublisher == null) return;
    try {
      final attachment = _attachmentController.text.trim();
      await _tempPublisher!.putJson(
        {
          'value': _temperature,
          'unit': 'celsius',
          'ts': DateTime.now().toIso8601String(),
        },
        attachment: attachment.isNotEmpty
            ? Uint8List.fromList(utf8.encode(attachment))
            : null,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Publish error: $e')));
      }
    }
  }

  Future<void> _publishHumidity() async {
    if (_humidityPublisher == null) return;
    try {
      final attachment = _attachmentController.text.trim();
      await _humidityPublisher!.putJson(
        {
          'value': _humidity,
          'unit': 'percent',
          'ts': DateTime.now().toIso8601String(),
        },
        attachment: attachment.isNotEmpty
            ? Uint8List.fromList(utf8.encode(attachment))
            : null,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Publish error: $e')));
      }
    }
  }

  Future<void> _publishStatus() async {
    if (_statusPublisher == null) return;
    try {
      await _statusPublisher!.putString(_statusText);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Publish error: $e')));
      }
    }
  }

  Future<void> _deleteSensorKey(String sensorName) async {
    if (_session == null) return;
    try {
      await _session!.delete('sensor/$sensorName');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted sensor/$sensorName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sensor Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recreate publishers with current QoS',
            onPressed: _session != null
                ? () async {
                    await _recreatePublishers();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Publishers recreated with new QoS')),
                      );
                    }
                  }
                : null,
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
              : Column(
                  children: [
                    // Sensor publishers section
                    Expanded(
                      flex: 3,
                      child: ListView(
                        padding: const EdgeInsets.all(8),
                        children: [
                          // Attachment metadata
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Attachment Metadata',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  TextField(
                                    controller: _attachmentController,
                                    decoration: const InputDecoration(
                                      hintText: 'key=value;key2=value2',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Temperature publisher
                          _buildSensorCard(
                            title: 'Temperature',
                            icon: Icons.thermostat,
                            color: Colors.orange,
                            value: '${_temperature.toStringAsFixed(1)} °C',
                            priority: _tempPriority,
                            congestion: _tempCongestion,
                            express: _tempExpress,
                            onPriorityChanged: (p) =>
                                setState(() => _tempPriority = p),
                            onCongestionChanged: (c) =>
                                setState(() => _tempCongestion = c),
                            onExpressChanged: (e) =>
                                setState(() => _tempExpress = e),
                            onSliderChanged: (v) =>
                                setState(() => _temperature = v),
                            sliderMin: -20,
                            sliderMax: 60,
                            sliderValue: _temperature,
                            onPublish: _publishTemperature,
                            onDelete: () => _deleteSensorKey('temperature'),
                          ),

                          // Humidity publisher
                          _buildSensorCard(
                            title: 'Humidity',
                            icon: Icons.water_drop,
                            color: Colors.blue,
                            value: '${_humidity.toStringAsFixed(1)} %',
                            priority: _humidityPriority,
                            congestion: _humidityCongestion,
                            onPriorityChanged: (p) =>
                                setState(() => _humidityPriority = p),
                            onCongestionChanged: (c) =>
                                setState(() => _humidityCongestion = c),
                            onSliderChanged: (v) =>
                                setState(() => _humidity = v),
                            sliderMin: 0,
                            sliderMax: 100,
                            sliderValue: _humidity,
                            onPublish: _publishHumidity,
                            onDelete: () => _deleteSensorKey('humidity'),
                          ),

                          // Status publisher
                          _buildStatusCard(),
                        ],
                      ),
                    ),

                    const Divider(height: 1),

                    // Received messages
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: Row(
                        children: [
                          const Text('Received Messages',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14)),
                          const Spacer(),
                          TextButton(
                            onPressed: () => setState(() => _messages.clear()),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: _messages.isEmpty
                          ? const Center(
                              child: Text('No messages received yet',
                                  style: TextStyle(color: Colors.grey)))
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final msg = _messages[index];
                                final isDelete =
                                    msg.kind == ZenohSampleKind.delete;
                                return Card(
                                  color: isDelete ? Colors.red[50] : null,
                                  child: ListTile(
                                    dense: true,
                                    leading: Icon(
                                      isDelete
                                          ? Icons.delete
                                          : Icons.arrow_downward,
                                      color:
                                          isDelete ? Colors.red : Colors.green,
                                      size: 20,
                                    ),
                                    title: Text(msg.key,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600)),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isDelete ? '[DELETED]' : msg.payload,
                                          style: const TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 11),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Wrap(
                                          spacing: 4,
                                          children: [
                                            if (msg.priority != null)
                                              _qosBadge(
                                                  msg.priority!.name,
                                                  _priorityColor(
                                                      msg.priority!)),
                                            if (msg.encoding != null)
                                              _qosBadge(msg.encoding!.mimeType,
                                                  Colors.purple),
                                            if (msg.attachment != null)
                                              _qosBadge('meta', Colors.teal),
                                          ],
                                        ),
                                      ],
                                    ),
                                    trailing: Text(
                                      _formatTime(msg.receivedAt),
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey[500]),
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

  Widget _buildSensorCard({
    required String title,
    required IconData icon,
    required Color color,
    required String value,
    required ZenohPriority priority,
    required ZenohCongestionControl congestion,
    bool? express,
    ValueChanged<bool>? onExpressChanged,
    required ValueChanged<ZenohPriority> onPriorityChanged,
    required ValueChanged<ZenohCongestionControl> onCongestionChanged,
    required ValueChanged<double> onSliderChanged,
    required double sliderMin,
    required double sliderMax,
    required double sliderValue,
    required VoidCallback onPublish,
    required VoidCallback onDelete,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                Text(value,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ],
            ),

            Slider(
              value: sliderValue,
              min: sliderMin,
              max: sliderMax,
              activeColor: color,
              onChanged: onSliderChanged,
            ),

            // QoS controls
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<ZenohPriority>(
                    value: priority,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Priority',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: ZenohPriority.values
                        .map((p) => DropdownMenuItem(
                            value: p,
                            child: Text(p.name,
                                style: const TextStyle(fontSize: 12))))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) onPriorityChanged(v);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<ZenohCongestionControl>(
                    value: congestion,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Congestion',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: ZenohCongestionControl.values
                        .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(c.name,
                                style: const TextStyle(fontSize: 12))))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) onCongestionChanged(v);
                    },
                  ),
                ),
              ],
            ),

            if (express != null && onExpressChanged != null) ...[
              const SizedBox(height: 4),
              SwitchListTile(
                title:
                    const Text('Express Mode', style: TextStyle(fontSize: 13)),
                subtitle: const Text('Skip congestion control',
                    style: TextStyle(fontSize: 11)),
                value: express,
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => onExpressChanged(v),
              ),
            ],

            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onPublish,
                    icon: const Icon(Icons.publish, size: 18),
                    label: const Text('Publish'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: Colors.red),
                  label:
                      const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.grey),
                const SizedBox(width: 8),
                const Text('Status',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                Text(_statusText,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'nominal', label: Text('Nominal')),
                ButtonSegment(value: 'warning', label: Text('Warning')),
                ButtonSegment(value: 'critical', label: Text('Critical')),
                ButtonSegment(value: 'offline', label: Text('Offline')),
              ],
              selected: {_statusText},
              onSelectionChanged: (v) => setState(() => _statusText = v.first),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Priority: ${_statusPriority.name}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(width: 8),
                Text('Congestion: ${_statusCongestion.name}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(width: 8),
                Text('Encoding: textPlain',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _publishStatus,
                    icon: const Icon(Icons.publish, size: 18),
                    label: const Text('Publish Status'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[700],
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _deleteSensorKey('status'),
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: Colors.red),
                  label:
                      const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _qosBadge(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9, color: color, fontWeight: FontWeight.w600)),
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
    _attachmentController.dispose();
    _disposeResources();
    super.dispose();
  }

  Future<void> _disposeResources() async {
    await _tempPublisher?.undeclare();
    await _humidityPublisher?.undeclare();
    await _statusPublisher?.undeclare();
    await _subscriber?.undeclare();
    await _session?.close();
  }
}

class _SensorMessage {
  final String key;
  final String payload;
  final ZenohEncoding? encoding;
  final ZenohPriority? priority;
  final ZenohCongestionControl? congestion;
  final String? attachment;
  final ZenohSampleKind kind;
  final DateTime receivedAt;

  _SensorMessage({
    required this.key,
    required this.payload,
    this.encoding,
    this.priority,
    this.congestion,
    this.attachment,
    required this.kind,
    required this.receivedAt,
  });
}
