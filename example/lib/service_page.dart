import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:zenoh_ffi/zenoh_ffi.dart';

/// Request/Reply Service - Edge Microservices
///
/// Demonstrates:
/// - declareQueryable() with replyJson(), replyString()
/// - get() with ZenohGetOptions (timeout, payload, attachment, encoding)
/// - getCollect() - collect all replies into a list
/// - ZenohRetry - automatic retry with exponential backoff
/// - Query payload (sending data with get request)
/// - Multiple queryable handlers
class ServicePage extends StatefulWidget {
  const ServicePage({super.key});

  @override
  State<ServicePage> createState() => _ServicePageState();
}

class _ServicePageState extends State<ServicePage> {
  ZenohSession? _session;
  bool _isDisposed = false;
  bool _isInitializing = true;
  String? _errorMessage;

  // Service side
  ZenohQueryable? _calcQueryable;
  ZenohQueryable? _echoQueryable;
  bool _serviceRunning = false;
  int _queriesHandled = 0;

  // Client side
  String _selectedOp = 'add';
  final TextEditingController _aController =
      TextEditingController(text: '10');
  final TextEditingController _bController =
      TextEditingController(text: '5');
  final TextEditingController _echoController =
      TextEditingController(text: 'Hello Zenoh!');
  double _timeout = 5;
  bool _useRetry = false;

  // Request/Reply log
  final List<_RequestLog> _logs = [];

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
        endpoints: [

          'tcp/localhost:7447',
          'tcp/127.0.0.1:7447',
        'tcp/10.81.29.92:7447',
        'tcp/10.0.0.2:7447', // android emulator localhost
        ],
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

  Future<void> _startService() async {
    if (_session == null || _serviceRunning) return;

    try {
      // Calculator queryable
      _calcQueryable = await _session!.declareQueryable(
        'service/calc',
        (query) {
          _handleCalcQuery(query);
        },
      );

      // Echo/uppercase queryable
      _echoQueryable = await _session!.declareQueryable(
        'service/echo',
        (query) {
          _handleEchoQuery(query);
        },
      );

      if (mounted && !_isDisposed) {
        setState(() => _serviceRunning = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Service start error: $e')),
        );
      }
    }
  }

  void _handleCalcQuery(ZenohQuery query) {
    try {
      // Parse parameters from selector query string or payload
      Map<String, dynamic>? params;

      // Try to parse from selector (e.g., service/calc?op=add&a=5&b=3)
      final selectorParts = query.selector.split('?');
      if (selectorParts.length > 1) {
        final queryString = selectorParts.last;
        final queryParams = Uri.splitQueryString(queryString);
        params = {
          'op': queryParams['op'] ?? 'add',
          'a': double.tryParse(queryParams['a'] ?? '0') ?? 0,
          'b': double.tryParse(queryParams['b'] ?? '0') ?? 0,
        };
      }

      if (params == null) {
        query.replyJson('service/calc', {'error': 'No parameters provided'});
        return;
      }

      final op = params['op'] as String;
      final a = (params['a'] as num).toDouble();
      final b = (params['b'] as num).toDouble();

      double result;
      switch (op) {
        case 'add':
          result = a + b;
          break;
        case 'subtract':
          result = a - b;
          break;
        case 'multiply':
          result = a * b;
          break;
        case 'divide':
          if (b == 0) {
            query.replyJson('service/calc', {'error': 'Division by zero'});
            _incrementQueries();
            return;
          }
          result = a / b;
          break;
        default:
          query.replyJson(
              'service/calc', {'error': 'Unknown operation: $op'});
          _incrementQueries();
          return;
      }

      query.replyJson('service/calc', {
        'op': op,
        'a': a,
        'b': b,
        'result': result,
        'ts': DateTime.now().toIso8601String(),
      });

      _incrementQueries();
    } catch (e) {
      query.replyJson('service/calc', {'error': e.toString()});
      _incrementQueries();
    }
  }

