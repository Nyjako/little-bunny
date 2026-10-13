#include "tls.h"

#include <goblin/appdirs.h>

#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/x509.h>

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>

#include "log.h"

#define SERVER_CERT_VALIDITY_SECONDS ((long)10 * 365 * 24 * 60 * 60)
#define SERVER_CERT_RSA_BITS 2048

static bool file_exists(const char *path)
{
    struct stat st;
    return stat(path, &st) == 0;
}

static EVP_PKEY *generate_key(void)
{
    EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new_id(EVP_PKEY_RSA, NULL);
    if (!ctx) {
        return NULL;
    }

    EVP_PKEY *key = NULL;
    if (EVP_PKEY_keygen_init(ctx) <= 0 || EVP_PKEY_CTX_set_rsa_keygen_bits(ctx, SERVER_CERT_RSA_BITS) <= 0 || EVP_PKEY_keygen(ctx, &key) <= 0) {
        EVP_PKEY_CTX_free(ctx);
        return NULL;
    }
    EVP_PKEY_CTX_free(ctx);
    return key;
}

static X509 *generate_self_signed_cert(EVP_PKEY *key)
{
    X509 *cert = X509_new();
    if (!cert) {
        return NULL;
    }

    ASN1_INTEGER_set(X509_get_serialNumber(cert), 1);
    X509_gmtime_adj(X509_get_notBefore(cert), 0);
    X509_gmtime_adj(X509_get_notAfter(cert), SERVER_CERT_VALIDITY_SECONDS);
    X509_set_pubkey(cert, key);

    X509_NAME *name = X509_get_subject_name(cert);
    X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC, (const unsigned char *)"little-bunny-server", -1, -1, 0);
    X509_set_issuer_name(cert, name); /* self-signed: issuer == subject */

    if (!X509_sign(cert, key, EVP_sha256())) {
        X509_free(cert);
        return NULL;
    }
    return cert;
}

static int write_combined_pem(const char *path, EVP_PKEY *key, X509 *cert)
{
    FILE *f = fopen(path, "wb");
    if (!f) {
        return -1;
    }
    int ok = PEM_write_X509(f, cert) && PEM_write_PrivateKey(f, key, NULL, NULL, 0, NULL, NULL);
    fclose(f);
    if (ok) {
        chmod(path, 0600);
    }
    return ok ? 0 : -1;
}

char *server_tls_ensure_cert(const char *data_dir)
{
    if (!data_dir) {
        return NULL;
    }

    char *path = goblin_appdir_join(data_dir, "server.pem");
    if (!path) {
        return NULL;
    }

    if (file_exists(path)) {
        return path;
    }

    EVP_PKEY *key = generate_key();
    if (!key) {
        free(path);
        return NULL;
    }

    X509 *cert = generate_self_signed_cert(key);
    if (!cert) {
        EVP_PKEY_free(key);
        free(path);
        return NULL;
    }

    int result = write_combined_pem(path, key, cert);
    X509_free(cert);
    EVP_PKEY_free(key);

    if (result != 0) {
        server_log("ERROR", "failed to write TLS certificate to %s", path);
        free(path);
        return NULL;
    }

    server_log("INFO", "Generated new self-signed TLS certificate at %s", path);
    return path;
}
