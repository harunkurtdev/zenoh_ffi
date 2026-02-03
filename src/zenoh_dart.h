#ifndef ZENOH_DART_H
#define ZENOH_DART_H

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if __has_include(<zenoh.h>)
#include <zenoh.h>
#elif __has_include("zenoh.h")
#include "zenoh.h"
#else
#error "zenoh.h not found!"
#endif

#if _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <unistd.h>
#endif

// Define proper export macros
#if defined(_WIN32)
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#elif defined(__GNUC__) && __GNUC__ >= 4
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FFI_PLUGIN_EXPORT
#endif

// ============================================================================
// Forward declarations
// ============================================================================
typedef struct ZenohSession ZenohSession;
typedef struct ZenohPublisher ZenohPublisher;
typedef struct ZenohSubscriber ZenohSubscriber;
typedef struct ZenohQueryable ZenohQueryable;
typedef struct ZenohLivelinessToken ZenohLivelinessToken;

// ============================================================================
// Enums - Priority and Congestion Control
// ============================================================================

typedef enum {
  ZENOH_PRIORITY_REAL_TIME = 1,
  ZENOH_PRIORITY_INTERACTIVE_HIGH = 2,
  ZENOH_PRIORITY_INTERACTIVE_LOW = 3,
  ZENOH_PRIORITY_DATA_HIGH = 4,
  ZENOH_PRIORITY_DATA = 5,
  ZENOH_PRIORITY_DATA_LOW = 6,
  ZENOH_PRIORITY_BACKGROUND = 7
} ZenohPriority;

typedef enum {
  ZENOH_CONGESTION_CONTROL_BLOCK = 0,
  ZENOH_CONGESTION_CONTROL_DROP = 1,
  ZENOH_CONGESTION_CONTROL_DROP_FIRST = 2
} ZenohCongestionControl;

typedef enum {
  ZENOH_SAMPLE_KIND_PUT = 0,
  ZENOH_SAMPLE_KIND_DELETE = 1
} ZenohSampleKind;

// ============================================================================
// Encoding Types
// ============================================================================

typedef enum {
  ZENOH_ENCODING_EMPTY = 0,
  ZENOH_ENCODING_BYTES = 1,
  ZENOH_ENCODING_STRING = 2,
  ZENOH_ENCODING_JSON = 3,
  ZENOH_ENCODING_TEXT_PLAIN = 4,
  ZENOH_ENCODING_TEXT_JSON = 5,
  ZENOH_ENCODING_TEXT_HTML = 6,
  ZENOH_ENCODING_TEXT_XML = 7,
  ZENOH_ENCODING_TEXT_CSS = 8,
  ZENOH_ENCODING_TEXT_CSV = 9,
  ZENOH_ENCODING_TEXT_JAVASCRIPT = 10,
  ZENOH_ENCODING_IMAGE_PNG = 11,
  ZENOH_ENCODING_IMAGE_JPEG = 12,
  ZENOH_ENCODING_IMAGE_GIF = 13,
  ZENOH_ENCODING_IMAGE_BMP = 14,
  ZENOH_ENCODING_IMAGE_WEBP = 15,
  ZENOH_ENCODING_APPLICATION_OCTET_STREAM = 16,
  ZENOH_ENCODING_APPLICATION_JSON = 17,
  ZENOH_ENCODING_APPLICATION_XML = 18,
  ZENOH_ENCODING_APPLICATION_CBOR = 19,
  ZENOH_ENCODING_APPLICATION_YAML = 20,
  ZENOH_ENCODING_APPLICATION_PROTOBUF = 21,
  ZENOH_ENCODING_APPLICATION_CDR = 22,
  ZENOH_ENCODING_CUSTOM = 100
} ZenohEncodingId;

// ============================================================================
// Publisher Options
// ============================================================================

typedef struct {
  ZenohPriority priority;
  ZenohCongestionControl congestion_control;
  ZenohEncodingId encoding;
  const char *encoding_schema;  // Optional schema for encoding
  bool is_express;              // Express mode for low latency
} ZenohPublisherOptions;

