#ifndef BUNNY_SERVER_TLS_H
#define BUNNY_SERVER_TLS_H

/* Ensures "<data_dir>/server.pem" (civetweb's combined cert+key convention)
 * exists, generating a self-signed ~10-year certificate if not. There's no
 * CA involved -- this server likely has no domain name, only a public IP --
 * so clients must pin this certificate rather than validating it against
 * the system trust store (see docs/architecture.md's "C server (M5)"
 * section). Returns a newly allocated path to that file (caller frees with
 * free()), or NULL on failure. */
char *server_tls_ensure_cert(const char *data_dir);

#endif /* BUNNY_SERVER_TLS_H */
