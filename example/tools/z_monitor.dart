/// Zenoh Network Monitor - "tcpdump for zenoh"
///
/// Scouts the network, subscribes to key patterns, and prints all traffic
/// with full metadata (timestamp, encoding, priority, congestion, attachment).
///
/// Usage:
///   dart run example/tools/z_monitor.dart [options]
///
/// Options:
///   --subscribe KEY   Key expression to subscribe to (can repeat, default: **)
///   --endpoint URL    Zenoh router endpoint (default: tcp/localhost:7447)
///   --scout           Run network scouting before subscribing
///   --timeout SEC     Scout timeout in seconds (default: 3)
///   --verbose         Show extra details
///   --help            Show this help
///
/// Demonstrates:
///   - ZenohSession.scout() with filters
///   - ZenohConfigBuilder.custom() for timestamping
///   - ALL ZenohSample fields: timestamp, encoding, priority, congestion, attachment
///   - ZenohEncoding.fromMimeType()
library;

import 'dart:async';
import 'dart:io';

import 'package:zenoh_ffi/zenoh_ffi.dart';

Future<void> main(List<String> args) async {
  // Parse arguments
  final subscribeKeys = <String>[];
  String endpoint = 'tcp/localhost:7447';
  bool doScout = false;
  int scoutTimeout = 3;
  bool verbose = false;

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--subscribe':
      case '-s':
        if (i + 1 < args.length) subscribeKeys.add(args[++i]);
        break;
      case '--endpoint':
      case '-e':
        if (i + 1 < args.length) endpoint = args[++i];
        break;
      case '--scout':
        doScout = true;
        break;
      case '--timeout':
      case '-t':
        if (i + 1 < args.length) scoutTimeout = int.tryParse(args[++i]) ?? 3;
        break;
      case '--verbose':
      case '-v':
        verbose = true;
        break;
      case '--help':
      case '-h':
        _printUsage();
        return;
    }
  }

  if (subscribeKeys.isEmpty) subscribeKeys.add('**');

  print('');
  print('Zenoh Network Monitor');
  print('=' * 40);
  print('Endpoint: $endpoint');
  print('Subscribe: ${subscribeKeys.join(', ')}');
  print('');

  // Scouting phase
  if (doScout) {
    print('--- Scouting (${scoutTimeout}s) ---');
    int found = 0;
    final scoutTimer = Timer(Duration(seconds: scoutTimeout), () {});

    try {
      await for (final info in ZenohSession.scout(what: 'peer|router')) {
        found++;
        print('  [$found] $info');
        if (!scoutTimer.isActive) break;
      }
    } catch (e) {
      print('  Scout error: $e');
    }
    print('  Found $found node(s).');
    print('');
  }

  // Open session with custom config (enable timestamping)
  print('Opening session...');
  final config = ZenohConfigBuilder()
      .mode('client')
      .connect([endpoint])
      .custom('timestamping', {'enabled': true})
      .multicastScouting(false);

  ZenohSession session;
  try {
    session = await ZenohSession.openWithConfig(config);
  } catch (e) {
    print('ERROR: Failed to open session: $e');
    print('Make sure zenohd is running: zenohd -l tcp/0.0.0.0:7447');
    exit(1);
  }

  print('Session opened: ${session.sessionId}');
  print('');

  // Subscribe to all patterns
  print('--- Subscribing to: ${subscribeKeys.join(', ')} ---');
  print('');

  int totalPut = 0;
  int totalDelete = 0;
  int totalBytes = 0;

  for (final pattern in subscribeKeys) {
    try {
      final sub = await session.declareSubscriber(pattern);
      sub.stream.listen((sample) {
        final now = DateTime.now();
        final ts = '${now.hour.toString().padLeft(2, '0')}:'
            '${now.minute.toString().padLeft(2, '0')}:'
            '${now.second.toString().padLeft(2, '0')}.'
            '${now.millisecond.toString().padLeft(3, '0')}';

        final kindStr = sample.kind == ZenohSampleKind.delete ? 'DELETE' : 'PUT';
        final isDelete = sample.kind == ZenohSampleKind.delete;

        if (isDelete) {
          totalDelete++;
        } else {
          totalPut++;
        }
        totalBytes += sample.payload.length;

        print('[$ts] $kindStr  ${sample.key}');
        print('  Payload (${sample.payload.length} bytes): '
            '${_truncate(sample.payloadString, 80)}');

        // Encoding with fromMimeType
        if (sample.encoding != null) {
          final resolved = ZenohEncoding.fromMimeType(sample.encoding!.mimeType);
          print('  Encoding: ${sample.encoding!.mimeType} (resolved: ${resolved.name})');
        }

        // Priority & Congestion
        if (sample.priority != null || sample.congestionControl != null) {
          final parts = <String>[];
          if (sample.priority != null) parts.add('Priority: ${sample.priority!.name}');
          if (sample.congestionControl != null) parts.add('Congestion: ${sample.congestionControl!.name}');
          print('  ${parts.join(' | ')}');
        }

        // Timestamp from ZenohSample.timestamp
        if (sample.timestamp != null) {
          print('  Timestamp: ${sample.timestamp!.toIso8601String()}');
        }

        // Attachment
        if (sample.attachment != null) {
          print('  Attachment: ${_truncate(sample.attachmentString ?? '', 80)}');
        }

        if (verbose) {
          print('  --- Stats: $totalPut PUT, $totalDelete DEL, '
              '${(totalBytes / 1024).toStringAsFixed(1)} KB total ---');
        }

        print('');
      });
      print('  Subscribed to: $pattern');
    } catch (e) {
      print('  ERROR subscribing to $pattern: $e');
    }
  }

  print('');
  print('Monitoring active. Press Ctrl+C to stop.');
  print('');

  // Wait for Ctrl+C
  await ProcessSignal.sigint.watch().first;

  print('');
  print('--- Final Stats ---');
  print('  Messages: $totalPut PUT, $totalDelete DELETE');
  print('  Total data: ${(totalBytes / 1024).toStringAsFixed(1)} KB');
  print('');

  await session.close();
  print('Session closed.');
}

String _truncate(String s, int maxLen) {
  if (s.length <= maxLen) return s;
  return '${s.substring(0, maxLen)}...';
}

void _printUsage() {
  print('''
Zenoh Network Monitor - "tcpdump for zenoh"

Usage:
  dart run example/tools/z_monitor.dart [options]

Options:
  --subscribe KEY   Key expression to subscribe (repeatable, default: **)
  --endpoint URL    Zenoh router endpoint (default: tcp/localhost:7447)
  --scout           Run network scouting before subscribing
  --timeout SEC     Scout timeout in seconds (default: 3)
  --verbose         Show running statistics
  --help            Show this help

Examples:
  dart run example/tools/z_monitor.dart --scout --subscribe "sensor/**"
  dart run example/tools/z_monitor.dart -s "demo/**" -s "home/**" -v
  dart run example/tools/z_monitor.dart -e tcp/192.168.1.10:7447
''');
}
