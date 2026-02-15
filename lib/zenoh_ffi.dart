/// Zenoh FFI - A Dart FFI binding for the Zenoh protocol
///
/// This library provides a complete Dart API for Zenoh, including:
/// - Session management
/// - Publishers and Subscribers
/// - Queryables and Get operations
/// - Liveliness tokens
/// - Priority and congestion control
/// - Encoding support
/// - Attachment/metadata support
library zenoh_ffi;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'dart:convert';

import 'src/gen/zenoh_ffi_bindings_generated.dart' as bindings;

// ============================================================================
// Library Loading
// ============================================================================

const String _libName = 'zenoh_ffi';

/// The dynamic library in which the symbols for [ZenohDartBindings] can be found.
final DynamicLibrary _dylib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

final bindings.ZenohDartBindings _bindings = bindings.ZenohDartBindings(_dylib);

// ============================================================================
// Exceptions
// ============================================================================

/// Base exception for all Zenoh errors
class ZenohException implements Exception {
  final String message;
  final int? errorCode;

  ZenohException(this.message, [this.errorCode]);

  @override
  String toString() => errorCode != null
      ? 'ZenohException: $message (code: $errorCode)'
      : 'ZenohException: $message';
}

/// Exception thrown when session operations fail
class ZenohSessionException extends ZenohException {
  ZenohSessionException(super.message, [super.errorCode]);
}

/// Exception thrown when publisher operations fail
class ZenohPublisherException extends ZenohException {
  ZenohPublisherException(super.message, [super.errorCode]);
}

/// Exception thrown when subscriber operations fail
class ZenohSubscriberException extends ZenohException {
  ZenohSubscriberException(super.message, [super.errorCode]);
}

/// Exception thrown when queryable operations fail
class ZenohQueryableException extends ZenohException {
  ZenohQueryableException(super.message, [super.errorCode]);
}

/// Exception thrown when query (get) operations fail
class ZenohQueryException extends ZenohException {
  ZenohQueryException(super.message, [super.errorCode]);
}

/// Exception thrown when key expression is invalid
class ZenohKeyExprException extends ZenohException {
  ZenohKeyExprException(super.message, [super.errorCode]);
}

/// Exception thrown when liveliness operations fail
class ZenohLivelinessException extends ZenohException {
  ZenohLivelinessException(super.message, [super.errorCode]);
}

/// Exception thrown when timeout occurs
class ZenohTimeoutException extends ZenohException {
  ZenohTimeoutException(String message) : super(message, null);
}

// ============================================================================
// Enums
// ============================================================================

/// Priority levels for Zenoh messages
enum ZenohPriority {
  realTime(1),
  interactiveHigh(2),
  interactiveLow(3),
  dataHigh(4),
  data(5),
  dataLow(6),
  background(7);

  final int value;
  const ZenohPriority(this.value);

  static ZenohPriority fromValue(int value) {
    return ZenohPriority.values.firstWhere(
      (p) => p.value == value,
      orElse: () => ZenohPriority.data,
    );
  }
}

/// Congestion control strategies
enum ZenohCongestionControl {
  block(0),
  drop(1),
  dropFirst(2);

  final int value;
  const ZenohCongestionControl(this.value);

  static ZenohCongestionControl fromValue(int value) {
    return ZenohCongestionControl.values.firstWhere(
      (c) => c.value == value,
      orElse: () => ZenohCongestionControl.drop,
    );
  }
}

/// Sample kinds
enum ZenohSampleKind {
  put(0),
  delete(1);

  final int value;
  const ZenohSampleKind(this.value);

  static ZenohSampleKind fromValue(int value) {
    return value == 1 ? ZenohSampleKind.delete : ZenohSampleKind.put;
  }
}

/// Encoding types for Zenoh data
enum ZenohEncoding {
  empty(0, 'empty'),
  bytes(1, 'zenoh/bytes'),
  string(2, 'zenoh/string'),
  json(3, 'application/json'),
  textPlain(4, 'text/plain'),
  textJson(5, 'text/json'),
  textHtml(6, 'text/html'),
  textXml(7, 'text/xml'),
  textCss(8, 'text/css'),
  textCsv(9, 'text/csv'),
  textJavascript(10, 'text/javascript'),
  imagePng(11, 'image/png'),
  imageJpeg(12, 'image/jpeg'),
  imageGif(13, 'image/gif'),
  imageBmp(14, 'image/bmp'),
  imageWebp(15, 'image/webp'),
  applicationOctetStream(16, 'application/octet-stream'),
  applicationJson(17, 'application/json'),
  applicationXml(18, 'application/xml'),
  applicationCbor(19, 'application/cbor'),
  applicationYaml(20, 'application/yaml'),
  applicationProtobuf(21, 'application/protobuf'),
  applicationCdr(22, 'application/cdr'),
  custom(100, 'custom');

  final int value;
  final String mimeType;
  const ZenohEncoding(this.value, this.mimeType);

