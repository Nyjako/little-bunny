#ifndef BUNNY_SERVER_ROUTES_SLIDESHOW_H
#define BUNNY_SERVER_ROUTES_SLIDESHOW_H

#include <civetweb.h>

#include "context.h"

/* GET /slideshow/posts?search_ids=1,2,3&count=20[&rating_mask=][&media_mask=]
 * -> bunny_core_slideshow_pick_random_posts (M51). No existing route owns
 * "/slideshow" yet, so this is its own resource file, same as routes_pools.c. */
void server_routes_register_slideshow(struct mg_context *mg_ctx, server_context_t *ctx);

#endif /* BUNNY_SERVER_ROUTES_SLIDESHOW_H */