// ============================================================================
// Put Options
// ============================================================================

typedef struct {
  ZenohPriority priority;
  ZenohCongestionControl congestion_control;
  ZenohEncodingId encoding;
  const char *encoding_schema;
  const uint8_t *attachment;
  size_t attachment_len;
  bool is_express;
} ZenohPutOptions;

// ============================================================================
// Query Options
// ============================================================================

typedef struct {
  uint64_t timeout_ms;  // Timeout in milliseconds (0 = default)
  ZenohPriority priority;
  ZenohCongestionControl congestion_control;
  const uint8_t *payload;
  size_t payload_len;
  ZenohEncodingId encoding;
  const uint8_t *attachment;
  size_t attachment_len;
} ZenohGetOptions;

// ============================================================================
// Callback Types
// ============================================================================

// Subscriber callback with extended info
typedef void (*ZenohSubscriberCallback)(const char *key, const uint8_t *value,
                                        size_t len, const char *kind,
                                        const char *attachment, void *context);

// Extended subscriber callback with full sample info
typedef void (*ZenohSubscriberCallbackEx)(
    const char *key, const uint8_t *value, size_t len, int sample_kind,
    int priority, int congestion_control, const char *encoding,
    const uint8_t *attachment, size_t attachment_len, uint64_t timestamp,
    void *context);

typedef void (*ZenohOnArgsCallback)(const char *value);

// Query callback with extended info
typedef void (*ZenohGetCallback)(const char *key, const uint8_t *value,
                                 size_t len, const char *kind, void *context);

// Extended query callback
typedef void (*ZenohGetCallbackEx)(const char *key, const uint8_t *value,
                                   size_t len, int sample_kind,
                                   const char *encoding,
                                   const uint8_t *attachment,
                                   size_t attachment_len, void *context);

// Query completion callback
typedef void (*ZenohGetCompleteCallback)(void *context);

typedef void (*ZenohQueryCallback)(const char *key, const char *selector,
                                   const uint8_t *value, size_t len,
                                   const char *kind, void *reply_context,
                                   void *user_context);

// Liveliness callback
typedef void (*ZenohLivelinessCallback)(const char *key, int is_alive,
                                        void *context);

// ============================================================================
// Library Management
// ============================================================================

FFI_PLUGIN_EXPORT int zenoh_init_logger(void);

// ============================================================================
// Session Management
// ============================================================================

FFI_PLUGIN_EXPORT ZenohSession *zenoh_open_session(const char *mode,
                                                   const char *endpoint);
FFI_PLUGIN_EXPORT ZenohSession *zenoh_open_session_with_config(
    const char *config_json);
FFI_PLUGIN_EXPORT void zenoh_close_session(ZenohSession *session);
FFI_PLUGIN_EXPORT const char *zenoh_session_info(ZenohSession *session);

// ============================================================================
// Publisher
// ============================================================================

FFI_PLUGIN_EXPORT ZenohPublisher *zenoh_declare_publisher(ZenohSession *session,
                                                          const char *key);
FFI_PLUGIN_EXPORT ZenohPublisher *zenoh_declare_publisher_with_options(
    ZenohSession *session, const char *key, ZenohPublisherOptions *options);
FFI_PLUGIN_EXPORT int zenoh_publisher_put(ZenohPublisher *publisher,
                                          const uint8_t *data, size_t len);
FFI_PLUGIN_EXPORT int zenoh_publisher_put_with_options(ZenohPublisher *publisher,
                                                       const uint8_t *data,
                                                       size_t len,
                                                       ZenohPutOptions *options);
FFI_PLUGIN_EXPORT int zenoh_publisher_delete(ZenohPublisher *publisher);
FFI_PLUGIN_EXPORT void zenoh_undeclare_publisher(ZenohPublisher *publisher);

// ============================================================================
// Subscriber
// ============================================================================

