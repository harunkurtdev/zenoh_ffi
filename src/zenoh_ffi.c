#include "zenoh_ffi.h"

// ============================================================================
// Struct definitions
// ============================================================================

struct ZenohSession {
  z_owned_session_t session;
};

struct ZenohPublisher {
  z_owned_publisher_t publisher;
};

struct ZenohSubscriber {
  z_owned_subscriber_t subscriber;
  ZenohSubscriberCallback callback;
  ZenohSubscriberCallbackEx callback_ex;
  void *context;
  bool is_liveliness;
  ZenohLivelinessCallback liveliness_callback;
};

struct ZenohQueryable {
  z_owned_queryable_t queryable;
  ZenohQueryCallback callback;
  void *context;
};

struct ZenohLivelinessToken {
  z_owned_liveliness_token_t token;
};

// ============================================================================
// Get Context for async queries
// ============================================================================

struct GetContext {
  ZenohGetCallback callback;
  ZenohGetCompleteCallback complete_callback;
  void *user_context;
  uint64_t timeout_ms;
};

// ============================================================================
// Liveliness Context
// ============================================================================

struct LivelinessContext {
  ZenohLivelinessCallback callback;
  void *user_context;
};

// ============================================================================
// Helper functions
// ============================================================================

static z_priority_t convert_priority(ZenohPriority priority) {
  switch (priority) {
  case ZENOH_PRIORITY_REAL_TIME:
    return Z_PRIORITY_REAL_TIME;
  case ZENOH_PRIORITY_INTERACTIVE_HIGH:
    return Z_PRIORITY_INTERACTIVE_HIGH;
  case ZENOH_PRIORITY_INTERACTIVE_LOW:
    return Z_PRIORITY_INTERACTIVE_LOW;
  case ZENOH_PRIORITY_DATA_HIGH:
    return Z_PRIORITY_DATA_HIGH;
  case ZENOH_PRIORITY_DATA:
    return Z_PRIORITY_DATA;
  case ZENOH_PRIORITY_DATA_LOW:
    return Z_PRIORITY_DATA_LOW;
  case ZENOH_PRIORITY_BACKGROUND:
    return Z_PRIORITY_BACKGROUND;
  default:
    return Z_PRIORITY_DATA;
  }
}

static z_congestion_control_t
convert_congestion_control(ZenohCongestionControl cc) {
  switch (cc) {
  case ZENOH_CONGESTION_CONTROL_BLOCK:
    return Z_CONGESTION_CONTROL_BLOCK;
  case ZENOH_CONGESTION_CONTROL_DROP:
    return Z_CONGESTION_CONTROL_DROP;
  // case ZENOH_CONGESTION_CONTROL_DROP_FIRST:
  //   return Z_CONGESTION_CONTROL_DROP_FIRST;
  default:
    return Z_CONGESTION_CONTROL_DROP;
  }
}

// Helper function to get all bytes data from z_loaned_bytes_t into a contiguous buffer.
// Uses the reader API to correctly handle fragmented (multi-slice) data.
// Caller must free the returned buffer.
static uint8_t* get_bytes_data(const z_loaned_bytes_t *bytes, size_t *out_len) {
  if (bytes == NULL) {
    *out_len = 0;
    return NULL;
  }

  *out_len = z_bytes_len(bytes);
  if (*out_len == 0) {
    return NULL;
  }

  uint8_t *buffer = (uint8_t *)malloc(*out_len);
  if (buffer == NULL) {
    *out_len = 0;
    return NULL;
  }

  z_bytes_reader_t reader = z_bytes_get_reader(bytes);
  z_bytes_reader_read(&reader, buffer, *out_len);

  return buffer;
}


static const z_loaned_encoding_t *get_encoding(ZenohEncodingId encoding) {
  switch (encoding) {
  case ZENOH_ENCODING_BYTES:
    return z_encoding_zenoh_bytes();
  case ZENOH_ENCODING_STRING:
    return z_encoding_zenoh_string();
  case ZENOH_ENCODING_JSON:
  case ZENOH_ENCODING_APPLICATION_JSON:
    return z_encoding_application_json();
  case ZENOH_ENCODING_TEXT_PLAIN:
    return z_encoding_text_plain();
  case ZENOH_ENCODING_TEXT_JSON:
    return z_encoding_text_json();
  case ZENOH_ENCODING_TEXT_HTML:
    return z_encoding_text_html();
  case ZENOH_ENCODING_TEXT_XML:
    return z_encoding_text_xml();
  case ZENOH_ENCODING_TEXT_CSS:
    return z_encoding_text_css();
  case ZENOH_ENCODING_TEXT_CSV:
    return z_encoding_text_csv();
  case ZENOH_ENCODING_TEXT_JAVASCRIPT:
    return z_encoding_text_javascript();
  case ZENOH_ENCODING_IMAGE_PNG:
    return z_encoding_image_png();
  case ZENOH_ENCODING_IMAGE_JPEG:
    return z_encoding_image_jpeg();
  case ZENOH_ENCODING_IMAGE_GIF:
    return z_encoding_image_gif();
  case ZENOH_ENCODING_IMAGE_BMP:
    return z_encoding_image_bmp();
  case ZENOH_ENCODING_IMAGE_WEBP:
    return z_encoding_image_webp();
  case ZENOH_ENCODING_APPLICATION_OCTET_STREAM:
    return z_encoding_application_octet_stream();
  case ZENOH_ENCODING_APPLICATION_XML:
    return z_encoding_application_xml();
  case ZENOH_ENCODING_APPLICATION_CBOR:
    return z_encoding_application_cbor();
  case ZENOH_ENCODING_APPLICATION_YAML:
    return z_encoding_application_yaml();
  case ZENOH_ENCODING_APPLICATION_PROTOBUF:
    return z_encoding_application_protobuf();
  case ZENOH_ENCODING_APPLICATION_CDR:
    return z_encoding_application_cdr();
  default:
    return z_encoding_zenoh_bytes();
  }
}

// ============================================================================
// Initialization
// ============================================================================

FFI_PLUGIN_EXPORT int zenoh_init_logger(void) {
  zc_try_init_log_from_env();
  return 0;
}

