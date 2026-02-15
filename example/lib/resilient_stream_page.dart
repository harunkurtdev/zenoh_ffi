import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:zenoh_ffi/zenoh_ffi.dart';

/// Resilient Streams & Error Recovery
///
/// Demonstrates:
/// - ZenohRetry.executeStream() - retry stream-based operations
/// - ZenohSession.get() raw Stream<ZenohReply> (incremental results)
/// - ZenohGetOptions.payload - send data with GET request
/// - Concurrent pub/sub operations on same session
class ResilientStreamPage extends StatefulWidget {
  const ResilientStreamPage({super.key});

  @override
  State<ResilientStreamPage> createState() => _ResilientStreamPageState();
}

class _ResilientStreamPageState extends State<ResilientStreamPage> {
  ZenohSession? _session;
  bool _isDisposed = false;
  bool _isInitializing = true;
  String? _errorMessage;

  // Retry config
  int _maxAttempts = 3;
  double _initialDelayMs = 500;
  double _backoffMultiplier = 2.0;
  double _maxDelayMs = 10000;
  bool _useExecuteStream = true;

  // Stream query
  final TextEditingController _selectorController =
      TextEditingController(text: 'stream/data/**');
  final TextEditingController _payloadController =
      TextEditingController(text: '{"filter": "temperature > 20"}');
  bool _queryRunning = false;
  final List<_StreamReply> _streamReplies = [];

  // Data provider queryable
  ZenohQueryable? _dataQueryable;
  bool _providerRunning = false;
  int _queriesServed = 0;

  // Concurrent operations
  ZenohPublisher? _pubA;
  ZenohPublisher? _pubB;
  ZenohSubscriber? _subC;
  bool _concurrentRunning = false;
  int _pubACount = 0;
  int _pubBCount = 0;
  int _subCCount = 0;
  Timer? _concurrentTimer;