  static ZenohEncoding fromValue(int value) {
    return ZenohEncoding.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ZenohEncoding.bytes,
    );
  }

  static ZenohEncoding fromMimeType(String mime) {
    return ZenohEncoding.values.firstWhere(
      (e) => e.mimeType == mime,
      orElse: () => ZenohEncoding.custom,
    );
  }
}

// ============================================================================
// Data Classes
// ============================================================================

/// Represents a sample received from a Zenoh subscription
class ZenohSample {
  final String key;
  final Uint8List payload;
  final ZenohSampleKind kind;
  final ZenohEncoding? encoding;
  final Uint8List? attachment;
  final ZenohPriority? priority;
  final ZenohCongestionControl? congestionControl;
  final DateTime? timestamp;

  ZenohSample({
    required this.key,
    required this.payload,
    this.kind = ZenohSampleKind.put,
    this.encoding,
    this.attachment,
    this.priority,
    this.congestionControl,
    this.timestamp,
  });

  /// Get payload as UTF-8 string
  String get payloadString => utf8.decode(payload, allowMalformed: true);

  /// Get attachment as UTF-8 string (if available)
  String? get attachmentString =>
      attachment != null ? utf8.decode(attachment!, allowMalformed: true) : null;

  @override
  String toString() =>
      'ZenohSample(key: $key, kind: $kind, size: ${payload.length})';
}

/// Represents a reply from a Zenoh query
class ZenohReply {
  final String key;
  final Uint8List payload;
  final ZenohSampleKind kind;
  final ZenohEncoding? encoding;
  final Uint8List? attachment;

  ZenohReply({
    required this.key,
    required this.payload,
    this.kind = ZenohSampleKind.put,
    this.encoding,
    this.attachment,
  });

  /// Get payload as UTF-8 string
  String get payloadString => utf8.decode(payload, allowMalformed: true);

  /// Get attachment as UTF-8 string (if available)
  String? get attachmentString =>
      attachment != null ? utf8.decode(attachment!, allowMalformed: true) : null;

  @override
  String toString() =>
      'ZenohReply(key: $key, kind: $kind, size: ${payload.length})';
}

/// Represents a query received by a Queryable
class ZenohQuery {
  final String key;
  final String selector;
  final Uint8List? value;
  final ZenohSampleKind kind;
  final ZenohEncoding? encoding;
  final Uint8List? attachment;
  final Pointer<Void> _replyContext;

  ZenohQuery({
    required this.key,
    required this.selector,
    this.value,
    this.kind = ZenohSampleKind.put,
    this.encoding,
    this.attachment,
    required Pointer<Void> replyContext,
  }) : _replyContext = replyContext;

  /// Send a reply to this query
  void reply(String key, Uint8List data,
      {ZenohEncoding? encoding, Uint8List? attachment}) {
    final keyPtr = key.toNativeUtf8().cast<Char>();
    final dataPtr = calloc<Uint8>(data.length);
    final dataList = dataPtr.asTypedList(data.length);
    dataList.setAll(0, data);

    if (encoding != null || attachment != null) {
      Pointer<Uint8> attPtr = nullptr;
      int attLen = 0;
      if (attachment != null && attachment.isNotEmpty) {
        attPtr = calloc<Uint8>(attachment.length);
        attPtr.asTypedList(attachment.length).setAll(0, attachment);
        attLen = attachment.length;
      }

      _bindings.zenoh_query_reply_with_options(
        _replyContext,
        keyPtr,
        dataPtr,
        data.length,
        encoding?.value ?? ZenohEncoding.bytes.value,
        attPtr,
        attLen,
      );

      if (attPtr != nullptr) calloc.free(attPtr);
    } else {
      _bindings.zenoh_query_reply(_replyContext, keyPtr, dataPtr, data.length);
    }

    calloc.free(keyPtr);
    calloc.free(dataPtr);
  }

  /// Send a string reply
  void replyString(String key, String data,
      {ZenohEncoding? encoding, String? attachment}) {
    reply(
      key,
      Uint8List.fromList(utf8.encode(data)),
      encoding: encoding ?? ZenohEncoding.textPlain,
      attachment: attachment != null
          ? Uint8List.fromList(utf8.encode(attachment))
          : null,
    );
  }

  /// Send a JSON reply
  void replyJson(String key, Object data, {String? attachment}) {
    reply(
      key,
      Uint8List.fromList(utf8.encode(jsonEncode(data))),
      encoding: ZenohEncoding.applicationJson,
      attachment: attachment != null
          ? Uint8List.fromList(utf8.encode(attachment))
          : null,
    );
  }
}

/// Options for publishing data
class ZenohPutOptions {
  final ZenohPriority priority;
  final ZenohCongestionControl congestionControl;
  final ZenohEncoding encoding;
  final Uint8List? attachment;
  final bool express;

  const ZenohPutOptions({
    this.priority = ZenohPriority.data,
    this.congestionControl = ZenohCongestionControl.drop,
    this.encoding = ZenohEncoding.bytes,
    this.attachment,
    this.express = false,
  });

  static const ZenohPutOptions defaultOptions = ZenohPutOptions();
}

/// Options for publisher declaration
class ZenohPublisherOptions {
  final ZenohPriority priority;
  final ZenohCongestionControl congestionControl;
  final ZenohEncoding encoding;
  final bool express;

