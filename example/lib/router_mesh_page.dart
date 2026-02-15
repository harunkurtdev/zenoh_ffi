import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:zenoh_ffi/zenoh_ffi.dart';

/// Router Mode & Advanced Configuration
///
/// Demonstrates:
/// - ZenohConfigBuilder.listen(endpoints) - set up listen addresses
/// - ZenohConfigBuilder.custom(key, value) - arbitrary config keys
/// - Router mode with ZenohSession.openWithConfig()
/// - Multiple sessions: router + client with sessionId comparison
/// - Ping-pong verification between sessions
class RouterMeshPage extends StatefulWidget {
  const RouterMeshPage({super.key});

  @override
  State<RouterMeshPage> createState() => _RouterMeshPageState();
}

class _RouterMeshPageState extends State<RouterMeshPage> {
  bool _isDisposed = false;

  // Session A (router/peer)
  ZenohSession? _sessionA;
  String _modeA = 'peer';
  final TextEditingController _connectA =
      TextEditingController(text: 'tcp/localhost:7447');
  final TextEditingController _listenA =
      TextEditingController(text: 'tcp/0.0.0.0:7448');
  bool _useListen = true;
  String? _sessionIdA;
  bool _connectingA = false;
  String? _errorA;

  // Session B (client)
  ZenohSession? _sessionB;
  String _modeB = 'client';
  final TextEditingController _connectB =
      TextEditingController(text: 'tcp/localhost:7447');
  String? _sessionIdB;
  bool _connectingB = false;
  String? _errorB;

  // Custom config entries
  final List<MapEntry<String, String>> _customConfigs = [];
  final TextEditingController _customKeyController = TextEditingController();
  final TextEditingController _customValueController = TextEditingController();

  // Ping-pong test
  final List<String> _pingLog = [];
  bool _pingRunning = false;

  @override
  void dispose() {
    _isDisposed = true;
    _connectA.dispose();
    _listenA.dispose();
    _connectB.dispose();
    _customKeyController.dispose();
    _customValueController.dispose();
    _sessionA?.close();
    _sessionB?.close();
    super.dispose();
  }

  Future<void> _openSessionA() async {
    setState(() {
      _connectingA = true;
      _errorA = null;
    });

    try {
      await _sessionA?.close();
      _sessionA = null;

      final config = ZenohConfigBuilder()
          .mode(_modeA)
          .connect([_connectA.text.trim()]);

      // Use .listen() if enabled
      if (_useListen && _listenA.text.trim().isNotEmpty) {
        config.listen([_listenA.text.trim()]);
      }

      // Add custom config entries via .custom()
      for (final entry in _customConfigs) {
        try {
          // Try parsing as JSON first
          final jsonValue = jsonDecode(entry.value);
          config.custom(entry.key, jsonValue);
        } catch (_) {
          // If not valid JSON, pass as string
          config.custom(entry.key, entry.value);
        }
      }

      config.multicastScouting(false);

      _sessionA = await ZenohSession.openWithConfig(config);

      if (mounted && !_isDisposed) {
        setState(() {
          _sessionIdA = _sessionA?.sessionId;
          _connectingA = false;
        });
      }
    } catch (e) {
      if (mounted && !_isDisposed) {
        setState(() {
          _connectingA = false;
          _errorA = e.toString();
          _sessionIdA = null;
        });
      }
    }
  }

  Future<void> _closeSessionA() async {
    await _sessionA?.close();
    _sessionA = null;
    if (mounted && !_isDisposed) {
      setState(() {
        _sessionIdA = null;
        _errorA = null;
      });
    }
  }

  Future<void> _openSessionB() async {
    setState(() {
      _connectingB = true;
      _errorB = null;
    });

    try {
      await _sessionB?.close();
      _sessionB = null;

      final config = ZenohConfigBuilder()
          .mode(_modeB)
          .connect([_connectB.text.trim()])
          .multicastScouting(false);

      _sessionB = await ZenohSession.openWithConfig(config);

      if (mounted && !_isDisposed) {
        setState(() {
          _sessionIdB = _sessionB?.sessionId;
          _connectingB = false;
        });
      }
    } catch (e) {
      if (mounted && !_isDisposed) {
        setState(() {
          _connectingB = false;
          _errorB = e.toString();
          _sessionIdB = null;
        });
      }
    }
  }

