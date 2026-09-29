#ifndef BUNNY_SERVER_ROUTES_TAGS_H
#define BUNNY_SERVER_ROUTES_TAGS_H

#include <civetweb.h>

#include "context.h"

/* GET /tags/autocomplete?site=&prefix=&limit= -> bunny_core_tag_autocomplete */
void server_routes_register_tags(struct mg_context *mg_ctx, server_context_t *ctx);

#endif /* BUNNY_SERVER_ROUTES_TAGS_H */
