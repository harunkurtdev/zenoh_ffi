import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:zenoh_ffi/zenoh_ffi.dart';

/// Query Payload - Bidirectional Request/Reply
///
/// Demonstrates:
/// - ZenohGetOptions.payload - send structured data with GET
/// - ZenohQuery.value - queryable reads incoming payload
/// - session.get() raw stream vs getCollect() comparison
/// - Full ZenohGetOptions (timeout, priority, congestion, payload, encoding, attachment)
class QueryPayloadPage extends StatefulWidget {
  const QueryPayloadPage({super.key});

  @override
  State<QueryPayloadPage> createState() => _QueryPayloadPageState();
}

class _QueryPayloadPageState extends State<QueryPayloadPage> {
  ZenohSession? _session;
  bool _isDisposed = false;
  bool _isInitializing = true;
  String? _errorMessage;

  // Database queryable
  ZenohQueryable? _dbQueryable;
  bool _dbRunning = false;
  int _queriesHandled = 0;
  final List<String> _receivedPayloads = [];

  // Mock dataset
  final List<Map<String, dynamic>> _dataset = [
    {'id': 1, 'name': 'Alice', 'age': 30, 'city': 'Istanbul', 'status': 'active'},
    {'id': 2, 'name': 'Bob', 'age': 25, 'city': 'Ankara', 'status': 'active'},
    {'id': 3, 'name': 'Charlie', 'age': 35, 'city': 'Izmir', 'status': 'inactive'},
    {'id': 4, 'name': 'Diana', 'age': 28, 'city': 'Istanbul', 'status': 'active'},
    {'id': 5, 'name': 'Eve', 'age': 42, 'city': 'Bursa', 'status': 'active'},
    {'id': 6, 'name': 'Frank', 'age': 22, 'city': 'Ankara', 'status': 'inactive'},
    {'id': 7, 'name': 'Grace', 'age': 31, 'city': 'Istanbul', 'status': 'active'},
    {'id': 8, 'name': 'Hank', 'age': 45, 'city': 'Izmir', 'status': 'active'},
  ];

  // Query builder
  final TextEditingController _payloadController = TextEditingController(
      text: '{"city": "Istanbul", "status": "active", "min_age": 25}');
  double _timeout = 5;
  ZenohPriority _priority = ZenohPriority.interactiveHigh;
  ZenohCongestionControl _congestion = ZenohCongestionControl.block;

  // Results
  final List<_QueryReply> _streamResults = [];
  final List<_QueryReply> _collectResults = [];
  int? _streamDurationMs;
  int? _collectDurationMs;
  bool _querying = false;

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