  Future<void> _closeSessionB() async {
    await _sessionB?.close();
    _sessionB = null;
    if (mounted && !_isDisposed) {
      setState(() {
        _sessionIdB = null;
        _errorB = null;
      });
    }
  }

  void _addCustomConfig() {
    final key = _customKeyController.text.trim();
    final value = _customValueController.text.trim();
    if (key.isEmpty) return;

    setState(() {
      _customConfigs.add(MapEntry(key, value));
      _customKeyController.clear();
      _customValueController.clear();
    });
  }

  Future<void> _runPingPong() async {
    if (_sessionA == null || _sessionB == null || _pingRunning) return;

    setState(() {
      _pingRunning = true;
      _pingLog.clear();
    });

    try {
      // Subscribe on B
      final subB = await _sessionB!.declareSubscriber('mesh/ping');
      final completer = Completer<String>();

      subB.stream.listen((sample) {
        if (!completer.isCompleted) {
          completer.complete(sample.payloadString);
        }
      });

      _addLog('A -> Publishing "ping" to mesh/ping');
      await _sessionA!.putString('mesh/ping', 'ping from session A',
          options: ZenohPutOptions(
            attachment:
                Uint8List.fromList(utf8.encode('sid=${_sessionIdA ?? "?"}')),
          ));

      // Wait for B to receive
      final received = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => 'TIMEOUT',
      );

      _addLog('B <- Received: "$received"');

      // Now B publishes back
      final subA = await _sessionA!.declareSubscriber('mesh/pong');
      final completer2 = Completer<String>();

      subA.stream.listen((sample) {
        if (!completer2.isCompleted) {
          completer2.complete(sample.payloadString);
        }
      });

      _addLog('B -> Publishing "pong" to mesh/pong');
      await _sessionB!.putString('mesh/pong', 'pong from session B');

      final received2 = await completer2.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => 'TIMEOUT',
      );

      _addLog('A <- Received: "$received2"');
      _addLog('Ping-pong complete!');

