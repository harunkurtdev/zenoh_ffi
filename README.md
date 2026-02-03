# zenoh_dart

A Dart binding for [Zenoh](https://zenoh.io/) - a high-performance, zero-overhead pub/sub, store/query, and compute protocol that unifies data in motion, data at rest, and computations.

`zenoh_dart` enables Dart and Flutter applications to seamlessly integrate with Zenoh's distributed systems capabilities.

![Video](./doc/video.MP4)

## Features

- **High Performance**: zero-overhead binding to Rust Zenoh core.
- **Pub/Sub**: Efficient publish/subscribe messaging.
- **Cross-Platform**: Supports Android, Linux, MacOS. (Windows & iOS pending verification).
- **Simple API**: Dart-friendly wrapper around FFI.

## Getting Started

Add `zenoh_dart` to your `pubspec.yaml`:

```yaml
dependencies:
  zenoh_dart: ^0.0.1
```

## Usage

### 1. Initialize Session

```dart
import 'package:zenoh_dart/zenoh_dart.dart';

void main() async {
  // Open a client session
  final session = await ZenohSession.open(
    mode: 'client',
    endpoints: ['tcp/localhost:7447']
  );

  // Use session...

  // Close when done
  await session.close();
}
```

### 2. Publish Data

```dart
// Declare a publisher
final publisher = await session.declarePublisher('demo/example');

// Put data
publisher.put('Hello Zenoh!');
```

### 3. Subscribe to Data

```dart
// Declare a subscriber
final subscriber = await session.declareSubscriber('demo/**');

// Listen to stream
subscriber.stream.listen((sample) {
  print('Received: ${sample.payloadString} on ${sample.key}');
});
```

## Setup & Build

This package uses `dart:ffi` to bind to the Zenoh Rust library.

### Android

The native libraries (`libzenoh_dart.so`) must be present in `android/src/main/jniLibs`.

### MacOS / Linux

The dynamic library (`zenoh_dart`) should be available in the load path.

## Feature Status

- [x] Session Management
- [x] Publisher
- [x] Subscriber
- [ ] Query/Reply
- [ ] Distributed Storage

## License

Apache 2.0 / Eclipse Public License 2.0
