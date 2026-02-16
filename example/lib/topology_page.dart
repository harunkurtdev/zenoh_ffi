import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:zenoh_ffi/zenoh_ffi.dart';

import 'showcase_painters.dart';

// ============================================================================
// Data Models
// ============================================================================

class _GraphNode {
  String id; // sessionId
  String mode; // client/peer/router
  String endpoint;
  bool isOnline;
  Offset position;
  int messageCount;
  DateTime createdAt;
  List<double> messageRateHistory; // last 30 readings

  _GraphNode({
    required this.id,
    required this.mode,
    this.endpoint = '',
    this.isOnline = true,
    this.position = Offset.zero,
    this.messageCount = 0,
    DateTime? createdAt,
    List<double>? messageRateHistory,
  })  : createdAt = createdAt ?? DateTime.now(),
        messageRateHistory = messageRateHistory ?? [];
}

class _GraphEdge {
  String fromId;
  String toId;

  _GraphEdge({required this.fromId, required this.toId});
}

class _ManagedSession {
  ZenohSession session;
  String id;
  String mode;
  String endpoint;
  ZenohLivelinessToken? token;
  ZenohPublisher? heartbeatPublisher;
  Timer? heartbeatTimer;
  int messagesSent;
  int messagesReceived;
  DateTime createdAt;

