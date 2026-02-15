import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zenoh_ffi/zenoh_ffi.dart';

/// Wildcard Explorer - Key Expression Testing
///
/// Demonstrates:
/// - ZenohPublisher.delete() - publisher tombstones vs session.delete()
/// - ZenohSample.timestamp - displayed for each sample
/// - Advanced wildcards: * (single level) vs ** (multi-level)
/// - ZenohSampleKind.put vs .delete visual comparison
class WildcardExplorerPage extends StatefulWidget {
  const WildcardExplorerPage({super.key});

  @override
  State<WildcardExplorerPage> createState() => _WildcardExplorerPageState();
}

class _WildcardExplorerPageState extends State<WildcardExplorerPage> {
  ZenohSession? _session;
  bool _isDisposed = false;
  bool _isInitializing = true;
  String? _errorMessage;

  // Publish
  final TextEditingController _keyController =
      TextEditingController(text: 'home/floor1/room1/temperature');
  final TextEditingController _valueController =
      TextEditingController(text: '22.5');
  ZenohPublisher? _publisher;
  String? _publisherKey;

  // Wildcard subscriptions
  final TextEditingController _wildcardController =
      TextEditingController(text: 'home/**');
  final Map<String, ZenohSubscriber> _subscriptions = {};
  final List<_MatchedSample> _matched = [];

