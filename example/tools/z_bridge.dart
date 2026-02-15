/// Zenoh Protocol Bridge / Relay
///
/// Relays messages between zenoh networks or namespaces by subscribing
/// on a source key pattern and republishing on a target prefix.
///
/// Usage:
///   dart run example/tools/z_bridge.dart [options]
///
/// Options:
///   --source-key KEY      Source key pattern to subscribe (default: source/**)
///   --target-prefix KEY   Target prefix to republish under (default: target)
///   --source-endpoint URL Source zenoh endpoint (default: tcp/localhost:7447)
///   --target-endpoint URL Target zenoh endpoint (same session if omitted)
///   --mode MODE           Session mode: client|peer (default: client)
///   --listen URL          Listen endpoint for peer/router mode
///   --retry N             Max retry attempts for reconnection (default: 3)
///   --help                Show this help
///
/// Demonstrates:
///   - ZenohConfigBuilder.listen() - listen endpoints
///   - ZenohConfigBuilder.custom() - arbitrary config keys
///   - Two sessions for cross-network relay
///   - ZenohRetry.executeStream() - resilient operations
///   - ZenohEncoding.fromMimeType() - encoding preservation
///   - ZenohPublisher.delete() - tombstone forwarding
///   - ZenohSampleKind.delete handling
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:zenoh_ffi/zenoh_ffi.dart';