FFI_PLUGIN_EXPORT void zenoh_free_string(char *str) {
  if (str != NULL) {
    free(str);
  }
}

// ============================================================================
// Default Options Initializers
// ============================================================================

FFI_PLUGIN_EXPORT void
zenoh_publisher_options_default(ZenohPublisherOptions *options) {
  if (options == NULL)
    return;
  options->priority = ZENOH_PRIORITY_DATA;
  options->congestion_control = ZENOH_CONGESTION_CONTROL_DROP;
  options->encoding = ZENOH_ENCODING_BYTES;
  options->encoding_schema = NULL;
  options->is_express = false;
}

FFI_PLUGIN_EXPORT void zenoh_put_options_default(ZenohPutOptions *options) {
  if (options == NULL)
    return;
  options->priority = ZENOH_PRIORITY_DATA;
  options->congestion_control = ZENOH_CONGESTION_CONTROL_DROP;
  options->encoding = ZENOH_ENCODING_BYTES;
  options->encoding_schema = NULL;
  options->attachment = NULL;
  options->attachment_len = 0;
  options->is_express = false;
}

FFI_PLUGIN_EXPORT void zenoh_get_options_default(ZenohGetOptions *options) {
  if (options == NULL)
    return;
  options->timeout_ms = 10000; // 10 seconds default
  options->priority = ZENOH_PRIORITY_DATA;
  options->congestion_control = ZENOH_CONGESTION_CONTROL_DROP;
  options->payload = NULL;
  options->payload_len = 0;
  options->encoding = ZENOH_ENCODING_BYTES;
  options->attachment = NULL;
  options->attachment_len = 0;
}

// ============================================================================
// Encoding Helpers
// ============================================================================

FFI_PLUGIN_EXPORT const char *zenoh_encoding_to_string(ZenohEncodingId encoding) {
  switch (encoding) {
  case ZENOH_ENCODING_EMPTY:
    return "empty";
  case ZENOH_ENCODING_BYTES:
    return "zenoh/bytes";
  case ZENOH_ENCODING_STRING:
    return "zenoh/string";
  case ZENOH_ENCODING_JSON:
    return "application/json";
  case ZENOH_ENCODING_TEXT_PLAIN:
    return "text/plain";
  case ZENOH_ENCODING_TEXT_JSON:
    return "text/json";
  case ZENOH_ENCODING_TEXT_HTML:
    return "text/html";
  case ZENOH_ENCODING_TEXT_XML:
    return "text/xml";
  case ZENOH_ENCODING_TEXT_CSS:
    return "text/css";
  case ZENOH_ENCODING_TEXT_CSV:
    return "text/csv";
  case ZENOH_ENCODING_TEXT_JAVASCRIPT:
    return "text/javascript";
  case ZENOH_ENCODING_IMAGE_PNG:
    return "image/png";
  case ZENOH_ENCODING_IMAGE_JPEG:
    return "image/jpeg";
  case ZENOH_ENCODING_IMAGE_GIF:
    return "image/gif";
  case ZENOH_ENCODING_IMAGE_BMP:
    return "image/bmp";
  case ZENOH_ENCODING_IMAGE_WEBP:
    return "image/webp";
  case ZENOH_ENCODING_APPLICATION_OCTET_STREAM:
    return "application/octet-stream";
  case ZENOH_ENCODING_APPLICATION_JSON:
    return "application/json";
  case ZENOH_ENCODING_APPLICATION_XML:
    return "application/xml";
  case ZENOH_ENCODING_APPLICATION_CBOR:
    return "application/cbor";
  case ZENOH_ENCODING_APPLICATION_YAML:
    return "application/yaml";
  case ZENOH_ENCODING_APPLICATION_PROTOBUF:
    return "application/protobuf";
  case ZENOH_ENCODING_APPLICATION_CDR:
    return "application/cdr";
  default:
    return "unknown";
  }
}

FFI_PLUGIN_EXPORT ZenohEncodingId zenoh_encoding_from_string(const char *str) {
  if (str == NULL)
    return ZENOH_ENCODING_EMPTY;
  if (strcmp(str, "zenoh/bytes") == 0)
    return ZENOH_ENCODING_BYTES;
  if (strcmp(str, "zenoh/string") == 0)
    return ZENOH_ENCODING_STRING;
  if (strcmp(str, "application/json") == 0)
    return ZENOH_ENCODING_APPLICATION_JSON;
  if (strcmp(str, "text/plain") == 0)
    return ZENOH_ENCODING_TEXT_PLAIN;
  if (strcmp(str, "text/json") == 0)
    return ZENOH_ENCODING_TEXT_JSON;
  if (strcmp(str, "text/html") == 0)
    return ZENOH_ENCODING_TEXT_HTML;
  if (strcmp(str, "text/xml") == 0)
    return ZENOH_ENCODING_TEXT_XML;
  if (strcmp(str, "text/css") == 0)
    return ZENOH_ENCODING_TEXT_CSS;
  if (strcmp(str, "text/csv") == 0)
    return ZENOH_ENCODING_TEXT_CSV;
  if (strcmp(str, "text/javascript") == 0)
    return ZENOH_ENCODING_TEXT_JAVASCRIPT;
  if (strcmp(str, "image/png") == 0)
    return ZENOH_ENCODING_IMAGE_PNG;
  if (strcmp(str, "image/jpeg") == 0)
    return ZENOH_ENCODING_IMAGE_JPEG;
  if (strcmp(str, "image/gif") == 0)
    return ZENOH_ENCODING_IMAGE_GIF;
  if (strcmp(str, "image/bmp") == 0)
    return ZENOH_ENCODING_IMAGE_BMP;
  if (strcmp(str, "image/webp") == 0)
    return ZENOH_ENCODING_IMAGE_WEBP;
  if (strcmp(str, "application/octet-stream") == 0)
    return ZENOH_ENCODING_APPLICATION_OCTET_STREAM;
  if (strcmp(str, "application/xml") == 0)
    return ZENOH_ENCODING_APPLICATION_XML;
  if (strcmp(str, "application/cbor") == 0)
    return ZENOH_ENCODING_APPLICATION_CBOR;
  if (strcmp(str, "application/yaml") == 0)
    return ZENOH_ENCODING_APPLICATION_YAML;
  if (strcmp(str, "application/protobuf") == 0)
    return ZENOH_ENCODING_APPLICATION_PROTOBUF;
  if (strcmp(str, "application/cdr") == 0)
    return ZENOH_ENCODING_APPLICATION_CDR;
  return ZENOH_ENCODING_CUSTOM;
}

