#include "bunny_core/core.h"

#include <e621/client.h>
#include <inkbunny/client.h>

#include <stdbool.h>
#include <string.h>

#include "internal.h"

e621_client_t *bunny_core_build_e621_client(bunny_core_t *core)
{
    bunny_db_account_t account;
    memset(&account, 0, sizeof(account));
    bool have_account = bunny_db_account_get(core->db, BUNNY_DB_SITE_E621, &account) == BUNNY_DB_OK;

    e621_config_t config;
    memset(&config, 0, sizeof(config));
    config.user_agent = core->user_agent;
    config.transport = core->e621_transport;
    config.min_request_interval_sec = core->min_request_interval_sec;
    if (have_account) {
        config.username = account.username;
        config.api_key = account.secret;
    }

    e621_client_t *client = e621_client_create(&config);
    if (have_account) {
        bunny_db_account_free(&account);
    }
    return client;
}

inkbunny_client_t *bunny_core_build_inkbunny_client(bunny_core_t *core)
{
    bunny_db_account_t account;
    memset(&account, 0, sizeof(account));
    bool have_account = bunny_db_account_get(core->db, BUNNY_DB_SITE_INKBUNNY, &account) == BUNNY_DB_OK;

    inkbunny_config_t config;
    memset(&config, 0, sizeof(config));
    config.transport = core->inkbunny_transport;
    config.min_request_interval_sec = core->min_request_interval_sec;

    inkbunny_client_t *client = inkbunny_client_create(&config);
    if (!client) {
        if (have_account) {
            bunny_db_account_free(&account);
        }
        return NULL;
    }

    /* Inkbunny needs at least a guest login for any search, since results
     * are only ever returned for a logged-in session (see inkbunny_login). */
    const char *username = have_account ? account.username : "guest";
    const char *password = have_account ? account.secret : NULL;
    inkbunny_result_t login_result = inkbunny_login(client, username, password);
    if (have_account) {
        bunny_db_account_free(&account);
    }
    if (login_result != INKBUNNY_OK) {
        inkbunny_client_destroy(client);
        return NULL;
    }
    return client;
}