  const ZenohPublisherOptions({
    this.priority = ZenohPriority.data,
    this.congestionControl = ZenohCongestionControl.drop,
    this.encoding = ZenohEncoding.bytes,
    this.express = false,
  });

  static const ZenohPublisherOptions defaultOptions = ZenohPublisherOptions();
}

/// Options for query (get) operations
class ZenohGetOptions {
  final Duration timeout;
  final ZenohPriority priority;
  final ZenohCongestionControl congestionControl;
  final Uint8List? payload;
  final ZenohEncoding encoding;
  final Uint8List? attachment;

  const ZenohGetOptions({
    this.timeout = const Duration(seconds: 10),
    this.priority = ZenohPriority.data,
    this.congestionControl = ZenohCongestionControl.drop,
    this.payload,
    this.encoding = ZenohEncoding.bytes,
    this.attachment,
  });

  static const ZenohGetOptions defaultOptions = ZenohGetOptions();
}

// ============================================================================
// Configuration Builder
// ============================================================================

/// Builder for creating Zenoh configuration
class ZenohConfigBuilder {
  final Map<String, dynamic> _config = {};

  /// Set the session mode (client, peer, or router)
  ZenohConfigBuilder mode(String mode) {
    _config['mode'] = mode;
    return this;
  }

  /// Add connect endpoints
  ZenohConfigBuilder connect(List<String> endpoints) {
    _config['connect'] = {'endpoints': endpoints};
    return this;
  }

  /// Add listen endpoints
  ZenohConfigBuilder listen(List<String> endpoints) {
    _config['listen'] = {'endpoints': endpoints};
    return this;
  }

  /// Enable/disable multicast scouting
  ZenohConfigBuilder multicastScouting(bool enabled) {
    _config['scouting'] = {
      'multicast': {'enabled': enabled}
    };
    return this;
  }

  /// Set gossip scouting
  ZenohConfigBuilder gossipScouting(bool enabled) {
    _config['scouting'] ??= {};
    (_config['scouting'] as Map)['gossip'] = {'enabled': enabled};
    return this;
  }

  /// Add custom configuration
  ZenohConfigBuilder custom(String key, dynamic value) {
    _config[key] = value;
    return this;
  }

  /// Build the configuration as JSON string
  String build() {
    return jsonEncode(_config);
  }
}

// ============================================================================
// Liveliness Token
// ============================================================================

/// Represents a liveliness token
class ZenohLivelinessToken {
  final Pointer<bindings.ZenohLivelinessToken> _handle;
  bool _isUndeclared = false;

  ZenohLivelinessToken._(this._handle);

  /// Undeclare and drop the liveliness token
  void undeclare() {
    if (_isUndeclared) return;
    _bindings.zenoh_undeclare_liveliness_token(_handle);
    _isUndeclared = true;
  }
}

/// Liveliness event received from a subscription
class ZenohLivelinessEvent {
  final String key;
  final bool isAlive;

  ZenohLivelinessEvent(this.key, this.isAlive);

  @override
  String toString() => 'ZenohLivelinessEvent(key: $key, alive: $isAlive)';
}

// ============================================================================
// Session
// ============================================================================

/// A Zenoh session providing all communication capabilities
class ZenohSession {
  final Pointer<bindings.ZenohSession> _handle;
  bool _isClosed = false;

  // Static maps to hold callbacks
  static final Map<int, StreamController<ZenohSample>> _subscribers = {};
  static final Map<int, StreamController<ZenohReply>> _queries = {};
  static final Map<int, void Function(ZenohQuery)> _queryables = {};
  static final Map<int, StreamController<ZenohLivelinessEvent>>
      _livelinessSubscribers = {};
  static final Map<int, Completer<void>> _queryCompleters = {};

  static int _nextSubscriberId = 0;
  static int _nextQueryId = 0;
  static int _nextQueryableId = 0;
  static int _nextLivelinessId = 0;

  // Native callback pointers
  static NativeCallable<bindings.ZenohSubscriberCallbackFunction>?
      _subscriberCallback;
  static NativeCallable<bindings.ZenohGetCallbackFunction>? _queryCallback;
  static NativeCallable<bindings.ZenohQueryCallbackFunction>?
      _queryableCallback;
  static NativeCallable<bindings.ZenohLivelinessCallbackFunction>?
      _livelinessCallback;
  static NativeCallable<bindings.ZenohGetCompleteCallbackFunction>?
      _queryCompleteCallback;

  ZenohSession._(this._handle);

  /// Open a Zenoh session with mode and endpoints
  static Future<ZenohSession> open({
    String mode = 'client',
    List<String> endpoints = const [],
  }) async {
    final modePtr = mode.toNativeUtf8().cast<Char>();

    Pointer<Char> endpointsPtr = nullptr;
    if (endpoints.isNotEmpty) {
      final endpointsJson = jsonEncode(endpoints);
      endpointsPtr = endpointsJson.toNativeUtf8().cast<Char>();
    }

    final handle = _bindings.zenoh_open_session(modePtr, endpointsPtr);

    calloc.free(modePtr);
    if (endpointsPtr != nullptr) calloc.free(endpointsPtr);

    if (handle == nullptr) {
      throw ZenohSessionException('Failed to open Zenoh session');
    }

    _ensureCallbacksInitialized();
    return ZenohSession._(handle);
  }

