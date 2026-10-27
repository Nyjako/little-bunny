#ifndef BUNNY_SERVER_ROUTES_TAGS_H
#define BUNNY_SERVER_ROUTES_TAGS_H

#include <civetweb.h>

#include "context.h"

/* GET /tags/autocomplete?site=&prefix=&limit= -> bunny_core_tag_autocomplete
 * GET /tags/top_favorited?site=&limit= -> bunny_core_top_favorited_tags
 *
 * M53 -- e621-only (see bunny_core_search_tags's own doc comment):
 * GET /tags/search?name_matches=&limit= -> bunny_core_search_tags
 * GET /wiki_pages?title= -> bunny_core_get_wiki_page
 * GET /tag_aliases?name_matches=&limit= -> bunny_core_search_tag_aliases
 * GET /tag_implications?name_matches=&limit= -> bunny_core_search_tag_implications */
void server_routes_register_tags(struct mg_context *mg_ctx, server_context_t *ctx);

#endif /* BUNNY_SERVER_ROUTES_TAGS_H */