// ============================================================================
// Session Management
// ============================================================================

FFI_PLUGIN_EXPORT ZenohSession *zenoh_open_session(const char *mode,
                                                   const char *endpoints) {
  z_owned_config_t config;
  z_config_default(&config);

  printf("[zenoh_ffi] open_session: mode='%s', endpoints='%s'\n",
         mode ? mode : "NULL", endpoints ? endpoints : "NULL");

  // Set mode - must be quoted for JSON5 (e.g. "\"peer\"")
  if (mode != NULL) {
    char mode_json[64];
    snprintf(mode_json, sizeof(mode_json), "\"%s\"", mode);
    int rc = zc_config_insert_json5(z_loan_mut(config), Z_CONFIG_MODE_KEY, mode_json);
    printf("[zenoh_ffi] set mode '%s' (json: %s) -> rc=%d\n", mode, mode_json, rc);
  }

  // Set endpoints (if provided) - always use connect key
  // In peer mode, endpoints are peers to connect TO (not listen on)
  // Listening is handled separately or via scouting
  if (endpoints != NULL && strlen(endpoints) > 0) {
    int rc = zc_config_insert_json5(z_loan_mut(config), Z_CONFIG_CONNECT_KEY,
                           endpoints);
    printf("[zenoh_ffi] set connect endpoints '%s' -> rc=%d\n", endpoints, rc);
  }

// MacOS multicast fix
#if defined(__APPLE__)
  zc_config_insert_json5(z_loan_mut(config), Z_CONFIG_MULTICAST_SCOUTING_KEY,
                         "false");
#endif

  z_owned_session_t s;
  printf("[zenoh_ffi] calling z_open...\n");
  int open_rc = z_open(&s, z_move(config), NULL);
  printf("[zenoh_ffi] z_open returned %d\n", open_rc);
  if (open_rc < 0) {
    return NULL;
  }

  ZenohSession *session = (ZenohSession *)malloc(sizeof(ZenohSession));
  if (session == NULL) {
    z_drop(z_move(s));
    return NULL;
  }
  session->session = s;
  return session;
}

FFI_PLUGIN_EXPORT ZenohSession *
zenoh_open_session_with_config(const char *config_json) {
  if (config_json == NULL)
    return NULL;

  z_owned_config_t config;
  if (zc_config_from_str(&config, config_json) < 0) {
    return NULL;
  }

  z_owned_session_t s;
  if (z_open(&s, z_move(config), NULL) < 0) {
    return NULL;
  }

  ZenohSession *session = (ZenohSession *)malloc(sizeof(ZenohSession));
  if (session == NULL) {
    z_drop(z_move(s));
    return NULL;
  }
  session->session = s;
  return session;
}

FFI_PLUGIN_EXPORT void zenoh_close_session(ZenohSession *session) {
  if (session != NULL) {
    z_drop(z_move(session->session));
    free(session);
  }
}

FFI_PLUGIN_EXPORT const char *zenoh_session_info(ZenohSession *session) {
  if (session == NULL)
    return NULL;

  z_id_t zid = z_info_zid(z_loan(session->session));

  // Convert zid to hex string
  char *result = (char *)malloc(37); // 16 bytes * 2 + separators + null
  if (result == NULL)
    return NULL;

  snprintf(result, 37, "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
           zid.id[0], zid.id[1], zid.id[2], zid.id[3], zid.id[4], zid.id[5],
           zid.id[6], zid.id[7], zid.id[8], zid.id[9], zid.id[10], zid.id[11],
           zid.id[12], zid.id[13], zid.id[14], zid.id[15]);

  return result;
}

// ============================================================================
// Publisher
// ============================================================================

FFI_PLUGIN_EXPORT ZenohPublisher *zenoh_declare_publisher(ZenohSession *session,
                                                          const char *key) {
  if (session == NULL || key == NULL)
    return NULL;

  z_view_keyexpr_t keyexpr;
  if (z_view_keyexpr_from_str(&keyexpr, key) < 0) {
    return NULL;
  }

  z_publisher_options_t options;
  z_publisher_options_default(&options);

  z_owned_publisher_t pub;
  if (z_declare_publisher(z_loan(session->session), &pub, z_loan(keyexpr),
                          &options) < 0) {
    return NULL;
  }

  ZenohPublisher *publisher = (ZenohPublisher *)malloc(sizeof(ZenohPublisher));
  if (publisher == NULL) {
    z_drop(z_move(pub));
    return NULL;
  }
  publisher->publisher = pub;
  return publisher;
}

FFI_PLUGIN_EXPORT ZenohPublisher *zenoh_declare_publisher_with_options(
    ZenohSession *session, const char *key, ZenohPublisherOptions *opts) {
  if (session == NULL || key == NULL)
    return NULL;

  z_view_keyexpr_t keyexpr;
  if (z_view_keyexpr_from_str(&keyexpr, key) < 0) {
    return NULL;
  }

  z_publisher_options_t options;
  z_publisher_options_default(&options);

  if (opts != NULL) {
    options.priority = convert_priority(opts->priority);
    options.congestion_control = convert_congestion_control(opts->congestion_control);
    options.is_express = opts->is_express;

    // Set encoding
    z_owned_encoding_t encoding;
    z_encoding_clone(&encoding, get_encoding(opts->encoding));
    options.encoding = z_encoding_move(&encoding);
  }

  z_owned_publisher_t pub;
  if (z_declare_publisher(z_loan(session->session), &pub, z_loan(keyexpr),
                          &options) < 0) {
    return NULL;
  }

  ZenohPublisher *publisher = (ZenohPublisher *)malloc(sizeof(ZenohPublisher));
  if (publisher == NULL) {
    z_drop(z_move(pub));
    return NULL;
  }
  publisher->publisher = pub;
  return publisher;
}