  /// Open a Zenoh session with a configuration builder
  static Future<ZenohSession> openWithConfig(ZenohConfigBuilder config) async {
    final configJson = config.build();
    final configPtr = configJson.toNativeUtf8().cast<Char>();

    final handle = _bindings.zenoh_open_session_with_config(configPtr);
    calloc.free(configPtr);

    if (handle == nullptr) {
      throw ZenohSessionException('Failed to open Zenoh session with config');
    }

    _ensureCallbacksInitialized();
    return ZenohSession._(handle);
  }

  static void _ensureCallbacksInitialized() {
    _subscriberCallback ??=
        NativeCallable<bindings.ZenohSubscriberCallbackFunction>.listener(
            _onSubscriberData);
    _queryCallback ??=
        NativeCallable<bindings.ZenohGetCallbackFunction>.listener(
            _onQueryData);
    _queryableCallback ??=
        NativeCallable<bindings.ZenohQueryCallbackFunction>.listener(
            _onQueryRequest);
    _livelinessCallback ??=
        NativeCallable<bindings.ZenohLivelinessCallbackFunction>.listener(
            _onLivelinessEvent);
    _queryCompleteCallback ??=
        NativeCallable<bindings.ZenohGetCompleteCallbackFunction>.listener(
            _onQueryComplete);
  }

  void _checkClosed() {
    if (_isClosed) throw ZenohSessionException('Session is closed');
  }

  /// Get the session's unique identifier
  String? get sessionId {
    _checkClosed();
    final infoPtr = _bindings.zenoh_session_info(_handle);
    if (infoPtr == nullptr) return null;
    final info = infoPtr.cast<Utf8>().toDartString();
    _bindings.zenoh_free_string(infoPtr.cast());
    return info;
  }

  /// Close the session
  Future<void> close() async {
    if (_isClosed) return;
    _bindings.zenoh_close_session(_handle);
    _isClosed = true;
  }

  // ============================================================================
  // Publisher Operations
  // ============================================================================

  /// Declare a publisher on a key expression
  Future<ZenohPublisher> declarePublisher(
    String key, {
    ZenohPublisherOptions options = ZenohPublisherOptions.defaultOptions,
  }) async {
    _checkClosed();
    final keyPtr = key.toNativeUtf8().cast<Char>();

    // Create options struct
    final optsPtr = calloc<bindings.ZenohPublisherOptions>();
    optsPtr.ref.priority = options.priority.value;
    optsPtr.ref.congestion_control = options.congestionControl.value;
    optsPtr.ref.encoding = options.encoding.value;
    optsPtr.ref.is_express = options.express;
    optsPtr.ref.encoding_schema = nullptr;

    final pubHandle = _bindings.zenoh_declare_publisher_with_options(
        _handle, keyPtr, optsPtr);

    calloc.free(keyPtr);
    calloc.free(optsPtr);

    if (pubHandle == nullptr) {
      throw ZenohPublisherException(
          'Failed to declare publisher for key: $key');
    }

    return ZenohPublisher._(pubHandle);
  }

  /// Put data on a key expression (ad-hoc publish)
  Future<void> put(
    String key,
    Uint8List data, {
    ZenohPutOptions options = ZenohPutOptions.defaultOptions,
  }) async {
    _checkClosed();
    final keyPtr = key.toNativeUtf8().cast<Char>();
    final dataPtr = calloc<Uint8>(data.length);
    final dataList = dataPtr.asTypedList(data.length);
    dataList.setAll(0, data);

    // Create options struct
    final optsPtr = calloc<bindings.ZenohPutOptions>();
    optsPtr.ref.priority = options.priority.value;
    optsPtr.ref.congestion_control = options.congestionControl.value;
    optsPtr.ref.encoding = options.encoding.value;
    optsPtr.ref.is_express = options.express;
    optsPtr.ref.encoding_schema = nullptr;

    if (options.attachment != null && options.attachment!.isNotEmpty) {
      final attPtr = calloc<Uint8>(options.attachment!.length);
      attPtr
          .asTypedList(options.attachment!.length)
          .setAll(0, options.attachment!);
      optsPtr.ref.attachment = attPtr;
      optsPtr.ref.attachment_len = options.attachment!.length;
    } else {
      optsPtr.ref.attachment = nullptr;
      optsPtr.ref.attachment_len = 0;
    }

    final result = _bindings.zenoh_put_with_options(
        _handle, keyPtr, dataPtr, data.length, optsPtr);

    if (optsPtr.ref.attachment != nullptr) {
      calloc.free(optsPtr.ref.attachment);
    }
    calloc.free(keyPtr);
    calloc.free(dataPtr);
    calloc.free(optsPtr);

    if (result < 0) throw ZenohException('Put failed', result);
  }

