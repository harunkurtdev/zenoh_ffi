import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:zenoh_ffi/zenoh_ffi.dart';

/// Key-Value Store - Distributed Configuration
///
/// Demonstrates:
/// - Full CRUD: put, get (getCollect), delete
/// - putString() / putJson() with encoding selection
/// - getCollect() for retrieving values
/// - Subscriber for real-time change notifications (PUT + DELETE kinds)
/// - ZenohSampleKind.put vs ZenohSampleKind.delete handling
/// - Attachments as metadata (author, version, TTL)
/// - Wildcard subscription for all keys in namespace
class KvStorePage extends StatefulWidget {
  const KvStorePage({super.key});

  @override
  State<KvStorePage> createState() => _KvStorePageState();
}

class _KvStorePageState extends State<KvStorePage> {
  ZenohSession? _session;
  bool _isDisposed = false;
  bool _isInitializing = true;
  String? _errorMessage;

  // Subscriber for watching changes
  ZenohSubscriber? _subscriber;
  bool _isWatching = false;

  // Form controllers
  final TextEditingController _keyController =
      TextEditingController(text: 'config/app-name');
  final TextEditingController _valueController =
      TextEditingController(text: 'My Zenoh App');
  final TextEditingController _authorController =
      TextEditingController(text: 'flutter');
  final TextEditingController _versionController =
      TextEditingController(text: '1');

  ZenohEncoding _selectedEncoding = ZenohEncoding.textPlain;
  ZenohPriority _selectedPriority = ZenohPriority.data;

  // Local KV store (mirrors what we know)
  final Map<String, _KvEntry> _store = {};

  // Change log
  final List<_ChangeEvent> _changeLog = [];

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

  Future<void> _toggleWatch() async {
    if (_session == null) return;

    if (_isWatching) {
      await _subscriber?.undeclare();
      _subscriber = null;
      if (mounted && !_isDisposed) {
        setState(() => _isWatching = false);
      }
    } else {
      try {
        _subscriber = await _session!.declareSubscriber('kv/**');
        _subscriber!.stream.listen((sample) {
          if (mounted && !_isDisposed) {
            setState(() {
              final isDelete = sample.kind == ZenohSampleKind.delete;

              if (isDelete) {
                _store.remove(sample.key);
              } else {
                _store[sample.key] = _KvEntry(
                  value: sample.payloadString,
                  encoding: sample.encoding,
                  metadata: sample.attachmentString,
                  updatedAt: DateTime.now(),
                );
              }

              _changeLog.insert(
                0,
                _ChangeEvent(
                  key: sample.key,
                  kind: sample.kind,
                  value: isDelete ? null : sample.payloadString,
                  metadata: sample.attachmentString,
                  timestamp: DateTime.now(),
                ),
              );
              if (_changeLog.length > 100) _changeLog.removeLast();
            });
          }
        });

        if (mounted && !_isDisposed) {
          setState(() => _isWatching = true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Watch error: $e')),
          );
        }
      }
    }
  }

  Future<void> _putKey() async {
    if (_session == null) return;

    final key = 'kv/${_keyController.text.trim()}';
    final value = _valueController.text;

    if (_keyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Key cannot be empty')),
      );
      return;
    }

