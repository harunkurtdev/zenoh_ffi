import 'dart:typed_data';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:zenoh_dart/zenoh_dart.dart';

void main() {
  group('ZenohEncoding', () {
    test('fromValue returns correct encoding', () {
      expect(ZenohEncoding.fromValue(1), equals(ZenohEncoding.bytes));
      expect(
          ZenohEncoding.fromValue(17), equals(ZenohEncoding.applicationJson));
      expect(ZenohEncoding.fromValue(4), equals(ZenohEncoding.textPlain));
    });

    test('fromValue returns bytes for unknown value', () {
      expect(ZenohEncoding.fromValue(999), equals(ZenohEncoding.bytes));
    });

    test('fromMimeType returns correct encoding', () {
      expect(ZenohEncoding.fromMimeType('application/json'),
          equals(ZenohEncoding.applicationJson));
      expect(ZenohEncoding.fromMimeType('text/plain'),
          equals(ZenohEncoding.textPlain));
      expect(ZenohEncoding.fromMimeType('image/png'),
          equals(ZenohEncoding.imagePng));
    });

    test('fromMimeType returns custom for unknown mime', () {
      expect(ZenohEncoding.fromMimeType('unknown/type'),
          equals(ZenohEncoding.custom));
    });

    test('mimeType returns correct string', () {
      expect(
          ZenohEncoding.applicationJson.mimeType, equals('application/json'));
      expect(ZenohEncoding.textPlain.mimeType, equals('text/plain'));
      expect(ZenohEncoding.bytes.mimeType, equals('zenoh/bytes'));
    });
  });

  group('ZenohPriority', () {
    test('fromValue returns correct priority', () {
      expect(ZenohPriority.fromValue(1), equals(ZenohPriority.realTime));
      expect(ZenohPriority.fromValue(5), equals(ZenohPriority.data));
      expect(ZenohPriority.fromValue(7), equals(ZenohPriority.background));
    });

    test('fromValue returns data for unknown value', () {
      expect(ZenohPriority.fromValue(999), equals(ZenohPriority.data));
    });

    test('value returns correct int', () {
      expect(ZenohPriority.realTime.value, equals(1));
      expect(ZenohPriority.data.value, equals(5));
      expect(ZenohPriority.background.value, equals(7));
    });
  });

  group('ZenohCongestionControl', () {
    test('fromValue returns correct congestion control', () {
      expect(ZenohCongestionControl.fromValue(0),
          equals(ZenohCongestionControl.block));
      expect(ZenohCongestionControl.fromValue(1),
          equals(ZenohCongestionControl.drop));
      expect(ZenohCongestionControl.fromValue(2),
          equals(ZenohCongestionControl.dropFirst));
    });

    test('fromValue returns drop for unknown value', () {
      expect(ZenohCongestionControl.fromValue(999),
          equals(ZenohCongestionControl.drop));
    });
  });

  group('ZenohSampleKind', () {
    test('fromValue returns correct kind', () {
      expect(ZenohSampleKind.fromValue(0), equals(ZenohSampleKind.put));
      expect(ZenohSampleKind.fromValue(1), equals(ZenohSampleKind.delete));
    });

    test('fromValue returns put for unknown value', () {
      expect(ZenohSampleKind.fromValue(999), equals(ZenohSampleKind.put));
    });
  });

  group('ZenohSample', () {
    test('creates sample with required fields', () {
      final sample = ZenohSample(
        key: 'test/key',
        payload: Uint8List.fromList([1, 2, 3]),
      );

      expect(sample.key, equals('test/key'));
      expect(sample.payload, equals(Uint8List.fromList([1, 2, 3])));
      expect(sample.kind, equals(ZenohSampleKind.put));
    });

    test('payloadString decodes UTF-8', () {
      final sample = ZenohSample(
        key: 'test/key',
        payload: Uint8List.fromList(utf8.encode('Hello World')),
      );

      expect(sample.payloadString, equals('Hello World'));
    });

    test('attachmentString decodes UTF-8 when present', () {
      final sample = ZenohSample(
        key: 'test/key',
        payload: Uint8List.fromList([1]),
        attachment: Uint8List.fromList(utf8.encode('metadata')),
      );

      expect(sample.attachmentString, equals('metadata'));
    });

    test('attachmentString returns null when no attachment', () {
      final sample = ZenohSample(
        key: 'test/key',
        payload: Uint8List.fromList([1]),
      );

      expect(sample.attachmentString, isNull);
    });

    test('toString returns descriptive string', () {
      final sample = ZenohSample(
        key: 'test/key',
        payload: Uint8List.fromList([1, 2, 3]),
        kind: ZenohSampleKind.delete,
      );

      expect(sample.toString(), contains('test/key'));
      expect(sample.toString(), contains('delete'));
      expect(sample.toString(), contains('3'));
    });
  });

  group('ZenohReply', () {
    test('creates reply with required fields', () {
      final reply = ZenohReply(
        key: 'test/key',
        payload: Uint8List.fromList([1, 2, 3]),
      );

      expect(reply.key, equals('test/key'));
      expect(reply.payload, equals(Uint8List.fromList([1, 2, 3])));
      expect(reply.kind, equals(ZenohSampleKind.put));
    });

    test('payloadString decodes UTF-8', () {
      final reply = ZenohReply(
        key: 'test/key',
        payload: Uint8List.fromList(utf8.encode('Response')),
      );

      expect(reply.payloadString, equals('Response'));
    });
  });

  group('ZenohPutOptions', () {
    test('defaultOptions has correct defaults', () {
      const options = ZenohPutOptions.defaultOptions;

      expect(options.priority, equals(ZenohPriority.data));
      expect(options.congestionControl, equals(ZenohCongestionControl.drop));
      expect(options.encoding, equals(ZenohEncoding.bytes));
      expect(options.attachment, isNull);
      expect(options.express, isFalse);
    });

    test('creates options with custom values', () {
      final options = ZenohPutOptions(
        priority: ZenohPriority.realTime,
        congestionControl: ZenohCongestionControl.block,
        encoding: ZenohEncoding.applicationJson,
        attachment: Uint8List.fromList([1, 2, 3]),
        express: true,
      );

      expect(options.priority, equals(ZenohPriority.realTime));
      expect(options.congestionControl, equals(ZenohCongestionControl.block));
      expect(options.encoding, equals(ZenohEncoding.applicationJson));
      expect(options.attachment, equals(Uint8List.fromList([1, 2, 3])));
      expect(options.express, isTrue);
    });
  });

  group('ZenohPublisherOptions', () {
    test('defaultOptions has correct defaults', () {
      const options = ZenohPublisherOptions.defaultOptions;

      expect(options.priority, equals(ZenohPriority.data));
      expect(options.congestionControl, equals(ZenohCongestionControl.drop));
      expect(options.encoding, equals(ZenohEncoding.bytes));
      expect(options.express, isFalse);
    });
  });

  group('ZenohGetOptions', () {
    test('defaultOptions has correct defaults', () {
      const options = ZenohGetOptions.defaultOptions;

      expect(options.timeout, equals(const Duration(seconds: 10)));
      expect(options.priority, equals(ZenohPriority.data));
      expect(options.congestionControl, equals(ZenohCongestionControl.drop));
      expect(options.payload, isNull);
      expect(options.encoding, equals(ZenohEncoding.bytes));
      expect(options.attachment, isNull);
    });

    test('creates options with custom timeout', () {
      const options = ZenohGetOptions(
        timeout: Duration(seconds: 30),
      );

      expect(options.timeout, equals(const Duration(seconds: 30)));
    });
  });

  group('ZenohConfigBuilder', () {
    test('builds empty config', () {
      final config = ZenohConfigBuilder().build();
      expect(config, equals('{}'));
    });

    test('builds config with mode', () {
      final config = ZenohConfigBuilder().mode('peer').build();

      final parsed = jsonDecode(config) as Map;
      expect(parsed['mode'], equals('peer'));
    });

    test('builds config with connect endpoints', () {
      final config = ZenohConfigBuilder()
          .connect(['tcp/127.0.0.1:7447', 'tcp/192.168.1.1:7447']).build();

      final parsed = jsonDecode(config) as Map;
      expect(parsed['connect']['endpoints'], contains('tcp/127.0.0.1:7447'));
      expect(parsed['connect']['endpoints'], contains('tcp/192.168.1.1:7447'));
    });

    test('builds config with listen endpoints', () {
      final config = ZenohConfigBuilder().listen(['tcp/0.0.0.0:7448']).build();

      final parsed = jsonDecode(config) as Map;
      expect(parsed['listen']['endpoints'], contains('tcp/0.0.0.0:7448'));
    });

    test('builds config with multicast scouting', () {
      final config = ZenohConfigBuilder().multicastScouting(false).build();

      final parsed = jsonDecode(config) as Map;
      expect(parsed['scouting']['multicast']['enabled'], isFalse);
    });

    test('builds config with gossip scouting', () {
      final config = ZenohConfigBuilder().gossipScouting(true).build();

      final parsed = jsonDecode(config) as Map;
      expect(parsed['scouting']['gossip']['enabled'], isTrue);
    });

    test('builds config with custom key', () {
      final config =
          ZenohConfigBuilder().custom('custom_key', 'custom_value').build();

      final parsed = jsonDecode(config) as Map;
      expect(parsed['custom_key'], equals('custom_value'));
    });

    test('chains multiple configurations', () {
      final config = ZenohConfigBuilder()
          .mode('client')
          .connect(['tcp/127.0.0.1:7447'])
          .multicastScouting(false)
          .build();

      final parsed = jsonDecode(config) as Map;
      expect(parsed['mode'], equals('client'));
      expect(parsed['connect']['endpoints'], contains('tcp/127.0.0.1:7447'));
      expect(parsed['scouting']['multicast']['enabled'], isFalse);
    });
  });

  group('ZenohLivelinessEvent', () {
    test('creates event with key and alive status', () {
      final event = ZenohLivelinessEvent('node/1', true);

      expect(event.key, equals('node/1'));
      expect(event.isAlive, isTrue);
    });

    test('toString returns descriptive string', () {
      final event = ZenohLivelinessEvent('node/1', false);

      expect(event.toString(), contains('node/1'));
      expect(event.toString(), contains('false'));
    });
  });

  group('ZenohRetry', () {
    test('creates retry with default values', () {
      const retry = ZenohRetry();

      expect(retry.maxAttempts, equals(3));
      expect(retry.initialDelay, equals(const Duration(milliseconds: 100)));
      expect(retry.backoffMultiplier, equals(2.0));
      expect(retry.maxDelay, equals(const Duration(seconds: 10)));
    });

    test('creates retry with custom values', () {
      const retry = ZenohRetry(
        maxAttempts: 5,
        initialDelay: Duration(milliseconds: 200),
        backoffMultiplier: 1.5,
        maxDelay: Duration(seconds: 30),
      );

      expect(retry.maxAttempts, equals(5));
      expect(retry.initialDelay, equals(const Duration(milliseconds: 200)));
      expect(retry.backoffMultiplier, equals(1.5));
      expect(retry.maxDelay, equals(const Duration(seconds: 30)));
    });

    test('execute returns result on success', () async {
      const retry = ZenohRetry(maxAttempts: 3);

      final result = await retry.execute(() async => 'success');

      expect(result, equals('success'));
    });

    test('execute retries on failure', () async {
      const retry = ZenohRetry(
        maxAttempts: 3,
        initialDelay: Duration(milliseconds: 10),
      );

      int attempts = 0;
      final result = await retry.execute(() async {
        attempts++;
        if (attempts < 3) {
          throw ZenohException('Test error');
        }
        return 'success';
      });

      expect(result, equals('success'));
      expect(attempts, equals(3));
    });

    test('execute throws after max attempts', () async {
      const retry = ZenohRetry(
        maxAttempts: 2,
        initialDelay: Duration(milliseconds: 10),
      );

      expect(
        () => retry.execute(() async {
          throw ZenohException('Always fails');
        }),
        throwsA(isA<ZenohException>()),
      );
    });
  });

  group('ZenohException', () {
    test('creates exception with message', () {
      final exception = ZenohException('Test error');

      expect(exception.message, equals('Test error'));
      expect(exception.errorCode, isNull);
    });

    test('creates exception with message and error code', () {
      final exception = ZenohException('Test error', -1);

      expect(exception.message, equals('Test error'));
      expect(exception.errorCode, equals(-1));
    });

    test('toString includes message', () {
      final exception = ZenohException('Test error');

      expect(exception.toString(), contains('Test error'));
    });

    test('toString includes error code when present', () {
      final exception = ZenohException('Test error', -1);

      expect(exception.toString(), contains('Test error'));
      expect(exception.toString(), contains('-1'));
    });
  });

  group('Specialized Exceptions', () {
    test('ZenohSessionException is a ZenohException', () {
      final exception = ZenohSessionException('Session error');
      expect(exception, isA<ZenohException>());
    });

    test('ZenohPublisherException is a ZenohException', () {
      final exception = ZenohPublisherException('Publisher error');
      expect(exception, isA<ZenohException>());
    });

    test('ZenohSubscriberException is a ZenohException', () {
      final exception = ZenohSubscriberException('Subscriber error');
      expect(exception, isA<ZenohException>());
    });

    test('ZenohQueryableException is a ZenohException', () {
      final exception = ZenohQueryableException('Queryable error');
      expect(exception, isA<ZenohException>());
    });

    test('ZenohQueryException is a ZenohException', () {
      final exception = ZenohQueryException('Query error');
      expect(exception, isA<ZenohException>());
    });

    test('ZenohKeyExprException is a ZenohException', () {
      final exception = ZenohKeyExprException('Key expression error');
      expect(exception, isA<ZenohException>());
    });

    test('ZenohLivelinessException is a ZenohException', () {
      final exception = ZenohLivelinessException('Liveliness error');
      expect(exception, isA<ZenohException>());
    });

    test('ZenohTimeoutException is a ZenohException', () {
      final exception = ZenohTimeoutException('Timeout');
      expect(exception, isA<ZenohException>());
      expect(exception.errorCode, isNull);
    });
  });
}
