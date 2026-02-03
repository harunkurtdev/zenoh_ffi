# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-02-03

### Changed
- **Package Renamed**: Package renamed from `zenoh_dart` to `zenoh_ffi` due to naming conflict on pub.dev
- This is a fresh release with all features from the original development

### Added

- **Liveliness Support**
  - `declareLivelinessToken()` - Advertise node presence on the network
  - `declareLivelinessSubscriber()` - Subscribe to liveliness changes
  - `livelinessGet()` - Query currently alive tokens

- **Priority and Congestion Control**
  - `ZenohPriority` enum with 7 priority levels (realTime, interactiveHigh, etc.)
  - `ZenohCongestionControl` enum (block, drop, dropFirst)
  - Configurable on publishers and put operations

- **Encoding Support**
  - `ZenohEncoding` enum with 23+ encoding types
  - Support for JSON, CBOR, Protobuf, YAML, images, and more
  - Automatic encoding detection and conversion

- **Attachments/Metadata**
  - Send metadata alongside messages via `attachment` parameter
  - Available on put, publish, query, and reply operations

- **Configuration Builder**
  - `ZenohConfigBuilder` - Fluent API for session configuration
  - Support for mode, connect, listen, scouting options

- **Retry Logic**
  - `ZenohRetry` class with exponential backoff
  - Configurable max attempts, initial delay, backoff multiplier

- **Custom Exceptions**
  - `ZenohException` - Base exception class
  - `ZenohSessionException` - Session-related errors
  - `ZenohPublisherException` - Publisher errors
  - `ZenohSubscriberException` - Subscriber errors
  - `ZenohQueryableException` - Queryable errors
  - `ZenohQueryException` - Query/Get errors
  - `ZenohLivelinessException` - Liveliness errors
  - `ZenohTimeoutException` - Timeout errors
  - `ZenohKeyExprException` - Invalid key expression

- **Configurable Query Timeout**
  - `ZenohGetOptions.timeout` parameter
  - Query completion callback from native layer

- **Convenience Methods**
  - `session.putString()` - Put UTF-8 string data
  - `session.putJson()` - Put JSON-encoded data
  - `publisher.putString()` - Publish UTF-8 string
  - `publisher.putJson()` - Publish JSON data
  - `query.replyString()` - Reply with string
  - `query.replyJson()` - Reply with JSON
  - `session.getCollect()` - Collect all query replies into a list

- **Session Info**
  - `session.sessionId` - Get session's unique identifier

- **Unit Tests**
  - Comprehensive test suite for all public APIs
  - Tests for enums, data classes, options, and utilities

- **Core Features** (from original development)
  - Zenoh Session Management (Client/Peer modes)
  - Publisher and Subscriber implementation
  - Query and Queryable support
  - Scouting functionality
  - FFI bindings for Android, macOS, Linux, iOS, Windows