  // Event log
  final List<_EventLog> _events = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeZenoh());
  }

  Future<void> _initializeZenoh() async {
    if (_isDisposed) return;
    try {
      _session = await ZenohSession.open(
        mode: 'peer',
        endpoints: ['tcp/localhost:7447', 'tcp/127.0.0.1:7447'],
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

  Future<void> _toggleDataProvider() async {
    if (_providerRunning) {
      await _dataQueryable?.undeclare();
      _dataQueryable = null;
      if (mounted && !_isDisposed) {
        setState(() {
          _providerRunning = false;
          _queriesServed = 0;
        });
      }
      return;
    }

    try {
      _dataQueryable =
          await _session!.declareQueryable('stream/data/**', (query) {
        // Read the query payload
        String filterInfo = 'none';
        if (query.value != null && query.value!.isNotEmpty) {
          try {
            final payload = utf8.decode(query.value!);
            filterInfo = payload;
          } catch (_) {
            filterInfo = '${query.value!.length} bytes';
          }
        }

        _addEvent('provider', 'Query received: ${query.selector} | payload: $filterInfo');

        // Reply with multiple data points
        for (int i = 0; i < 5; i++) {
          query.replyJson('stream/data/point-$i', {
            'index': i,
            'value': 20.0 + i * 2.5,
            'unit': 'celsius',
            'filter_applied': filterInfo,
          });
        }

        if (mounted && !_isDisposed) {
          setState(() => _queriesServed++);
        }
      });

      if (mounted && !_isDisposed) {
        setState(() => _providerRunning = true);
      }
    } catch (e) {
      _addEvent('error', 'Provider start failed: $e');
    }
  }

  Future<void> _executeStreamQuery() async {
    if (_session == null || _queryRunning) return;

    setState(() {
      _queryRunning = true;
      _streamReplies.clear();
    });

    final selector = _selectorController.text.trim();
    final payloadText = _payloadController.text.trim();
    final stopwatch = Stopwatch()..start();

    try {
      final options = ZenohGetOptions(
        timeout: const Duration(seconds: 10),
        payload: payloadText.isNotEmpty
            ? Uint8List.fromList(utf8.encode(payloadText))
            : null,
        encoding: ZenohEncoding.applicationJson,
        priority: ZenohPriority.interactiveHigh,
        congestionControl: ZenohCongestionControl.block,
        attachment: Uint8List.fromList(utf8.encode('client=resilient-stream')),
      );

      if (_useExecuteStream) {
        // ZenohRetry.executeStream()
        final retry = ZenohRetry(
          maxAttempts: _maxAttempts,
          initialDelay: Duration(milliseconds: _initialDelayMs.toInt()),
          backoffMultiplier: _backoffMultiplier,
          maxDelay: Duration(milliseconds: _maxDelayMs.toInt()),
        );

        _addEvent('retry', 'executeStream: maxAttempts=$_maxAttempts, delay=${_initialDelayMs.toInt()}ms');

        await for (final reply
            in retry.executeStream(() => _session!.get(selector, options: options))) {
          if (!mounted || _isDisposed) break;
          final elapsed = stopwatch.elapsedMilliseconds;
          setState(() {
            _streamReplies.add(_StreamReply(
              key: reply.key,
              payload: reply.payloadString,
              encoding: reply.encoding?.mimeType,
              attachment: reply.attachmentString,
              elapsedMs: elapsed,
            ));
          });
        }
      } else {
        // Direct session.get() raw stream
        _addEvent('stream', 'Raw get() stream on: $selector');

        await for (final reply
            in _session!.get(selector, options: options)) {
          if (!mounted || _isDisposed) break;
          final elapsed = stopwatch.elapsedMilliseconds;
          setState(() {
            _streamReplies.add(_StreamReply(
              key: reply.key,
              payload: reply.payloadString,
              encoding: reply.encoding?.mimeType,
              attachment: reply.attachmentString,
              elapsedMs: elapsed,
            ));
          });
        }
      }

      stopwatch.stop();
      _addEvent('done', 'Stream complete: ${_streamReplies.length} replies in ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      _addEvent('error', 'Stream failed: $e');
    } finally {
      if (mounted && !_isDisposed) {
        setState(() => _queryRunning = false);
      }
    }
  }

  Future<void> _toggleConcurrent() async {
    if (_concurrentRunning) {
      _concurrentTimer?.cancel();
      await _pubA?.undeclare();
      await _pubB?.undeclare();
      await _subC?.undeclare();
      _pubA = null;
      _pubB = null;
      _subC = null;
      if (mounted && !_isDisposed) {
        setState(() {
          _concurrentRunning = false;
          _pubACount = 0;
          _pubBCount = 0;
          _subCCount = 0;
        });
      }
      return;
    }

    try {
      _pubA = await _session!.declarePublisher('concurrent/channel-a',
          options: ZenohPublisherOptions(
              priority: ZenohPriority.realTime,
              congestionControl: ZenohCongestionControl.drop));

      _pubB = await _session!.declarePublisher('concurrent/channel-b',
          options: ZenohPublisherOptions(
              priority: ZenohPriority.background,
              congestionControl: ZenohCongestionControl.drop));

      _subC = await _session!.declareSubscriber('concurrent/**');
      _subC!.stream.listen((sample) {
        if (mounted && !_isDisposed) {
          setState(() => _subCCount++);
        }
      });

      // Publish concurrently every 500ms
      _concurrentTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
        try {
          await _pubA?.putString('A: ${DateTime.now().millisecondsSinceEpoch}');
          if (mounted && !_isDisposed) setState(() => _pubACount++);
        } catch (e) {
          _addEvent('error', 'PubA: $e');
        }
        try {
          await _pubB?.putString('B: ${DateTime.now().millisecondsSinceEpoch}');
          if (mounted && !_isDisposed) setState(() => _pubBCount++);
        } catch (e) {
          _addEvent('error', 'PubB: $e');
        }
      });

      if (mounted && !_isDisposed) {
        setState(() => _concurrentRunning = true);
      }
      _addEvent('concurrent', 'Started: 2 publishers + 1 subscriber');
    } catch (e) {
      _addEvent('error', 'Concurrent start failed: $e');
    }
  }

  void _addEvent(String type, String message) {
    if (mounted && !_isDisposed) {
      setState(() {
        _events.insert(0, _EventLog(
          type: type,
          message: message,
          time: DateTime.now(),
        ));
        if (_events.length > 100) _events.removeLast();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Resilient Streams'),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.stream), text: 'Stream Query'),
            Tab(icon: Icon(Icons.sync), text: 'Concurrent'),
            Tab(icon: Icon(Icons.list_alt), text: 'Event Log'),
          ]),
        ),
        body: _isInitializing
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? _buildErrorWidget()
                : TabBarView(children: [
                    _buildStreamTab(),
                    _buildConcurrentTab(),
                    _buildLogTab(),
                  ]),
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
            const Text('Connection Failed',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('$_errorMessage',
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
              child: const Column(children: [
                Text('Make sure a Zenoh router is running:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                SizedBox(height: 4),
                SelectableText('zenohd -l tcp/0.0.0.0:7447',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 13)),
              ]),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                setState(() { _isInitializing = true; _errorMessage = null; });
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

  Widget _buildStreamTab() {
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // Data provider
              Card(
                color: _providerRunning ? Colors.green[50] : null,
                child: ListTile(
                  leading: Icon(_providerRunning ? Icons.dns : Icons.dns_outlined,
                      color: _providerRunning ? Colors.green : Colors.grey),
                  title: Text(_providerRunning
                      ? 'Data Provider Active ($_queriesServed queries served)'
                      : 'Data Provider Stopped'),
                  subtitle: const Text('Queryable on stream/data/**'),
                  trailing: Switch(
                      value: _providerRunning,
                      onChanged: (_) => _toggleDataProvider()),
                ),
              ),

              // Retry config
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ZenohRetry Config',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      SwitchListTile(
                        title: const Text('Use executeStream()', style: TextStyle(fontSize: 13)),
                        subtitle: Text(_useExecuteStream
                            ? 'Retries the entire stream on failure'
                            : 'Direct get() stream (no retry)'),
                        value: _useExecuteStream,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) => setState(() => _useExecuteStream = v),
                      ),
                      if (_useExecuteStream) ...[
                        _sliderRow('Max Attempts', _maxAttempts.toDouble(), 1, 10, (v) {
                          setState(() => _maxAttempts = v.toInt());
                        }, '${_maxAttempts}x'),
                        _sliderRow('Initial Delay', _initialDelayMs, 100, 5000, (v) {
                          setState(() => _initialDelayMs = v);
                        }, '${_initialDelayMs.toInt()}ms'),
                        _sliderRow('Backoff', _backoffMultiplier, 1.0, 4.0, (v) {
                          setState(() => _backoffMultiplier = v);
                        }, '${_backoffMultiplier.toStringAsFixed(1)}x'),
                        _sliderRow('Max Delay', _maxDelayMs, 1000, 60000, (v) {
                          setState(() => _maxDelayMs = v);
                        }, '${(_maxDelayMs / 1000).toStringAsFixed(0)}s'),
                      ],
                    ],
                  ),
                ),
              ),

              // Query input
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      TextField(
                        controller: _selectorController,
                        decoration: const InputDecoration(
                            labelText: 'Selector',
                            border: OutlineInputBorder(), isDense: true),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _payloadController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                            labelText: 'Query Payload (ZenohGetOptions.payload)',
                            border: OutlineInputBorder(), isDense: true),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _queryRunning ? null : _executeStreamQuery,
                        icon: _queryRunning
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.play_arrow),
                        label: Text(_queryRunning ? 'Streaming...' : 'Execute Stream Query'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            const Text('Stream Replies', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('${_streamReplies.length} received'),
          ]),
        ),
        Expanded(
          flex: 2,
          child: _streamReplies.isEmpty
              ? const Center(child: Text('Run a stream query to see incremental replies',
                  style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _streamReplies.length,
                  itemBuilder: (context, index) {
                    final r = _streamReplies[index];
                    return Card(
                      child: ListTile(
                        dense: true,
                        leading: Text('#${index + 1}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        title: Text(r.key, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                        subtitle: Text(r.payload, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11)),
                        trailing: Text('${r.elapsedMs}ms',
                            style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildConcurrentTab() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: _toggleConcurrent,
            icon: Icon(_concurrentRunning ? Icons.stop : Icons.play_arrow),
            label: Text(_concurrentRunning ? 'Stop All' : 'Start Concurrent Operations'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: _concurrentRunning ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          _concurrentCard('Publisher A', 'concurrent/channel-a',
              'realTime + drop', Icons.publish, Colors.red, _pubACount, _pubA != null),
          _concurrentCard('Publisher B', 'concurrent/channel-b',
              'background + drop', Icons.publish, Colors.blue, _pubBCount, _pubB != null),
          _concurrentCard('Subscriber C', 'concurrent/**',
              'Listening to both channels', Icons.hearing, Colors.green, _subCCount, _subC != null),
        ],
      ),
    );
  }

  Widget _concurrentCard(String title, String key, String desc,
      IconData icon, Color color, int count, bool active) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: active ? color : Colors.grey),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: active ? color : Colors.grey)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(key, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
            Text(desc, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ],
        ),
        trailing: Text('$count', style: TextStyle(
            fontSize: 20, fontWeight: FontWeight.bold, color: active ? color : Colors.grey)),
      ),
    );
  }

  Widget _buildLogTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            const Text('Event Log', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton(onPressed: () => setState(() => _events.clear()),
                child: const Text('Clear')),
          ]),
        ),
        Expanded(
          child: _events.isEmpty
              ? const Center(child: Text('No events yet', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _events.length,
                  itemBuilder: (context, index) {
                    final e = _events[index];
                    return ListTile(
                      dense: true,
                      leading: _eventIcon(e.type),
                      title: Text(e.message, style: const TextStyle(fontSize: 12)),
                      trailing: Text(
                        '${e.time.hour.toString().padLeft(2, '0')}:${e.time.minute.toString().padLeft(2, '0')}:${e.time.second.toString().padLeft(2, '0')}',
                        style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _eventIcon(String type) {
    switch (type) {
      case 'error': return const Icon(Icons.error, color: Colors.red, size: 18);
      case 'retry': return const Icon(Icons.replay, color: Colors.orange, size: 18);
      case 'stream': return const Icon(Icons.stream, color: Colors.blue, size: 18);
      case 'provider': return const Icon(Icons.dns, color: Colors.green, size: 18);
      case 'concurrent': return const Icon(Icons.sync, color: Colors.purple, size: 18);
      case 'done': return const Icon(Icons.check_circle, color: Colors.green, size: 18);
      default: return const Icon(Icons.info, color: Colors.grey, size: 18);
    }
  }

  Widget _sliderRow(String label, double value, double min, double max,
      ValueChanged<double> onChanged, String display) {
    return Row(children: [
      SizedBox(width: 90, child: Text(label, style: const TextStyle(fontSize: 12))),
      Expanded(
        child: Slider(value: value, min: min, max: max, onChanged: onChanged),
      ),
      SizedBox(width: 60, child: Text(display, style: const TextStyle(fontSize: 12))),
    ]);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _selectorController.dispose();
    _payloadController.dispose();
    _concurrentTimer?.cancel();
    _pubA?.undeclare();
    _pubB?.undeclare();
    _subC?.undeclare();
    _dataQueryable?.undeclare();
    _session?.close();
    super.dispose();
  }
}

class _StreamReply {
  final String key;
  final String payload;
  final String? encoding;
  final String? attachment;
  final int elapsedMs;

  _StreamReply({required this.key, required this.payload, this.encoding,
      this.attachment, required this.elapsedMs});
}

class _EventLog {
  final String type;
  final String message;
  final DateTime time;

  _EventLog({required this.type, required this.message, required this.time});
}
