#ifndef BUNNY_SERVER_ROUTES_QR_H
#define BUNNY_SERVER_ROUTES_QR_H

#include <civetweb.h>

#include "context.h"

/* POST /qr -> PNG image. Body: {"server_url","bearer_token","cert_sha256"}
 * (the client's own already-configured connection info, see
 * NetworkedConfig app-side) -- renders it as the same connection QR
 * `bunny_server --qr` prints to a terminal, so an already-connected device
 * can show it for a second device to scan without the app needing its own
 * QR-rendering library. */
void server_routes_register_qr(struct mg_context *mg_ctx, server_context_t *ctx);

#endif /* BUNNY_SERVER_ROUTES_QR_H */
