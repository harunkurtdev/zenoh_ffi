// zenoh_dart.dart

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'dart:convert';

import 'src/gen/zenoh_dart_bindings_generated.dart' as bindings;

const String _libName = 'zenoh_dart';

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

// --- Classes ---

class ZenohSample {
  final String key;
  final Uint8List payload;
  final String kind;

  ZenohSample(this.key, this.payload, this.kind);

  String get payloadString => utf8.decode(payload);
}

class ZenohReply {
  final String key;
  final Uint8List payload;
  final String kind;

  ZenohReply(this.key, this.payload, this.kind);

  String get payloadString => utf8.decode(payload);
}

class ZenohQuery {
  final String key;
  final String selector;
  final Uint8List? value;
  final String kind;
  final Pointer<Void> _replyContext;

  ZenohQuery(
      this.key, this.selector, this.value, this.kind, this._replyContext);

  /// Send a reply to this query
  void reply(String key, Uint8List data) {
    final keyPtr = key.toNativeUtf8().cast<Char>();
    final dataPtr = calloc<Uint8>(data.length);
    final dataList = dataPtr.asTypedList(data.length);
    dataList.setAll(0, data);

    _bindings.zenoh_query_reply(_replyContext, keyPtr, dataPtr, data.length);

    calloc.free(keyPtr);
    calloc.free(dataPtr);
  }

  void replyString(String key, String data) {
    reply(key, Uint8List.fromList(utf8.encode(data)));
  }
}

class ZenohSession {
  final Pointer<bindings.ZenohSession> _handle;
  bool _isClosed = false;

  // Static maps to hold callbacks
  static final Map<int, StreamController<ZenohSample>> _subscribers = {};
  static final Map<int, StreamController<ZenohReply>> _queries = {};
  static final Map<int, void Function(ZenohQuery)> _queryables = {};

  static int _nextSubscriberId = 0;
  static int _nextQueryId = 0;
  static int _nextQueryableId = 0;

  // Native callback pointers
  static NativeCallable<bindings.ZenohSubscriberCallbackFunction>?
      _subscriberCallback;
  static NativeCallable<bindings.ZenohGetCallbackFunction>? _queryCallback;
  static NativeCallable<bindings.ZenohQueryCallbackFunction>?
      _queryableCallback;

  ZenohSession._(this._handle);

  /// Open a Zenoh Session
  static Future<ZenohSession> open(
      {String mode = 'client', List<String> endpoints = const []}) async {
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
      throw Exception('Failed to open Zenoh session');
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
  }

  void _checkClosed() {
    if (_isClosed) throw Exception('Session is closed');
  }

  Future<void> close() async {
    if (_isClosed) return; // Idempotent
    _bindings.zenoh_close_session(_handle);
    _isClosed = true;
  }

  // --- Publisher ---

  Future<ZenohPublisher> declarePublisher(String key) async {
    _checkClosed();
    final keyPtr = key.toNativeUtf8().cast<Char>();
    final pubHandle = _bindings.zenoh_declare_publisher(_handle, keyPtr);
    calloc.free(keyPtr);

    if (pubHandle == nullptr) {
      throw Exception('Failed to declare publisher for key: $key');
    }

    return ZenohPublisher._(pubHandle);
  }

  Future<void> put(String key, Uint8List data) async {
    _checkClosed();
    final keyPtr = key.toNativeUtf8().cast<Char>();
    final dataPtr = calloc<Uint8>(data.length);
    final dataList = dataPtr.asTypedList(data.length);
    dataList.setAll(0, data);

    final result = _bindings.zenoh_put(_handle, keyPtr, dataPtr, data.length);

    calloc.free(keyPtr);
    calloc.free(dataPtr);

    if (result < 0) throw Exception('Put failed');
  }

  Future<void> putString(String key, String value) async {
    await put(key, Uint8List.fromList(utf8.encode(value)));
  }

  Future<void> delete(String key) async {
    _checkClosed();
    final keyPtr = key.toNativeUtf8().cast<Char>();

    final result = _bindings.zenoh_delete(_handle, keyPtr);
    calloc.free(keyPtr);

    if (result < 0) throw Exception('Delete failed');
  }

  // --- Subscriber ---

  Future<ZenohSubscriber> declareSubscriber(String key) async {
    _checkClosed();

    final id = _nextSubscriberId++;
    final controller = StreamController<ZenohSample>();
    _subscribers[id] = controller;

    final context = Pointer<Void>.fromAddress(id);
    final keyPtr = key.toNativeUtf8().cast<Char>();

    final subHandle = _bindings.zenoh_declare_subscriber(
        _handle, keyPtr, _subscriberCallback!.nativeFunction, context);
    calloc.free(keyPtr);

    if (subHandle == nullptr) {
      _subscribers.remove(id);
      throw Exception('Failed to declare subscriber for key: $key');
    }

    controller.onCancel = () {
      // Cleanup is ideally explicit via undeclare, but we can't easily do it here safely without async.
    };

    return ZenohSubscriber._(subHandle, controller, id);
  }

  // --- Query (Get) ---

  Stream<ZenohReply> get(String selector) {
    _checkClosed();
    final id = _nextQueryId++;
    final controller = StreamController<ZenohReply>();
    _queries[id] = controller;

    final context = Pointer<Void>.fromAddress(id);
    final selectorPtr = selector.toNativeUtf8().cast<Char>();

    _bindings.zenoh_get_async(
        _handle, selectorPtr, _queryCallback!.nativeFunction, context);

    calloc.free(selectorPtr);

    // Workaround for missing "query complete" signal in current C wrapper
    // Closes stream after 2 seconds.
    Future.delayed(const Duration(seconds: 2), () {
      if (!controller.isClosed) {
        controller.close();
        _queries.remove(id);
      }
    });

    return controller.stream;
  }

