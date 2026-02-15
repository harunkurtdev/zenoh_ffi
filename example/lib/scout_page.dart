import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zenoh_ffi/zenoh_ffi.dart';

/// Network Scout & Config Builder
///
/// Demonstrates:
/// - ZenohSession.scout() - discover peers and routers on the network
/// - ZenohConfigBuilder - programmatic config construction
/// - ZenohSession.openWithConfig() - open session from config builder
/// - sessionId - unique session identifier
class ScoutPage extends StatefulWidget {
  const ScoutPage({super.key});

  @override
  State<ScoutPage> createState() => _ScoutPageState();
}

class _ScoutPageState extends State<ScoutPage> {
  ZenohSession? _session;
  bool _isDisposed = false;

  // Scouting state
  bool _isScouting = false;
  final List<_ScoutResult> _scoutResults = [];

  // Config builder state
  String _mode = 'peer';
  bool _multicastScouting = true;
  bool _gossipScouting = true;
  final TextEditingController _endpointController =
      TextEditingController(text: 'tcp/localhost:7447');
  String? _sessionId;
  bool _isConnecting = false;
  String? _connectionError;
  bool _isSessionOpen = false;

  // Scout filter
  String _scoutWhat = 'peer|router';

  @override
  void dispose() {
    _isDisposed = true;
    _endpointController.dispose();
    _disposeResources();
    super.dispose();
  }

  Future<void> _disposeResources() async {
    await _session?.close();
  }

