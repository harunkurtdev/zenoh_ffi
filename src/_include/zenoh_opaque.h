//
// Copyright (c) 2024 ZettaScale Technology
//
// This program and the accompanying materials are made available under the
// terms of the Eclipse Public License 2.0 which is available at
// http://www.eclipse.org/legal/epl-2.0, or the Apache License, Version 2.0
// which is available at https://www.apache.org/licenses/LICENSE-2.0.
//
// SPDX-License-Identifier: EPL-2.0 OR Apache-2.0
//
// Contributors:
//   ZettaScale Zenoh Team, <zenoh@zettascale.tech>
//
// clang-format off
#ifdef DOCS
#define ALIGN(n)
#define ZENOHC_API
#endif
/**
 * A loaned Zenoh data.
 */
typedef struct ALIGN(8) z_loaned_bytes_t {
  uint8_t _0[32];
} z_loaned_bytes_t;
/**
 * A Zenoh data.
 *
 * To minimize copies and reallocations, Zenoh may provide data in several separate buffers.
 */
typedef struct ALIGN(8) z_owned_bytes_t {
  uint8_t _0[32];
} z_owned_bytes_t;
/**
 * A loaned sequence of bytes.
 */
typedef struct ALIGN(8) z_loaned_slice_t {
  uint8_t _0[32];
} z_loaned_slice_t;
/**
 * A loaned string.
 */
typedef struct ALIGN(8) z_loaned_string_t {
  uint8_t _0[32];
} z_loaned_string_t;
typedef struct ALIGN(8) z_owned_slice_t {
  uint8_t _0[32];
} z_owned_slice_t;
/**
 * The wrapper type for strings allocated by Zenoh.
 */
typedef struct ALIGN(8) z_owned_string_t {
  uint8_t _0[32];
} z_owned_string_t;
/**
 * A contiguous sequence of bytes owned by some other entity.
 */
typedef struct ALIGN(8) z_view_slice_t {
  uint8_t _0[32];
} z_view_slice_t;
/**
 * A reader for payload.
 */
typedef struct ALIGN(8) z_bytes_reader_t {
  uint8_t _0[24];
} z_bytes_reader_t;
/**
 * An loaned writer for payload.
 */
typedef struct ALIGN(8) z_loaned_bytes_writer_t {
  uint8_t _0[56];
} z_loaned_bytes_writer_t;
/**
 * An owned writer for payload.
 */
typedef struct ALIGN(8) z_owned_bytes_writer_t {
  uint8_t _0[56];
} z_owned_bytes_writer_t;
/**
 * A loaned Zenoh session.
 */
typedef struct ALIGN(8) z_loaned_session_t {
  uint8_t _0[8];
} z_loaned_session_t;
/**
 * A loaned hello message.
 */
typedef struct ALIGN(8) z_loaned_hello_t {
  uint8_t _0[48];
} z_loaned_hello_t;
/**
 * Loaned closure.
 */
typedef struct z_loaned_closure_hello_t {
  size_t _0;
  size_t _1;
  size_t _2;
} z_loaned_closure_hello_t;
/**
 * A loaned Zenoh query.
 */
typedef struct ALIGN(8) z_loaned_query_t {
  uint8_t _0[136];
} z_loaned_query_t;
/**
 * Loaned closure.
 */
typedef struct z_loaned_closure_query_t {
  size_t _0;
  size_t _1;
  size_t _2;
} z_loaned_closure_query_t;
/**
 * A loaned reply.
 */
typedef struct ALIGN(8) z_loaned_reply_t {
  uint8_t _0[184];
} z_loaned_reply_t;
/**
 * Loaned closure.
 */
typedef struct z_loaned_closure_reply_t {
  size_t _0;
  size_t _1;
  size_t _2;
} z_loaned_closure_reply_t;
/**
 * A loaned Zenoh sample.
 */
typedef struct ALIGN(8) z_loaned_sample_t {
  uint8_t _0[184];
} z_loaned_sample_t;
/**
 * Loaned closure.
 */
