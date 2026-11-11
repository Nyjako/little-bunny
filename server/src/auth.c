#include "auth.h"

#include <goblin/appdirs.h>
#include <goblin/fileio.h>
#include <goblin/hex.h>
#include <goblin/secure_compare.h>
#include <openssl/rand.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "log.h"

#define SERVER_AUTH_TOKEN_BYTES 32
#define SERVER_AUTH_TOKEN_HEX_LEN (SERVER_AUTH_TOKEN_BYTES * 2)

static char *read_file_contents(const char *path)
{
    size_t len = 0;
    char *buf = goblin_read_file(path, &len);
    if (!buf) {
        return NULL;
    }

    /* trim trailing newline, in case the file was hand-edited */
    while (len > 0 && (buf[len - 1] == '\n' || buf[len - 1] == '\r')) {
        buf[--len] = '\0';
    }
    return buf;
}

static char *generate_hex_token(void)
{
    unsigned char raw[SERVER_AUTH_TOKEN_BYTES];
    if (RAND_bytes(raw, sizeof(raw)) != 1) {
        return NULL;
    }

    char *hex = malloc(SERVER_AUTH_TOKEN_HEX_LEN + 1);
    if (!hex) {
        return NULL;
    }
    goblin_bytes_to_hex(raw, sizeof(raw), hex);
    return hex;
}

static int write_file_restricted(const char *path, const char *contents)
{
    FILE *f = fopen(path, "wb");
    if (!f) {
        return -1;
    }
    size_t len = strlen(contents);
    size_t written = fwrite(contents, 1, len, f);
    fclose(f);
    if (written != len) {
        return -1;
    }
    chmod(path, 0600);
    return 0;
}

server_auth_t *server_auth_load(const char *data_dir)
{
    if (!data_dir) {
        return NULL;
    }

    char *path = goblin_appdir_join(data_dir, "auth_token");
    if (!path) {
        return NULL;
    }

    char *token = read_file_contents(path);
    bool generated = false;
    if (!token || strlen(token) != SERVER_AUTH_TOKEN_HEX_LEN) {
        free(token);
        token = generate_hex_token();
        if (!token) {
            free(path);
            return NULL;
        }
        if (write_file_restricted(path, token) != 0) {
            server_log("ERROR", "failed to write auth token to %s", path);
            free(token);
            free(path);
            return NULL;
        }
        generated = true;
    }
    free(path);

    if (generated) {
        server_log("INFO", "Generated new server auth token: %s", token);
        server_log("INFO", "Copy this into your client's server settings -- it will not be shown again automatically.");
    }

    server_auth_t *auth = calloc(1, sizeof(server_auth_t));
    if (!auth) {
        free(token);
        return NULL;
    }
    auth->token = token;
    return auth;
}

void server_auth_free(server_auth_t *auth)
{
    if (!auth) {
        return;
    }
    free(auth->token);
    free(auth);
}

bool server_auth_verify(const server_auth_t *auth, const char *presented_token)
{
    if (!auth || !auth->token) {
        return false;
    }
    return goblin_secure_streq(auth->token, presented_token);
}

#define SERVER_AUTH_BEARER_PREFIX "Bearer "

bool server_auth_check_request(const server_auth_t *auth, struct mg_connection *conn)
{
    const char *header = mg_get_header(conn, "Authorization");
    const char *presented = NULL;
    if (header && strncmp(header, SERVER_AUTH_BEARER_PREFIX, strlen(SERVER_AUTH_BEARER_PREFIX)) == 0) {
        presented = header + strlen(SERVER_AUTH_BEARER_PREFIX);
    }

    if (!server_auth_verify(auth, presented)) {
        mg_send_http_error(conn, 401, "{\"error\":\"missing or invalid bearer token\"}");
        return false;
    }
    return true;
}
