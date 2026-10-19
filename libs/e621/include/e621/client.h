#ifndef E621_CLIENT_H
#define E621_CLIENT_H

#include <bunny_common/http.h>
#include <stdbool.h>
#include <stdint.h>

#include "e621/error.h"
#include "e621/types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct e621_client e621_client_t;

typedef struct
{
    const char *base_url;   /* NULL => "https://e621.net" */
    const char *user_agent; /* required by e621's API etiquette; e.g. "LittleBunny/0.1 (by yourname)" */
    const char *username;   /* optional; required for authenticated calls (favorite/vote/comment) */
    const char *api_key;    /* optional; required alongside username for authenticated calls */

    /* Seconds to wait between requests made by this client (rate limiting).
     * 0 disables the default and issues requests as fast as the transport allows. */
    double min_request_interval_sec; /* 0 => use the built-in default (~0.5s, e621's ~2 req/s etiquette) */

    /* Overrides the HTTP transport; pass NULL to use the real curl-backed transport.
     * Tests inject a fake transport here. */
    const bunny_http_transport_t *transport;
} e621_config_t;

e621_client_t *e621_client_create(const e621_config_t *config);
void e621_client_destroy(e621_client_t *client);

e621_result_t e621_search_posts(e621_client_t *client, const char *tags, int page, int limit, e621_post_list_t *out_posts);

/* Cursor-based pagination (e621's recommended method for iterating a large
 * result set -- plain numeric `page` can duplicate/skip posts that are
 * created/deleted between requests, and errors above page 750). Overrides
 * any `order:` meta-tag in `tags`, always walking strictly by post id. */
e621_result_t e621_search_posts_after(e621_client_t *client, const char *tags, int64_t after_post_id, int limit, e621_post_list_t *out_posts);
e621_result_t e621_search_posts_before(e621_client_t *client, const char *tags, int64_t before_post_id, int limit, e621_post_list_t *out_posts);

e621_result_t e621_get_post(e621_client_t *client, int64_t post_id, e621_post_t *out_post);

/* Requires username/api_key on the client config. */
e621_result_t e621_favorite_add(e621_client_t *client, int64_t post_id);
e621_result_t e621_favorite_remove(e621_client_t *client, int64_t post_id);

/* score must be +1 or -1. Requires username/api_key on the client config. */
e621_result_t e621_vote(e621_client_t *client, int64_t post_id, int score, bool no_unvote);

/* user_id is e621's numeric account id (as a string), NOT a username -
 * that's what the favorites.json endpoint takes. Pass NULL to list the
 * authenticated client's own favorites. */
e621_result_t e621_list_favorites(e621_client_t *client, const char *user_id, int page, e621_post_list_t *out_posts);

/* Requires username/api_key on the client config unless anonymous is true. */
e621_result_t e621_comment_create(e621_client_t *client, int64_t post_id, const char *body, bool anonymous, e621_comment_t *out_comment);

/* Requires username/api_key on the client config -- e621's profile JSON only
 * includes blacklisted_tags when authenticated as that same account, so this
 * always asks about `client`'s own configured username, not an arbitrary one.
 * *out_blacklisted_tags receives the raw multi-line field verbatim (one
 * blacklist entry per line, some lines possibly multi-tag "AND" groups like
 * "rating:e young"), or an empty string if the account has none set -- never
 * NULL on E621_OK. Splitting/validating lines is the caller's job, not this
 * client's (matches tools/e621_blacklist_experiment/e621_blacklist.py's own
 * get_blacklisted_tags(), which this mirrors). Caller frees. */
e621_result_t e621_get_blacklisted_tags(e621_client_t *client, char **out_blacklisted_tags);

e621_result_t e621_comment_list(e621_client_t *client, int64_t post_id, e621_comment_list_t *out_comments);

/* A post's e621_post_t.pool_ids / e621_post_t.relationships give you the ids to pass here. */
e621_result_t e621_get_pool(e621_client_t *client, int64_t pool_id, e621_pool_t *out_pool);

#ifdef __cplusplus
}
#endif

#endif /* E621_CLIENT_H */
