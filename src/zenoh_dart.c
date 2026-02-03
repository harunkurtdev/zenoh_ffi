#include "zenoh_dart.h"

// Struct definitions
struct ZenohSession {
  z_owned_session_t session;
};

struct ZenohPublisher {
  z_owned_publisher_t publisher;
};

struct ZenohSubscriber {
  z_owned_subscriber_t subscriber;
  ZenohSubscriberCallback callback;
  void *context;
};

// --- Helpers ---

// Initialize logger (optional)
FFI_PLUGIN_EXPORT int zenoh_init_logger(void) {
  z_init_logger();
  return 0;
}

void zenoh_free_string(char *str) {
  if (str != NULL) {
    free(str);
  }
}

// --- Session Management ---

FFI_PLUGIN_EXPORT ZenohSession *zenoh_open_session(const char *mode,
                                                   const char *endpoints) {
  z_owned_config_t config;
  z_config_default(&config);

  // Set mode
  zc_config_insert_json5(z_loan_mut(config), Z_CONFIG_MODE_KEY, mode);

  // Set endpoints (if provided)
  if (endpoints != NULL && strlen(endpoints) > 0) {
    if (strstr(mode, "peer") != NULL) {
      zc_config_insert_json5(z_loan_mut(config), Z_CONFIG_LISTEN_KEY,
                             endpoints);
    } else {
      zc_config_insert_json5(z_loan_mut(config), Z_CONFIG_CONNECT_KEY,
                             endpoints);
    }
  }

// MacOS multicast fix
#if defined(__APPLE__)
  zc_config_insert_json5(z_loan_mut(config), Z_CONFIG_MULTICAST_SCOUTING_KEY,
                         "false");
#endif

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

// --- Publisher ---

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

FFI_PLUGIN_EXPORT int zenoh_publisher_put(ZenohPublisher *publisher,
                                          const uint8_t *data, size_t len) {
  if (publisher == NULL)
    return -1;

  z_publisher_put_options_t options;
  z_publisher_put_options_default(&options);

  z_owned_bytes_t payload;
  // Keep internal copy safe if needed, but here we can just create from pointer
  // if we don't transfer ownership. z_bytes_copy_from_buf makes a copy.
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

// --- Subscriber ---

// Callback wrapper for subscribers
static void subscriber_data_handler(const z_loaned_sample_t *sample,
                                    void *arg) {
  ZenohSubscriber *sub = (ZenohSubscriber *)arg;
  if (sub == NULL || sub->callback == NULL)
    return;

  // Get Key
  z_view_string_t key_str;
  z_keyexpr_as_view_string(z_sample_keyexpr(sample), &key_str);
  const char *key = z_string_data(z_loan(key_str));

  // Get Kind
  const char *kind_str = "PUT"; // Default
  z_sample_kind_t kind = z_sample_kind(sample);
  if (kind == Z_SAMPLE_KIND_DELETE)
    kind_str = "DELETE";

  // Get Payload
  const z_loaned_bytes_t *payload = z_sample_payload(sample);
  const uint8_t *data = NULL;
  size_t len = 0;

  if (payload != NULL) {
    data = z_bytes_data(payload);
    len = z_bytes_len(payload);
  }

  // Get Attachment (optional, simplified for now)
  const char *attachment = "";

  // Call Dart callback
  sub->callback(key, data, len, kind_str, attachment, sub->context);
}

static void drop_subscriber_wrapper(void *arg) {
  // Optional: cleanup context if it was malloc'd specifically for this wrapper
  // For now, we assume context is managed by Dart or is just an ID
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
  sub->context = context;

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

FFI_PLUGIN_EXPORT void zenoh_undeclare_subscriber(ZenohSubscriber *subscriber) {
  if (subscriber != NULL) {
    z_drop(z_move(subscriber->subscriber));
    free(subscriber);
  }
}

// --- Ad-hoc Operations ---

FFI_PLUGIN_EXPORT int zenoh_put(ZenohSession *session, const char *key,
                                const uint8_t *data, size_t len) {
  if (session == NULL || key == NULL)
    return -1;

  z_view_keyexpr_t keyexpr;
  if (z_view_keyexpr_from_str(&keyexpr, key) < 0)
    return -1;

  z_put_options_t options;
  z_put_options_default(&options);

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

// --- Query (Get) ---

// Struct to pass context to reply callback
struct GetContext {
  ZenohGetCallback callback;
  void *user_context;
};

static void get_reply_handler(z_loaned_reply_t *reply, void *arg) {
  struct GetContext *ctx = (struct GetContext *)arg;
  if (ctx == NULL || ctx->callback == NULL)
    return;

  if (z_reply_is_ok(reply)) {
    const z_loaned_sample_t *sample = z_reply_ok(reply);

    // Key
    z_view_string_t key_str;
    z_keyexpr_as_view_string(z_sample_keyexpr(sample), &key_str);
    const char *key = z_string_data(z_loan(key_str));

    // Payload
    const z_loaned_bytes_t *payload = z_sample_payload(sample);
    const uint8_t *data = NULL;
    size_t len = 0;

    if (payload != NULL) {
      data = z_bytes_data(payload);
      len = z_bytes_len(payload);
    }

    // Kind
    const char *kind_str = "PUT"; // Default
    if (z_sample_kind(sample) == Z_SAMPLE_KIND_DELETE)
      kind_str = "DELETE";

    ctx->callback(key, data, len, kind_str, ctx->user_context);
  }
}

static void drop_get_context(void *arg) {
  if (arg != NULL) {
    free(arg);
  }
}

// --- Queryable ---

struct ZenohQueryable {
  z_owned_queryable_t queryable;
  ZenohQueryCallback callback;
  void *context;
};

// Callback wrapper for queryable
static void query_handler(const z_loaned_query_t *query, void *arg) {
  ZenohQueryable *q = (ZenohQueryable *)arg;
  if (q == NULL || q->callback == NULL)
    return;

  // Get Key Selector
  z_view_keyexpr_t keyexpr = z_query_keyexpr(query);
  z_view_string_t key_str;
  z_keyexpr_as_view_string(keyexpr, &key_str);
  const char *key = z_string_data(z_loan(key_str));

  // Get Selector (parameters)
  z_view_string_t selector_str = z_query_parameters(query);
  const char *selector = z_string_data(z_loan(selector_str));

  // Get Payload (Value)
  const z_loaned_bytes_t *payload = z_query_payload(query); // Can be NULL
  const uint8_t *data = NULL;
  size_t len = 0;
  if (payload != NULL) {
    data = z_bytes_data(payload);
    len = z_bytes_len(payload);
  }

  // Get Kind (optional, usually empty for query?)
  const char *kind = "GET";

  // Reply Context needs to be passed to allow replying
  // We can pass the `query` object itself as the reply context, BUT
  // `query` is loaned and only valid during this callback.
  // `zenoh_query_reply` must be called synchronously inside this callback
  // OR we need to clone the query/reply capability?
  // Zenoh C API `z_query_reply` uses `z_loaned_query_t`.
  // So we pass `query` as `reply_context`. It is only valid for the duration of
  // the callback. If async reply is needed, we would need to clone it (if
  // supported). For now, assume sync reply or valid lifetime.
  q->callback(key, selector, data, len, kind, (void *)query, q->context);
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

  // We are replying to the query.
  z_query_reply(query, z_loan(keyexpr), z_move(payload), &options);
}

// --- Scouting ---

static void scout_callback_wrapper(const z_loaned_hello_t *hello, void *arg) {
  void (*cb)(const char *) = (void (*)(const char *))arg;
  if (cb) {
    // Extract info from hello
    // Simplified for now, just saying "Found Peer"
    // In real impl, parse z_hello_whatami(hello), z_hello_locators(hello)
    cb("{\"event\": \"peer_discovered\"}");
  }
}

static void drop_scout_wrapper(void *arg) {}

FFI_PLUGIN_EXPORT void zenoh_scout(const char *what, const char *config,
                                   void (*callback)(const char *info)) {
  z_whatami_t w = Z_WHATAMI_PEER | Z_WHATAMI_ROUTER; // Default both
  if (what && strcmp(what, "router") == 0)
    w = Z_WHATAMI_ROUTER;
  else if (what && strcmp(what, "peer") == 0)
    w = Z_WHATAMI_PEER;

  z_scout_options_t options;
  z_scout_options_default(&options);
  options.what = w;
  options.timeout_ms = 1000; // 1 second scout

  z_owned_config_t cfg;
  z_config_default(&cfg); // Start default
  if (config) {
    // If config provided, try to parse? Or manual?
    // z_config_from_str(config) ??
    // For simplicity, passing config string might need proper parsing.
    // Or we just rely on default multicast.
  }

  // This block is blocking in C usually unless we use closure?
  // z_scout is usually blocking and returns channel or calls callback.
  // Wait, z_scout with closure:
  z_owned_closure_hello_t closure;
  z_closure_hello(&closure, scout_callback_wrapper, drop_scout_wrapper,
                  (void *)callback);

  z_scout(z_move(cfg), &options, &closure);
}