FFI_PLUGIN_EXPORT ZenohSubscriber *
zenoh_declare_subscriber(ZenohSession *session, const char *key,
                         ZenohSubscriberCallback callback, void *context);
FFI_PLUGIN_EXPORT ZenohSubscriber *zenoh_declare_subscriber_ex(
    ZenohSession *session, const char *key, ZenohSubscriberCallbackEx callback,
    void *context);
FFI_PLUGIN_EXPORT void zenoh_undeclare_subscriber(ZenohSubscriber *subscriber);

// ============================================================================
// Queryable
// ============================================================================

FFI_PLUGIN_EXPORT ZenohQueryable *
zenoh_declare_queryable(ZenohSession *session, const char *key_expr,
                        ZenohQueryCallback callback, void *context);
FFI_PLUGIN_EXPORT void zenoh_undeclare_queryable(ZenohQueryable *queryable);
FFI_PLUGIN_EXPORT void zenoh_query_reply(void *reply_context, const char *key,
                                         const uint8_t *data, size_t len);
FFI_PLUGIN_EXPORT void zenoh_query_reply_with_options(
    void *reply_context, const char *key, const uint8_t *data, size_t len,
    ZenohEncodingId encoding, const uint8_t *attachment, size_t attachment_len);

// ============================================================================
// Ad-hoc Operations
// ============================================================================

FFI_PLUGIN_EXPORT int zenoh_put(ZenohSession *session, const char *key,
                                const uint8_t *data, size_t len);
FFI_PLUGIN_EXPORT int zenoh_put_with_options(ZenohSession *session,
                                             const char *key,
                                             const uint8_t *data, size_t len,
                                             ZenohPutOptions *options);
FFI_PLUGIN_EXPORT int zenoh_delete(ZenohSession *session, const char *key);

// ============================================================================
// Query (Get)
// ============================================================================

FFI_PLUGIN_EXPORT void zenoh_get_async(ZenohSession *session,
                                       const char *selector,
                                       ZenohGetCallback callback,
                                       void *context);
FFI_PLUGIN_EXPORT void zenoh_get_async_with_options(
    ZenohSession *session, const char *selector, ZenohGetCallback callback,
    ZenohGetCompleteCallback complete_callback, void *context,
    ZenohGetOptions *options);

// ============================================================================
// Liveliness
// ============================================================================

FFI_PLUGIN_EXPORT ZenohLivelinessToken *
zenoh_declare_liveliness_token(ZenohSession *session, const char *key_expr);
FFI_PLUGIN_EXPORT void
zenoh_undeclare_liveliness_token(ZenohLivelinessToken *token);

FFI_PLUGIN_EXPORT ZenohSubscriber *zenoh_declare_liveliness_subscriber(
    ZenohSession *session, const char *key_expr,
    ZenohLivelinessCallback callback, void *context, bool history);

FFI_PLUGIN_EXPORT void zenoh_liveliness_get(ZenohSession *session,
                                            const char *key_expr,
                                            ZenohLivelinessCallback callback,
                                            void *context, uint64_t timeout_ms);

// ============================================================================
// Scouting
// ============================================================================

FFI_PLUGIN_EXPORT void zenoh_scout(const char *what, const char *config,
                                   void (*callback)(const char *info));

// ============================================================================
// Helpers
// ============================================================================

FFI_PLUGIN_EXPORT void zenoh_free_string(char *str);

// Default options initializers
FFI_PLUGIN_EXPORT void zenoh_publisher_options_default(
    ZenohPublisherOptions *options);
FFI_PLUGIN_EXPORT void zenoh_put_options_default(ZenohPutOptions *options);
FFI_PLUGIN_EXPORT void zenoh_get_options_default(ZenohGetOptions *options);

// Encoding helpers
FFI_PLUGIN_EXPORT const char *zenoh_encoding_to_string(ZenohEncodingId encoding);
FFI_PLUGIN_EXPORT ZenohEncodingId zenoh_encoding_from_string(const char *str);

#endif  // ZENOH_DART_H