FFI_PLUGIN_EXPORT int zenoh_publisher_put(ZenohPublisher *publisher,
                                          const uint8_t *data, size_t len) {
  if (publisher == NULL)
    return -1;

  z_publisher_put_options_t options;
  z_publisher_put_options_default(&options);

  z_owned_bytes_t payload;
  z_bytes_copy_from_buf(&payload, data, len);

  int rc = z_publisher_put(z_loan(publisher->publisher), z_move(payload),
                         &options);
  printf("[zenoh_ffi] publisher_put(%zu bytes) -> rc=%d\n", len, rc);
  return rc;
}

FFI_PLUGIN_EXPORT int zenoh_publisher_put_with_options(ZenohPublisher *publisher,
                                                       const uint8_t *data,
                                                       size_t len,
                                                       ZenohPutOptions *opts) {
  if (publisher == NULL)
    return -1;

  z_publisher_put_options_t options;
  z_publisher_put_options_default(&options);

  if (opts != NULL) {
    // Set encoding
    z_owned_encoding_t encoding;
    z_encoding_clone(&encoding, get_encoding(opts->encoding));
    options.encoding = z_encoding_move(&encoding);

    // Set attachment if provided
    if (opts->attachment != NULL && opts->attachment_len > 0) {
      z_owned_bytes_t attachment;
      z_bytes_copy_from_buf(&attachment, opts->attachment, opts->attachment_len);
      options.attachment = z_bytes_move(&attachment);
    }
  }

  z_owned_bytes_t payload;
  z_bytes_copy_from_buf(&payload, data, len);

  return z_publisher_put(z_loan(publisher->publisher), z_move(payload),
                         &options);
}

FFI_PLUGIN_EXPORT int zenoh_publisher_delete(ZenohPublisher *publisher) {
  if (publisher == NULL)
    return -1;

  z_publisher_delete_options_t options;
  z_publisher_delete_options_default(&options);

  return z_publisher_delete(z_loan(publisher->publisher), &options);
}

FFI_PLUGIN_EXPORT void zenoh_undeclare_publisher(ZenohPublisher *publisher) {
  if (publisher != NULL) {
    z_drop(z_move(publisher->publisher));
    free(publisher);
  }
}

// ============================================================================
// Subscriber Callbacks
// ============================================================================

static void subscriber_data_handler(z_loaned_sample_t *sample,
                                    void *arg) {
  ZenohSubscriber *sub = (ZenohSubscriber *)arg;
  if (sub == NULL || sub->callback == NULL)
    return;

  // Get Key - null-terminated heap copy (Dart will free via zenoh_free_string)
  z_view_string_t key_str;
  z_keyexpr_as_view_string(z_sample_keyexpr(sample), &key_str);
  size_t key_len = z_string_len(z_loan(key_str));
  char *key = (char *)malloc(key_len + 1);
  if (key == NULL) return;
  memcpy(key, z_string_data(z_loan(key_str)), key_len);
  key[key_len] = '\0';

  // Get Kind - heap copy (Dart will free)
  z_sample_kind_t kind = z_sample_kind(sample);
  const char *kind_literal = (kind == Z_SAMPLE_KIND_DELETE) ? "DELETE" : "PUT";
  size_t kind_len = strlen(kind_literal);
  char *kind_str = (char *)malloc(kind_len + 1);
  if (kind_str == NULL) { free(key); return; }
  memcpy(kind_str, kind_literal, kind_len + 1);

  // Get Payload - heap copy (Dart will free)
  const z_loaned_bytes_t *payload = z_sample_payload(sample);
  size_t len = 0;
  uint8_t *data = NULL;
  z_owned_string_t payload_string;
  if (z_bytes_to_string(payload, &payload_string) == 0) {
    len = z_string_len(z_loan(payload_string));
    data = (uint8_t *)malloc(len);
    if (data != NULL) {
      memcpy(data, z_string_data(z_loan(payload_string)), len);
    }
    z_drop(z_move(payload_string));
  } else {
    data = get_bytes_data(payload, &len);
  }

  // Get Attachment - heap copy (Dart will free)
  const z_loaned_bytes_t *attachment_bytes = z_sample_attachment(sample);
  char *attachment_str = (char *)malloc(1);
  if (attachment_str == NULL) { free(key); free(kind_str); free(data); return; }
  attachment_str[0] = '\0';
  if (attachment_bytes != NULL && z_bytes_len(attachment_bytes) > 0) {
    z_owned_string_t att_string;
    if (z_bytes_to_string(attachment_bytes, &att_string) == 0) {
      size_t att_len = z_string_len(z_loan(att_string));
      free(attachment_str);
      attachment_str = (char *)malloc(att_len + 1);
      if (attachment_str != NULL) {
        memcpy(attachment_str, z_string_data(z_loan(att_string)), att_len);
        attachment_str[att_len] = '\0';
      }
      z_drop(z_move(att_string));
    }
  }

  printf("[zenoh_ffi] subscriber_data_handler: key='%s', len=%zu, kind='%s'\n",
         key, len, kind_str);

  // DO NOT FREE - NativeCallable.listener is async, Dart will free these
  sub->callback(key, data, len, kind_str, attachment_str, sub->context);
}

