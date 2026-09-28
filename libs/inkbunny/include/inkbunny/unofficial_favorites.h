#ifndef INKBUNNY_UNOFFICIAL_FAVORITES_H
#define INKBUNNY_UNOFFICIAL_FAVORITES_H

#include <stdint.h>

#include "inkbunny/client.h"
#include "inkbunny/error.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * UNOFFICIAL. Inkbunny's documented API has no endpoint to add or remove a
 * favorite (see inkbunny/client.h and docs/architecture.md, "Inkbunny API
 * constraints"). These functions instead drive the website's own internal
 * flow -- the same requests a browser makes when clicking the favorite
 * stars -- reverse-engineered from the site's own js82/fav.rev01.js and
 * verified live against a real account on 2026-09-28.
 *
 * Unlike the rest of this library, these:
 *  - depend on exact HTML markup Inkbunny could change at any time without
 *    notice (confirmed fragile in practice: the site mixes single- and
 *    double-quoted HTML attributes across its own pages);
 *  - always make real network calls (there's no injectable transport for
 *    them, since they need a persistent cookie-jar session that the rest of
 *    this library's stateless request model doesn't have) -- there are no
 *    fixture-based unit tests for these, only manual/live verification;
 *  - authenticate via the website's own session (login.php ->
 *    login_process.php, cookie-based), which is separate from inkbunny_login()'s
 *    api_login.php session (`sid`). You need both if you also want to
 *    search/fetch submissions with the same client.
 */

/* Logs into the website itself using the same username/password
 * inkbunny_login() takes. Required once before inkbunny_favorite_add() or
 * inkbunny_favorite_remove() will work. */
inkbunny_result_t inkbunny_website_login(inkbunny_client_t *client, const char *username, const char *password);

/* stars must be 1, 2, or 3. Requires a prior successful inkbunny_website_login(). */
inkbunny_result_t inkbunny_favorite_add(inkbunny_client_t *client, int64_t submission_id, int stars);

/* Requires a prior successful inkbunny_website_login(). */
inkbunny_result_t inkbunny_favorite_remove(inkbunny_client_t *client, int64_t submission_id);

#ifdef __cplusplus
}
#endif

#endif /* INKBUNNY_UNOFFICIAL_FAVORITES_H */
