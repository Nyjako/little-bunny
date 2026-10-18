#include "bunny_core/core.h"

#include <e621/client.h>
#include <inkbunny/client.h>

#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include "internal.h"

e621_client_t *bunny_core_build_e621_client(bunny_core_t *core)
{
    bunny_db_account_t account;
    memset(&account, 0, sizeof(account));
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bool have_account = bunny_db_account_get(read_db, BUNNY_DB_SITE_E621, &account) == BUNNY_DB_OK;
    bunny_core_db_read_unlock(core, slot);

    /* e621's API etiquette requires a contact identifier in the User-Agent
     * (e.g. "LittleBunny/1.0.0 (by someuser on e621)") -- formatted here,
     * per client construction, since the configured account (if any) is
     * only known inside bunny_core, not at bunny_core_open() time when
     * core->user_agent's bare app name/version was first set. */
    char formatted_user_agent[256];
    const char *user_agent = core->user_agent;
    if (have_account && account.username) {
        snprintf(formatted_user_agent, sizeof(formatted_user_agent), "%s (by %s on e621)", core->user_agent, account.username);
        user_agent = formatted_user_agent;
    }

    e621_config_t config;
    memset(&config, 0, sizeof(config));
    config.user_agent = user_agent;
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
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bool have_account = bunny_db_account_get(read_db, BUNNY_DB_SITE_INKBUNNY, &account) == BUNNY_DB_OK;
    bunny_core_db_read_unlock(core, slot);

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