  Future<void> _startScouting() async {
    if (_isScouting) return;

    setState(() {
      _isScouting = true;
      _scoutResults.clear();
    });

    try {
      final timeout = Timer(const Duration(seconds: 5), () {
        if (mounted && !_isDisposed && _isScouting) {
          setState(() => _isScouting = false);
        }
      });

      await for (final info in ZenohSession.scout(what: _scoutWhat)) {
        if (!mounted || _isDisposed) break;
        setState(() {
          _scoutResults.add(_ScoutResult(
            info: info,
            discoveredAt: DateTime.now(),
          ));
        });
      }

      timeout.cancel();
    } catch (e) {
      if (mounted && !_isDisposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scout error: $e')),
        );
      }
    } finally {
      if (mounted && !_isDisposed) {
        setState(() => _isScouting = false);
      }
    }
  }

  Future<void> _openSessionWithConfig() async {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
      _connectionError = null;
    });

    try {
      // Close existing session if any
      await _session?.close();
      _session = null;

      // Build config using ZenohConfigBuilder
      final config = ZenohConfigBuilder()
          .mode(_mode)
          .connect([_endpointController.text.trim()])
          .multicastScouting(_multicastScouting)
          .gossipScouting(_gossipScouting);

      _session = await ZenohSession.openWithConfig(config);

      if (mounted && !_isDisposed) {
        setState(() {
          _sessionId = _session?.sessionId;
          _isSessionOpen = true;
          _isConnecting = false;
        });
      }
    } catch (e) {
      if (mounted && !_isDisposed) {
        setState(() {
          _isConnecting = false;
          _connectionError = e.toString();
          _isSessionOpen = false;
          _sessionId = null;
        });
      }
    }
  }

  Future<void> _closeSession() async {
    await _session?.close();
    _session = null;
    if (mounted && !_isDisposed) {
      setState(() {
        _isSessionOpen = false;
        _sessionId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Network Scout'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.radar), text: 'Scout'),
              Tab(icon: Icon(Icons.settings), text: 'Config Builder'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildScoutTab(),
            _buildConfigTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildScoutTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Scout filter
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Discovery Filter',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'peer|router', label: Text('All')),
                      ButtonSegment(value: 'peer', label: Text('Peers')),
                      ButtonSegment(value: 'router', label: Text('Routers')),
                    ],
                    selected: {_scoutWhat},
                    onSelectionChanged: (value) {
                      setState(() => _scoutWhat = value.first);
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Scout button
          ElevatedButton.icon(
            onPressed: _isScouting ? null : _startScouting,
            icon: _isScouting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.radar),
            label: Text(_isScouting ? 'Scanning...' : 'Start Scouting'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
          ),

          const SizedBox(height: 12),

          // Results header
          Row(
            children: [
              const Text('Discovered Nodes',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('${_scoutResults.length} found',
                  style: TextStyle(color: Colors.grey[600])),
            ],
          ),
          const SizedBox(height: 8),

          // Results list
          Expanded(
            child: _scoutResults.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off,
                            size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 8),
                        Text(
                          _isScouting
                              ? 'Scanning the network...'
                              : 'Press "Start Scouting" to discover Zenoh nodes.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _scoutResults.length,
                    itemBuilder: (context, index) {
                      final result = _scoutResults[index];
                      return Card(
                        child: ExpansionTile(
                          leading:
                              const Icon(Icons.router, color: Colors.indigo),
                          title: Text('Node #${index + 1}'),
                          subtitle: Text(
                            'Discovered at ${_formatTime(result.discoveredAt)}',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: SelectableText(
                                result.info,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Config Builder Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ZenohConfigBuilder',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 4),
                  Text('Build a session config programmatically',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  const SizedBox(height: 16),

                  // Mode selector
                  const Text('Mode',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'client', label: Text('Client')),
                      ButtonSegment(value: 'peer', label: Text('Peer')),
                      ButtonSegment(value: 'router', label: Text('Router')),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (value) {
                      setState(() => _mode = value.first);
                    },
                  ),

                  const SizedBox(height: 16),

                  // Endpoint
                  const Text('Connect Endpoint',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _endpointController,
                    decoration: const InputDecoration(
                      hintText: 'tcp/localhost:7447',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Scouting toggles
                  SwitchListTile(
                    title: const Text('Multicast Scouting'),
                    subtitle: const Text('Discover peers via multicast'),
                    value: _multicastScouting,
                    dense: true,
                    onChanged: (v) => setState(() => _multicastScouting = v),
                  ),
                  SwitchListTile(
                    title: const Text('Gossip Scouting'),
                    subtitle: const Text('Discover peers via gossip protocol'),
                    value: _gossipScouting,
                    dense: true,
                    onChanged: (v) => setState(() => _gossipScouting = v),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Config preview
          Card(
            color: Colors.grey[900],
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Config Preview',
                      style: TextStyle(
                          color: Colors.white70, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SelectableText(
                    _buildConfigPreview(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.greenAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Connect / Disconnect button
          if (_isSessionOpen)
            ElevatedButton.icon(
              onPressed: _closeSession,
              icon: const Icon(Icons.link_off),
              label: const Text('Disconnect'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Colors.red[400],
                foregroundColor: Colors.white,
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: _isConnecting ? null : _openSessionWithConfig,
              icon: _isConnecting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.link),
              label: Text(
                  _isConnecting ? 'Connecting...' : 'Open Session with Config'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),

          const SizedBox(height: 12),

          // Session info
          if (_connectionError != null)
            Card(
              color: Colors.red[50],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _connectionError!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_isSessionOpen) ...[
            Card(
              color: Colors.green[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green),
                        const SizedBox(width: 8),
                        const Text('Session Active',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Mode: $_mode', style: const TextStyle(fontSize: 13)),
                    Text('Endpoint: ${_endpointController.text}',
                        style: const TextStyle(fontSize: 13)),
                    if (_sessionId != null)
                      SelectableText(
                        'Session ID: $_sessionId',
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _buildConfigPreview() {
    return '''ZenohConfigBuilder()
  .mode('$_mode')
  .connect(['${_endpointController.text}'])
  .multicastScouting($_multicastScouting)
  .gossipScouting($_gossipScouting)''';
  }

  String _formatTime(DateTime dt) => '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';
}

class _ScoutResult {
  final String info;
  final DateTime discoveredAt;

  _ScoutResult({required this.info, required this.discoveredAt});
}