  _ManagedSession({
    required this.session,
    required this.id,
    required this.mode,
    required this.endpoint,
    this.token,
    this.heartbeatPublisher,
    this.heartbeatTimer,
    this.messagesSent = 0,
    this.messagesReceived = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

// ============================================================================
// TopologyPage
// ============================================================================

class TopologyPage extends StatefulWidget {
  const TopologyPage({super.key});

  @override
  State<TopologyPage> createState() => _TopologyPageState();
}

class _TopologyPageState extends State<TopologyPage>
    with TickerProviderStateMixin {
  bool _isDisposed = false;
  bool _isInitializing = true;
  String? _errorMessage;

  // Main session
  ZenohSession? _mainSession;
  ZenohLivelinessSubscriber? _healthSub;
  ZenohSubscriber? _heartbeatSub;

  // Managed sessions (main + up to 2 additional)
  final List<_ManagedSession> _managedSessions = [];

  // Graph data
  final List<_GraphNode> _nodes = [];
  final List<_GraphEdge> _edges = [];

  // Animation
  late AnimationController _particleController;

  // Node Manager form state
  String _newMode = 'peer';
  final TextEditingController _newConnectCtrl =
      TextEditingController(text: 'tcp/localhost:7447');
  final TextEditingController _newListenCtrl = TextEditingController();
  bool _newMulticast = true;
  bool _newGossip = true;
  final List<MapEntry<String, String>> _customConfigs = [];
  final TextEditingController _customKeyCtrl = TextEditingController();
  final TextEditingController _customValueCtrl = TextEditingController();
  bool _isOpeningSession = false;

  // Health tab
  bool _isScouting = false;
  bool _isRefreshing = false;

  // Liveliness status per node id
  final Map<String, bool> _livelinessStatus = {};

  @override
  void initState() {
    super.initState();
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeZenoh();
    });
  }

  Future<void> _initializeZenoh() async {
    if (_isDisposed) return;

    try {
      _mainSession = await ZenohSession.open(
        mode: 'peer',
        endpoints: [
          'tcp/localhost:7447',
          'tcp/127.0.0.1:7447',
          'tcp/10.81.29.92:7447',
          'tcp/10.0.0.2:7447',
        ],
      );

      final mainId = _mainSession!.sessionId ?? 'main-session';

      // Declare liveliness token for main session
      final mainToken =
          await _mainSession!.declareLivelinessToken('topology/$mainId');

      // Subscribe to liveliness for health monitoring
      _healthSub = await _mainSession!.declareLivelinessSubscriber(
        'topology/**',
        history: true,
      );
      _healthSub!.stream.listen((event) {
        if (mounted && !_isDisposed) {
          setState(() {
            _livelinessStatus[event.key] = event.isAlive;
            // Update node online status
            final nodeKey = event.key.replaceFirst('topology/', '');
            for (final node in _nodes) {
              if (node.id == nodeKey) {
                node.isOnline = event.isAlive;
              }
            }
          });
        }
      });

      // Subscribe to heartbeat messages
      _heartbeatSub =
          await _mainSession!.declareSubscriber('topology/heartbeat/**');
      _heartbeatSub!.stream.listen((sample) {
        if (mounted && !_isDisposed) {
          final senderId = sample.key.replaceFirst('topology/heartbeat/', '');
          setState(() {
            for (final node in _nodes) {
              if (node.id == senderId) {
                node.messageCount++;
                node.messageRateHistory.add(node.messageCount.toDouble());
                if (node.messageRateHistory.length > 30) {
                  node.messageRateHistory.removeAt(0);
                }
              }
            }
            // Update managed session received count
            for (final ms in _managedSessions) {
              if (ms.id != senderId) {
                ms.messagesReceived++;
              }
            }
          });
        }
      });

      // Declare heartbeat publisher for main session
      final mainPub = await _mainSession!.declarePublisher(
        'topology/heartbeat/$mainId',
        options: const ZenohPublisherOptions(
          encoding: ZenohEncoding.textPlain,
        ),
      );

      final managed = _ManagedSession(
        session: _mainSession!,
        id: mainId,
        mode: 'peer',
        endpoint: 'tcp/localhost:7447',
        token: mainToken,
        heartbeatPublisher: mainPub,
      );

      // Start heartbeat timer
      managed.heartbeatTimer =
          Timer.periodic(const Duration(seconds: 2), (_) async {
        if (!_isDisposed && managed.heartbeatPublisher != null) {
          try {
            await managed.heartbeatPublisher!.putString(
              '${DateTime.now().millisecondsSinceEpoch}',
            );
            if (mounted && !_isDisposed) {
              setState(() => managed.messagesSent++);
            }
          } catch (_) {}
        }
      });

      _managedSessions.add(managed);

      // Add main node to graph
      _nodes.add(_GraphNode(
        id: mainId,
        mode: 'peer',
        endpoint: 'tcp/localhost:7447',
        isOnline: true,
      ));

      _layoutNodes();

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

  void _layoutNodes() {
    if (_nodes.isEmpty) return;
    const canvasCenter = Offset(400, 300);
    const radius = 180.0;

    if (_nodes.length == 1) {
      _nodes[0].position = canvasCenter;
    } else {
      for (int i = 0; i < _nodes.length; i++) {
        final angle = (2 * pi * i / _nodes.length) - pi / 2;
        _nodes[i].position = Offset(
          canvasCenter.dx + radius * cos(angle),
          canvasCenter.dy + radius * sin(angle),
        );
      }
    }
  }

  Future<void> _openNewSession() async {
    if (_isOpeningSession || _managedSessions.length >= 3) return;

    setState(() => _isOpeningSession = true);

    try {
      final config = ZenohConfigBuilder()
          .mode(_newMode)
          .connect([_newConnectCtrl.text.trim()]);

      if (_newListenCtrl.text.trim().isNotEmpty) {
        config.listen([_newListenCtrl.text.trim()]);
      }

      config.multicastScouting(_newMulticast);
      config.gossipScouting(_newGossip);

      for (final entry in _customConfigs) {
        try {
          final jsonValue = jsonDecode(entry.value);
          config.custom(entry.key, jsonValue);
        } catch (_) {
          config.custom(entry.key, entry.value);
        }
      }

      final session = await ZenohSession.openWithConfig(config);
      final sessionId = session.sessionId ?? 'session-${_managedSessions.length}';

      // Declare liveliness token
      final token =
          await session.declareLivelinessToken('topology/$sessionId');

      // Declare heartbeat publisher
      final pub = await session.declarePublisher(
        'topology/heartbeat/$sessionId',
        options: const ZenohPublisherOptions(
          encoding: ZenohEncoding.textPlain,
        ),
      );

      final managed = _ManagedSession(
        session: session,
        id: sessionId,
        mode: _newMode,
        endpoint: _newConnectCtrl.text.trim(),
        token: token,
        heartbeatPublisher: pub,
      );

      managed.heartbeatTimer =
          Timer.periodic(const Duration(seconds: 2), (_) async {
        if (!_isDisposed && managed.heartbeatPublisher != null) {
          try {
            await managed.heartbeatPublisher!.putString(
              '${DateTime.now().millisecondsSinceEpoch}',
            );
            if (mounted && !_isDisposed) {
              setState(() => managed.messagesSent++);
            }
          } catch (_) {}
        }
      });

      _managedSessions.add(managed);

      // Add node to graph
      _nodes.add(_GraphNode(
        id: sessionId,
        mode: _newMode,
        endpoint: _newConnectCtrl.text.trim(),
        isOnline: true,
      ));

      // Add edges from new node to existing nodes
      for (final existing in _nodes) {
        if (existing.id != sessionId) {
          _edges.add(_GraphEdge(fromId: sessionId, toId: existing.id));
        }
      }

      _layoutNodes();

      if (mounted && !_isDisposed) {
        setState(() => _isOpeningSession = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Session opened: ${sessionId.substring(0, min(8, sessionId.length))}...')),
        );
      }
    } catch (e) {
      if (mounted && !_isDisposed) {
        setState(() => _isOpeningSession = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open session: $e')),
        );
      }
    }
  }

  Future<void> _closeSession(int index) async {
    if (index < 0 || index >= _managedSessions.length) return;

    final managed = _managedSessions[index];
    managed.heartbeatTimer?.cancel();
    managed.token?.undeclare();
    await managed.heartbeatPublisher?.undeclare();

    // Don't close main session from this method if it's index 0
    if (index == 0) {
      // Main session -- just remove from managed, don't close
      // Actually, close it and let the whole page go to error
      // Better: only allow closing non-main sessions
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot close the main session')),
        );
      }
      return;
    }

    await managed.session.close();

    final removedId = managed.id;
    _managedSessions.removeAt(index);
    _nodes.removeWhere((n) => n.id == removedId);
    _edges.removeWhere((e) => e.fromId == removedId || e.toId == removedId);
    _layoutNodes();

    if (mounted && !_isDisposed) {
      setState(() {});
    }
  }

  Future<void> _scoutNetwork() async {
    if (_isScouting) return;

    setState(() => _isScouting = true);

    try {
      final timeout = Timer(const Duration(seconds: 5), () {
        if (mounted && !_isDisposed && _isScouting) {
          setState(() => _isScouting = false);
        }
      });

      await for (final info in ZenohSession.scout(what: 'peer|router')) {
        if (!mounted || _isDisposed) break;

        // Create a pseudo-node from scout info
        final scoutId = 'scout-${info.hashCode.abs().toRadixString(16)}';
        final alreadyExists = _nodes.any((n) => n.id == scoutId);
        if (!alreadyExists) {
          setState(() {
            _nodes.add(_GraphNode(
              id: scoutId,
              mode: info.contains('router') ? 'router' : 'peer',
              endpoint: info,
              isOnline: true,
            ));
            // Connect to main node
            if (_nodes.length > 1) {
              _edges.add(_GraphEdge(
                  fromId: scoutId, toId: _nodes.first.id));
            }
            _layoutNodes();
          });
        }
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

  Future<void> _refreshLiveliness() async {
    if (_mainSession == null || _isRefreshing) return;

    setState(() => _isRefreshing = true);

    try {
      final events = <ZenohLivelinessEvent>[];
      await for (final event in _mainSession!
          .livelinessGet('topology/**', timeout: const Duration(seconds: 3))) {
        events.add(event);
      }

      if (mounted && !_isDisposed) {
        setState(() {
          // Mark all as potentially offline
          for (final node in _nodes) {
            node.isOnline = false;
          }
          _livelinessStatus.clear();

          for (final event in events) {
            _livelinessStatus[event.key] = event.isAlive;
            final nodeKey = event.key.replaceFirst('topology/', '');
            for (final node in _nodes) {
              if (node.id == nodeKey) {
                node.isOnline = event.isAlive;
              }
            }
          }
        });
      }
    } catch (e) {
      if (mounted && !_isDisposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Refresh error: $e')),
        );
      }
    } finally {
      if (mounted && !_isDisposed) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  void _addCustomConfig() {
    final key = _customKeyCtrl.text.trim();
    final value = _customValueCtrl.text.trim();
    if (key.isEmpty) return;
    setState(() {
      _customConfigs.add(MapEntry(key, value));
      _customKeyCtrl.clear();
      _customValueCtrl.clear();
    });
  }

  void _showNodeDetail(_GraphNode node) {
    final managed = _managedSessions
        .where((ms) => ms.id == node.id)
        .toList();
    final ms = managed.isNotEmpty ? managed.first : null;
    final uptime = DateTime.now().difference(node.createdAt);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.45,
          minChildSize: 0.3,
          maxChildSize: 0.7,
          expand: false,
          builder: (ctx, scrollCtrl) {
            return ListView(
              controller: scrollCtrl,
              padding: EdgeInsets.zero,
              children: [
                // Gradient header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _nodeColor(node.mode),
                        _nodeColor(node.mode).withAlpha(180),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            node.isOnline ? Icons.circle : Icons.circle_outlined,
                            color: node.isOnline ? Colors.greenAccent : Colors.red,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            node.isOnline ? 'ONLINE' : 'OFFLINE',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        node.id.length > 16
                            ? '${node.id.substring(0, 16)}...'
                            : node.id,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Mode: ${node.mode}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                // Details
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _detailRow('Session ID', node.id),
                      _detailRow('Mode', node.mode),
                      _detailRow('Endpoint', node.endpoint),
                      _detailRow(
                          'Messages Sent',
                          ms != null
                              ? '${ms.messagesSent}'
                              : '${node.messageCount}'),
                      _detailRow(
                          'Messages Received',
                          ms != null ? '${ms.messagesReceived}' : '--'),
                      _detailRow(
                        'Uptime',
                        _formatDuration(uptime),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _nodeColor(String mode) {
    switch (mode) {
      case 'router':
        return Colors.green[600]!;
      case 'client':
        return Colors.orange[600]!;
      case 'peer':
      default:
        return Colors.blue[600]!;
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  String _buildConfigPreview() {
    final sb = StringBuffer("ZenohConfigBuilder()\n  .mode('$_newMode')");
    sb.write("\n  .connect(['${_newConnectCtrl.text}'])");
    if (_newListenCtrl.text.trim().isNotEmpty) {
      sb.write("\n  .listen(['${_newListenCtrl.text}'])");
    }
    sb.write('\n  .multicastScouting($_newMulticast)');
    sb.write('\n  .gossipScouting($_newGossip)');
    for (final c in _customConfigs) {
      sb.write("\n  .custom('${c.key}', '${c.value}')");
    }
    return sb.toString();
  }

  // ==========================================================================
  // Build
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Network Topology'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.hub), text: 'Topology'),
              Tab(icon: Icon(Icons.settings), text: 'Node Manager'),
              Tab(icon: Icon(Icons.monitor_heart), text: 'Health'),
            ],
          ),
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
                ? _buildErrorWidget()
                : TabBarView(
                    children: [
                      _buildTopologyTab(),
                      _buildNodeManagerTab(),
                      _buildHealthTab(),
                    ],
                  ),
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
                    style:
                        TextStyle(fontFamily: 'monospace', fontSize: 13),
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
    );
  }

  // ==========================================================================
  // Tab 1 - Topology
  // ==========================================================================

  Widget _buildTopologyTab() {
    return Column(
      children: [
        // Section header
        GradientCard(
          colors: const [Color(0xFF0D47A1), Color(0xFF1565C0)],
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.hub, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Network Graph',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              Text(
                '${_nodes.length} nodes, ${_edges.length} edges',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        // Graph area
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blueGrey.withAlpha(60)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: InteractiveViewer(
                boundaryMargin: const EdgeInsets.all(200),
                minScale: 0.3,
                maxScale: 3.0,
                child: AnimatedBuilder(
                  animation: _particleController,
                  builder: (context, child) {
                    return GestureDetector(
                      onTapUp: (details) {
                        _handleGraphTap(details.localPosition);
                      },
                      child: CustomPaint(
                        size: const Size(800, 600),
                        painter: _TopologyGraphPainter(
                          nodes: _nodes,
                          edges: _edges,
                          particleProgress: _particleController.value,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        // Legend
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendItem(Colors.blue, 'Peer'),
              const SizedBox(width: 16),
              _legendItem(Colors.green, 'Router'),
              const SizedBox(width: 16),
              _legendItem(Colors.orange, 'Client'),
              const SizedBox(width: 16),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey, width: 2),
                ),
              ),
              const SizedBox(width: 4),
              const Text('Offline', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  void _handleGraphTap(Offset tapPosition) {
    for (final node in _nodes) {
      if ((tapPosition - node.position).distance < 35) {
        _showNodeDetail(node);
        return;
      }
    }
  }

  // ==========================================================================
  // Tab 2 - Node Manager
  // ==========================================================================

  Widget _buildNodeManagerTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Config form
        const GradientCard(
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
          margin: EdgeInsets.only(bottom: 8),
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.add_circle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Add New Session',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                  selected: {_newMode},
                  onSelectionChanged: (v) =>
                      setState(() => _newMode = v.first),
                ),

                const SizedBox(height: 16),

                // Connect endpoint
                const Text('Connect Endpoint',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                TextField(
                  controller: _newConnectCtrl,
                  decoration: const InputDecoration(
                    hintText: 'tcp/localhost:7447',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),

                const SizedBox(height: 16),

                // Listen endpoint
                const Text('Listen Endpoint (optional)',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                TextField(
                  controller: _newListenCtrl,
                  decoration: const InputDecoration(
                    hintText: 'tcp/0.0.0.0:7448',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),

                const SizedBox(height: 12),

                // Scouting toggles
                SwitchListTile(
                  title: const Text('Multicast Scouting'),
                  subtitle: const Text('Discover peers via multicast'),
                  value: _newMulticast,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => _newMulticast = v),
                ),
                SwitchListTile(
                  title: const Text('Gossip Scouting'),
                  subtitle: const Text('Discover peers via gossip protocol'),
                  value: _newGossip,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => _newGossip = v),
                ),

                const SizedBox(height: 12),

                // Custom config
                const Text('Custom Config Keys',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _customKeyCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Key',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _customValueCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Value (JSON)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _addCustomConfig,
                      icon: const Icon(Icons.add_circle, color: Colors.blue),
                    ),
                  ],
                ),
                if (_customConfigs.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children:
                        _customConfigs.asMap().entries.map((e) {
                      return Chip(
                        label: Text(
                          '${e.value.key}=${e.value.value}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        onDeleted: () {
                          setState(
                              () => _customConfigs.removeAt(e.key));
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

        const SizedBox(height: 8),

        // Open session button
        ElevatedButton.icon(
          onPressed: _isOpeningSession || _managedSessions.length >= 3
              ? null
              : _openNewSession,
          icon: _isOpeningSession
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.link),
          label: Text(_isOpeningSession
              ? 'Opening...'
              : _managedSessions.length >= 3
                  ? 'Max 3 Sessions'
                  : 'Open Session'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        ),

        const SizedBox(height: 16),

        // Managed sessions list
        GradientCard(
          colors: const [Color(0xFF37474F), Color(0xFF455A64)],
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.devices, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Active Sessions',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              Text(
                '${_managedSessions.length}/3',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),

        ..._managedSessions.asMap().entries.map((entry) {
          final idx = entry.key;
          final ms = entry.value;
          final shortId = ms.id.substring(0, min(8, ms.id.length));
          final isMain = idx == 0;
          return Card(
            child: ListTile(
              leading: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _nodeColor(ms.mode),
                ),
              ),
              title: Text(
                '${isMain ? "[Main] " : ""}$shortId...',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              subtitle: Text(
                'Mode: ${ms.mode} | ${ms.endpoint}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: isMain
                  ? const Chip(
                      label: Text('Main',
                          style: TextStyle(fontSize: 10, color: Colors.white)),
                      backgroundColor: Colors.blue,
                    )
                  : IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () => _closeSession(idx),
                      tooltip: 'Close Session',
                    ),
            ),
          );
        }),

        const SizedBox(height: 16),
      ],
    );
  }

  // ==========================================================================
  // Tab 3 - Health
  // ==========================================================================

  Widget _buildHealthTab() {
    return Column(
      children: [
        // Action buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isScouting ? null : _scoutNetwork,
                  icon: _isScouting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.radar),
                  label: Text(_isScouting ? 'Scanning...' : 'Scout Network'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isRefreshing ? null : _refreshLiveliness,
                  icon: _isRefreshing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                  label: Text(_isRefreshing ? 'Refreshing...' : 'Refresh All'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 4),

        // Health cards
        Expanded(
          child: _nodes.isEmpty
              ? const Center(
                  child: Text(
                    'No nodes detected yet.\nUse "Scout Network" to discover nodes.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemCount: _nodes.length,
                  itemBuilder: (context, index) {
                    final node = _nodes[index];
                    return _buildHealthCard(node);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildHealthCard(_GraphNode node) {
    final uptime = DateTime.now().difference(node.createdAt);
    final liveKey = 'topology/${node.id}';
    final isAlive = _livelinessStatus[liveKey] ?? node.isOnline;
    final shortId = node.id.substring(0, min(8, node.id.length));

    // Build sparkline data: use messageRateHistory or generate from count
    List<double> sparkData = node.messageRateHistory;
    if (sparkData.length < 2) {
      sparkData = List.generate(
          30, (i) => (node.messageCount * (i + 1) / 30).toDouble());
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _nodeColor(node.mode),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$shortId... (${node.mode})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                PulsingDot(
                  color: isAlive ? Colors.green : Colors.red,
                  size: 10,
                  active: isAlive,
                ),
                const SizedBox(width: 6),
                Text(
                  isAlive ? 'Alive' : 'Dead',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isAlive ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Sparkline
            SizedBox(
              height: 50,
              child: CustomPaint(
                size: const Size(double.infinity, 50),
                painter: SparklinePainter(
                  data: sparkData,
                  lineColor: _nodeColor(node.mode),
                  strokeWidth: 1.5,
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Stats row
            Row(
              children: [
                _statChip(Icons.timer, 'Uptime: ${_formatDuration(uptime)}'),
                const SizedBox(width: 8),
                _statChip(Icons.message, 'Msgs: ${node.messageCount}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // Dispose
  // ==========================================================================

  @override
  void dispose() {
    _isDisposed = true;
    _particleController.dispose();
    _newConnectCtrl.dispose();
    _newListenCtrl.dispose();
    _customKeyCtrl.dispose();
    _customValueCtrl.dispose();
    _disposeResources();
    super.dispose();
  }

  Future<void> _disposeResources() async {
    for (final ms in _managedSessions) {
      ms.heartbeatTimer?.cancel();
      ms.token?.undeclare();
      await ms.heartbeatPublisher?.undeclare();
      // Don't close main session separately -- it's the same as _mainSession
      if (ms.session != _mainSession) {
        await ms.session.close();
      }
    }
    await _heartbeatSub?.undeclare();
    await _healthSub?.undeclare();
    await _mainSession?.close();
  }
}

// ============================================================================
// Topology Graph Painter
// ============================================================================

class _TopologyGraphPainter extends CustomPainter {
  final List<_GraphNode> nodes;
  final List<_GraphEdge> edges;
  final double particleProgress; // 0.0-1.0 animated

  _TopologyGraphPainter({
    required this.nodes,
    required this.edges,
    required this.particleProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw grid pattern for background
    final gridPaint = Paint()
      ..color = Colors.white.withAlpha(8)
      ..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw edges
    for (final edge in edges) {
      final fromNode = _findNode(edge.fromId);
      final toNode = _findNode(edge.toId);
      if (fromNode == null || toNode == null) continue;

      final edgePaint = Paint()
        ..color = Colors.white.withAlpha(40)
        ..strokeWidth = 1.5;
      canvas.drawLine(fromNode.position, toNode.position, edgePaint);

      // Draw animated particles along edges
      _drawParticle(canvas, fromNode.position, toNode.position,
          particleProgress);
      _drawParticle(canvas, toNode.position, fromNode.position,
          (particleProgress + 0.5) % 1.0);
    }

    // Draw nodes
    for (final node in nodes) {
      _drawNode(canvas, node);
    }
  }

  void _drawParticle(Canvas canvas, Offset from, Offset to, double t) {
    final pos = Offset.lerp(from, to, t)!;
    final particlePaint = Paint()
      ..color = Colors.cyanAccent.withAlpha(200);
    canvas.drawCircle(pos, 3, particlePaint);

    // Trail
    final trailPaint = Paint()
      ..color = Colors.cyanAccent.withAlpha(60);
    final trailT = (t - 0.05).clamp(0.0, 1.0);
    final trailPos = Offset.lerp(from, to, trailT)!;
    canvas.drawCircle(trailPos, 2, trailPaint);
  }

  void _drawNode(Canvas canvas, _GraphNode node) {
    const nodeRadius = 28.0;

    // Glow for online nodes
    if (node.isOnline) {
      final glowAlpha = (120 + 60 * sin(particleProgress * 2 * pi)).toInt();
      final glowPaint = Paint()
        ..color = _modeColor(node.mode).withAlpha(glowAlpha.clamp(0, 255))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawCircle(node.position, nodeRadius + 6, glowPaint);
    }

    // Node gradient circle
    final gradientPaint = Paint()
      ..shader = RadialGradient(
        colors: node.isOnline
            ? [
                _modeColor(node.mode),
                _modeColor(node.mode).withAlpha(180),
              ]
            : [
                Colors.grey[600]!,
                Colors.grey[800]!,
              ],
      ).createShader(
          Rect.fromCircle(center: node.position, radius: nodeRadius));
    canvas.drawCircle(node.position, nodeRadius, gradientPaint);

    // Border
    final borderPaint = Paint()
      ..color = node.isOnline
          ? Colors.white.withAlpha(80)
          : Colors.grey.withAlpha(60)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(node.position, nodeRadius, borderPaint);

    // Label: short sessionId
    final shortId = node.id.length > 8 ? node.id.substring(0, 8) : node.id;
    final idPainter = TextPainter(
      text: TextSpan(
        text: shortId,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: nodeRadius * 2 - 4);
    idPainter.paint(
      canvas,
      Offset(
        node.position.dx - idPainter.width / 2,
        node.position.dy - 6,
      ),
    );

    // Mode label below
    final modePainter = TextPainter(
      text: TextSpan(
        text: node.mode,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    modePainter.paint(
      canvas,
      Offset(
        node.position.dx - modePainter.width / 2,
        node.position.dy + 4,
      ),
    );
  }

  Color _modeColor(String mode) {
    switch (mode) {
      case 'router':
        return Colors.green;
      case 'client':
        return Colors.orange;
      case 'peer':
      default:
        return Colors.blue;
    }
  }

  _GraphNode? _findNode(String id) {
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  @override
  bool shouldRepaint(covariant _TopologyGraphPainter oldDelegate) {
    return particleProgress != oldDelegate.particleProgress ||
        nodes.length != oldDelegate.nodes.length ||
        edges.length != oldDelegate.edges.length;
  }
}