  void _handleEchoQuery(ZenohQuery query) {
    try {
      final selectorParts = query.selector.split('?');
      String text = 'no input';
      String mode = 'echo';

      if (selectorParts.length > 1) {
        final queryParams = Uri.splitQueryString(selectorParts.last);
        text = queryParams['text'] ?? 'no input';
        mode = queryParams['mode'] ?? 'echo';
      }

      String response;
      if (mode == 'uppercase') {
        response = text.toUpperCase();
      } else if (mode == 'reverse') {
        response = text.split('').reversed.join('');
      } else {
        response = text;
      }

      query.replyString('service/echo', response);
      _incrementQueries();
    } catch (e) {
      query.replyString('service/echo', 'Error: $e');
      _incrementQueries();
    }
  }

  void _incrementQueries() {
    if (mounted && !_isDisposed) {
      setState(() => _queriesHandled++);
    }
  }

  Future<void> _stopService() async {
    await _calcQueryable?.undeclare();
    await _echoQueryable?.undeclare();
    _calcQueryable = null;
    _echoQueryable = null;

    if (mounted && !_isDisposed) {
      setState(() {
        _serviceRunning = false;
        _queriesHandled = 0;
      });
    }
  }

  Future<void> _sendCalcRequest() async {
    if (_session == null) return;

    final a = double.tryParse(_aController.text) ?? 0;
    final b = double.tryParse(_bController.text) ?? 0;
    final selector =
        'service/calc?op=$_selectedOp&a=$a&b=$b';

    final stopwatch = Stopwatch()..start();

    try {
      List<ZenohReply> replies;

      if (_useRetry) {
        final retry = ZenohRetry(
          maxAttempts: 3,
          initialDelay: const Duration(milliseconds: 500),
        );
        replies = await retry.execute(
          () => _session!.getCollect(
            selector,
            options: ZenohGetOptions(
              timeout: Duration(seconds: _timeout.toInt()),
              encoding: ZenohEncoding.applicationJson,
              attachment:
                  Uint8List.fromList(utf8.encode('client=flutter-service-page')),
            ),
          ),
        );
      } else {
        replies = await _session!.getCollect(
          selector,
          options: ZenohGetOptions(
            timeout: Duration(seconds: _timeout.toInt()),
            encoding: ZenohEncoding.applicationJson,
            attachment:
                Uint8List.fromList(utf8.encode('client=flutter-service-page')),
          ),
        );
      }

      stopwatch.stop();

      if (mounted && !_isDisposed) {
        setState(() {
          for (final reply in replies) {
            _logs.insert(
              0,
              _RequestLog(
                request: '$_selectedOp($a, $b)',
                response: reply.payloadString,
                duration: stopwatch.elapsed,
                isError: false,
                usedRetry: _useRetry,
              ),
            );
          }
          if (replies.isEmpty) {
            _logs.insert(
              0,
              _RequestLog(
                request: '$_selectedOp($a, $b)',
                response: 'No reply (timeout)',
                duration: stopwatch.elapsed,
                isError: true,
                usedRetry: _useRetry,
              ),
            );
          }
          if (_logs.length > 50) _logs.removeLast();
        });
      }
    } catch (e) {
      stopwatch.stop();
      if (mounted && !_isDisposed) {
        setState(() {
          _logs.insert(
            0,
            _RequestLog(
              request: '$_selectedOp($a, $b)',
              response: 'Error: $e',
              duration: stopwatch.elapsed,
              isError: true,
              usedRetry: _useRetry,
            ),
          );
        });
      }
    }
  }

