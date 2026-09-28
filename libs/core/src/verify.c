#include "bunny_core/core.h"

#include <e621/client.h>
#include <inkbunny/client.h>

#include <string.h>

#include "internal.h"

static bunny_core_result_t verify_e621(bunny_core_t *core, const char *username, const char *secret)
{
    e621_config_t config;
    memset(&config, 0, sizeof(config));
    config.user_agent = core->user_agent;
    config.transport = core->e621_transport;
    config.min_request_interval_sec = core->min_request_interval_sec;
    config.username = username;
    config.api_key = secret;

    e621_client_t *client = e621_client_create(&config);
    if (!client) {
        return BUNNY_CORE_ERR_SITE;
    }

    e621_post_list_t favorites;
    memset(&favorites, 0, sizeof(favorites));
    e621_result_t result = e621_list_favorites(client, NULL, 1, &favorites);
    e621_client_destroy(client);
    if (result != E621_OK) {
        return BUNNY_CORE_ERR_SITE;
    }

    e621_post_list_free(&favorites);
    return BUNNY_CORE_OK;
}

static bunny_core_result_t verify_inkbunny(bunny_core_t *core, const char *username, const char *secret)
{
    inkbunny_config_t config;
    memset(&config, 0, sizeof(config));
    config.transport = core->inkbunny_transport;
    config.min_request_interval_sec = core->min_request_interval_sec;

    inkbunny_client_t *client = inkbunny_client_create(&config);
    if (!client) {
        return BUNNY_CORE_ERR_SITE;
    }

    inkbunny_result_t result = inkbunny_login(client, username, secret);
    inkbunny_client_destroy(client);
    return result == INKBUNNY_OK ? BUNNY_CORE_OK : BUNNY_CORE_ERR_SITE;
}

bunny_core_result_t bunny_core_account_verify(bunny_core_t *core, bunny_db_site_t site, const char *username, const char *secret)
{
    if (!core || !username || !secret) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }

    switch (site) {
        case BUNNY_DB_SITE_E621:
            return verify_e621(core, username, secret);
        case BUNNY_DB_SITE_INKBUNNY:
            return verify_inkbunny(core, username, secret);
        default:
            return BUNNY_CORE_ERR_INVALID_ARG;
    }
}
