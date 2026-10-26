#ifndef BUNNY_SERVER_STATUS_H
#define BUNNY_SERVER_STATUS_H

#include <stdbool.h>

#include "config.h"

/* Prints an informational dump of this deployment's local state -- data_dir,
 * port, poll interval, bearer token, cert fingerprint, public IP/derived
 * server URL, database file size, and whether an update is currently
 * staged. Purely informational, no pass/fail verdict (see health_check.h for
 * that) -- effectively deploy/dump_server_info.sh folded into the binary.
 * Safe to run while the real service is live (read-only). Returns false
 * (logged to stderr) only on a hard failure reading config-level files
 * (auth token, TLS cert) -- a failed public-IP lookup is reported inline
 * instead, same as `--qr` already treats it. */
bool server_print_status(const server_config_t *config);

#endif /* BUNNY_SERVER_STATUS_H */