static void subscriber_data_handler_ex(z_loaned_sample_t *sample,
                                       void *arg) {
  ZenohSubscriber *sub = (ZenohSubscriber *)arg;
  if (sub == NULL || sub->callback_ex == NULL)
    return;

  // Get Key - heap copy (Dart will free)
  z_view_string_t key_str;
  z_keyexpr_as_view_string(z_sample_keyexpr(sample), &key_str);
  size_t key_len = z_string_len(z_loan(key_str));
  char *key = (char *)malloc(key_len + 1);
  if (key == NULL) return;
  memcpy(key, z_string_data(z_loan(key_str)), key_len);
  key[key_len] = '\0';

  // Get Kind
  int sample_kind = (z_sample_kind(sample) == Z_SAMPLE_KIND_DELETE) ? 1 : 0;

  // Get Priority and Congestion Control
  int priority = (int)z_sample_priority(sample);
  int congestion = (int)z_sample_congestion_control(sample);

  // Get Encoding - heap copy (Dart will free)
  const z_loaned_encoding_t *enc = z_sample_encoding(sample);
  z_owned_string_t enc_str;
  z_encoding_to_string(enc, &enc_str);
  size_t enc_len = z_string_len(z_loan(enc_str));
  char *encoding = (char *)malloc(enc_len + 1);
  if (encoding == NULL) { free(key); z_drop(z_move(enc_str)); return; }
  memcpy(encoding, z_string_data(z_loan(enc_str)), enc_len);
  encoding[enc_len] = '\0';
  z_drop(z_move(enc_str));

  // Get Payload - heap copy (Dart will free)
  const z_loaned_bytes_t *payload = z_sample_payload(sample);
  z_owned_string_t payload_string;
  size_t len = 0;
  uint8_t *data = NULL;
  if (z_bytes_to_string(payload, &payload_string) == 0) {
    len = z_string_len(z_loan(payload_string));
    data = (uint8_t *)malloc(len);
    if (data != NULL) {
      memcpy(data, z_string_data(z_loan(payload_string)), len);
    }
    z_drop(z_move(payload_string));
  } else {
    data = get_bytes_data(payload, &len);
  }

  // Get Attachment - heap copy (Dart will free)
  const z_loaned_bytes_t *attachment_bytes = z_sample_attachment(sample);
  size_t attachment_len = 0;
  uint8_t *attachment = get_bytes_data(attachment_bytes, &attachment_len);

  // Get Timestamp (simplified - just use 0 for now)
  uint64_t timestamp = 0;

  // DO NOT FREE - NativeCallable.listener is async, Dart will free these
  sub->callback_ex(key, data, len, sample_kind, priority, congestion, encoding,
                   attachment, attachment_len, timestamp, sub->context);
}

static void drop_subscriber_wrapper(void *arg) {
  // Context cleanup handled elsewhere
}

FFI_PLUGIN_EXPORT ZenohSubscriber *
zenoh_declare_subscriber(ZenohSession *session, const char *key,
                         ZenohSubscriberCallback callback, void *context) {
  if (session == NULL || key == NULL)
    return NULL;

  z_view_keyexpr_t keyexpr;
  if (z_view_keyexpr_from_str(&keyexpr, key) < 0)
    return NULL;

  ZenohSubscriber *sub = (ZenohSubscriber *)malloc(sizeof(ZenohSubscriber));
  if (sub == NULL)
    return NULL;

  sub->callback = callback;
  sub->callback_ex = NULL;
  sub->context = context;
  sub->is_liveliness = false;
  sub->liveliness_callback = NULL;

  z_subscriber_options_t options;
  z_subscriber_options_default(&options);

  z_owned_closure_sample_t closure;
  z_closure_sample(&closure, subscriber_data_handler, drop_subscriber_wrapper,
                   sub);

  if (z_declare_subscriber(z_loan(session->session), &sub->subscriber,
                           z_loan(keyexpr), z_move(closure), &options) < 0) {
    free(sub);
    return NULL;
  }

  return sub;
}

FFI_PLUGIN_EXPORT ZenohSubscriber *zenoh_declare_subscriber_ex(
    ZenohSession *session, const char *key, ZenohSubscriberCallbackEx callback,
    void *context) {
  if (session == NULL || key == NULL)
    return NULL;

  z_view_keyexpr_t keyexpr;
  if (z_view_keyexpr_from_str(&keyexpr, key) < 0)
    return NULL;

  ZenohSubscriber *sub = (ZenohSubscriber *)malloc(sizeof(ZenohSubscriber));
  if (sub == NULL)
    return NULL;

  sub->callback = NULL;
  sub->callback_ex = callback;
  sub->context = context;
  sub->is_liveliness = false;
  sub->liveliness_callback = NULL;

  z_subscriber_options_t options;
  z_subscriber_options_default(&options);

  z_owned_closure_sample_t closure;
  z_closure_sample(&closure, subscriber_data_handler_ex, drop_subscriber_wrapper,
                   sub);

  if (z_declare_subscriber(z_loan(session->session), &sub->subscriber,
                           z_loan(keyexpr), z_move(closure), &options) < 0) {
    free(sub);
    return NULL;
  }

  return sub;
}

FFI_PLUGIN_EXPORT void zenoh_undeclare_subscriber(ZenohSubscriber *subscriber) {
  if (subscriber != NULL) {
    z_drop(z_move(subscriber->subscriber));
    free(subscriber);
  }
}

// ============================================================================
// Ad-hoc Operations
// ============================================================================

FFI_PLUGIN_EXPORT int zenoh_put(ZenohSession *session, const char *key,
                                const uint8_t *data, size_t len) {
  if (session == NULL || key == NULL)
    return -1;

  z_view_keyexpr_t keyexpr;
  if (z_view_keyexpr_from_str(&keyexpr, key) < 0) {
    printf("[zenoh_ffi] zenoh_put: invalid keyexpr '%s'\n", key);
    return -1;
  }

  z_put_options_t options;
  z_put_options_default(&options);

  z_owned_bytes_t payload;
  z_bytes_copy_from_buf(&payload, data, len);

  int rc = z_put(z_loan(session->session), z_loan(keyexpr), z_move(payload),
               &options);
  printf("[zenoh_ffi] zenoh_put('%s', %zu bytes) -> rc=%d\n", key, len, rc);
  return rc;
}

FFI_PLUGIN_EXPORT int zenoh_put_with_options(ZenohSession *session,
                                             const char *key,
                                             const uint8_t *data, size_t len,
                                             ZenohPutOptions *opts) {
  if (session == NULL || key == NULL)
    return -1;

  z_view_keyexpr_t keyexpr;
  if (z_view_keyexpr_from_str(&keyexpr, key) < 0)
    return -1;

  z_put_options_t options;
  z_put_options_default(&options);

  if (opts != NULL) {
    options.priority = convert_priority(opts->priority);
    options.congestion_control = convert_congestion_control(opts->congestion_control);
    options.is_express = opts->is_express;

    // Set encoding
    z_owned_encoding_t encoding;
    z_encoding_clone(&encoding, get_encoding(opts->encoding));
    options.encoding = z_encoding_move(&encoding);

    // Set attachment
    if (opts->attachment != NULL && opts->attachment_len > 0) {
      z_owned_bytes_t attachment;
      z_bytes_copy_from_buf(&attachment, opts->attachment, opts->attachment_len);
      options.attachment = z_bytes_move(&attachment);
    }
  }

  z_owned_bytes_t payload;
  z_bytes_copy_from_buf(&payload, data, len);

  return z_put(z_loan(session->session), z_loan(keyexpr), z_move(payload),
               &options);
}

