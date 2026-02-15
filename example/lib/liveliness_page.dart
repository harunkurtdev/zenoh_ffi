import 'package:flutter/material.dart';
import 'package:zenoh_ffi/zenoh_ffi.dart';

/// Liveliness Monitor - IoT Fleet Management
///
/// Demonstrates:
/// - declareLivelinessToken() - announce device presence
/// - declareLivelinessSubscriber() with history - monitor fleet
/// - livelinessGet() - query currently alive devices
/// - Token undeclare for going offline
class LivelinessPage extends StatefulWidget {
  const LivelinessPage({super.key});

  @override
  State<LivelinessPage> createState() => _LivelinessPageState();
}

class _LivelinessPageState extends State<LivelinessPage> {
  ZenohSession? _session;
  ZenohLivelinessToken? _token;
  ZenohLivelinessSubscriber? _liveSub;
  bool _isDisposed = false;
  bool _isInitializing = true;
  String? _errorMessage;
  bool _isOnline = false;
  String _deviceId = '';

  // Tracked devices: key -> {isAlive, lastSeen}
  final Map<String, _DeviceInfo> _devices = {};
  final List<String> _eventLog = [];

  @override
  void initState() {
    super.initState();
    _deviceId = 'flutter-${DateTime.now().millisecondsSinceEpoch % 10000}';
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
        ],
      );

      // Subscribe to liveliness changes with history to get existing tokens
      _liveSub = await _session!.declareLivelinessSubscriber(
        'device/**',
        history: true,
      );

      _liveSub!.stream.listen((event) {
        if (mounted && !_isDisposed) {
          setState(() {
            _devices[event.key] = _DeviceInfo(
              isAlive: event.isAlive,
              lastSeen: DateTime.now(),
            );
            _eventLog.insert(
              0,
              '[${_formatTime(DateTime.now())}] ${event.key} -> '
                  '${event.isAlive ? "ONLINE" : "OFFLINE"}',
            );
            // Keep log manageable
            if (_eventLog.length > 50) _eventLog.removeLast();
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

  Future<void> _toggleOnline() async {
    if (_session == null) return;

    try {
      if (_isOnline) {
        // Go offline: undeclare token
        _token?.undeclare();
        _token = null;
        if (mounted && !_isDisposed) {
          setState(() => _isOnline = false);
        }
      } else {
        // Go online: declare liveliness token
        _token = await _session!.declareLivelinessToken('device/$_deviceId');
        if (mounted && !_isDisposed) {
          setState(() => _isOnline = true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _refreshDevices() async {
    if (_session == null) return;

    try {
      final events = <ZenohLivelinessEvent>[];
      await for (final event
          in _session!.livelinessGet('device/**', timeout: const Duration(seconds: 3))) {
        events.add(event);
      }

      if (mounted && !_isDisposed) {
        setState(() {
          // Mark all existing as potentially offline
          for (final key in _devices.keys.toList()) {
            _devices[key] = _DeviceInfo(
              isAlive: false,
              lastSeen: _devices[key]!.lastSeen,
            );
          }
          // Update with fresh data
          for (final event in events) {
            _devices[event.key] = _DeviceInfo(
              isAlive: event.isAlive,
              lastSeen: DateTime.now(),
            );
          }
          _eventLog.insert(
            0,
            '[${_formatTime(DateTime.now())}] Refreshed: ${events.length} device(s) found',
          );
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Refresh error: $e')),
        );
      }
    }
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Liveliness Monitor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _session != null ? _refreshDevices : null,
            tooltip: 'Query alive devices',
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
                        const Icon(Icons.cloud_off, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        const Text(
                          'Connection Failed',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
                                style: TextStyle(fontFamily: 'monospace', fontSize: 13),
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
                    // Device status card
                    Card(
                      margin: const EdgeInsets.all(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              Icons.circle,
                              color: _isOnline ? Colors.green : Colors.red,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Device: $_deviceId',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  Text(
                                    _isOnline ? 'Online' : 'Offline',
                                    style: TextStyle(
                                      color: _isOnline ? Colors.green : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _toggleOnline,
                              icon: Icon(_isOnline ? Icons.cloud_off : Icons.cloud_done),
                              label: Text(_isOnline ? 'Go Offline' : 'Go Online'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    _isOnline ? Colors.red[400] : Colors.green[400],
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Fleet status
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Text(
                            'Fleet Devices',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          Text(
                            '${_devices.values.where((d) => d.isAlive).length} online / '
                            '${_devices.length} total',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),

                    // Device list
                    Expanded(
                      flex: 2,
                      child: _devices.isEmpty
                          ? const Center(
                              child: Text(
                                'No devices detected yet.\nGo online and press refresh.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(8),
                              itemCount: _devices.length,
                              itemBuilder: (context, index) {
                                final key = _devices.keys.elementAt(index);
                                final info = _devices[key]!;
                                return ListTile(
                                  leading: Icon(
                                    Icons.devices,
                                    color: info.isAlive ? Colors.green : Colors.grey,
                                  ),
                                  title: Text(key),
                                  subtitle: Text(
                                      'Last seen: ${_formatTime(info.lastSeen)}'),
                                  trailing: Chip(
                                    label: Text(
                                      info.isAlive ? 'ALIVE' : 'DEAD',
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 12),
                                    ),
                                    backgroundColor:
                                        info.isAlive ? Colors.green : Colors.red,
                                  ),
                                );
                              },
                            ),
                    ),

                    const Divider(),

                    // Event log
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Text(
                            'Event Log',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => setState(() => _eventLog.clear()),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _eventLog.length,
                        itemBuilder: (context, index) {
                          final log = _eventLog[index];
                          final isOnline = log.contains('ONLINE') || log.contains('Refreshed');
                          return Text(
                            log,
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: isOnline ? Colors.green[700] : Colors.red[700],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _disposeResources();
    super.dispose();
  }

  Future<void> _disposeResources() async {
    _token?.undeclare();
    await _liveSub?.undeclare();
    await _session?.close();
  }
}

class _DeviceInfo {
  final bool isAlive;
  final DateTime lastSeen;

  _DeviceInfo({required this.isAlive, required this.lastSeen});
}