  Future<void> _sendEchoRequest() async {
    if (_session == null) return;

    final text = _echoController.text;
    final mode = _selectedOp == 'uppercase'
        ? 'uppercase'
        : _selectedOp == 'reverse'
            ? 'reverse'
            : 'echo';
    final selector =
        'service/echo?text=${Uri.encodeComponent(text)}&mode=$mode';

    final stopwatch = Stopwatch()..start();

    try {
      final replies = await _session!.getCollect(
        selector,
        options: ZenohGetOptions(
          timeout: Duration(seconds: _timeout.toInt()),
        ),
      );

      stopwatch.stop();

      if (mounted && !_isDisposed) {
        setState(() {
          for (final reply in replies) {
            _logs.insert(
              0,
              _RequestLog(
                request: '$mode("$text")',
                response: reply.payloadString,
                duration: stopwatch.elapsed,
                isError: false,
                usedRetry: false,
              ),
            );
          }
          if (replies.isEmpty) {
            _logs.insert(
              0,
              _RequestLog(
                request: '$mode("$text")',
                response: 'No reply (timeout)',
                duration: stopwatch.elapsed,
                isError: true,
                usedRetry: false,
              ),
            );
          }
          if (_logs.length > 50) _logs.removeLast();
        });
      }
    } catch (e) {
      stopwatch.stop();
      if (mounted && !_isDisposed) {
        setState(() {
          _logs.insert(
            0,
            _RequestLog(
              request: '$mode("$text")',
              response: 'Error: $e',
              duration: stopwatch.elapsed,
              isError: true,
              usedRetry: false,
            ),
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Request/Reply Service'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.dns), text: 'Service'),
              Tab(icon: Icon(Icons.send), text: 'Client'),
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
                : TabBarView(
                    children: [
                      _buildServiceTab(),
                      _buildClientTab(),
                    ],
                  ),
      ),
    );
  }

  Widget _buildServiceTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Service status card
          Card(
            color: _serviceRunning ? Colors.green[50] : Colors.grey[100],
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(
                    _serviceRunning ? Icons.cloud_done : Icons.cloud_off,
                    size: 48,
                    color: _serviceRunning ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _serviceRunning ? 'Service Running' : 'Service Stopped',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color:
                          _serviceRunning ? Colors.green : Colors.grey[700],
                    ),
                  ),
                  if (_serviceRunning)
                    Text('Handled $_queriesHandled queries',
                        style: TextStyle(color: Colors.grey[600])),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed:
                        _serviceRunning ? _stopService : _startService,
                    icon: Icon(_serviceRunning
                        ? Icons.stop
                        : Icons.play_arrow),
                    label: Text(
                        _serviceRunning ? 'Stop Service' : 'Start Service'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _serviceRunning ? Colors.red : Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Registered endpoints
          const Text('Registered Endpoints',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          _buildEndpointTile(
            'service/calc',
            'Calculator: add, subtract, multiply, divide',
            'Params: ?op=add&a=5&b=3',
            Icons.calculate,
          ),
          _buildEndpointTile(
            'service/echo',
            'Echo / Transform text',
            'Params: ?text=hello&mode=echo|uppercase|reverse',
            Icons.repeat,
          ),
        ],
      ),
    );
  }

  Widget _buildEndpointTile(
      String key, String description, String params, IconData icon) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: _serviceRunning ? Colors.blue : Colors.grey),
        title: Text(key, style: const TextStyle(fontFamily: 'monospace')),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(description),
            Text(params,
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  Widget _buildClientTab() {
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Operation selector
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Operation',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('Add'),
                              selected: _selectedOp == 'add',
                              onSelected: (_) =>
                                  setState(() => _selectedOp = 'add'),
                            ),
                            ChoiceChip(
                              label: const Text('Subtract'),
                              selected: _selectedOp == 'subtract',
                              onSelected: (_) =>
                                  setState(() => _selectedOp = 'subtract'),
                            ),
                            ChoiceChip(
                              label: const Text('Multiply'),
                              selected: _selectedOp == 'multiply',
                              onSelected: (_) =>
                                  setState(() => _selectedOp = 'multiply'),
                            ),
                            ChoiceChip(
                              label: const Text('Divide'),
                              selected: _selectedOp == 'divide',
                              onSelected: (_) =>
                                  setState(() => _selectedOp = 'divide'),
                            ),
                            ChoiceChip(
                              label: const Text('Echo'),
                              selected: _selectedOp == 'echo',
                              onSelected: (_) =>
                                  setState(() => _selectedOp = 'echo'),
                            ),
                            ChoiceChip(
                              label: const Text('Uppercase'),
                              selected: _selectedOp == 'uppercase',
                              onSelected: (_) =>
                                  setState(() => _selectedOp = 'uppercase'),
                            ),
                            ChoiceChip(
                              label: const Text('Reverse'),
                              selected: _selectedOp == 'reverse',
                              onSelected: (_) =>
                                  setState(() => _selectedOp = 'reverse'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Input fields
                if (_selectedOp == 'echo' ||
                    _selectedOp == 'uppercase' ||
                    _selectedOp == 'reverse')
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        controller: _echoController,
                        decoration: const InputDecoration(
                          labelText: 'Text Input',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  )
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _aController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'A',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(_selectedOp == 'add'
                                ? '+'
                                : _selectedOp == 'subtract'
                                    ? '-'
                                    : _selectedOp == 'multiply'
                                        ? '*'
                                        : '/'),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _bController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'B',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 8),

                // Options
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('Timeout: '),
                            Expanded(
                              child: Slider(
                                value: _timeout,
                                min: 1,
                                max: 30,
                                divisions: 29,
                                label: '${_timeout.toInt()}s',
                                onChanged: (v) =>
                                    setState(() => _timeout = v),
                              ),
                            ),
                            Text('${_timeout.toInt()}s'),
                          ],
                        ),
                        SwitchListTile(
                          title: const Text('Use ZenohRetry'),
                          subtitle: const Text(
                              '3 attempts, 500ms initial delay, exponential backoff'),
                          value: _useRetry,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (v) =>
                              setState(() => _useRetry = v),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Send button
                ElevatedButton.icon(
                  onPressed: (_selectedOp == 'echo' ||
                          _selectedOp == 'uppercase' ||
                          _selectedOp == 'reverse')
                      ? _sendEchoRequest
                      : _sendCalcRequest,
                  icon: const Icon(Icons.send),
                  label: Text(_useRetry
                      ? 'Send with Retry'
                      : 'Send Request'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),

        const Divider(height: 1),

        // Results log
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              const Text('Request/Reply Log',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _logs.clear()),
                child: const Text('Clear'),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: _logs.isEmpty
              ? const Center(
                  child: Text('Send a request to see results',
                      style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[index];
                    return Card(
                      color: log.isError ? Colors.red[50] : Colors.green[50],
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          log.isError
                              ? Icons.error_outline
                              : Icons.check_circle_outline,
                          color: log.isError ? Colors.red : Colors.green,
                          size: 20,
                        ),
                        title: Text(
                          log.request,
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(log.response,
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 12)),
                            Row(
                              children: [
                                Text(
                                  '${log.duration.inMilliseconds}ms',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[600]),
                                ),
                                if (log.usedRetry) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.2),
                                      borderRadius:
                                          BorderRadius.circular(4),
                                    ),
                                    child: const Text('RETRY',
                                        style: TextStyle(
                                            fontSize: 9,
                                            color: Colors.orange)),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _aController.dispose();
    _bController.dispose();
    _echoController.dispose();
    _disposeResources();
    super.dispose();
  }

  Future<void> _disposeResources() async {
    await _calcQueryable?.undeclare();
    await _echoQueryable?.undeclare();
    await _session?.close();
  }
}

class _RequestLog {
  final String request;
  final String response;
  final Duration duration;
  final bool isError;
  final bool usedRetry;

  _RequestLog({
    required this.request,
    required this.response,
    required this.duration,
    required this.isError,
    required this.usedRetry,
  });
}
