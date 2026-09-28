#ifndef BUNNY_SERVER_CONFIG_H
#define BUNNY_SERVER_CONFIG_H

typedef struct
{
    int port;
    char *data_dir;
    char *user_agent;
    int poll_interval_sec;
} server_config_t;

/* Reads BUNNY_SERVER_PORT/DATA_DIR/USER_AGENT/POLL_INTERVAL_SEC from the
 * environment, falling back to sensible defaults (data_dir via GOBLIN's
 * appdirs.h). Ensures data_dir exists (mkdir -p). Caller owns the returned
 * config; free with server_config_free. Returns NULL on allocation/mkdir
 * failure. */
server_config_t *server_config_load(void);
void server_config_free(server_config_t *config);

#endif /* BUNNY_SERVER_CONFIG_H */