  /// Put a string on a key expression
  Future<void> putString(
    String key,
    String value, {
    ZenohPutOptions? options,
  }) async {
    await put(
      key,
      Uint8List.fromList(utf8.encode(value)),
      options:
          options ?? const ZenohPutOptions(encoding: ZenohEncoding.textPlain),
    );
  }

  /// Put JSON data on a key expression
  Future<void> putJson(
    String key,
    Object value, {
    Uint8List? attachment,
  }) async {
    await put(
      key,
      Uint8List.fromList(utf8.encode(jsonEncode(value))),
      options: ZenohPutOptions(
        encoding: ZenohEncoding.applicationJson,
        attachment: attachment,
      ),
    );
  }

  /// Delete data on a key expression
  Future<void> delete(String key) async {
    _checkClosed();
    final keyPtr = key.toNativeUtf8().cast<Char>();

    final result = _bindings.zenoh_delete(_handle, keyPtr);
    calloc.free(keyPtr);

    if (result < 0) throw ZenohException('Delete failed', result);
  }

  // ============================================================================
  // Subscriber Operations
  // ============================================================================

  /// Declare a subscriber on a key expression
  Future<ZenohSubscriber> declareSubscriber(String key) async {
    _checkClosed();

    final id = _nextSubscriberId++;
    final controller = StreamController<ZenohSample>();
    _subscribers[id] = controller;

    final context = Pointer<Void>.fromAddress(id);
    final keyPtr = key.toNativeUtf8().cast<Char>();

    final subHandle = _bindings.zenoh_declare_subscriber(
      _handle,
      keyPtr,
      _subscriberCallback!.nativeFunction,
      context,
    );
    calloc.free(keyPtr);

    if (subHandle == nullptr) {
      _subscribers.remove(id);
      throw ZenohSubscriberException(
          'Failed to declare subscriber for key: $key');
    }

    controller.onCancel = () {
      // Cleanup handled in undeclare
    };

    return ZenohSubscriber._(subHandle, controller, id);
  }

  // ============================================================================
  // Query (Get) Operations
  // ============================================================================

  /// Query data from the network
  Stream<ZenohReply> get(
    String selector, {
    ZenohGetOptions options = ZenohGetOptions.defaultOptions,
  }) {
    _checkClosed();
    final id = _nextQueryId++;
    final controller = StreamController<ZenohReply>();
    final completer = Completer<void>();
    _queries[id] = controller;
    _queryCompleters[id] = completer;

    final context = Pointer<Void>.fromAddress(id);
    final selectorPtr = selector.toNativeUtf8().cast<Char>();

    // Create options struct
    final optsPtr = calloc<bindings.ZenohGetOptions>();
    optsPtr.ref.timeout_ms = options.timeout.inMilliseconds;
    optsPtr.ref.priority = options.priority.value;
    optsPtr.ref.congestion_control = options.congestionControl.value;
    optsPtr.ref.encoding = options.encoding.value;

    if (options.payload != null && options.payload!.isNotEmpty) {
      final payloadPtr = calloc<Uint8>(options.payload!.length);
      payloadPtr
          .asTypedList(options.payload!.length)
          .setAll(0, options.payload!);
      optsPtr.ref.payload = payloadPtr;
      optsPtr.ref.payload_len = options.payload!.length;
    } else {
      optsPtr.ref.payload = nullptr;
      optsPtr.ref.payload_len = 0;
    }

    if (options.attachment != null && options.attachment!.isNotEmpty) {
      final attPtr = calloc<Uint8>(options.attachment!.length);
      attPtr
          .asTypedList(options.attachment!.length)
          .setAll(0, options.attachment!);
      optsPtr.ref.attachment = attPtr;
      optsPtr.ref.attachment_len = options.attachment!.length;
    } else {
      optsPtr.ref.attachment = nullptr;
      optsPtr.ref.attachment_len = 0;
    }

    _bindings.zenoh_get_async_with_options(
      _handle,
      selectorPtr,
      _queryCallback!.nativeFunction,
      _queryCompleteCallback!.nativeFunction,
      context,
      optsPtr,
    );

    // Clean up options
    if (optsPtr.ref.payload != nullptr) calloc.free(optsPtr.ref.payload);
    if (optsPtr.ref.attachment != nullptr) calloc.free(optsPtr.ref.attachment);
    calloc.free(selectorPtr);
    calloc.free(optsPtr);

    // The stream will be closed when the query completes (via completion callback)
    // Add a timeout fallback just in case
    Future.delayed(options.timeout + const Duration(seconds: 1), () {
      if (!controller.isClosed) {
        controller.close();
        _queries.remove(id);
        _queryCompleters.remove(id);
      }
    });

    return controller.stream;
  }

  /// Query and collect all replies into a list
  Future<List<ZenohReply>> getCollect(
    String selector, {
    ZenohGetOptions options = ZenohGetOptions.defaultOptions,
  }) async {
    final replies = <ZenohReply>[];
    await for (final reply in get(selector, options: options)) {
      replies.add(reply);
    }
    return replies;
  }

  // ============================================================================
  // Queryable Operations
  // ============================================================================

