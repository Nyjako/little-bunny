#ifndef BUNNY_SERVER_AUTH_H
#define BUNNY_SERVER_AUTH_H

#include <civetweb.h>

#include <stdbool.h>

typedef struct
{
    char *token; /* hex-encoded, owned */
} server_auth_t;

/* Loads the auth token from "<data_dir>/auth_token", generating and writing
 * a new random one (0600 permissions) if the file doesn't exist yet. Logs
 * the token to stdout when freshly generated, so the operator can copy it
 * into a client -- it is not shown again on subsequent runs. Returns NULL
 * on failure. */
server_auth_t *server_auth_load(const char *data_dir);
void server_auth_free(server_auth_t *auth);

/* Constant-time comparison against the loaded token, so a wrong guess can't
 * be narrowed down by response timing. */
bool server_auth_verify(const server_auth_t *auth, const char *presented_token);

/* Checks the "Authorization: Bearer <token>" header on `conn` against
 * `auth`. On failure it sends the 401 response itself and returns false --
 * the caller (a route handler) should return immediately without doing any
 * bunny_core work. Every route except /health must call this first. */
bool server_auth_check_request(const server_auth_t *auth, struct mg_connection *conn);

#endif /* BUNNY_SERVER_AUTH_H */