typedef struct z_loaned_closure_sample_t {
  size_t _0;
  size_t _1;
  size_t _2;
} z_loaned_closure_sample_t;
/**
 * @brief A Zenoh ID.
 *
 * In general, valid Zenoh IDs are LSB-first 128bit unsigned and non-zero integers.
 */
typedef struct ALIGN(1) z_id_t {
  uint8_t id[16];
} z_id_t;
/**
 * @brief Loaned closure.
 */
typedef struct z_loaned_closure_zid_t {
  size_t _0;
  size_t _1;
  size_t _2;
} z_loaned_closure_zid_t;
/**
 * An owned conditional variable.
 *
 * Used in combination with `z_owned_mutex_t` to wake up thread when certain conditions are met.
 */
typedef struct ALIGN(8) z_owned_condvar_t {
  uint8_t _0[24];
} z_owned_condvar_t;
/**
 * A loaned conditional variable.
 */
typedef struct ALIGN(8) z_loaned_condvar_t {
  uint8_t _0[16];
} z_loaned_condvar_t;
/**
 * A loaned mutex.
 */
typedef struct ALIGN(8) z_loaned_mutex_t {
  uint8_t _0[32];
} z_loaned_mutex_t;
/**
 * An owned Zenoh configuration.
 */
typedef struct ALIGN(8) z_owned_config_t {
  uint8_t _0[1984];
} z_owned_config_t;
/**
 * A loaned Zenoh configuration.
 */
typedef struct ALIGN(8) z_loaned_config_t {
  uint8_t _0[1984];
} z_loaned_config_t;
/**
 * A loaned key expression.
 *
 * Key expressions can identify a single key or a set of keys.
 *
 * Examples :
 *    - ``"key/expression"``.
 *    - ``"key/ex*"``.
 *
 * Using `z_declare_keyexpr` allows Zenoh to optimize a key expression,
 * both for local processing and network-wise.
 */
typedef struct ALIGN(8) z_loaned_keyexpr_t {
  uint8_t _0[32];
} z_loaned_keyexpr_t;
/**
 * A Zenoh-allocated <a href="https://zenoh.io/docs/manual/abstractions/#key-expression"> key expression </a>.
 *
 * Key expressions can identify a single key or a set of keys.
 *
 * Examples :
 *    - ``"key/expression"``.
 *    - ``"key/ex*"``.
 *
 * Key expressions can be mapped to numerical ids through `z_declare_keyexpr`
 * for wire and computation efficiency.
 *
 * Internally key expressiobn can be either:
 *   - A plain string expression.
 *   - A pure numerical id.
 *   - The combination of a numerical prefix and a string suffix.
 */
typedef struct ALIGN(8) z_owned_keyexpr_t {
  uint8_t _0[32];
} z_owned_keyexpr_t;
/**
 * An owned Zenoh <a href="https://zenoh.io/docs/manual/abstractions/#publisher"> publisher </a>.
 */
typedef struct ALIGN(8) z_owned_publisher_t {
  uint8_t _0[104];
} z_owned_publisher_t;
/**
 * The <a href="https://zenoh.io/docs/manual/abstractions/#encoding"> encoding </a> of Zenoh data.
 */
typedef struct ALIGN(8) z_owned_encoding_t {
  uint8_t _0[40];
} z_owned_encoding_t;
/**
 * An owned Zenoh <a href="https://zenoh.io/docs/manual/abstractions/#queryable"> queryable </a>.
 *
 * Responds to queries sent via `z_get()` with intersecting key expression.
 */
typedef struct ALIGN(8) z_owned_queryable_t {
  uint8_t _0[48];
} z_owned_queryable_t;
/**
 * An owned Zenoh <a href="https://zenoh.io/docs/manual/abstractions/#subscriber"> subscriber </a>.
 *
 * Receives data from publication on intersecting key expressions.
 * Destroying the subscriber cancels the subscription.
 */