Future<void> main(List<String> args) async {
  String sourceKey = 'source/**';
  String targetPrefix = 'target';
  String sourceEndpoint = 'tcp/localhost:7447';
  String? targetEndpoint;
  String mode = 'client';
  String? listenEndpoint;
  int maxRetry = 3;

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--source-key':
      case '-s':
        if (i + 1 < args.length) sourceKey = args[++i];
        break;
      case '--target-prefix':
      case '-t':
        if (i + 1 < args.length) targetPrefix = args[++i];
        break;
      case '--source-endpoint':
        if (i + 1 < args.length) sourceEndpoint = args[++i];
        break;
      case '--target-endpoint':
        if (i + 1 < args.length) targetEndpoint = args[++i];
        break;
      case '--mode':
      case '-m':
        if (i + 1 < args.length) mode = args[++i];
        break;
      case '--listen':
      case '-l':
        if (i + 1 < args.length) listenEndpoint = args[++i];
        break;
      case '--retry':
      case '-r':
        if (i + 1 < args.length) maxRetry = int.tryParse(args[++i]) ?? 3;
        break;
      case '--help':
      case '-h':
        _printUsage();
        return;
    }
  }

  print('');
  print('Zenoh Protocol Bridge');
  print('=' * 50);
  print('Mode:            $mode');
  print('Source key:      $sourceKey');
  print('Target prefix:   $targetPrefix');
  print('Source endpoint: $sourceEndpoint');
  print('Target endpoint: ${targetEndpoint ?? "(same session)"}');
  if (listenEndpoint != null) print('Listen endpoint: $listenEndpoint');
  print('Max retries:     $maxRetry');
  print('');

  // --- Open source session ---
  print('Opening source session...');
  final sourceConfig = ZenohConfigBuilder()
      .mode(mode)
      .connect([sourceEndpoint])
      .custom('timestamping', {'enabled': true})
      .multicastScouting(false);

  if (listenEndpoint != null) {
    sourceConfig.listen([listenEndpoint]);
  }

  ZenohSession sourceSession;
  try {
    sourceSession = await ZenohSession.openWithConfig(sourceConfig);
  } catch (e) {
    print('ERROR: Failed to open source session: $e');
    print('Make sure zenohd is running: zenohd -l tcp/0.0.0.0:7447');
    exit(1);
  }
  print('Source session: ${sourceSession.sessionId}');

  // --- Open target session (or reuse source) ---
  ZenohSession targetSession;
  bool separateSessions = false;

  if (targetEndpoint != null && targetEndpoint != sourceEndpoint) {
    print('Opening target session...');
    separateSessions = true;
    final targetConfig = ZenohConfigBuilder()
        .mode(mode)
        .connect([targetEndpoint])
        .custom('timestamping', {'enabled': true})
        .multicastScouting(false);

    try {
      targetSession = await ZenohSession.openWithConfig(targetConfig);
    } catch (e) {
      print('ERROR: Failed to open target session: $e');
      await sourceSession.close();
      exit(1);
    }
    print('Target session: ${targetSession.sessionId}');
  } else {
    targetSession = sourceSession;
    print('Using same session for source and target.');
  }
  print('');

  // --- Bridge statistics ---
  int totalRelayed = 0;
  int totalDeletes = 0;
  int totalBytes = 0;
  int totalErrors = 0;
  final startTime = DateTime.now();

  // --- Retry wrapper ---
  final retry = ZenohRetry(
    maxAttempts: maxRetry,
    initialDelay: const Duration(milliseconds: 200),
    backoffMultiplier: 2.0,
    maxDelay: const Duration(seconds: 5),
  );

  // --- Declare target publishers (lazily cached) ---
  final publisherCache = <String, ZenohPublisher>{};

  Future<ZenohPublisher> getOrCreatePublisher(String targetKey, ZenohEncoding? encoding) async {
    if (publisherCache.containsKey(targetKey)) {
      return publisherCache[targetKey]!;
    }

    final pub = await retry.execute(() async {
      return targetSession.declarePublisher(
        targetKey,
        options: ZenohPublisherOptions(
          priority: ZenohPriority.data,
          congestionControl: ZenohCongestionControl.drop,
          encoding: encoding ?? ZenohEncoding.bytes,
        ),
      );
    });
    publisherCache[targetKey] = pub;
    return pub;
  }

  // --- Subscribe and relay ---
  print('--- Starting bridge: $sourceKey -> $targetPrefix/... ---');
  print('');

  ZenohSubscriber? subscriber;

  try {
    // Use retry for the subscription itself
    subscriber = await retry.execute(() async {
      return sourceSession.declareSubscriber(sourceKey);
    });

    print('Subscribed to: $sourceKey');
    print('Bridge active. Press Ctrl+C to stop.');
    print('');

    await for (final sample in subscriber!.stream) {
      // Compute target key by replacing source prefix
      final relativeKey = _extractRelativeKey(sample.key, sourceKey);
      final targetKey = relativeKey.isNotEmpty
          ? '$targetPrefix/$relativeKey'
          : targetPrefix;

      final isDelete = sample.kind == ZenohSampleKind.delete;
      final ts = _formatTimestamp(DateTime.now());

      try {
        if (isDelete) {
          // Forward tombstone using ZenohPublisher.delete()
          final pub = await getOrCreatePublisher(targetKey, null);
          await pub.delete();
          totalDeletes++;

          print('[$ts] DELETE  ${sample.key} -> $targetKey');
        } else {
          // Forward PUT with encoding preservation
          ZenohEncoding resolvedEncoding = ZenohEncoding.bytes;
          if (sample.encoding != null) {
            resolvedEncoding = ZenohEncoding.fromMimeType(sample.encoding!.mimeType);
          }

          final pub = await getOrCreatePublisher(targetKey, resolvedEncoding);

          // Build put options preserving QoS and metadata
          final putOptions = ZenohPutOptions(
            priority: sample.priority ?? ZenohPriority.data,
            congestionControl: sample.congestionControl ?? ZenohCongestionControl.drop,
            encoding: resolvedEncoding,
            attachment: sample.attachment,
            express: false,
          );

          await pub.put(sample.payload, options: putOptions);
          totalRelayed++;
          totalBytes += sample.payload.length;

          // Log relay event
          final sizeStr = _formatBytes(sample.payload.length);
          final encStr = resolvedEncoding.mimeType;
          print('[$ts] PUT     ${sample.key} -> $targetKey  ($sizeStr, $encStr)');

          // Show timestamp from sample if available
          if (sample.timestamp != null) {
            print('         source timestamp: ${sample.timestamp!.toIso8601String()}');
          }

          // Show attachment if present
          if (sample.attachment != null) {
            final attStr = utf8.decode(sample.attachment!, allowMalformed: true);
            print('         attachment: ${_truncate(attStr, 60)}');
          }
        }
      } catch (e) {
        totalErrors++;
        print('[$ts] ERROR   ${sample.key} -> $targetKey: $e');
      }
    }
  } on ZenohException catch (e) {
    print('Bridge error: $e');
  }

  // Ctrl+C handler
  ProcessSignal.sigint.watch().listen((_) async {
    print('');
    print('--- Bridge Statistics ---');
    final elapsed = DateTime.now().difference(startTime);
    print('  Uptime:   ${elapsed.inMinutes}m ${elapsed.inSeconds % 60}s');
    print('  Relayed:  $totalRelayed PUT, $totalDeletes DELETE');
    print('  Data:     ${_formatBytes(totalBytes)}');
    print('  Errors:   $totalErrors');
    if (totalRelayed > 0 && elapsed.inSeconds > 0) {
      final rate = totalRelayed / elapsed.inSeconds;
      print('  Rate:     ${rate.toStringAsFixed(1)} msg/s');
    }
    print('');

    // Cleanup publishers
    for (final pub in publisherCache.values) {
      try {
        await pub.undeclare();
      } catch (_) {}
    }

    // Close subscriber
    try {
      await subscriber?.undeclare();
    } catch (_) {}

    // Close sessions
    await sourceSession.close();
    if (separateSessions) {
      await targetSession.close();
    }
    print('Sessions closed.');
    exit(0);
  });

  // Keep alive
  await Completer<void>().future;
}

