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

// Forward declarations
typedef struct ZenohSession ZenohSession;
typedef struct ZenohPublisher ZenohPublisher;
typedef struct ZenohSubscriber ZenohSubscriber;
typedef struct ZenohQueryable ZenohQueryable;

// Callback Types
typedef void (*ZenohSubscriberCallback)(const char *key, const uint8_t *value,
                                        size_t len, const char *kind,
                                        const char *attachment, void *context);
typedef void (*ZenohOnArgsCallback)(const char *value);
typedef void (*ZenohGetCallback)(const char *key, const uint8_t *value,
                                 size_t len, const char *kind, void *context);
typedef void (*ZenohQueryCallback)(const char *key, const char *selector,
                                   const uint8_t *value, size_t len,
                                   const char *kind, void *reply_context,
                                   void *user_context);

// Library Management
FFI_PLUGIN_EXPORT int zenoh_init_logger(void);

// Session Management
FFI_PLUGIN_EXPORT ZenohSession *zenoh_open_session(const char *mode,
                                                   const char *endpoint);
FFI_PLUGIN_EXPORT void zenoh_close_session(ZenohSession *session);

// Publisher
FFI_PLUGIN_EXPORT ZenohPublisher *zenoh_declare_publisher(ZenohSession *session,
                                                          const char *key);
FFI_PLUGIN_EXPORT int zenoh_publisher_put(ZenohPublisher *publisher,
                                          const uint8_t *data, size_t len);
FFI_PLUGIN_EXPORT int zenoh_publisher_delete(ZenohPublisher *publisher);
FFI_PLUGIN_EXPORT void zenoh_undeclare_publisher(ZenohPublisher *publisher);

// Subscriber
FFI_PLUGIN_EXPORT ZenohSubscriber *
zenoh_declare_subscriber(ZenohSession *session, const char *key,
                         ZenohSubscriberCallback callback, void *context);
FFI_PLUGIN_EXPORT void zenoh_undeclare_subscriber(ZenohSubscriber *subscriber);

// Queryable
FFI_PLUGIN_EXPORT ZenohQueryable *
zenoh_declare_queryable(ZenohSession *session, const char *key_expr,
                        ZenohQueryCallback callback, void *context);
FFI_PLUGIN_EXPORT void zenoh_undeclare_queryable(ZenohQueryable *queryable);
FFI_PLUGIN_EXPORT void zenoh_query_reply(void *reply_context, const char *key,
                                         const uint8_t *data, size_t len);

// Ad-hoc Operations
FFI_PLUGIN_EXPORT int zenoh_put(ZenohSession *session, const char *key,
                                const uint8_t *data, size_t len);
FFI_PLUGIN_EXPORT int zenoh_delete(ZenohSession *session, const char *key);

// Query (Get)
FFI_PLUGIN_EXPORT void zenoh_get_async(ZenohSession *session,
                                       const char *selector,
                                       ZenohGetCallback callback,
                                       void *context);

// Scouting
FFI_PLUGIN_EXPORT void zenoh_scout(const char *what, const char *config,
                                   void (*callback)(const char *info));
// Query (Get)
FFI_PLUGIN_EXPORT void zenoh_get_async(ZenohSession *session,
                                       const char *selector,
                                       ZenohGetCallback callback,
                                       void *context);

// Helpers
FFI_PLUGIN_EXPORT void zenoh_free_string(char *str);

#endif // ZENOH_DART_H