FFI_PLUGIN_EXPORT int zenoh_delete(ZenohSession *session, const char *key) {
  if (session == NULL || key == NULL)
    return -1;

  z_view_keyexpr_t keyexpr;
  if (z_view_keyexpr_from_str(&keyexpr, key) < 0)
    return -1;

  z_delete_options_t options;
  z_delete_options_default(&options);

  return z_delete(z_loan(session->session), z_loan(keyexpr), &options);
}

// ============================================================================
// Query (Get)
// ============================================================================

static void get_reply_handler(struct z_loaned_reply_t *reply, void *arg) {
  struct GetContext *ctx = (struct GetContext *)arg;
  if (ctx == NULL || ctx->callback == NULL)
    return;

  if (z_reply_is_ok(reply)) {
    const z_loaned_sample_t *sample = z_reply_ok(reply);

    // Key - null-terminated copy
    z_view_string_t key_str;
    z_keyexpr_as_view_string(z_sample_keyexpr(sample), &key_str);
    size_t key_len = z_string_len(z_loan(key_str));
    char *key = (char *)malloc(key_len + 1);
    if (key == NULL) return;
    memcpy(key, z_string_data(z_loan(key_str)), key_len);
    key[key_len] = '\0';

    // Payload
    const z_loaned_bytes_t *payload = z_sample_payload(sample);
    z_owned_string_t payload_string;
    size_t len = 0;
    uint8_t *data = NULL;
    if (z_bytes_to_string(payload, &payload_string) == 0) {
      len = z_string_len(z_loan(payload_string));
      data = (uint8_t *)malloc(len);
      if (data != NULL) {
        memcpy(data, z_string_data(z_loan(payload_string)), len);
      }
      z_drop(z_move(payload_string));
    } else {
      data = get_bytes_data(payload, &len);
    }

    // Kind - heap copy (Dart will free)
    const char *kind_literal = (z_sample_kind(sample) == Z_SAMPLE_KIND_DELETE) ? "DELETE" : "PUT";
    size_t kind_len = strlen(kind_literal);
    char *kind_str = (char *)malloc(kind_len + 1);
    if (kind_str == NULL) { free(key); free(data); return; }
    memcpy(kind_str, kind_literal, kind_len + 1);

    // DO NOT FREE - NativeCallable.listener is async, Dart will free these
    ctx->callback(key, data, len, kind_str, ctx->user_context);
  }
}

static void drop_get_context(void *arg) {
  struct GetContext *ctx = (struct GetContext *)arg;
  if (ctx != NULL) {
    // Call completion callback if provided
    if (ctx->complete_callback != NULL) {
      ctx->complete_callback(ctx->user_context);
    }
    free(ctx);
  }
}

FFI_PLUGIN_EXPORT void zenoh_get_async(ZenohSession *session,
                                       const char *selector,
                                       ZenohGetCallback callback,
                                       void *context) {
  ZenohGetOptions opts;
  zenoh_get_options_default(&opts);
  zenoh_get_async_with_options(session, selector, callback, NULL, context,
                               &opts);
}

FFI_PLUGIN_EXPORT void zenoh_get_async_with_options(
    ZenohSession *session, const char *selector, ZenohGetCallback callback,
    ZenohGetCompleteCallback complete_callback, void *context,
    ZenohGetOptions *opts) {
  if (session == NULL || selector == NULL)
    return;

  z_view_keyexpr_t keyexpr;
  if (z_view_keyexpr_from_str(&keyexpr, selector) < 0)
    return;

  struct GetContext *ctx =
      (struct GetContext *)malloc(sizeof(struct GetContext));
  if (ctx == NULL)
    return;

  ctx->callback = callback;
  ctx->complete_callback = complete_callback;
  ctx->user_context = context;
  ctx->timeout_ms = opts ? opts->timeout_ms : 10000;

  z_get_options_t options;
  z_get_options_default(&options);

  if (opts != NULL) {
    options.timeout_ms = opts->timeout_ms;
    options.priority = convert_priority(opts->priority);
    options.congestion_control = convert_congestion_control(opts->congestion_control);

    // Set payload if provided
    if (opts->payload != NULL && opts->payload_len > 0) {
      z_owned_bytes_t payload;
      z_bytes_copy_from_buf(&payload, opts->payload, opts->payload_len);
      options.payload = z_bytes_move(&payload);

      // Set encoding
      z_owned_encoding_t encoding;
      z_encoding_clone(&encoding, get_encoding(opts->encoding));
      options.encoding = z_encoding_move(&encoding);
    }

    // Set attachment
    if (opts->attachment != NULL && opts->attachment_len > 0) {
      z_owned_bytes_t attachment;
      z_bytes_copy_from_buf(&attachment, opts->attachment, opts->attachment_len);
      options.attachment = z_bytes_move(&attachment);
    }
  }

  z_owned_closure_reply_t closure;
  z_closure_reply(&closure, get_reply_handler, drop_get_context, ctx);

  z_get(z_loan(session->session), z_loan(keyexpr), "", z_move(closure),
        &options);
}

// ============================================================================
// Queryable
// ============================================================================

