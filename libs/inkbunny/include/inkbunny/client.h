#ifndef INKBUNNY_CLIENT_H
#define INKBUNNY_CLIENT_H

#include <bunny_common/http.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "inkbunny/error.h"
#include "inkbunny/types.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Inkbunny's official API has no endpoint to add/remove a favorite or to
 * post/list comment content -- verified against the live API and the
 * official docs during M2 (2026-09). It only exposes read-only signals:
 * inkbunny_submission_t.is_favorite, .favorites_count, .comments_count, and
 * (for favorites specifically) the ability to list an *existing* favorites
 * list via inkbunny_search_params_t.favorited_by_user_id. Favoriting and
 * commenting are deliberately not implemented here. Do not add undocumented
 * unofficial endpoints to this library without a fresh decision from the
 * user -- that trade-off (official API only vs. reverse-engineering the
 * website's internal calls) was already raised and decided once.
 */

typedef struct inkbunny_client inkbunny_client_t;

typedef struct
{
    const char *base_url; /* NULL => "https://inkbunny.net" */

    /* Seconds between requests made by this client (rate limiting). No official
     * rate limit is published for Inkbunny; 0.5s is a conservative default. */
    double min_request_interval_sec;

    /* Overrides the HTTP transport; pass NULL to use the real curl-backed transport.
     * Tests inject a fake transport here. */
    const bunny_http_transport_t *transport;
} inkbunny_config_t;

inkbunny_client_t *inkbunny_client_create(const inkbunny_config_t *config);
void inkbunny_client_destroy(inkbunny_client_t *client);

/* Logs in and stores the session id on the client for subsequent calls.
 * Use username "guest" with an empty/NULL password for anonymous, public-only access. */
inkbunny_result_t inkbunny_login(inkbunny_client_t *client, const char *username, const char *password);
inkbunny_result_t inkbunny_logout(inkbunny_client_t *client);

/* The numeric Inkbunny user id of the account currently logged in via
 * inkbunny_login() -- 0 before any login, or for a guest login (the same
 * sentinel Inkbunny's own login response uses for a guest session). Feeds
 * inkbunny_search_params_t.favorited_by_user_id for a "my own favorites"
 * search, since that field needs the numeric id, not a username. */
int64_t inkbunny_client_get_user_id(const inkbunny_client_t *client);

/* Bits for inkbunny_search_params_t.search_in_mask -- which of api_search.php's
 * text-matching fields `text` is searched against. At least one of
 * KEYWORDS/TITLE/DESCRIPTION/MD5 must be set for `text` to do anything (per
 * Inkbunny's own docs); 0 defaults to KEYWORDS, matching the API's own
 * default when none of "keywords"/"title"/"description" is sent at all. */
#define INKBUNNY_SEARCH_IN_KEYWORDS 1
#define INKBUNNY_SEARCH_IN_TITLE 2
#define INKBUNNY_SEARCH_IN_DESCRIPTION 4
#define INKBUNNY_SEARCH_IN_MD5 8

typedef enum
{
    INKBUNNY_FIELD_JOIN_OR,  /* match text found in ANY of the chosen fields (api_search.php's own default) */
    INKBUNNY_FIELD_JOIN_AND, /* match text found in ALL of the chosen fields */
} inkbunny_field_join_t;

typedef enum
{
    INKBUNNY_STRING_JOIN_AND,   /* every word in `text` must be found (api_search.php's own default) */
    INKBUNNY_STRING_JOIN_OR,    /* any word in `text` matches */
    INKBUNNY_STRING_JOIN_EXACT, /* `text` matches as one exact phrase */
} inkbunny_string_join_t;

typedef enum
{
    INKBUNNY_SCRAPS_BOTH, /* Main gallery + Scraps (api_search.php's own default) */
    INKBUNNY_SCRAPS_NO,   /* Main gallery only */
    INKBUNNY_SCRAPS_ONLY, /* Scraps only */
} inkbunny_scraps_t;

/* Bits for inkbunny_search_params_t.submission_type_mask -- bit (type_id - 1)
 * per submission_type_id (api_search.php's own `type` param, 1-14). 0 means
 * unset/every type. */
#define INKBUNNY_SUBMISSION_TYPE_BIT(type_id) (1u << ((type_id) - 1))

typedef struct
{
    const char *text; /* may be NULL; matched against the search_in_mask fields below */
    int search_in_mask; /* INKBUNNY_SEARCH_IN_* bits; 0 defaults to KEYWORDS (api_search.php's own text/keywords default) */
    inkbunny_field_join_t field_join;   /* only meaningful when more than one search_in_mask bit is set */
    inkbunny_string_join_t string_join; /* only meaningful when `text` has more than one word */
    const char *favorited_by_user_id;   /* may be NULL; Inkbunny's numeric user id (as a string) whose existing favorites to list */
    const char *username;               /* may be NULL; limits results to this exact (case-insensitive) uploader username */
    int64_t pool_id;                    /* 0 means unset; lists every submission in this pool (confirmed live against the real API --
                                         * undocumented in Inkbunny's official API docs, but works identically to e621's own
                                         * `pool:<id>` search tag). Results come back newest-first by creation date, with no
                                         * endpoint to fetch the pool's own authoritative ordering (unlike e621's
                                         * GET /pools/{id}.json) -- callers that need reading order should treat the reversed
                                         * creation-date order as a best-effort placeholder, same as e621's pools did before
                                         * that authoritative-ordering fetch was added. */
    unsigned submission_type_mask;       /* INKBUNNY_SUBMISSION_TYPE_BIT(id) bits; 0 means every type */
    int days_limit;                      /* 0 means unset/no limit; api_search.php's own `dayslimit` */
    const char *order_by;                /* may be NULL (defaults to "create_datetime"); one of api_search.php's own `orderby` values, passed through verbatim */
    bool random;                          /* api_search.php's own `random` -- shuffles results after every other filter/sort is applied */
    inkbunny_scraps_t scraps;
    int page; /* 1-based; 0 or negative defaults to 1 */
} inkbunny_search_params_t;

/* Requires a prior successful inkbunny_login() (a guest login is enough for public content). */
inkbunny_result_t inkbunny_search(inkbunny_client_t *client, const inkbunny_search_params_t *params, inkbunny_submission_list_t *out_submissions);

inkbunny_result_t inkbunny_get_submission(inkbunny_client_t *client, int64_t submission_id, inkbunny_submission_t *out_submission);

/* Up to 100 ids per call (Inkbunny's own limit); more than that returns INKBUNNY_ERR_INVALID_ARG. */
inkbunny_result_t inkbunny_get_submissions(inkbunny_client_t *client, const int64_t *submission_ids, size_t submission_id_count, inkbunny_submission_list_t *out_submissions);

#ifdef __cplusplus
}
#endif

#endif /* INKBUNNY_CLIENT_H */