  // --- Queryable ---

  Future<ZenohQueryable> declareQueryable(
      String keyExpr, void Function(ZenohQuery) handler) async {
    _checkClosed();

    final id = _nextQueryableId++;
    _queryables[id] = handler;

    final context = Pointer<Void>.fromAddress(id);
    final keyPtr = keyExpr.toNativeUtf8().cast<Char>();

    final qHandle = _bindings.zenoh_declare_queryable(
        _handle, keyPtr, _queryableCallback!.nativeFunction, context);

    calloc.free(keyPtr);

    if (qHandle == nullptr) {
      _queryables.remove(id);
      throw Exception('Failed to declare queryable for key: $keyExpr');
    }

    return ZenohQueryable._(qHandle, id);
  }

  // --- Scouting ---

  static Stream<String> scout({String what = 'peer|router', String? config}) {
    final controller = StreamController<String>();

    final whatPtr = what.toNativeUtf8().cast<Char>();
    final configPtr =
        config != null ? config.toNativeUtf8().cast<Char>() : nullptr;

    final callback = NativeCallable<Void Function(Pointer<Char>)>.listener(
        (Pointer<Char> info) {
      final infoStr = info.cast<Utf8>().toDartString();
      controller.add(infoStr);
    });

    Future(() {
      // Blocking scout call
      _bindings.zenoh_scout(whatPtr, configPtr, callback.nativeFunction);

      calloc.free(whatPtr);
      if (configPtr != nullptr) calloc.free(configPtr);
      callback.close();
      controller.close();
    });

    return controller.stream;
  }

  // --- Callbacks ---

  static void _onSubscriberData(
      Pointer<Char> key,
      Pointer<Uint8> value,
      int len,
      Pointer<Char> kind,
      Pointer<Char> attachment,
      Pointer<Void> context) {
    int id = context.address;
    if (_subscribers.containsKey(id)) {
      final keyStr = key.cast<Utf8>().toDartString();
      final kindStr = kind.cast<Utf8>().toDartString();
      final payload = Uint8List.fromList(value.asTypedList(len));

      _subscribers[id]?.add(ZenohSample(keyStr, payload, kindStr));
    }
  }

  static void _onQueryData(Pointer<Char> key, Pointer<Uint8> value, int len,
      Pointer<Char> kind, Pointer<Void> context) {
    int id = context.address;
    if (_queries.containsKey(id)) {
      final keyStr = key.cast<Utf8>().toDartString();
      final kindStr = kind.cast<Utf8>().toDartString();
      final payload = Uint8List.fromList(value.asTypedList(len));

      _queries[id]?.add(ZenohReply(keyStr, payload, kindStr));
    }
  }

  static void _onQueryRequest(
      Pointer<Char> key,
      Pointer<Char> selector,
      Pointer<Uint8> value,
      int len,
      Pointer<Char> kind,
      Pointer<Void> replyContext,
      Pointer<Void> userContext) {
    int id = userContext.address;
    if (_queryables.containsKey(id)) {
      final keyStr = key.cast<Utf8>().toDartString();
      final selectorStr = selector.cast<Utf8>().toDartString();
      final kindStr = kind.cast<Utf8>().toDartString();
      final payload =
          len > 0 ? Uint8List.fromList(value.asTypedList(len)) : null;

      final query =
          ZenohQuery(keyStr, selectorStr, payload, kindStr, replyContext);
      _queryables[id]?.call(query);
    }
  }
}

class ZenohPublisher {
  final Pointer<bindings.ZenohPublisher> _handle;
  bool _isUndeclared = false;

  ZenohPublisher._(this._handle);

  Future<void> put(Uint8List data) async {
    if (_isUndeclared) throw Exception('Publisher is undeclared');

    final dataPtr = calloc<Uint8>(data.length);
    final dataList = dataPtr.asTypedList(data.length);
    dataList.setAll(0, data);

    final result = _bindings.zenoh_publisher_put(_handle, dataPtr, data.length);
    calloc.free(dataPtr);

    if (result < 0) throw Exception('Publisher put failed');
  }

  Future<void> putString(String value) async {
    await put(Uint8List.fromList(utf8.encode(value)));
  }

  Future<void> delete() async {
    if (_isUndeclared) throw Exception('Publisher is undeclared');
    _bindings.zenoh_publisher_delete(_handle);
  }

  Future<void> undeclare() async {
    if (_isUndeclared) return;
    _bindings.zenoh_undeclare_publisher(_handle);
    _isUndeclared = true;
  }
}

class ZenohSubscriber {
  final Pointer<bindings.ZenohSubscriber> _handle;
  final StreamController<ZenohSample> _controller;
  final int _id;
  bool _isUndeclared = false;

  ZenohSubscriber._(this._handle, this._controller, this._id);

  Stream<ZenohSample> get stream => _controller.stream;

  Future<void> undeclare() async {
    if (_isUndeclared) return;
    _bindings.zenoh_undeclare_subscriber(_handle);
    _isUndeclared = true;
    _controller.close();
    ZenohSession._subscribers.remove(_id);
  }
}

class ZenohQueryable {
  final Pointer<bindings.ZenohQueryable> _handle;
  final int _id;
  bool _isUndeclared = false;

  ZenohQueryable._(this._handle, this._id);

  Future<void> undeclare() async {
    if (_isUndeclared) return;
    _bindings.zenoh_undeclare_queryable(_handle);
    _isUndeclared = true;
    ZenohSession._queryables.remove(_id);
  }
}
