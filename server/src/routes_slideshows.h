#ifndef BUNNY_SERVER_ROUTES_SLIDESHOWS_H
#define BUNNY_SERVER_ROUTES_SLIDESHOWS_H

#include <civetweb.h>

#include "context.h"

/* M51 v2: persisted, download-backed slideshows.
 *   GET/POST   /slideshows
 *   GET/PUT/DELETE /slideshows/{id}
 *   GET/POST   /slideshows/{id}/searches
 *   DELETE     /slideshows/{id}/searches/{search_id}
 *   GET        /slideshows/{id}/posts[?search_id=]
 *   POST       /slideshows/{id}/reroll
 *   POST       /slideshows/{id}/searches/{search_id}/reroll
 *   POST       /slideshows/{id}/searches/{search_id}/replace (body {dead_post_id}) */
void server_routes_register_slideshows(struct mg_context *mg_ctx, server_context_t *ctx);

#endif /* BUNNY_SERVER_ROUTES_SLIDESHOWS_H */