  Future<void> _toggleDatabase() async {
    if (_dbRunning) {
      await _dbQueryable?.undeclare();
      _dbQueryable = null;
      if (mounted && !_isDisposed) {
        setState(() { _dbRunning = false; _queriesHandled = 0; _receivedPayloads.clear(); });
      }
      return;
    }

    try {
      _dbQueryable = await _session!.declareQueryable('db/users', (query) {
        // Read the incoming query payload via ZenohQuery.value
        Map<String, dynamic>? filter;
        if (query.value != null && query.value!.isNotEmpty) {
          try {
            final payloadStr = utf8.decode(query.value!);
            filter = jsonDecode(payloadStr) as Map<String, dynamic>;
            if (mounted && !_isDisposed) {
              setState(() {
                _receivedPayloads.insert(0, payloadStr);
                if (_receivedPayloads.length > 20) _receivedPayloads.removeLast();
              });
            }
          } catch (_) {}
        }

        // Filter dataset based on payload
        var results = List<Map<String, dynamic>>.from(_dataset);
        if (filter != null) {
          if (filter.containsKey('city')) {
            results = results.where((r) => r['city'] == filter!['city']).toList();
          }
          if (filter.containsKey('status')) {
            results = results.where((r) => r['status'] == filter!['status']).toList();
          }
          if (filter.containsKey('min_age')) {
            results = results.where((r) => (r['age'] as int) >= (filter!['min_age'] as int)).toList();
          }
          if (filter.containsKey('name')) {
            final name = (filter['name'] as String).toLowerCase();
            results = results.where((r) => (r['name'] as String).toLowerCase().contains(name)).toList();
          }
        }

        // Reply with each matching record
        for (final record in results) {
          query.replyJson('db/users', record,
              attachment: 'total=${results.length}');
        }

        if (mounted && !_isDisposed) {
          setState(() => _queriesHandled++);
        }
      });

      if (mounted && !_isDisposed) {
        setState(() => _dbRunning = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('DB error: $e')));
      }
    }
  }

  ZenohGetOptions _buildGetOptions() {
    final payloadText = _payloadController.text.trim();
    return ZenohGetOptions(
      timeout: Duration(seconds: _timeout.toInt()),
      priority: _priority,
      congestionControl: _congestion,
      payload: payloadText.isNotEmpty
          ? Uint8List.fromList(utf8.encode(payloadText))
          : null,
      encoding: ZenohEncoding.applicationJson,
      attachment: Uint8List.fromList(utf8.encode('client=query-payload-page')),
    );
  }

  Future<void> _queryBothModes() async {
    if (_session == null || _querying) return;
    setState(() {
      _querying = true;
      _streamResults.clear();
      _collectResults.clear();
      _streamDurationMs = null;
      _collectDurationMs = null;
    });

    final options = _buildGetOptions();

    // 1. Raw stream mode: session.get()
    try {
      final sw1 = Stopwatch()..start();
      await for (final reply in _session!.get('db/users', options: options)) {
        if (!mounted || _isDisposed) break;
        setState(() {
          _streamResults.add(_QueryReply(
            key: reply.key,
            payload: reply.payloadString,
            encoding: reply.encoding?.mimeType,
            attachment: reply.attachmentString,
          ));
        });
      }
      sw1.stop();
      if (mounted && !_isDisposed) {
        setState(() => _streamDurationMs = sw1.elapsedMilliseconds);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Stream error: $e')));
      }
    }

    // 2. Batch mode: getCollect()
    try {
      final sw2 = Stopwatch()..start();
      final replies = await _session!.getCollect('db/users', options: options);
      sw2.stop();
      if (mounted && !_isDisposed) {
        setState(() {
          _collectDurationMs = sw2.elapsedMilliseconds;
          _collectResults.addAll(replies.map((r) => _QueryReply(
            key: r.key,
            payload: r.payloadString,
            encoding: r.encoding?.mimeType,
            attachment: r.attachmentString,
          )));
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Collect error: $e')));
      }
    }

    if (mounted && !_isDisposed) {
      setState(() => _querying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Query Payload'),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.search), text: 'Query'),
            Tab(icon: Icon(Icons.dns), text: 'Database'),
          ]),
        ),
        body: _isInitializing
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? _buildErrorWidget()
                : TabBarView(children: [_buildQueryTab(), _buildDbTab()]),
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

  Widget _buildQueryTab() {
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Query Payload (ZenohGetOptions.payload)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text('Send structured filter data with your GET request',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _payloadController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                            labelText: 'JSON Payload',
                            border: OutlineInputBorder(), isDense: true),
                      ),
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 4, children: [
                        ActionChip(
                          label: const Text('Istanbul active', style: TextStyle(fontSize: 10)),
                          onPressed: () => _payloadController.text =
                              '{"city": "Istanbul", "status": "active"}',
                        ),
                        ActionChip(
                          label: const Text('Age > 30', style: TextStyle(fontSize: 10)),
                          onPressed: () => _payloadController.text = '{"min_age": 30}',
                        ),
                        ActionChip(
                          label: const Text('All records', style: TextStyle(fontSize: 10)),
                          onPressed: () => _payloadController.text = '{}',
                        ),
                        ActionChip(
                          label: const Text('Name: alice', style: TextStyle(fontSize: 10)),
                          onPressed: () => _payloadController.text = '{"name": "alice"}',
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Full ZenohGetOptions', style: TextStyle(fontWeight: FontWeight.bold)),
                      Row(children: [
                        const Text('Timeout: ', style: TextStyle(fontSize: 12)),
                        Expanded(
                          child: Slider(
                            value: _timeout, min: 1, max: 30, divisions: 29,
                            label: '${_timeout.toInt()}s',
                            onChanged: (v) => setState(() => _timeout = v),
                          ),
                        ),
                        Text('${_timeout.toInt()}s', style: const TextStyle(fontSize: 12)),
                      ]),
                      Row(children: [
                        Expanded(
                          child: DropdownButtonFormField<ZenohPriority>(
                            value: _priority, isExpanded: true,
                            decoration: const InputDecoration(
                                labelText: 'Priority', border: OutlineInputBorder(), isDense: true),
                            items: ZenohPriority.values.map((p) =>
                                DropdownMenuItem(value: p,
                                    child: Text(p.name, style: const TextStyle(fontSize: 12)))).toList(),
                            onChanged: (v) { if (v != null) setState(() => _priority = v); },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<ZenohCongestionControl>(
                            value: _congestion, isExpanded: true,
                            decoration: const InputDecoration(
                                labelText: 'Congestion', border: OutlineInputBorder(), isDense: true),
                            items: ZenohCongestionControl.values.map((c) =>
                                DropdownMenuItem(value: c,
                                    child: Text(c.name, style: const TextStyle(fontSize: 12)))).toList(),
                            onChanged: (v) { if (v != null) setState(() => _congestion = v); },
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _querying ? null : _queryBothModes,
                icon: _querying
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.compare_arrows),
                label: Text(_querying ? 'Querying...' : 'Query (stream + collect)'),
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: Colors.blue, foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Results comparison
        Expanded(
          flex: 3,
          child: Row(
            children: [
              Expanded(child: _buildResultColumn(
                'get() Stream', _streamResults, _streamDurationMs, Colors.blue)),
              const VerticalDivider(width: 1),
              Expanded(child: _buildResultColumn(
                'getCollect()', _collectResults, _collectDurationMs, Colors.green)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResultColumn(String title, List<_QueryReply> results,
      int? durationMs, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          color: color.withValues(alpha: 0.1),
          child: Row(children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: color)),
            const Spacer(),
            if (durationMs != null) Text('${durationMs}ms',
                style: TextStyle(fontSize: 11, color: color)),
            Text(' (${results.length})', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ]),
        ),
        Expanded(
          child: results.isEmpty
              ? Center(child: Text('No results', style: TextStyle(color: Colors.grey[400], fontSize: 12)))
              : ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final r = results[index];
                    return ListTile(
                      dense: true,
                      title: Text(r.payload, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 10)),
                      subtitle: r.attachment != null
                          ? Text(r.attachment!, style: TextStyle(fontSize: 9, color: Colors.grey[600]))
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDbTab() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: _dbRunning ? Colors.green[50] : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Icon(_dbRunning ? Icons.storage : Icons.storage_outlined,
                    size: 40, color: _dbRunning ? Colors.green : Colors.grey),
                const SizedBox(height: 8),
                Text(_dbRunning
                    ? 'Database Active ($_queriesHandled queries)'
                    : 'Database Stopped',
                    style: TextStyle(fontWeight: FontWeight.bold,
                        color: _dbRunning ? Colors.green : Colors.grey)),
                const Text('Queryable on db/users - reads ZenohQuery.value',
                    style: TextStyle(fontSize: 11)),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _toggleDatabase,
                  icon: Icon(_dbRunning ? Icons.stop : Icons.play_arrow),
                  label: Text(_dbRunning ? 'Stop' : 'Start Database'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _dbRunning ? Colors.red : Colors.green,
                      foregroundColor: Colors.white),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Mock Dataset (8 records)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
            child: ListView(
              children: [
                DataTable(
                  columnSpacing: 16,
                  horizontalMargin: 8,
                  headingRowHeight: 32,
                  dataRowMinHeight: 28,
                  dataRowMaxHeight: 32,
                  columns: const [
                    DataColumn(label: Text('Name', style: TextStyle(fontSize: 11))),
                    DataColumn(label: Text('Age', style: TextStyle(fontSize: 11)), numeric: true),
                    DataColumn(label: Text('City', style: TextStyle(fontSize: 11))),
                    DataColumn(label: Text('Status', style: TextStyle(fontSize: 11))),
                  ],
                  rows: _dataset.map((r) => DataRow(cells: [
                    DataCell(Text('${r['name']}', style: const TextStyle(fontSize: 11))),
                    DataCell(Text('${r['age']}', style: const TextStyle(fontSize: 11))),
                    DataCell(Text('${r['city']}', style: const TextStyle(fontSize: 11))),
                    DataCell(Text('${r['status']}', style: const TextStyle(fontSize: 11))),
                  ])).toList(),
                ),
                if (_receivedPayloads.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Received Payloads (ZenohQuery.value)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ..._receivedPayloads.map((p) => Card(
                    color: Colors.grey[100],
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: SelectableText(p,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                    ),
                  )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _payloadController.dispose();
    _dbQueryable?.undeclare();
    _session?.close();
    super.dispose();
  }
}

class _QueryReply {
  final String key;
  final String payload;
  final String? encoding;
  final String? attachment;

  _QueryReply({required this.key, required this.payload, this.encoding, this.attachment});
}