static void query_handler(z_loaned_query_t *query, void *arg) {
  ZenohQueryable *q = (ZenohQueryable *)arg;
  if (q == NULL || q->callback == NULL)
    return;

  // Get Key Selector - null-terminated copy
  const z_loaned_keyexpr_t *keyexpr = z_query_keyexpr(query);
  z_view_string_t key_str;
  z_keyexpr_as_view_string(keyexpr, &key_str);
  size_t key_len = z_string_len(z_loan(key_str));
  char *key = (char *)malloc(key_len + 1);
  if (key == NULL) return;
  memcpy(key, z_string_data(z_loan(key_str)), key_len);
  key[key_len] = '\0';

  // Get Selector (parameters) - null-terminated copy
  z_view_string_t selector_str;
  z_query_parameters(query, &selector_str);
  size_t sel_len = z_string_len(z_loan(selector_str));
  char *selector = (char *)malloc(sel_len + 1);
  if (selector == NULL) { free(key); return; }
  memcpy(selector, z_string_data(z_loan(selector_str)), sel_len);
  selector[sel_len] = '\0';

  // Get Payload (Value)
  const z_loaned_bytes_t *payload = z_query_payload(query);
  size_t len = 0;
  uint8_t *data = get_bytes_data(payload, &len);

  const char *kind = "GET";

  // Kind - heap copy (Dart will free)
  size_t kind_len = strlen(kind);
  char *kind_copy = (char *)malloc(kind_len + 1);
  if (kind_copy == NULL) { free(key); free(selector); free(data); return; }
  memcpy(kind_copy, kind, kind_len + 1);

  // DO NOT FREE - NativeCallable.listener is async, Dart will free these
  q->callback(key, selector, data, len, kind_copy, (void *)query, q->context);
}

static void drop_queryable_wrapper(void *arg) {
  // Cleanup if needed
}

FFI_PLUGIN_EXPORT ZenohQueryable *
zenoh_declare_queryable(ZenohSession *session, const char *key_expr,
                        ZenohQueryCallback callback, void *context) {
  if (session == NULL || key_expr == NULL)
    return NULL;

  z_view_keyexpr_t keyopts;
  if (z_view_keyexpr_from_str(&keyopts, key_expr) < 0)
    return NULL;

  ZenohQueryable *q = (ZenohQueryable *)malloc(sizeof(ZenohQueryable));
  if (q == NULL)
    return NULL;

  q->callback = callback;
  q->context = context;

  z_queryable_options_t options;
  z_queryable_options_default(&options);

  z_owned_closure_query_t closure;
  z_closure_query(&closure, query_handler, drop_queryable_wrapper, q);

  if (z_declare_queryable(z_loan(session->session), &q->queryable,
                          z_loan(keyopts), z_move(closure), &options) < 0) {
    free(q);
    return NULL;
  }

  return q;
}

FFI_PLUGIN_EXPORT void zenoh_undeclare_queryable(ZenohQueryable *queryable) {
  if (queryable != NULL) {
    z_drop(z_move(queryable->queryable));
    free(queryable);
  }
}

FFI_PLUGIN_EXPORT void zenoh_query_reply(void *reply_context, const char *key,
                                         const uint8_t *data, size_t len) {
  const z_loaned_query_t *query = (const z_loaned_query_t *)reply_context;
  if (query == NULL)
    return;

  z_view_keyexpr_t keyexpr;
  if (z_view_keyexpr_from_str(&keyexpr, key) < 0)
    return;

  z_query_reply_options_t options;
  z_query_reply_options_default(&options);

  z_owned_bytes_t payload;
  z_bytes_copy_from_buf(&payload, data, len);

  z_query_reply(query, z_loan(keyexpr), z_move(payload), &options);
}

FFI_PLUGIN_EXPORT void zenoh_query_reply_with_options(
    void *reply_context, const char *key, const uint8_t *data, size_t len,
    ZenohEncodingId encoding, const uint8_t *attachment,
    size_t attachment_len) {
  const z_loaned_query_t *query = (const z_loaned_query_t *)reply_context;
  if (query == NULL)
    return;

  z_view_keyexpr_t keyexpr;
  if (z_view_keyexpr_from_str(&keyexpr, key) < 0)
    return;

  z_query_reply_options_t options;
  z_query_reply_options_default(&options);

  // Set encoding
  z_owned_encoding_t enc;
  z_encoding_clone(&enc, get_encoding(encoding));
  options.encoding = z_encoding_move(&enc);

  // Set attachment
  if (attachment != NULL && attachment_len > 0) {
    z_owned_bytes_t att;
    z_bytes_copy_from_buf(&att, attachment, attachment_len);
    options.attachment = z_bytes_move(&att);
  }

  z_owned_bytes_t payload;
  z_bytes_copy_from_buf(&payload, data, len);

  z_query_reply(query, z_loan(keyexpr), z_move(payload), &options);
}

// ============================================================================
// Liveliness
// ============================================================================

FFI_PLUGIN_EXPORT ZenohLivelinessToken *
zenoh_declare_liveliness_token(ZenohSession *session, const char *key_expr) {
  if (session == NULL || key_expr == NULL)
    return NULL;

  z_view_keyexpr_t keyexpr;
  if (z_view_keyexpr_from_str(&keyexpr, key_expr) < 0)
    return NULL;

  ZenohLivelinessToken *token =
      (ZenohLivelinessToken *)malloc(sizeof(ZenohLivelinessToken));
  if (token == NULL)
    return NULL;

  z_liveliness_token_options_t options;
  z_liveliness_token_options_default(&options);

  if (z_liveliness_declare_token(z_loan(session->session), &token->token,
                                 z_loan(keyexpr), &options) < 0) {
    free(token);
    return NULL;
  }

  return token;
}

FFI_PLUGIN_EXPORT void
zenoh_undeclare_liveliness_token(ZenohLivelinessToken *token) {
  if (token != NULL) {
    z_liveliness_undeclare_token(z_liveliness_token_move(&token->token));
    free(token);
  }
}

// Liveliness subscriber callback
static void liveliness_sample_handler(z_loaned_sample_t *sample,
                                      void *arg) {
  ZenohSubscriber *sub = (ZenohSubscriber *)arg;
  if (sub == NULL || sub->liveliness_callback == NULL)
    return;

  // Get Key - null-terminated copy
  z_view_string_t key_str;
  z_keyexpr_as_view_string(z_sample_keyexpr(sample), &key_str);
  size_t key_len = z_string_len(z_loan(key_str));
  char *key = (char *)malloc(key_len + 1);
  if (key == NULL) return;
  memcpy(key, z_string_data(z_loan(key_str)), key_len);
  key[key_len] = '\0';

  // Get alive status from sample kind
  int is_alive = (z_sample_kind(sample) == Z_SAMPLE_KIND_PUT) ? 1 : 0;

  // DO NOT FREE key - NativeCallable.listener is async, Dart will free
  sub->liveliness_callback(key, is_alive, sub->context);
}

