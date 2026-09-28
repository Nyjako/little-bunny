#ifndef BUNNY_SERVER_ROUTES_ACCOUNTS_H
#define BUNNY_SERVER_ROUTES_ACCOUNTS_H

#include <civetweb.h>

#include "context.h"

/* POST /accounts (body: site, username, secret) -> bunny_core_account_set
 * GET /accounts/{site} -> bunny_core_account_get (never echoes `secret` back)
 * DELETE /accounts/{site} -> bunny_core_account_delete */
void server_routes_register_accounts(struct mg_context *mg_ctx, server_context_t *ctx);

#endif /* BUNNY_SERVER_ROUTES_ACCOUNTS_H */
