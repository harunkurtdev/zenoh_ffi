# zenoh_dart

A Dart binding for [Zenoh](https://zenoh.io/) - a high-performance, zero-overhead pub/sub, store/query, and compute protocol that unifies data in motion, data at rest, and computations.

`zenoh_dart` enables Dart and Flutter applications to seamlessly integrate with Zenoh's distributed systems capabilities.

![Video](./doc/video.MP4)

## Features

- **High Performance**: Zero-overhead binding to Zenoh-C core
- **Pub/Sub**: Efficient publish/subscribe messaging with priority and congestion control
- **Query/Reply**: Request-response pattern with configurable timeouts
- **Liveliness**: Monitor node presence on the network
- **Encoding Support**: Multiple data formats (JSON, CBOR, Protobuf, etc.)
- **Attachments**: Send metadata with messages
- **Cross-Platform**: Supports Android, Linux, macOS (Windows & iOS pending verification)
- **Configuration Builder**: Fluent API for session configuration
- **Retry Logic**: Built-in retry mechanism with exponential backoff
- **Type-Safe Exceptions**: Specific exception types for different error scenarios

## Getting Started

Add `zenoh_dart` to your `pubspec.yaml`:

```yaml
dependencies:
  zenoh_dart: ^0.0.1
```

## Usage

### 1. Open a Session

```dart
import 'package:zenoh_dart/zenoh_dart.dart';

void main() async {
  // Simple client session
  final session = await ZenohSession.open(
    mode: 'client',
    endpoints: ['tcp/localhost:7447'],
  );

  // Or use the configuration builder for more control
  final config = ZenohConfigBuilder()
    .mode('client')
    .connect(['tcp/localhost:7447'])
    .multicastScouting(false)
    .build();

  final session = await ZenohSession.openWithConfig(config);

  // Use session...

  // Close when done
  await session.close();
}
```

### 2. Publish Data

```dart
// Declare a publisher with options
final publisher = await session.declarePublisher(
  'demo/example',
  options: ZenohPublisherOptions(
    priority: ZenohPriority.realTime,
    congestionControl: ZenohCongestionControl.block,
    encoding: ZenohEncoding.applicationJson,
  ),
);

// Put binary data
await publisher.put(Uint8List.fromList([1, 2, 3]));

// Put string
await publisher.putString('Hello Zenoh!');

// Put JSON with attachment
await publisher.putJson(
  {'message': 'Hello', 'count': 42},
  attachment: Uint8List.fromList(utf8.encode('metadata')),
);

// Ad-hoc publish (without declaring a publisher)
await session.putJson('demo/adhoc', {'value': 123});

// Cleanup
await publisher.undeclare();
```

### 3. Subscribe to Data

```dart
// Declare a subscriber
final subscriber = await session.declareSubscriber('demo/**');

// Listen to stream
subscriber.stream.listen((sample) {
  print('Key: ${sample.key}');
  print('Payload: ${sample.payloadString}');
  print('Kind: ${sample.kind}');
  print('Attachment: ${sample.attachmentString}');
});

// Cleanup
await subscriber.undeclare();
```

### 4. Query/Reply (Get)

```dart
// Query data with timeout
final replies = session.get(
  'demo/**',
  options: ZenohGetOptions(
    timeout: Duration(seconds: 5),
    priority: ZenohPriority.data,
  ),
);

await for (final reply in replies) {
  print('Reply from ${reply.key}: ${reply.payloadString}');
}

// Or collect all replies
final allReplies = await session.getCollect('demo/**');
```

### 5. Queryable (Answer Queries)

```dart
// Declare a queryable
final queryable = await session.declareQueryable('demo/resource', (query) {
  print('Received query: ${query.key}');

  // Reply with string
  query.replyString(query.key, 'Response data');

  // Or reply with JSON
  query.replyJson(query.key, {'status': 'ok', 'value': 42});
});

// Cleanup
await queryable.undeclare();
```

### 6. Liveliness (Node Presence Detection)

```dart
// Declare a liveliness token (advertise presence)
final token = await session.declareLivelinessToken('nodes/my-node');

// Subscribe to liveliness changes
final liveSub = await session.declareLivelinessSubscriber(
  'nodes/**',
  history: true, // Get currently alive tokens
);

liveSub.stream.listen((event) {
  if (event.isAlive) {
    print('Node came online: ${event.key}');
  } else {
    print('Node went offline: ${event.key}');
  }
});

// Query currently alive tokens
await for (final event in session.livelinessGet('nodes/**')) {
  print('Currently alive: ${event.key}');
}

// Cleanup
token.undeclare();
await liveSub.undeclare();
```

### 7. Scouting

```dart
// Discover Zenoh routers and peers on the network
await for (final info in ZenohSession.scout()) {
  final data = jsonDecode(info);
  print('Found ${data['whatami']}: ${data['zid']}');
}
```

### 8. Retry Logic

```dart
// Use built-in retry for unreliable operations
final retry = ZenohRetry(
  maxAttempts: 5,
  initialDelay: Duration(milliseconds: 100),
  backoffMultiplier: 2.0,
  maxDelay: Duration(seconds: 10),
);

final session = await retry.execute(() => ZenohSession.open(
  mode: 'client',
  endpoints: ['tcp/localhost:7447'],
));
```

## API Reference

### Enums

| Enum | Values | Description |
|------|--------|-------------|
| `ZenohPriority` | `realTime`, `interactiveHigh`, `interactiveLow`, `dataHigh`, `data`, `dataLow`, `background` | Message priority levels |
| `ZenohCongestionControl` | `block`, `drop`, `dropFirst` | Congestion handling strategy |
| `ZenohSampleKind` | `put`, `delete` | Type of sample |
| `ZenohEncoding` | `bytes`, `string`, `json`, `textPlain`, `applicationJson`, `applicationCbor`, `applicationProtobuf`, etc. | Data encoding types |

### Classes

| Class | Description |
|-------|-------------|
| `ZenohSession` | Main entry point for all Zenoh operations |
| `ZenohPublisher` | Publisher for sending data on a key expression |
| `ZenohSubscriber` | Subscriber for receiving data |
| `ZenohQueryable` | Handler for incoming queries |
| `ZenohLivelinessToken` | Token to advertise presence |
| `ZenohLivelinessSubscriber` | Subscriber for presence changes |
| `ZenohConfigBuilder` | Fluent builder for session configuration |
| `ZenohRetry` | Utility for retry logic with exponential backoff |

### Exceptions

| Exception | Description |
|-----------|-------------|
| `ZenohException` | Base exception for all Zenoh errors |
| `ZenohSessionException` | Session-related errors |
| `ZenohPublisherException` | Publisher errors |
| `ZenohSubscriberException` | Subscriber errors |
| `ZenohQueryableException` | Queryable errors |
| `ZenohQueryException` | Query/Get errors |
| `ZenohLivelinessException` | Liveliness errors |
| `ZenohTimeoutException` | Timeout errors |
| `ZenohKeyExprException` | Invalid key expression |

## Setup & Build

This package uses `dart:ffi` to bind to the Zenoh-C library.

### Building Native Libraries

```bash
cd src
mkdir -p build && cd build
cmake ..
make
```

### Android

The native libraries (`libzenoh_dart.so`) must be present in `android/src/main/jniLibs`.

### macOS / Linux

The dynamic library should be available in the load path or bundled with the application.

### Windows

The `zenoh_dart.dll` must be in the application's directory or system PATH.

## Feature Status

- [x] Session Management
- [x] Publisher with Priority/Congestion Control
- [x] Subscriber
- [x] Query/Reply (Get/Queryable)
- [x] Liveliness Tokens
- [x] Encoding Support (JSON, CBOR, Protobuf, etc.)
- [x] Attachments/Metadata
- [x] Configuration Builder
- [x] Retry Logic
- [x] Custom Exceptions
- [x] Configurable Query Timeout
- [ ] Pull Subscribers
- [ ] Distributed Storage

## Running Tests

```bash
flutter test
```

## License

Apache 2.0 / Eclipse Public License 2.0