typedef struct ALIGN(8) z_owned_subscriber_t {
  uint8_t _0[48];
} z_owned_subscriber_t;
/**
 * A Zenoh <a href="https://zenoh.io/docs/manual/abstractions/#timestamp"> timestamp </a>.
 *
 * It consists of a time generated by a Hybrid Logical Clock (HLC) in NPT64 format and a unique zenoh identifier.
 */
typedef struct ALIGN(8) z_timestamp_t {
  uint8_t _0[24];
} z_timestamp_t;
/**
 * A loaned Zenoh encoding.
 */
typedef struct ALIGN(8) z_loaned_encoding_t {
  uint8_t _0[40];
} z_loaned_encoding_t;
/**
 * An owned Zenoh fifo query handler.
 */
typedef struct ALIGN(8) z_owned_fifo_handler_query_t {
  uint8_t _0[8];
} z_owned_fifo_handler_query_t;
/**
 * An owned Zenoh fifo reply handler.
 */
typedef struct ALIGN(8) z_owned_fifo_handler_reply_t {
  uint8_t _0[8];
} z_owned_fifo_handler_reply_t;
/**
 * An owned Zenoh fifo sample handler.
 */
typedef struct ALIGN(8) z_owned_fifo_handler_sample_t {
  uint8_t _0[8];
} z_owned_fifo_handler_sample_t;
/**
 * An loaned Zenoh fifo query handler.
 */
typedef struct ALIGN(8) z_loaned_fifo_handler_query_t {
  uint8_t _0[8];
} z_loaned_fifo_handler_query_t;
/**
 * An owned Zenoh query received by a queryable.
 *
 * Queries are atomically reference-counted, letting you extract them from the callback that handed them to you by cloning.
 */
typedef struct ALIGN(8) z_owned_query_t {
  uint8_t _0[136];
} z_owned_query_t;
/**
 * An loaned Zenoh fifo reply handler.
 */
typedef struct ALIGN(8) z_loaned_fifo_handler_reply_t {
  uint8_t _0[8];
} z_loaned_fifo_handler_reply_t;
/**
 * An owned reply from a Queryable to a `z_get()`.
 */
typedef struct ALIGN(8) z_owned_reply_t {
  uint8_t _0[184];
} z_owned_reply_t;
/**
 * An loaned Zenoh fifo sample handler.
 */
typedef struct ALIGN(8) z_loaned_fifo_handler_sample_t {
  uint8_t _0[8];
} z_loaned_fifo_handler_sample_t;
/**
 * An owned Zenoh sample.
 *
 * This is a read only type that can only be constructed by cloning a `z_loaned_sample_t`.
 * Like all owned types, it should be freed using z_drop or z_sample_drop.
 */
typedef struct ALIGN(8) z_owned_sample_t {
  uint8_t _0[184];
} z_owned_sample_t;
/**
 * An owned Zenoh-allocated hello message returned by a Zenoh entity to a scout message sent with `z_scout()`.
 */
typedef struct ALIGN(8) z_owned_hello_t {
  uint8_t _0[48];
} z_owned_hello_t;
/**
 * An array of maybe-owned non-null terminated strings.
 *
 */
typedef struct ALIGN(8) z_owned_string_array_t {
  uint8_t _0[24];
} z_owned_string_array_t;
/**
 * @brief A liveliness token that can be used to provide the network with information about connectivity to its
 * declarer: when constructed, a PUT sample will be received by liveliness subscribers on intersecting key
 * expressions.
 *
 * A DELETE on the token's key expression will be received by subscribers if the token is destroyed, or if connectivity between the subscriber and the token's creator is lost.
 */
typedef struct ALIGN(8) z_owned_liveliness_token_t {
  uint8_t _0[16];
} z_owned_liveliness_token_t;
/**
 * An owned mutex.
 */
typedef struct ALIGN(8) z_owned_mutex_t {
  uint8_t _0[32];
} z_owned_mutex_t;
/**
 * A Zenoh reply error - a combination of reply error payload and its encoding.
 */