/// Extract the relative key portion after the wildcard prefix.
/// e.g. sourceKey='factory/**', sampleKey='factory/line1/temp' -> 'line1/temp'
String _extractRelativeKey(String sampleKey, String sourcePattern) {
  // Remove wildcard suffixes from pattern
  String prefix = sourcePattern
      .replaceAll('/**', '')
      .replaceAll('/*', '')
      .replaceAll('**', '')
      .replaceAll('*', '');

  // Remove trailing slash
  if (prefix.endsWith('/')) prefix = prefix.substring(0, prefix.length - 1);

  if (prefix.isEmpty) return sampleKey;

  if (sampleKey.startsWith('$prefix/')) {
    return sampleKey.substring(prefix.length + 1);
  }
  if (sampleKey == prefix) return '';

  return sampleKey;
}

String _formatTimestamp(DateTime dt) {
  return '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}.'
      '${dt.millisecond.toString().padLeft(3, '0')}';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
}

String _truncate(String s, int maxLen) {
  if (s.length <= maxLen) return s;
  return '${s.substring(0, maxLen)}...';
}

void _printUsage() {
  print('''
Zenoh Protocol Bridge / Relay

Relays messages between zenoh networks or namespaces.
Subscribes on a source key pattern and republishes under a target prefix.

Usage:
  dart run example/tools/z_bridge.dart [options]

Options:
  --source-key KEY      Source key pattern to subscribe (default: source/**)
  --target-prefix KEY   Target prefix to republish under (default: target)
  --source-endpoint URL Source zenoh endpoint (default: tcp/localhost:7447)
  --target-endpoint URL Target zenoh endpoint (same session if omitted)
  --mode MODE           Session mode: client|peer (default: client)
  --listen URL          Listen endpoint for peer/router mode
  --retry N             Max retry attempts (default: 3)
  --help                Show this help

Examples:
  # Bridge factory data to cloud namespace
  dart run example/tools/z_bridge.dart \\
    --source-key "factory/**" --target-prefix "cloud/factory"

  # Cross-network relay between two routers
  dart run example/tools/z_bridge.dart \\
    --source-endpoint tcp/192.168.1.10:7447 \\
    --target-endpoint tcp/10.0.0.1:7447 \\
    --source-key "sensor/**" --target-prefix "remote/sensor"

  # Peer mode with listen endpoint
  dart run example/tools/z_bridge.dart \\
    --mode peer --listen tcp/0.0.0.0:7448 \\
    --source-key "home/**" --target-prefix "aggregated/home"

Features:
  - Encoding preservation via ZenohEncoding.fromMimeType()
  - Tombstone forwarding via ZenohPublisher.delete()
  - QoS preservation (priority, congestion control)
  - Attachment forwarding
  - Lazy publisher caching
  - Retry with exponential backoff
  - Real-time relay statistics
''');
}