FFI_PLUGIN_EXPORT ZenohSubscriber *zenoh_declare_liveliness_subscriber(
    ZenohSession *session, const char *key_expr,
    ZenohLivelinessCallback callback, void *context, bool history) {
  if (session == NULL || key_expr == NULL)
    return NULL;

  z_view_keyexpr_t keyexpr;
  if (z_view_keyexpr_from_str(&keyexpr, key_expr) < 0)
    return NULL;

  ZenohSubscriber *sub = (ZenohSubscriber *)malloc(sizeof(ZenohSubscriber));
  if (sub == NULL)
    return NULL;

  sub->callback = NULL;
  sub->callback_ex = NULL;
  sub->context = context;
  sub->is_liveliness = true;
  sub->liveliness_callback = callback;

  z_liveliness_subscriber_options_t options;
  z_liveliness_subscriber_options_default(&options);
  options.history = history;

  z_owned_closure_sample_t closure;
  z_closure_sample(&closure, liveliness_sample_handler, drop_subscriber_wrapper,
                   sub);

  if (z_liveliness_declare_subscriber(z_loan(session->session), &sub->subscriber,
                                      z_loan(keyexpr), z_move(closure),
                                      &options) < 0) {
    free(sub);
    return NULL;
  }

  return sub;
}

// Liveliness get callback context
struct LivelinessGetContext {
  ZenohLivelinessCallback callback;
  void *user_context;
};

static void liveliness_get_reply_handler(struct z_loaned_reply_t *reply, void *arg) {
  struct LivelinessGetContext *ctx = (struct LivelinessGetContext *)arg;
  if (ctx == NULL || ctx->callback == NULL)
    return;

  if (z_reply_is_ok(reply)) {
    const z_loaned_sample_t *sample = z_reply_ok(reply);

    z_view_string_t key_str;
    z_keyexpr_as_view_string(z_sample_keyexpr(sample), &key_str);
    size_t key_len = z_string_len(z_loan(key_str));
    char *key = (char *)malloc(key_len + 1);
    if (key == NULL) return;
    memcpy(key, z_string_data(z_loan(key_str)), key_len);
    key[key_len] = '\0';

    // DO NOT FREE key - NativeCallable.listener is async, Dart will free
    ctx->callback(key, 1, ctx->user_context);
  }
}

static void drop_liveliness_get_context(void *arg) {
  if (arg != NULL) {
    free(arg);
  }
}

FFI_PLUGIN_EXPORT void zenoh_liveliness_get(ZenohSession *session,
                                            const char *key_expr,
                                            ZenohLivelinessCallback callback,
                                            void *context,
                                            uint64_t timeout_ms) {
  if (session == NULL || key_expr == NULL)
    return;

  z_view_keyexpr_t keyexpr;
  if (z_view_keyexpr_from_str(&keyexpr, key_expr) < 0)
    return;

  struct LivelinessGetContext *ctx =
      (struct LivelinessGetContext *)malloc(sizeof(struct LivelinessGetContext));
  if (ctx == NULL)
    return;

  ctx->callback = callback;
  ctx->user_context = context;

  z_liveliness_get_options_t options;
  z_liveliness_get_options_default(&options);
  options.timeout_ms = timeout_ms > 0 ? timeout_ms : 10000;

  z_owned_closure_reply_t closure;
  z_closure_reply(&closure, liveliness_get_reply_handler,
                  drop_liveliness_get_context, ctx);

  z_liveliness_get(z_loan(session->session), z_loan(keyexpr), z_move(closure),
                   &options);
}

// ============================================================================
// Scouting
// ============================================================================

static void scout_callback_wrapper(struct z_loaned_hello_t *hello, void *arg) {
  void (*cb)(const char *) = (void (*)(const char *))arg;
  if (cb) {
    // Extract whatami
    z_whatami_t whatami = z_hello_whatami(hello);
    const char *whatami_str = "unknown";
    if (whatami == Z_WHATAMI_ROUTER)
      whatami_str = "router";
    else if (whatami == Z_WHATAMI_PEER)
      whatami_str = "peer";
    else if (whatami == Z_WHATAMI_CLIENT)
      whatami_str = "client";

    // Extract zid
    z_id_t zid = z_hello_zid(hello);
    char zid_str[37];
    snprintf(zid_str, 37,
             "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
             zid.id[0], zid.id[1], zid.id[2], zid.id[3], zid.id[4], zid.id[5],
             zid.id[6], zid.id[7], zid.id[8], zid.id[9], zid.id[10], zid.id[11],
             zid.id[12], zid.id[13], zid.id[14], zid.id[15]);

    // Build JSON response
    char json[512];
    snprintf(json, sizeof(json),
             "{\"event\":\"peer_discovered\",\"whatami\":\"%s\",\"zid\":\"%s\"}",
             whatami_str, zid_str);

    cb(json);
  }
}

static void drop_scout_wrapper(void *arg) {}

FFI_PLUGIN_EXPORT void zenoh_scout(const char *what, const char *config,
                                   void (*callback)(const char *info)) {
  z_what_t w = Z_WHAT_ROUTER_PEER;
  if (what && strcmp(what, "router") == 0)
    w = Z_WHAT_ROUTER;
  else if (what && strcmp(what, "peer") == 0)
    w = Z_WHAT_PEER;

  z_scout_options_t options;
  z_scout_options_default(&options);
  options.what = w;
  options.timeout_ms = 1000;

  z_owned_config_t cfg;
  z_config_default(&cfg);

  z_owned_closure_hello_t closure;
  z_closure_hello(&closure, scout_callback_wrapper, drop_scout_wrapper,
                  (void *)callback);

  z_scout(z_move(cfg), z_move(closure), &options);
}