typedef struct ALIGN(8) z_owned_reply_err_t {
  uint8_t _0[72];
} z_owned_reply_err_t;
/**
 * An owned Zenoh ring query handler.
 */
typedef struct ALIGN(8) z_owned_ring_handler_query_t {
  uint8_t _0[8];
} z_owned_ring_handler_query_t;
/**
 * An owned Zenoh ring reply handler.
 */
typedef struct ALIGN(8) z_owned_ring_handler_reply_t {
  uint8_t _0[8];
} z_owned_ring_handler_reply_t;
/**
 * An owned Zenoh ring sample handler.
 */
typedef struct ALIGN(8) z_owned_ring_handler_sample_t {
  uint8_t _0[8];
} z_owned_ring_handler_sample_t;
/**
 * An owned Zenoh session.
 */
typedef struct ALIGN(8) z_owned_session_t {
  uint8_t _0[8];
} z_owned_session_t;
/**
 * An owned Zenoh task.
 */
typedef struct ALIGN(8) z_owned_task_t {
  uint8_t _0[24];
} z_owned_task_t;
/**
 * The view over a string.
 */
typedef struct ALIGN(8) z_view_string_t {
  uint8_t _0[32];
} z_view_string_t;
typedef struct ALIGN(8) z_loaned_liveliness_token_t {
  uint8_t _0[16];
} z_loaned_liveliness_token_t;
/**
 * A loaned Zenoh publisher.
 */
typedef struct ALIGN(8) z_loaned_publisher_t {
  uint8_t _0[104];
} z_loaned_publisher_t;
/**
 * A loaned Zenoh queryable.
 */
typedef struct ALIGN(8) z_loaned_queryable_t {
  uint8_t _0[48];
} z_loaned_queryable_t;
/**
 * A loaned Zenoh reply error.
 */
typedef struct ALIGN(8) z_loaned_reply_err_t {
  uint8_t _0[72];
} z_loaned_reply_err_t;
/**
 * An loaned Zenoh ring query handler.
 */
typedef struct ALIGN(8) z_loaned_ring_handler_query_t {
  uint8_t _0[8];
} z_loaned_ring_handler_query_t;
/**
 * An loaned Zenoh ring reply handler.
 */
typedef struct ALIGN(8) z_loaned_ring_handler_reply_t {
  uint8_t _0[8];
} z_loaned_ring_handler_reply_t;
/**
 * An loaned Zenoh ring sample handler.
 */
typedef struct ALIGN(8) z_loaned_ring_handler_sample_t {
  uint8_t _0[8];
} z_loaned_ring_handler_sample_t;
/**
 * A loaned string array.
 */
typedef struct ALIGN(8) z_loaned_string_array_t {
  uint8_t _0[24];
} z_loaned_string_array_t;
/**
 * A loaned Zenoh subscriber.
 */
typedef struct ALIGN(8) z_loaned_subscriber_t {
  uint8_t _0[48];
} z_loaned_subscriber_t;
/**
 * A user allocated string, viewed as a key expression.
 */
typedef struct ALIGN(8) z_view_keyexpr_t {
  uint8_t _0[32];
} z_view_keyexpr_t;
/**
 * Loaned closure.
 */
typedef struct zc_loaned_closure_log_t {
  size_t _0;
  size_t _1;
  size_t _2;
} zc_loaned_closure_log_t;
/**
 * @brief A Zenoh serializer.
 */
typedef struct ALIGN(8) ze_deserializer_t {
  uint8_t _0[24];
} ze_deserializer_t;
/**
 * @brief An owned Zenoh serializer.
 */
typedef struct ALIGN(8) ze_owned_serializer_t {
  uint8_t _0[56];
} ze_owned_serializer_t;
/**
 * @brief A loaned Zenoh serializer.
 */
typedef struct ALIGN(8) ze_loaned_serializer_t {
  uint8_t _0[56];
} ze_loaned_serializer_t;
