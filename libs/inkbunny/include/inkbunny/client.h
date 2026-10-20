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

typedef struct
{
    const char *text;                 /* may be NULL; matched against title/description/keywords by default */
    bool keywords_only;               /* restrict text matching to keywords only */
    const char *favorited_by_user_id; /* may be NULL; Inkbunny's numeric user id (as a string) whose existing favorites to list */
    int64_t pool_id;                  /* 0 means unset; lists every submission in this pool (confirmed live against the real API --
                                        * undocumented in Inkbunny's official API docs, but works identically to e621's own
                                        * `pool:<id>` search tag). Results come back newest-first by creation date, with no
                                        * endpoint to fetch the pool's own authoritative ordering (unlike e621's
                                        * GET /pools/{id}.json) -- callers that need reading order should treat the reversed
                                        * creation-date order as a best-effort placeholder, same as e621's pools did before
                                        * that authoritative-ordering fetch was added. */
    int page;                         /* 1-based; 0 or negative defaults to 1 */
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
