#ifndef BUNNY_SERVER_ROUTES_QUEUE_H
#define BUNNY_SERVER_ROUTES_QUEUE_H

#include <civetweb.h>

#include "context.h"

/* POST /posts/{id}/favorite (body: optional stars) -> bunny_core_queue_favorite_add
 * DELETE /posts/{id}/favorite -> bunny_core_queue_favorite_remove
 * POST /posts/{id}/vote (body: score, no_unvote) -> bunny_core_queue_vote
 * POST /posts/{id}/comment (body: body, anonymous) -> bunny_core_queue_comment
 * POST /sync -> bunny_core_sync_due_searches
 * POST /queue/process -> bunny_core_process_queue
 * All queue actions respond 202 (accepted, not yet processed). */
void server_routes_register_queue(struct mg_context *mg_ctx, server_context_t *ctx);

#endif /* BUNNY_SERVER_ROUTES_QUEUE_H */
