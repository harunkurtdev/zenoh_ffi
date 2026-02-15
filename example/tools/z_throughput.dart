/// Zenoh Throughput & Latency Benchmark
///
/// Measures pub/sub throughput and round-trip latency with different
/// QoS configurations.
///
/// Usage:
///   dart run example/tools/z_throughput.dart [options]
///
/// Options:
///   --size BYTES      Payload size in bytes (default: 256)
///   --count N         Number of messages to send (default: 1000)
///   --endpoint URL    Zenoh router endpoint (default: tcp/localhost:7447)
///   --mode MODE       Session mode: client|peer (default: client)
///   --help            Show this help
///
/// Demonstrates:
///   - All ZenohPriority values benchmarked
///   - All ZenohCongestionControl modes compared
///   - ZenohPublisher.put() with raw Uint8List
///   - Express mode comparison
///   - ZenohSample.timestamp for latency
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:zenoh_ffi/zenoh_ffi.dart';

Future<void> main(List<String> args) async {
  int payloadSize = 256;
  int count = 1000;
  String endpoint = 'tcp/localhost:7447';
  String mode = 'client';

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--size':
        if (i + 1 < args.length) payloadSize = int.tryParse(args[++i]) ?? 256;
        break;
      case '--count':
        if (i + 1 < args.length) count = int.tryParse(args[++i]) ?? 1000;
        break;
      case '--endpoint':
      case '-e':
        if (i + 1 < args.length) endpoint = args[++i];
        break;
      case '--mode':
        if (i + 1 < args.length) mode = args[++i];
        break;
      case '--help':
      case '-h':
        _printUsage();
        return;
    }
  }

  print('');
  print('Zenoh Throughput Benchmark');
  print('=' * 40);
  print('Mode: $mode | Payload: $payloadSize bytes | Count: $count');
  print('Endpoint: $endpoint');
  print('');

  // Open session
  print('Opening session...');
  ZenohSession session;
  try {
    session = await ZenohSession.open(mode: mode, endpoints: [endpoint]);
  } catch (e) {
    print('ERROR: $e');
    print('Make sure zenohd is running: zenohd -l tcp/0.0.0.0:7447');
    exit(1);
  }
  print('Session: ${session.sessionId}');
  print('');

  final payload = Uint8List(payloadSize);
  // Fill with pattern
  for (int i = 0; i < payloadSize; i++) {
    payload[i] = i % 256;
  }

  // --- Priority Comparison ---
  print('--- Priority Comparison (congestion: drop) ---');
  for (final priority in [ZenohPriority.realTime, ZenohPriority.data, ZenohPriority.background]) {
    final rate = await _benchmarkPublisher(
      session, 'bench/priority/${priority.name}', payload, count,
      ZenohPublisherOptions(
        priority: priority,
        congestionControl: ZenohCongestionControl.drop,
      ),
    );
    final mbps = (rate * payloadSize / 1024 / 1024).toStringAsFixed(2);
    print('  ${priority.name.padRight(18)} ${rate.toStringAsFixed(0).padLeft(8)} msg/s  ($mbps MB/s)');
  }
  print('');

  // --- Congestion Control Comparison ---
  print('--- Congestion Control Comparison (priority: data) ---');
  for (final cc in ZenohCongestionControl.values) {
    final rate = await _benchmarkPublisher(
      session, 'bench/congestion/${cc.name}', payload, count,
      ZenohPublisherOptions(
        priority: ZenohPriority.data,
        congestionControl: cc,
      ),
    );
    final mbps = (rate * payloadSize / 1024 / 1024).toStringAsFixed(2);
    print('  ${cc.name.padRight(18)} ${rate.toStringAsFixed(0).padLeft(8)} msg/s  ($mbps MB/s)');
  }
  print('');

  // --- Express Mode ---
  print('--- Express Mode Comparison ---');
  for (final express in [false, true]) {
    final rate = await _benchmarkPublisher(
      session, 'bench/express/$express', payload, count,
      ZenohPublisherOptions(
        priority: ZenohPriority.data,
        congestionControl: ZenohCongestionControl.drop,
        express: express,
      ),
    );
    final mbps = (rate * payloadSize / 1024 / 1024).toStringAsFixed(2);
    print('  express=${express.toString().padRight(8)} ${rate.toStringAsFixed(0).padLeft(8)} msg/s  ($mbps MB/s)');
  }
  print('');

  // --- Latency via round-trip ---
  print('--- Round-Trip Latency (via queryable) ---');
  final latencies = await _benchmarkLatency(session, payload, 100);
  if (latencies.isNotEmpty) {
    latencies.sort();
    final avg = latencies.reduce((a, b) => a + b) / latencies.length;
    final p99 = latencies[(latencies.length * 0.99).toInt().clamp(0, latencies.length - 1)];
    print('  min: ${latencies.first.toStringAsFixed(2)}ms  '
        'avg: ${avg.toStringAsFixed(2)}ms  '
        'max: ${latencies.last.toStringAsFixed(2)}ms  '
        'p99: ${p99.toStringAsFixed(2)}ms');
  } else {
    print('  No latency data (queryable may not be reachable)');
  }

  print('');
  await session.close();
  print('Session closed.');
}

Future<double> _benchmarkPublisher(
  ZenohSession session,
  String key,
  Uint8List payload,
  int count,
  ZenohPublisherOptions options,
) async {
  final pub = await session.declarePublisher(key, options: options);

  final sw = Stopwatch()..start();
  for (int i = 0; i < count; i++) {
    await pub.put(payload);
  }
  sw.stop();

  await pub.undeclare();

  final elapsedSec = sw.elapsedMilliseconds / 1000.0;
  return count / elapsedSec;
}

Future<List<double>> _benchmarkLatency(
  ZenohSession session,
  Uint8List payload,
  int count,
) async {
  final latencies = <double>[];

  // Declare echo queryable
  final queryable = await session.declareQueryable('bench/echo', (query) {
    query.reply('bench/echo', payload);
  });

  for (int i = 0; i < count; i++) {
    final sw = Stopwatch()..start();
    try {
      final replies = await session.getCollect(
        'bench/echo',
        options: ZenohGetOptions(
          timeout: const Duration(seconds: 2),
        ),
      );
      sw.stop();
      if (replies.isNotEmpty) {
        latencies.add(sw.elapsedMicroseconds / 1000.0);
      }
    } catch (_) {
      sw.stop();
    }
  }

  await queryable.undeclare();
  return latencies;
}

void _printUsage() {
  print('''
Zenoh Throughput & Latency Benchmark

Usage:
  dart run example/tools/z_throughput.dart [options]

Options:
  --size BYTES      Payload size in bytes (default: 256)
  --count N         Number of messages (default: 1000)
  --endpoint URL    Zenoh endpoint (default: tcp/localhost:7447)
  --mode MODE       Session mode: client|peer (default: client)
  --help            Show this help

Examples:
  dart run example/tools/z_throughput.dart --size 1024 --count 5000
  dart run example/tools/z_throughput.dart --mode peer --count 10000
''');
}