  // Key tree
  final Map<String, _KeyNode> _keyTree = {};

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
        setState(() { _isInitializing = false; _errorMessage = null; });
      }
    } catch (e) {
      if (mounted && !_isDisposed) {
        setState(() { _isInitializing = false; _errorMessage = e.toString(); });
      }
    }
  }

  Future<void> _ensurePublisher() async {
    final key = _keyController.text.trim();
    if (key.isEmpty || _session == null) return;

    if (_publisherKey != key) {
      await _publisher?.undeclare();
      _publisher = await _session!.declarePublisher(key);
      _publisherKey = key;
    }
  }

  Future<void> _publishPut() async {
    try {
      await _ensurePublisher();
      await _publisher!.putString(_valueController.text);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PUT ${_keyController.text}'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _publishDelete() async {
    try {
      await _ensurePublisher();
      // ZenohPublisher.delete() - sends a tombstone DELETE through the publisher
      await _publisher!.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('DELETE (tombstone) ${_keyController.text}'),
              backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _addSubscription() async {
    if (_session == null) return;
    final pattern = _wildcardController.text.trim();
    if (pattern.isEmpty || _subscriptions.containsKey(pattern)) return;

    try {
      final sub = await _session!.declareSubscriber(pattern);
      _subscriptions[pattern] = sub;

      sub.stream.listen((sample) {
        if (mounted && !_isDisposed) {
          setState(() {
            final isDelete = sample.kind == ZenohSampleKind.delete;

            // Update key tree
            if (isDelete) {
              _keyTree[sample.key] = _KeyNode(
                key: sample.key,
                value: null,
                isDeleted: true,
                timestamp: sample.timestamp,
                lastUpdate: DateTime.now(),
              );
            } else {
              _keyTree[sample.key] = _KeyNode(
                key: sample.key,
                value: sample.payloadString,
                isDeleted: false,
                timestamp: sample.timestamp,
                lastUpdate: DateTime.now(),
              );
            }

            // Add to matched list
            _matched.insert(0, _MatchedSample(
              key: sample.key,
              value: isDelete ? null : sample.payloadString,
              kind: sample.kind,
              matchedPattern: pattern,
              timestamp: sample.timestamp,
              receivedAt: DateTime.now(),
            ));
            if (_matched.length > 100) _matched.removeLast();
          });
        }
      });

      if (mounted && !_isDisposed) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Subscribe error: $e')),
        );
      }
    }
  }

  Future<void> _removeSubscription(String pattern) async {
    final sub = _subscriptions.remove(pattern);
    await sub?.undeclare();
    if (mounted && !_isDisposed) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wildcard Explorer')),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorWidget()
              : Column(
                  children: [
                    Expanded(flex: 4, child: _buildTopSection()),
                    const Divider(height: 1),
                    _buildMatchHeader(),
                    Expanded(flex: 3, child: _buildMatchList()),
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
            const Text('Connection Failed',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('$_errorMessage', textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber[50], borderRadius: BorderRadius.circular(8),
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

  Widget _buildTopSection() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Pattern cheat sheet
        Card(
          color: Colors.blue[50],
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Zenoh Wildcard Syntax',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                _syntaxRow('*', 'Matches exactly one level', 'home/* matches home/temp but NOT home/floor1/temp'),
                _syntaxRow('**', 'Matches zero or more levels', 'home/** matches home/temp AND home/floor1/room1/temp'),
                _syntaxRow('a/*/c', 'Single wildcard in path', 'Matches a/x/c, a/y/c but not a/x/y/c'),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Publish panel
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Publish (via Publisher)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: _keyController,
                  decoration: const InputDecoration(
                      labelText: 'Key Expression',
                      border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _valueController,
                  decoration: const InputDecoration(
                      labelText: 'Value', border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _publishPut,
                      icon: const Icon(Icons.publish, size: 18),
                      label: const Text('PUT'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green, foregroundColor: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _publishDelete,
                      icon: const Icon(Icons.delete_forever, size: 18),
                      label: const Text('DELETE (tombstone)'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red, foregroundColor: Colors.white),
                    ),
                  ),
                ]),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('publisher.delete() sends a tombstone SampleKind.delete',
                      style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Subscribe panel
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Subscribe with Wildcards',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _wildcardController,
                      decoration: const InputDecoration(
                          labelText: 'Wildcard pattern',
                          border: OutlineInputBorder(), isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _addSubscription,
                    child: const Text('Subscribe'),
                  ),
                ]),
                const SizedBox(height: 4),
                Wrap(spacing: 4, children: [
                  ..._quickPattern('home/*'),
                  ..._quickPattern('home/**'),
                  ..._quickPattern('home/*/room1/*'),
                  ..._quickPattern('**'),
                ]),
                if (_subscriptions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Active Subscriptions:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  Wrap(spacing: 6, runSpacing: 4,
                    children: _subscriptions.keys.map((p) => Chip(
                      label: Text(p, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () => _removeSubscription(p),
                      backgroundColor: Colors.blue[50],
                    )).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Key tree
        if (_keyTree.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Text('Key Tree', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const Spacer(),
                    TextButton(onPressed: () => setState(() => _keyTree.clear()),
                        child: const Text('Clear')),
                  ]),
                  ..._keyTree.values.map((node) => ListTile(
                    dense: true,
                    leading: Icon(
                      node.isDeleted ? Icons.delete : Icons.circle,
                      color: node.isDeleted ? Colors.red : Colors.green,
                      size: 16,
                    ),
                    title: Text(
                      node.key,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        decoration: node.isDeleted ? TextDecoration.lineThrough : null,
                        color: node.isDeleted ? Colors.red : null,
                      ),
                    ),
                    subtitle: node.isDeleted
                        ? const Text('DELETED', style: TextStyle(color: Colors.red, fontSize: 10))
                        : Text(node.value ?? '', style: const TextStyle(fontSize: 11)),
                    trailing: node.timestamp != null
                        ? Text(_formatTs(node.timestamp!),
                            style: TextStyle(fontSize: 9, color: Colors.grey[500]))
                        : null,
                  )),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMatchHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(children: [
        const Text('Matched Samples', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const Spacer(),
        Text('${_matched.length}', style: TextStyle(color: Colors.grey[600])),
        TextButton(onPressed: () => setState(() => _matched.clear()),
            child: const Text('Clear')),
      ]),
    );
  }

  Widget _buildMatchList() {
    if (_matched.isEmpty) {
      return const Center(
        child: Text('Subscribe to a pattern, then publish data to see matches',
            style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: _matched.length,
      itemBuilder: (context, index) {
        final m = _matched[index];
        final isDelete = m.kind == ZenohSampleKind.delete;
        return Card(
          color: isDelete ? Colors.red[50] : Colors.green[50],
          child: ListTile(
            dense: true,
            leading: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isDelete ? Colors.red : Colors.green,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(isDelete ? 'DEL' : 'PUT',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
            title: Text(m.key, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isDelete) Text(m.value ?? '', style: const TextStyle(fontSize: 11)),
                Row(children: [
                  Text('pattern: ${m.matchedPattern}',
                      style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                  if (m.timestamp != null) ...[
                    const SizedBox(width: 8),
                    Text('ts: ${_formatTs(m.timestamp!)}',
                        style: TextStyle(fontSize: 10, color: Colors.teal[600])),
                  ],
                ]),
              ],
            ),
            trailing: Text(_formatTime(m.receivedAt),
                style: TextStyle(fontSize: 10, color: Colors.grey[500])),
          ),
        );
      },
    );
  }

  List<Widget> _quickPattern(String pattern) {
    return [
      ActionChip(
        label: Text(pattern, style: const TextStyle(fontFamily: 'monospace', fontSize: 10)),
        onPressed: () {
          _wildcardController.text = pattern;
          _addSubscription();
        },
      ),
    ];
  }

  Widget _syntaxRow(String syntax, String desc, String example) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 30,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
              color: Colors.blue, borderRadius: BorderRadius.circular(4)),
          child: Text(syntax,
              style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
              textAlign: TextAlign.center),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(desc, style: const TextStyle(fontSize: 12)),
            Text(example, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
          ]),
        ),
      ]),
    );
  }

  String _formatTime(DateTime dt) => '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';

  String _formatTs(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}.${dt.millisecond.toString().padLeft(3, '0')}';

  @override
  void dispose() {
    _isDisposed = true;
    _keyController.dispose();
    _valueController.dispose();
    _wildcardController.dispose();
    _publisher?.undeclare();
    for (final sub in _subscriptions.values) {
      sub.undeclare();
    }
    _session?.close();
    super.dispose();
  }
}

class _KeyNode {
  final String key;
  final String? value;
  final bool isDeleted;
  final DateTime? timestamp;
  final DateTime lastUpdate;

  _KeyNode({required this.key, this.value, required this.isDeleted,
      this.timestamp, required this.lastUpdate});
}

class _MatchedSample {
  final String key;
  final String? value;
  final ZenohSampleKind kind;
  final String matchedPattern;
  final DateTime? timestamp;
  final DateTime receivedAt;

  _MatchedSample({required this.key, this.value, required this.kind,
      required this.matchedPattern, this.timestamp, required this.receivedAt});
}