  /// Declare a queryable on a key expression
  Future<ZenohQueryable> declareQueryable(
    String keyExpr,
    void Function(ZenohQuery) handler,
  ) async {
    _checkClosed();

    final id = _nextQueryableId++;
    _queryables[id] = handler;

    final context = Pointer<Void>.fromAddress(id);
    final keyPtr = keyExpr.toNativeUtf8().cast<Char>();

    final qHandle = _bindings.zenoh_declare_queryable(
      _handle,
      keyPtr,
      _queryableCallback!.nativeFunction,
      context,
    );

    calloc.free(keyPtr);

    if (qHandle == nullptr) {
      _queryables.remove(id);
      throw ZenohQueryableException(
          'Failed to declare queryable for key: $keyExpr');
    }

    return ZenohQueryable._(qHandle, id);
  }

  // ============================================================================
  // Liveliness Operations
  // ============================================================================

  /// Declare a liveliness token
  Future<ZenohLivelinessToken> declareLivelinessToken(String keyExpr) async {
    _checkClosed();
    final keyPtr = keyExpr.toNativeUtf8().cast<Char>();

    final tokenHandle =
        _bindings.zenoh_declare_liveliness_token(_handle, keyPtr);
    calloc.free(keyPtr);

    if (tokenHandle == nullptr) {
      throw ZenohLivelinessException(
          'Failed to declare liveliness token for key: $keyExpr');
    }

    return ZenohLivelinessToken._(tokenHandle);
  }

  /// Subscribe to liveliness changes
  Future<ZenohLivelinessSubscriber> declareLivelinessSubscriber(
    String keyExpr, {
    bool history = false,
  }) async {
    _checkClosed();

    final id = _nextLivelinessId++;
    final controller = StreamController<ZenohLivelinessEvent>();
    _livelinessSubscribers[id] = controller;

    final context = Pointer<Void>.fromAddress(id);
    final keyPtr = keyExpr.toNativeUtf8().cast<Char>();

    final subHandle = _bindings.zenoh_declare_liveliness_subscriber(
      _handle,
      keyPtr,
      _livelinessCallback!.nativeFunction,
      context,
      history,
    );
    calloc.free(keyPtr);

    if (subHandle == nullptr) {
      _livelinessSubscribers.remove(id);
      throw ZenohLivelinessException(
          'Failed to declare liveliness subscriber for key: $keyExpr');
    }

    return ZenohLivelinessSubscriber._(subHandle, controller, id);
  }

  /// Query currently alive tokens
  Stream<ZenohLivelinessEvent> livelinessGet(
    String keyExpr, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    _checkClosed();

    final id = _nextLivelinessId++;
    final controller = StreamController<ZenohLivelinessEvent>();
    _livelinessSubscribers[id] = controller;

    final context = Pointer<Void>.fromAddress(id);
    final keyPtr = keyExpr.toNativeUtf8().cast<Char>();

    _bindings.zenoh_liveliness_get(
      _handle,
      keyPtr,
      _livelinessCallback!.nativeFunction,
      context,
      timeout.inMilliseconds,
    );

    calloc.free(keyPtr);

    // Close stream after timeout
    Future.delayed(timeout + const Duration(milliseconds: 100), () {
      if (!controller.isClosed) {
        controller.close();
        _livelinessSubscribers.remove(id);
      }
    });

    return controller.stream;
  }

  // ============================================================================
  // Scouting
  // ============================================================================

  /// Scout for Zenoh peers and routers on the network
  static Stream<String> scout({String what = 'peer|router', String? config}) {
    final controller = StreamController<String>();

    final whatPtr = what.toNativeUtf8().cast<Char>();
    final configPtr =
        config != null ? config.toNativeUtf8().cast<Char>() : nullptr;

    final callback = NativeCallable<Void Function(Pointer<Char>)>.listener(
      (Pointer<Char> info) {
        final infoStr = info.cast<Utf8>().toDartString();
        controller.add(infoStr);
      },
    );

    Future(() {
      _bindings.zenoh_scout(whatPtr, configPtr, callback.nativeFunction);

      calloc.free(whatPtr);
      if (configPtr != nullptr) calloc.free(configPtr);
      callback.close();
      controller.close();
    });

    return controller.stream;
  }

  // ============================================================================
  // Callbacks
  // ============================================================================

  static void _onSubscriberData(
    Pointer<Char> key,
    Pointer<Uint8> value,
    int len,
    Pointer<Char> kind,
    Pointer<Char> attachment,
    Pointer<Void> context,
  ) {
    try {
      int id = context.address;
      if (_subscribers.containsKey(id)) {
        final keyStr = key.cast<Utf8>().toDartString();
        final kindStr = kind.cast<Utf8>().toDartString();
        final payload = len > 0 && value.address != 0
            ? Uint8List.fromList(value.asTypedList(len))
            : Uint8List(0);
        final attStr = attachment.address != 0
            ? attachment.cast<Utf8>().toDartString()
            : '';

        _subscribers[id]?.add(ZenohSample(
          key: keyStr,
          payload: payload,
          kind: kindStr == 'DELETE'
              ? ZenohSampleKind.delete
              : ZenohSampleKind.put,
          attachment: attStr.isNotEmpty
              ? Uint8List.fromList(utf8.encode(attStr))
              : null,
        ));
      }
    } catch (e) {
      print('Error in subscriber callback: $e');
    } finally {
      // Free native memory allocated by C side
      malloc.free(key);
      malloc.free(kind);
      if (attachment.address != 0) malloc.free(attachment);
      if (value.address != 0 && len > 0) malloc.free(value);
    }
  }

