import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:zenoh_ffi/zenoh_ffi.dart';

/// Binary Data Transfer
///
/// Demonstrates:
/// - Binary encoding types: imagePng, imageJpeg, applicationCbor, applicationOctetStream
/// - ZenohEncoding.fromMimeType() for resolving received encodings
/// - ZenohQuery.reply() with raw Uint8List bytes
/// - ZenohPutOptions with ALL fields combined
/// - ZenohSample.timestamp display
class ImageTransferPage extends StatefulWidget {
  const ImageTransferPage({super.key});

  @override
  State<ImageTransferPage> createState() => _ImageTransferPageState();
}

class _ImageTransferPageState extends State<ImageTransferPage> {
  ZenohSession? _session;
  bool _isDisposed = false;
  bool _isInitializing = true;
  String? _errorMessage;

  // Subscriber
  ZenohSubscriber? _subscriber;

  // File server queryable
  ZenohQueryable? _fileQueryable;
  bool _fileServerRunning = false;
  final Map<String, Uint8List> _servedFiles = {};

  // Send config
  ZenohEncoding _selectedEncoding = ZenohEncoding.imagePng;
  double _dataSize = 256;
  ZenohPriority _sendPriority = ZenohPriority.dataHigh;
  ZenohCongestionControl _sendCongestion = ZenohCongestionControl.block;
  bool _sendExpress = false;
  final TextEditingController _filenameController =
      TextEditingController(text: 'data-001.bin');

  // Received
  final List<_ReceivedBinary> _received = [];

