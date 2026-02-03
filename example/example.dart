/// This example demonstrates the basic usage of zenoh_ffi package.
///
/// For a complete Flutter application example, see the `lib/` directory.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:zenoh_ffi/zenoh_ffi.dart';

Future<void> main() async {
  // Example 1: Open a session
  print('Opening Zenoh session...');
  final session = await ZenohSession.open(
    mode: 'peer',
    endpoints: [], // Empty for peer mode with multicast discovery
  );
  print('Session opened: ${session.sessionId}');

  // Example 2: Using Configuration Builder
  final config = ZenohConfigBuilder()
      .mode('client')
      .connect(['tcp/127.0.0.1:7447'])
      .multicastScouting(false)
      .build();
  print('Config: $config');

  // Example 3: Declare a subscriber
  final subscriber = await session.declareSubscriber('demo/**');
  subscriber.stream.listen((sample) {
    print('Received: ${sample.payloadString} on ${sample.key}');
    print('  Kind: ${sample.kind}');
    print('  Attachment: ${sample.attachmentString}');
  });

  // Example 4: Declare a publisher with options
  final publisher = await session.declarePublisher(
    'demo/example',
    options: const ZenohPublisherOptions(
      priority: ZenohPriority.data,
      congestionControl: ZenohCongestionControl.drop,
      encoding: ZenohEncoding.textPlain,
    ),
  );

  // Example 5: Publish data
  await publisher.putString('Hello from Zenoh Dart!');

  // Example 6: Publish JSON with attachment
  await publisher.putJson(
    {'message': 'Hello', 'timestamp': DateTime.now().toIso8601String()},
    attachment: Uint8List.fromList(utf8.encode('metadata:source=dart')),
  );

  // Example 7: Ad-hoc put with options
  await session.put(
    'demo/adhoc',
    Uint8List.fromList(utf8.encode('Ad-hoc message')),
    options: const ZenohPutOptions(
      priority: ZenohPriority.realTime,
      encoding: ZenohEncoding.textPlain,
    ),
  );

  // Example 8: Declare a queryable
  final queryable = await session.declareQueryable('demo/query', (query) {
    print('Received query for: ${query.key}');
    query.replyJson(query.key, {
      'status': 'ok',
      'data': 'Response from queryable',
    });
  });

  // Example 9: Query data with timeout
  final replies = session.get(
    'demo/**',
    options: const ZenohGetOptions(
      timeout: Duration(seconds: 5),
    ),
  );

  await for (final reply in replies) {
    print('Reply: ${reply.payloadString}');
  }

  // Example 10: Liveliness token
  final token = await session.declareLivelinessToken('nodes/dart-example');

  // Example 11: Subscribe to liveliness
  final liveSub = await session.declareLivelinessSubscriber(
    'nodes/**',
    history: true,
  );

  liveSub.stream.listen((event) {
    print('Liveliness: ${event.key} is ${event.isAlive ? "alive" : "dead"}');
  });

  // Example 12: Retry logic
  const retry = ZenohRetry(
    maxAttempts: 3,
    initialDelay: Duration(milliseconds: 100),
  );

  try {
    await retry.execute(() async {
      // Some operation that might fail
      await session.putString('demo/retry', 'Retried message');
    });
  } on ZenohException catch (e) {
    print('Operation failed after retries: $e');
  }

  // Cleanup
  await Future.delayed(const Duration(seconds: 2));

  token.undeclare();
  await liveSub.undeclare();
  await queryable.undeclare();
  await publisher.undeclare();
  await subscriber.undeclare();
  await session.close();

  print('Session closed.');
}