  static void _onQueryData(
    Pointer<Char> key,
    Pointer<Uint8> value,
    int len,
    Pointer<Char> kind,
    Pointer<Void> context,
  ) {
    try {
      int id = context.address;
      if (_queries.containsKey(id)) {
        final keyStr = key.cast<Utf8>().toDartString();
        final kindStr = kind.cast<Utf8>().toDartString();
        final payload = len > 0 && value.address != 0
            ? Uint8List.fromList(value.asTypedList(len))
            : Uint8List(0);

        _queries[id]?.add(ZenohReply(
          key: keyStr,
          payload: payload,
          kind:
              kindStr == 'DELETE' ? ZenohSampleKind.delete : ZenohSampleKind.put,
        ));
      }
    } finally {
      // Free native memory allocated by C side
      malloc.free(key);
      malloc.free(kind);
      if (value.address != 0 && len > 0) malloc.free(value);
    }
  }

  static void _onQueryComplete(Pointer<Void> context) {
    int id = context.address;
    if (_queries.containsKey(id)) {
      _queries[id]?.close();
      _queries.remove(id);
    }
    if (_queryCompleters.containsKey(id)) {
      _queryCompleters[id]?.complete();
      _queryCompleters.remove(id);
    }
  }

  static void _onQueryRequest(
    Pointer<Char> key,
    Pointer<Char> selector,
    Pointer<Uint8> value,
    int len,
    Pointer<Char> kind,
    Pointer<Void> replyContext,
    Pointer<Void> userContext,
  ) {
    try {
      int id = userContext.address;
      if (_queryables.containsKey(id)) {
        final keyStr = key.cast<Utf8>().toDartString();
        final selectorStr = selector.cast<Utf8>().toDartString();
        final kindStr = kind.cast<Utf8>().toDartString();
        final payload =
            len > 0 && value.address != 0 ? Uint8List.fromList(value.asTypedList(len)) : null;

        final query = ZenohQuery(
          key: keyStr,
          selector: selectorStr,
          value: payload,
          kind:
              kindStr == 'DELETE' ? ZenohSampleKind.delete : ZenohSampleKind.put,
          replyContext: replyContext,
        );
        _queryables[id]?.call(query);
      }
    } finally {
      // Free native memory allocated by C side
      malloc.free(key);
      malloc.free(selector);
      malloc.free(kind);
      if (value.address != 0 && len > 0) malloc.free(value);
    }
  }

  static void _onLivelinessEvent(
    Pointer<Char> key,
    int isAlive,
    Pointer<Void> context,
  ) {
    try {
      int id = context.address;
      if (_livelinessSubscribers.containsKey(id)) {
        final keyStr = key.cast<Utf8>().toDartString();
        _livelinessSubscribers[id]
            ?.add(ZenohLivelinessEvent(keyStr, isAlive != 0));
      }
    } finally {
      // Free native memory allocated by C side
      malloc.free(key);
    }
  }
}

// ============================================================================
// Publisher
// ============================================================================

/// A Zenoh publisher for sending data on a specific key expression
class ZenohPublisher {
  final Pointer<bindings.ZenohPublisher> _handle;
  bool _isUndeclared = false;

  ZenohPublisher._(this._handle);

  void _checkUndeclared() {
    if (_isUndeclared) throw ZenohPublisherException('Publisher is undeclared');
  }

  /// Put data through this publisher
  Future<void> put(Uint8List data, {ZenohPutOptions? options}) async {
    _checkUndeclared();

    final dataPtr = calloc<Uint8>(data.length);
    final dataList = dataPtr.asTypedList(data.length);
    dataList.setAll(0, data);

    int result;
    if (options != null) {
      final optsPtr = calloc<bindings.ZenohPutOptions>();
      optsPtr.ref.priority = options.priority.value;
      optsPtr.ref.congestion_control = options.congestionControl.value;
      optsPtr.ref.encoding = options.encoding.value;
      optsPtr.ref.is_express = options.express;
      optsPtr.ref.encoding_schema = nullptr;

      if (options.attachment != null && options.attachment!.isNotEmpty) {
        final attPtr = calloc<Uint8>(options.attachment!.length);
        attPtr
            .asTypedList(options.attachment!.length)
            .setAll(0, options.attachment!);
        optsPtr.ref.attachment = attPtr;
        optsPtr.ref.attachment_len = options.attachment!.length;
      } else {
        optsPtr.ref.attachment = nullptr;
        optsPtr.ref.attachment_len = 0;
      }

      result = _bindings.zenoh_publisher_put_with_options(
          _handle, dataPtr, data.length, optsPtr);

      if (optsPtr.ref.attachment != nullptr) {
        calloc.free(optsPtr.ref.attachment);
      }
      calloc.free(optsPtr);
    } else {
      result = _bindings.zenoh_publisher_put(_handle, dataPtr, data.length);
    }

    calloc.free(dataPtr);

    if (result < 0) {
      throw ZenohPublisherException('Publisher put failed', result);
    }
  }