      await subB.undeclare();
      await subA.undeclare();
    } catch (e) {
      _addLog('Error: $e');
    } finally {
      if (mounted && !_isDisposed) {
        setState(() => _pingRunning = false);
      }
    }
  }

  void _addLog(String msg) {
    if (mounted && !_isDisposed) {
      setState(() => _pingLog.add(
          '[${DateTime.now().toString().substring(11, 19)}] $msg'));
    }
  }

  String _buildConfigPreviewA() {
    final sb = StringBuffer('ZenohConfigBuilder()\n  .mode(\'$_modeA\')');
    sb.write('\n  .connect([\'${_connectA.text}\'])');
    if (_useListen && _listenA.text.isNotEmpty) {
      sb.write('\n  .listen([\'${_listenA.text}\'])');
    }
    for (final c in _customConfigs) {
      sb.write('\n  .custom(\'${c.key}\', \'${c.value}\')');
    }
    sb.write('\n  .multicastScouting(false)');
    return sb.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Router & Config')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Custom config builder
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Custom Config (.custom())',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('Add arbitrary zenoh config keys',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _customKeyController,
                        decoration: const InputDecoration(
                            hintText: 'e.g. timestamping',
                            labelText: 'Key',
                            border: OutlineInputBorder(),
                            isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _customValueController,
                        decoration: const InputDecoration(
                            hintText: 'e.g. {"enabled": true}',
                            labelText: 'Value (JSON)',
                            border: OutlineInputBorder(),
                            isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                        onPressed: _addCustomConfig,
                        icon: const Icon(Icons.add_circle, color: Colors.blue)),
                  ]),
                  if (_customConfigs.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: _customConfigs.asMap().entries.map((e) {
                        return Chip(
                          label: Text('${e.value.key}=${e.value.value}',
                              style: const TextStyle(fontSize: 11)),
                          deleteIcon: const Icon(Icons.close, size: 14),
                          onDeleted: () {
                            setState(() => _customConfigs.removeAt(e.key));
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Session A
          _buildSessionCard(
            label: 'Session A',
            color: Colors.indigo,
            mode: _modeA,
            onModeChanged: (m) => setState(() => _modeA = m),
            connectController: _connectA,
            sessionId: _sessionIdA,
            isConnecting: _connectingA,
            error: _errorA,
            isOpen: _sessionA != null,
            onOpen: _openSessionA,
            onClose: _closeSessionA,
            extra: Column(
              children: [
                SwitchListTile(
                  title: const Text('Listen Endpoint (.listen())',
                      style: TextStyle(fontSize: 13)),
                  value: _useListen,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => _useListen = v),
                ),
                if (_useListen)
                  TextField(
                    controller: _listenA,
                    decoration: const InputDecoration(
                        labelText: 'Listen address',
                        border: OutlineInputBorder(),
                        isDense: true),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Session B
          _buildSessionCard(
            label: 'Session B',
            color: Colors.teal,
            mode: _modeB,
            onModeChanged: (m) => setState(() => _modeB = m),
            connectController: _connectB,
            sessionId: _sessionIdB,
            isConnecting: _connectingB,
            error: _errorB,
            isOpen: _sessionB != null,
            onOpen: _openSessionB,
            onClose: _closeSessionB,
          ),

          const SizedBox(height: 8),

          // Config preview
          Card(
            color: Colors.grey[900],
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Config Preview (Session A)',
                      style: TextStyle(
                          color: Colors.white70, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SelectableText(
                    _buildConfigPreviewA(),
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.greenAccent),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Ping-pong test
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ping-Pong Test',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('A publishes → B receives → B publishes → A receives',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _sessionA != null && _sessionB != null && !_pingRunning
                        ? _runPingPong
                        : null,
                    icon: _pingRunning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync),
                    label: Text(_pingRunning ? 'Running...' : 'Run Ping-Pong'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white),
                  ),
                  if (_sessionA == null || _sessionB == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Both sessions must be open',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[600])),
                    ),
                  if (_pingLog.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _pingLog
                            .map((l) => Text(l,
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 11)))
                            .toList(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard({
    required String label,
    required Color color,
    required String mode,
    required ValueChanged<String> onModeChanged,
    required TextEditingController connectController,
    String? sessionId,
    required bool isConnecting,
    String? error,
    required bool isOpen,
    required VoidCallback onOpen,
    required VoidCallback onClose,
    Widget? extra,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isOpen ? Colors.green : Colors.grey),
              ),
              const SizedBox(width: 8),
              Text(label,
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
              const Spacer(),
              if (sessionId != null)
                Text('ID: ${sessionId.substring(0, min(8, sessionId.length))}...',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 10)),
            ]),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'client', label: Text('Client')),
                ButtonSegment(value: 'peer', label: Text('Peer')),
                ButtonSegment(value: 'router', label: Text('Router')),
              ],
              selected: {mode},
              onSelectionChanged: (v) => onModeChanged(v.first),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: connectController,
              decoration: const InputDecoration(
                  labelText: 'Connect endpoint',
                  border: OutlineInputBorder(),
                  isDense: true),
            ),
            if (extra != null) ...[const SizedBox(height: 8), extra],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
            const SizedBox(height: 8),
            isOpen
                ? ElevatedButton.icon(
                    onPressed: onClose,
                    icon: const Icon(Icons.link_off),
                    label: const Text('Disconnect'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white),
                  )
                : ElevatedButton.icon(
                    onPressed: isConnecting ? null : onOpen,
                    icon: isConnecting
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.link),
                    label: Text(isConnecting ? 'Connecting...' : 'Connect'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: color, foregroundColor: Colors.white),
                  ),
          ],
        ),
      ),
    );
  }
}