  // File server query results
  final List<_QueryResult> _queryResults = [];

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
        endpoints: [
          'tcp/localhost:7447',
          'tcp/127.0.0.1:7447',
        ],
      );

      // Subscribe to media/**
      _subscriber = await _session!.declareSubscriber('media/**');
      _subscriber!.stream.listen((sample) {
        if (mounted && !_isDisposed) {
          // Use fromMimeType to resolve encoding
          final resolvedEncoding = sample.encoding != null
              ? ZenohEncoding.fromMimeType(sample.encoding!.mimeType)
              : ZenohEncoding.bytes;

          setState(() {
            _received.insert(
              0,
              _ReceivedBinary(
                key: sample.key,
                payload: sample.payload,
                encoding: resolvedEncoding,
                mimeType: sample.encoding?.mimeType ?? 'unknown',
                priority: sample.priority,
                congestion: sample.congestionControl,
                attachment: sample.attachmentString,
                timestamp: sample.timestamp,
                kind: sample.kind,
                receivedAt: DateTime.now(),
              ),
            );
            if (_received.length > 50) _received.removeLast();
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

  Uint8List _generateBinaryData(int size, ZenohEncoding encoding) {
    final rng = Random();
    if (encoding == ZenohEncoding.imagePng) {
      // Minimal 1x1 PNG header + random IDAT
      final header = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
      ];
      final rest = List.generate(
          max(0, size - header.length), (_) => rng.nextInt(256));
      return Uint8List.fromList([...header, ...rest]);
    } else if (encoding == ZenohEncoding.imageJpeg) {
      // JPEG SOI marker + random data
      final header = [0xFF, 0xD8, 0xFF, 0xE0];
      final rest = List.generate(
          max(0, size - header.length), (_) => rng.nextInt(256));
      return Uint8List.fromList([...header, ...rest]);
    } else if (encoding == ZenohEncoding.applicationCbor) {
      // CBOR map header (0xBF = indefinite-length map) + random
      final header = [0xBF];
      final rest = List.generate(
          max(0, size - header.length), (_) => rng.nextInt(256));
      return Uint8List.fromList([...header, ...rest]);
    }
    return Uint8List.fromList(List.generate(size, (_) => rng.nextInt(256)));
  }

  Future<void> _publishBinary() async {
    if (_session == null) return;
    try {
      final data = _generateBinaryData(_dataSize.toInt(), _selectedEncoding);
      final metadata = {
        'filename': _filenameController.text,
        'size': data.length,
        'encoding': _selectedEncoding.mimeType,
        'ts': DateTime.now().toIso8601String(),
      };

      // ZenohPutOptions with ALL fields combined
      await _session!.put(
        'media/binary/${_filenameController.text}',
        data,
        options: ZenohPutOptions(
          priority: _sendPriority,
          congestionControl: _sendCongestion,
          encoding: _selectedEncoding,
          attachment: Uint8List.fromList(utf8.encode(jsonEncode(metadata))),
          express: _sendExpress,
        ),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Sent ${data.length} bytes as ${_selectedEncoding.mimeType}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Send error: $e')));
      }
    }
  }

  Future<void> _toggleFileServer() async {
    if (_fileServerRunning) {
      await _fileQueryable?.undeclare();
      _fileQueryable = null;
      if (mounted && !_isDisposed) {
        setState(() => _fileServerRunning = false);
      }
      return;
    }

    try {
      // Pre-populate some served files
      _servedFiles['hello.txt'] =
          Uint8List.fromList(utf8.encode('Hello from Zenoh file server!'));
      _servedFiles['image.png'] =
          _generateBinaryData(512, ZenohEncoding.imagePng);
      _servedFiles['data.cbor'] =
          _generateBinaryData(256, ZenohEncoding.applicationCbor);

      // Queryable replying with raw bytes via query.reply()
      _fileQueryable =
          await _session!.declareQueryable('media/files/**', (query) {
        final parts = query.selector.split('/');
        final filename = parts.isNotEmpty ? parts.last : '';

        if (filename == '**' || filename == '*') {
          // List all files
          for (final entry in _servedFiles.entries) {
            final ext = entry.key.split('.').last;
            final encoding = ext == 'png'
                ? ZenohEncoding.imagePng
                : ext == 'cbor'
                    ? ZenohEncoding.applicationCbor
                    : ZenohEncoding.applicationOctetStream;
            query.reply(
              'media/files/${entry.key}',
              entry.value,
              encoding: encoding,
              attachment: Uint8List.fromList(
                  utf8.encode('size=${entry.value.length}')),
            );
          }
        } else if (_servedFiles.containsKey(filename)) {
          query.reply(
            'media/files/$filename',
            _servedFiles[filename]!,
            encoding: ZenohEncoding.applicationOctetStream,
            attachment: Uint8List.fromList(
                utf8.encode('size=${_servedFiles[filename]!.length}')),
          );
        }
      });

      if (mounted && !_isDisposed) {
        setState(() => _fileServerRunning = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('File server error: $e')));
      }
    }
  }

  Future<void> _queryFiles(String pattern) async {
    if (_session == null) return;
    try {
      setState(() => _queryResults.clear());

      // Using session.get() raw stream
      await for (final reply
          in _session!.get('media/files/$pattern')) {
        if (mounted && !_isDisposed) {
          setState(() {
            _queryResults.add(_QueryResult(
              key: reply.key,
              size: reply.payload.length,
              encoding: reply.encoding?.mimeType ?? 'unknown',
              attachment: reply.attachmentString,
            ));
          });
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Query returned ${_queryResults.length} file(s)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Query error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Binary Transfer'),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.upload), text: 'Send'),
            Tab(icon: Icon(Icons.download), text: 'Receive'),
            Tab(icon: Icon(Icons.dns), text: 'File Server'),
          ]),
        ),
        body: _isInitializing
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? _buildErrorWidget()
                : TabBarView(children: [
                    _buildSendTab(),
                    _buildReceiveTab(),
                    _buildFileServerTab(),
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

  Widget _buildSendTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Binary Encoding',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<ZenohEncoding>(
                    value: _selectedEncoding,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        border: OutlineInputBorder(), isDense: true),
                    items: [
                      ZenohEncoding.imagePng,
                      ZenohEncoding.imageJpeg,
                      ZenohEncoding.applicationCbor,
                      ZenohEncoding.applicationOctetStream,
                      ZenohEncoding.applicationProtobuf,
                    ]
                        .map((e) => DropdownMenuItem(
                            value: e,
                            child: Text(e.mimeType,
                                style: const TextStyle(fontSize: 13))))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedEncoding = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    const Text('Data size: '),
                    Expanded(
                      child: Slider(
                        value: _dataSize,
                        min: 16,
                        max: 4096,
                        divisions: 100,
                        label: '${_dataSize.toInt()} bytes',
                        onChanged: (v) => setState(() => _dataSize = v),
                      ),
                    ),
                    Text('${_dataSize.toInt()} B'),
                  ]),
                  TextField(
                    controller: _filenameController,
                    decoration: const InputDecoration(
                      labelText: 'Filename (attachment metadata)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
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
                  const Text('QoS Options (ALL fields)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<ZenohPriority>(
                        value: _sendPriority,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Priority',
                            border: OutlineInputBorder(),
                            isDense: true),
                        items: ZenohPriority.values
                            .map((p) => DropdownMenuItem(
                                value: p,
                                child: Text(p.name,
                                    style: const TextStyle(fontSize: 12))))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _sendPriority = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<ZenohCongestionControl>(
                        value: _sendCongestion,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Congestion',
                            border: OutlineInputBorder(),
                            isDense: true),
                        items: ZenohCongestionControl.values
                            .map((c) => DropdownMenuItem(
                                value: c,
                                child: Text(c.name,
                                    style: const TextStyle(fontSize: 12))))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _sendCongestion = v);
                        },
                      ),
                    ),
                  ]),
                  SwitchListTile(
                    title: const Text('Express Mode', style: TextStyle(fontSize: 13)),
                    value: _sendExpress,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => setState(() => _sendExpress = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _publishBinary,
            icon: const Icon(Icons.send),
            label: const Text('Publish Binary Data'),
            style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiveTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            const Text('Received on media/**',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('${_received.length} items',
                style: TextStyle(color: Colors.grey[600])),
            TextButton(
                onPressed: () => setState(() => _received.clear()),
                child: const Text('Clear')),
          ]),
        ),
        Expanded(
          child: _received.isEmpty
              ? const Center(
                  child: Text('Waiting for binary data on media/**...',
                      style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: _received.length,
                  itemBuilder: (context, index) {
                    final item = _received[index];
                    final isDelete = item.kind == ZenohSampleKind.delete;
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      child: ExpansionTile(
                        leading: Icon(
                          _encodingIcon(item.encoding),
                          color: isDelete ? Colors.red : Colors.deepPurple,
                        ),
                        title: Text(item.key,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: Wrap(spacing: 4, children: [
                          _badge(item.mimeType, Colors.purple),
                          _badge('${item.payload.length} B', Colors.blue),
                          if (item.priority != null)
                            _badge(item.priority!.name, Colors.orange),
                          if (item.timestamp != null)
                            _badge(
                                _formatDateTime(item.timestamp!), Colors.teal),
                        ]),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Hex Preview (first 64 bytes):',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12)),
                                const SizedBox(height: 4),
                                SelectableText(
                                  _hexDump(item.payload, 64),
                                  style: const TextStyle(
                                      fontFamily: 'monospace', fontSize: 11),
                                ),
                                if (item.attachment != null) ...[
                                  const SizedBox(height: 8),
                                  Text('Attachment: ${item.attachment}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600])),
                                ],
                                if (item.timestamp != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                      'Timestamp: ${item.timestamp!.toIso8601String()}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600])),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFileServerTab() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: _fileServerRunning ? Colors.green[50] : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Icon(
                  _fileServerRunning ? Icons.cloud_done : Icons.cloud_off,
                  size: 40,
                  color: _fileServerRunning ? Colors.green : Colors.grey,
                ),
                const SizedBox(height: 8),
                Text(
                  _fileServerRunning
                      ? 'File Server Active (media/files/**)'
                      : 'File Server Stopped',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _fileServerRunning ? Colors.green : Colors.grey),
                ),
                Text(
                  'Serves files via query.reply() with raw bytes',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _toggleFileServer,
                  icon: Icon(
                      _fileServerRunning ? Icons.stop : Icons.play_arrow),
                  label: Text(_fileServerRunning ? 'Stop' : 'Start'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _fileServerRunning ? Colors.red : Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ]),
            ),
          ),
          if (_fileServerRunning) ...[
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Served Files',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    ..._servedFiles.entries.map((e) => ListTile(
                          dense: true,
                          leading:
                              const Icon(Icons.insert_drive_file, size: 18),
                          title: Text(e.key),
                          trailing: Text('${e.value.length} B'),
                        )),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _queryFiles('**'),
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Query All Files'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _queryFiles('hello.txt'),
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Query hello.txt'),
                ),
              ),
            ]),
          ],
          if (_queryResults.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Query Results (via session.get stream)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            ..._queryResults.map((r) => Card(
                  child: ListTile(
                    dense: true,
                    title: Text(r.key, style: const TextStyle(fontSize: 13)),
                    subtitle: Text('${r.size} B | ${r.encoding}'),
                    trailing: r.attachment != null
                        ? Text(r.attachment!,
                            style: const TextStyle(fontSize: 10))
                        : null,
                  ),
                )),
          ],
        ],
      ),
    );
  }

  IconData _encodingIcon(ZenohEncoding encoding) {
    if (encoding == ZenohEncoding.imagePng ||
        encoding == ZenohEncoding.imageJpeg) return Icons.image;
    if (encoding == ZenohEncoding.applicationCbor) return Icons.data_object;
    if (encoding == ZenohEncoding.applicationProtobuf) return Icons.schema;
    return Icons.description;
  }

  Widget _badge(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9, color: color, fontWeight: FontWeight.w600)),
    );
  }

  String _hexDump(Uint8List data, int maxBytes) {
    final len = min(data.length, maxBytes);
    final sb = StringBuffer();
    for (int i = 0; i < len; i++) {
      sb.write(data[i].toRadixString(16).padLeft(2, '0'));
      if (i % 16 == 15) {
        sb.writeln();
      } else {
        sb.write(' ');
      }
    }
    if (data.length > maxBytes) sb.write('...');
    return sb.toString().trim();
  }

  String _formatDateTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}.'
      '${dt.millisecond.toString().padLeft(3, '0')}';

  @override
  void dispose() {
    _isDisposed = true;
    _filenameController.dispose();
    _subscriber?.undeclare();
    _fileQueryable?.undeclare();
    _session?.close();
    super.dispose();
  }
}

class _ReceivedBinary {
  final String key;
  final Uint8List payload;
  final ZenohEncoding encoding;
  final String mimeType;
  final ZenohPriority? priority;
  final ZenohCongestionControl? congestion;
  final String? attachment;
  final DateTime? timestamp;
  final ZenohSampleKind kind;
  final DateTime receivedAt;

  _ReceivedBinary({
    required this.key, required this.payload, required this.encoding,
    required this.mimeType, this.priority, this.congestion, this.attachment,
    this.timestamp, required this.kind, required this.receivedAt,
  });
}

class _QueryResult {
  final String key;
  final int size;
  final String encoding;
  final String? attachment;

  _QueryResult({
    required this.key, required this.size,
    required this.encoding, this.attachment,
  });
}