  /// Put a string through this publisher
  Future<void> putString(String value, {ZenohPutOptions? options}) async {
    await put(
      Uint8List.fromList(utf8.encode(value)),
      options:
          options ?? const ZenohPutOptions(encoding: ZenohEncoding.textPlain),
    );
  }

  /// Put JSON data through this publisher
  Future<void> putJson(Object value, {Uint8List? attachment}) async {
    await put(
      Uint8List.fromList(utf8.encode(jsonEncode(value))),
      options: ZenohPutOptions(
        encoding: ZenohEncoding.applicationJson,
        attachment: attachment,
      ),
    );
  }

  /// Delete through this publisher
  Future<void> delete() async {
    _checkUndeclared();
    _bindings.zenoh_publisher_delete(_handle);
  }

  /// Undeclare and drop the publisher
  Future<void> undeclare() async {
    if (_isUndeclared) return;
    _bindings.zenoh_undeclare_publisher(_handle);
    _isUndeclared = true;
  }
}

// ============================================================================
// Subscriber
// ============================================================================

/// A Zenoh subscriber for receiving data on a key expression
class ZenohSubscriber {
  final Pointer<bindings.ZenohSubscriber> _handle;
  final StreamController<ZenohSample> _controller;
  final int _id;
  bool _isUndeclared = false;

  ZenohSubscriber._(this._handle, this._controller, this._id);

  /// Stream of received samples
  Stream<ZenohSample> get stream => _controller.stream;

  /// Undeclare and drop the subscriber
  Future<void> undeclare() async {
    if (_isUndeclared) return;
    _bindings.zenoh_undeclare_subscriber(_handle);
    _isUndeclared = true;
    _controller.close();
    ZenohSession._subscribers.remove(_id);
  }
}

// ============================================================================
// Queryable
// ============================================================================

/// A Zenoh queryable for handling queries on a key expression
class ZenohQueryable {
  final Pointer<bindings.ZenohQueryable> _handle;
  final int _id;
  bool _isUndeclared = false;

  ZenohQueryable._(this._handle, this._id);

  /// Undeclare and drop the queryable
  Future<void> undeclare() async {
    if (_isUndeclared) return;
    _bindings.zenoh_undeclare_queryable(_handle);
    _isUndeclared = true;
    ZenohSession._queryables.remove(_id);
  }
}

// ============================================================================
// Liveliness Subscriber
// ============================================================================

/// A Zenoh liveliness subscriber for monitoring token presence
class ZenohLivelinessSubscriber {
  final Pointer<bindings.ZenohSubscriber> _handle;
  final StreamController<ZenohLivelinessEvent> _controller;
  final int _id;
  bool _isUndeclared = false;

  ZenohLivelinessSubscriber._(this._handle, this._controller, this._id);

  /// Stream of liveliness events
  Stream<ZenohLivelinessEvent> get stream => _controller.stream;

  /// Undeclare and drop the subscriber
  Future<void> undeclare() async {
    if (_isUndeclared) return;
    _bindings.zenoh_undeclare_subscriber(_handle);
    _isUndeclared = true;
    _controller.close();
    ZenohSession._livelinessSubscribers.remove(_id);
  }
}

// ============================================================================
// Retry Wrapper
// ============================================================================

/// Utility class for adding retry logic to Zenoh operations
class ZenohRetry {
  final int maxAttempts;
  final Duration initialDelay;
  final double backoffMultiplier;
  final Duration maxDelay;

  const ZenohRetry({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 100),
    this.backoffMultiplier = 2.0,
    this.maxDelay = const Duration(seconds: 10),
  });

  /// Execute an operation with retry logic
  Future<T> execute<T>(Future<T> Function() operation) async {
    Duration delay = initialDelay;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await operation();
      } on ZenohException {
        if (attempt == maxAttempts) rethrow;

        // Wait before retry
        await Future.delayed(delay);

        // Calculate next delay with backoff
        delay = Duration(
          milliseconds: (delay.inMilliseconds * backoffMultiplier).toInt(),
        );
        if (delay > maxDelay) {
          delay = maxDelay;
        }
      }
    }

    throw ZenohException('Retry failed after $maxAttempts attempts');
  }

  /// Execute a stream operation with retry logic
  Stream<T> executeStream<T>(Stream<T> Function() operation) async* {
    Duration delay = initialDelay;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await for (final item in operation()) {
          yield item;
        }
        return;
      } on ZenohException {
        if (attempt == maxAttempts) rethrow;

        await Future.delayed(delay);

        delay = Duration(
          milliseconds: (delay.inMilliseconds * backoffMultiplier).toInt(),
        );
        if (delay > maxDelay) {
          delay = maxDelay;
        }
      }
    }
  }
}