    try {
      // Build metadata attachment
      final metadata = <String, dynamic>{};
      if (_authorController.text.isNotEmpty) {
        metadata['author'] = _authorController.text;
      }
      if (_versionController.text.isNotEmpty) {
        metadata['version'] = _versionController.text;
      }
      metadata['ts'] = DateTime.now().toIso8601String();

      final attachment = metadata.isNotEmpty
          ? Uint8List.fromList(utf8.encode(jsonEncode(metadata)))
          : null;

      if (_selectedEncoding == ZenohEncoding.applicationJson ||
          _selectedEncoding == ZenohEncoding.json) {
        // Try to parse as JSON, fallback to wrapping as string
        Object jsonValue;
        try {
          jsonValue = jsonDecode(value);
        } catch (_) {
          jsonValue = {'value': value};
        }
        await _session!.putJson(key, jsonValue, attachment: attachment);
      } else {
        await _session!.putString(
          key,
          value,
          options: ZenohPutOptions(
            encoding: _selectedEncoding,
            priority: _selectedPriority,
            attachment: attachment,
          ),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PUT $key'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Increment version
      final currentVersion = int.tryParse(_versionController.text) ?? 0;
      _versionController.text = '${currentVersion + 1}';
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PUT error: $e')),
        );
      }
    }
  }

  Future<void> _getKey() async {
    if (_session == null) return;

    final key = 'kv/${_keyController.text.trim()}';
    if (_keyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Key cannot be empty')),
      );
      return;
    }

    try {
      final replies = await _session!.getCollect(
        key,
        options: ZenohGetOptions(
          timeout: const Duration(seconds: 5),
        ),
      );

      if (mounted && !_isDisposed) {
        if (replies.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Key not found: $key'),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          setState(() {
            for (final reply in replies) {
              _store[reply.key] = _KvEntry(
                value: reply.payloadString,
                encoding: reply.encoding,
                metadata: reply.attachmentString,
                updatedAt: DateTime.now(),
              );
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('GET $key -> ${replies.length} result(s)'),
              backgroundColor: Colors.blue,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GET error: $e')),
        );
      }
    }
  }

  Future<void> _getAll() async {
    if (_session == null) return;

    try {
      final replies = await _session!.getCollect(
        'kv/**',
        options: ZenohGetOptions(
          timeout: const Duration(seconds: 5),
        ),
      );

      if (mounted && !_isDisposed) {
        setState(() {
          _store.clear();
          for (final reply in replies) {
            _store[reply.key] = _KvEntry(
              value: reply.payloadString,
              encoding: reply.encoding,
              metadata: reply.attachmentString,
              updatedAt: DateTime.now(),
            );
          }
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('GET kv/** -> ${replies.length} key(s)'),
              backgroundColor: Colors.blue,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GET ALL error: $e')),
        );
      }
    }
  }

  Future<void> _deleteKey() async {
    if (_session == null) return;

    final key = 'kv/${_keyController.text.trim()}';
    if (_keyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Key cannot be empty')),
      );
      return;
    }

    try {
      await _session!.delete(key);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('DELETE $key'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('DELETE error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Key-Value Store'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Fetch all keys',
            onPressed: _session != null ? _getAll : null,
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
                    // Input form
                    Expanded(
                      flex: 3,
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          // Watch toggle
                          Card(
                            color: _isWatching ? Colors.blue[50] : null,
                            child: ListTile(
                              leading: Icon(
                                _isWatching
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                color: _isWatching ? Colors.blue : Colors.grey,
                              ),
                              title: Text(_isWatching
                                  ? 'Watching kv/** (live updates)'
                                  : 'Not watching for changes'),
                              trailing: Switch(
                                value: _isWatching,
                                onChanged: (_) => _toggleWatch(),
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Key & Value
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TextField(
                                    controller: _keyController,
                                    decoration: const InputDecoration(
                                      labelText: 'Key (under kv/ namespace)',
                                      prefixText: 'kv/',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _valueController,
                                    maxLines: 2,
                                    decoration: const InputDecoration(
                                      labelText: 'Value',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: DropdownButtonFormField<
                                            ZenohEncoding>(
                                          value: _selectedEncoding,
                                          isExpanded: true,
                                          decoration: const InputDecoration(
                                            labelText: 'Encoding',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                          items: [
                                            ZenohEncoding.textPlain,
                                            ZenohEncoding.applicationJson,
                                            ZenohEncoding.string,
                                            ZenohEncoding.bytes,
                                          ]
                                              .map((e) => DropdownMenuItem(
                                                  value: e,
                                                  child: Text(e.mimeType,
                                                      style: const TextStyle(
                                                          fontSize: 12))))
                                              .toList(),
                                          onChanged: (v) {
                                            if (v != null) {
                                              setState(
                                                  () => _selectedEncoding = v);
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: DropdownButtonFormField<
                                            ZenohPriority>(
                                          value: _selectedPriority,
                                          isExpanded: true,
                                          decoration: const InputDecoration(
                                            labelText: 'Priority',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                          items: ZenohPriority.values
                                              .map((p) => DropdownMenuItem(
                                                  value: p,
                                                  child: Text(p.name,
                                                      style: const TextStyle(
                                                          fontSize: 12))))
                                              .toList(),
                                          onChanged: (v) {
                                            if (v != null) {
                                              setState(
                                                  () => _selectedPriority = v);
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Metadata
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Metadata (attachment)',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _authorController,
                                          decoration: const InputDecoration(
                                            labelText: 'Author',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: _versionController,
                                          decoration: const InputDecoration(
                                            labelText: 'Version',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Action buttons
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _putKey,
                                    icon: const Icon(Icons.upload, size: 18),
                                    label: const Text('PUT'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _getKey,
                                    icon: const Icon(Icons.download, size: 18),
                                    label: const Text('GET'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _deleteKey,
                                    icon: const Icon(Icons.delete, size: 18),
                                    label: const Text('DELETE'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // KV Table
                          if (_store.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.only(top: 8, bottom: 4),
                              child: Text('Stored Keys',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                            ),
                            ..._store.entries.map((entry) {
                              return Card(
                                child: ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.vpn_key,
                                      size: 18, color: Colors.blue),
                                  title: Text(entry.key,
                                      style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.value.value,
                                        style: const TextStyle(fontSize: 12),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Wrap(
                                        spacing: 4,
                                        children: [
                                          if (entry.value.encoding != null)
                                            _badge(
                                                entry.value.encoding!.mimeType,
                                                Colors.purple),
                                          if (entry.value.metadata != null)
                                            _badge('meta', Colors.teal),
                                          _badge(
                                              _formatTime(
                                                  entry.value.updatedAt),
                                              Colors.grey),
                                        ],
                                      ),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.content_copy,
                                        size: 16),
                                    onPressed: () {
                                      // Extract just the key part after kv/
                                      final shortKey =
                                          entry.key.startsWith('kv/')
                                              ? entry.key.substring(3)
                                              : entry.key;
                                      _keyController.text = shortKey;
                                      _valueController.text = entry.value.value;
                                    },
                                    tooltip: 'Copy to form',
                                  ),
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),

                    const Divider(height: 1),

                    // Change log
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: Row(
                        children: [
                          const Text('Change Log',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14)),
                          const Spacer(),
                          TextButton(
                            onPressed: () => setState(() => _changeLog.clear()),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: _changeLog.isEmpty
                          ? Center(
                              child: Text(
                                _isWatching
                                    ? 'Waiting for changes on kv/**...'
                                    : 'Enable watching to see live changes',
                                style: const TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              itemCount: _changeLog.length,
                              itemBuilder: (context, index) {
                                final event = _changeLog[index];
                                final isDelete =
                                    event.kind == ZenohSampleKind.delete;
                                return ListTile(
                                  dense: true,
                                  leading: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color:
                                          isDelete ? Colors.red : Colors.green,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isDelete ? 'DEL' : 'PUT',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  title: Text(event.key,
                                      style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 12)),
                                  subtitle: Text(
                                    isDelete
                                        ? 'Key deleted'
                                        : event.value ?? '',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.grey[600]),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Text(
                                    _formatTime(event.timestamp),
                                    style: TextStyle(
                                        fontSize: 10, color: Colors.grey[500]),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9, color: color, fontWeight: FontWeight.w600)),
    );
  }

  String _formatTime(DateTime dt) => '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _isDisposed = true;
    _keyController.dispose();
    _valueController.dispose();
    _authorController.dispose();
    _versionController.dispose();
    _disposeResources();
    super.dispose();
  }

  Future<void> _disposeResources() async {
    await _subscriber?.undeclare();
    await _session?.close();
  }
}

class _KvEntry {
  final String value;
  final ZenohEncoding? encoding;
  final String? metadata;
  final DateTime updatedAt;

  _KvEntry({
    required this.value,
    this.encoding,
    this.metadata,
    required this.updatedAt,
  });
}

class _ChangeEvent {
  final String key;
  final ZenohSampleKind kind;
  final String? value;
  final String? metadata;
  final DateTime timestamp;

  _ChangeEvent({
    required this.key,
    required this.kind,
    this.value,
    this.metadata,
    required this.timestamp,
  });
}
