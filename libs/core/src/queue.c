#include "bunny_core/core.h"

#include <bunny_common/json.h>
#include <cJSON.h>
#include <e621/client.h>
#include <goblin/cstr.h>
#include <inkbunny/client.h>
#include <inkbunny/unofficial_favorites.h>

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include "internal.h"

static char *build_vote_payload(int score, bool no_unvote)
{
    cJSON *payload = cJSON_CreateObject();
    cJSON_AddNumberToObject(payload, "score", score);
    cJSON_AddBoolToObject(payload, "no_unvote", no_unvote);
    char *payload_str = cJSON_PrintUnformatted(payload);
    cJSON_Delete(payload);
    return payload_str;
}

static char *build_comment_payload(const char *body, bool anonymous)
{
    cJSON *payload = cJSON_CreateObject();
    cJSON_AddStringToObject(payload, "body", body);
    cJSON_AddBoolToObject(payload, "anonymous", anonymous);
    char *payload_str = cJSON_PrintUnformatted(payload);
    cJSON_Delete(payload);
    return payload_str;
}

static char *build_favorite_payload(int stars)
{
    if (stars < 0) {
        return NULL;
    }
    cJSON *payload = cJSON_CreateObject();
    cJSON_AddNumberToObject(payload, "stars", stars);
    char *payload_str = cJSON_PrintUnformatted(payload);
    cJSON_Delete(payload);
    return payload_str;
}

bunny_core_result_t bunny_core_queue_favorite_add(bunny_core_t *core, int64_t post_id, int stars)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    char *payload = build_favorite_payload(stars);
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_action_queue_add(core->db, post_id, BUNNY_DB_ACTION_FAVORITE_ADD, payload, NULL);
    bunny_core_db_unlock(core);
    free(payload);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_queue_favorite_remove(bunny_core_t *core, int64_t post_id)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_action_queue_add(core->db, post_id, BUNNY_DB_ACTION_FAVORITE_REMOVE, NULL, NULL);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_queue_vote(bunny_core_t *core, int64_t post_id, int score, bool no_unvote)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    char *payload = build_vote_payload(score, no_unvote);
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_action_queue_add(core->db, post_id, BUNNY_DB_ACTION_VOTE, payload, NULL);
    bunny_core_db_unlock(core);
    free(payload);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_queue_comment(bunny_core_t *core, int64_t post_id, const char *body, bool anonymous)
{
    if (!core || !body) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    char *payload = build_comment_payload(body, anonymous);
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_action_queue_add(core->db, post_id, BUNNY_DB_ACTION_COMMENT, payload, NULL);
    bunny_core_db_unlock(core);
    free(payload);
    return bunny_core_map_db_result(result);
}

static bunny_core_result_t process_e621_action(e621_client_t *client, const bunny_db_action_t *action, int64_t external_id, char **out_error)
{
    e621_result_t result;
    switch (action->action_type) {
        case BUNNY_DB_ACTION_FAVORITE_ADD:
            result = e621_favorite_add(client, external_id);
            break;
        case BUNNY_DB_ACTION_FAVORITE_REMOVE:
            result = e621_favorite_remove(client, external_id);
            break;
        case BUNNY_DB_ACTION_VOTE: {
            cJSON *payload = action->payload ? cJSON_Parse(action->payload) : NULL;
            int score = bunny_json_get_int_or(payload, "score", 1);
            bool no_unvote = bunny_json_get_bool_or(payload, "no_unvote", false);
            cJSON_Delete(payload);
            result = e621_vote(client, external_id, score, no_unvote);
            break;
        }
        case BUNNY_DB_ACTION_COMMENT: {
            cJSON *payload = action->payload ? cJSON_Parse(action->payload) : NULL;
            const char *body = bunny_json_get_string_or(payload, "body", NULL);
            bool anonymous = bunny_json_get_bool_or(payload, "anonymous", false);
            if (!body) {
                cJSON_Delete(payload);
                *out_error = goblin_copy_cstr("comment action is missing its body");
                return BUNNY_CORE_ERR_INVALID_ARG;
            }
            e621_comment_t comment;
            result = e621_comment_create(client, external_id, body, anonymous, &comment);
            cJSON_Delete(payload);
            if (result == E621_OK) {
                e621_comment_free(&comment);
            }
            break;
        }
        default:
            *out_error = goblin_copy_cstr("unknown action type");
            return BUNNY_CORE_ERR_INVALID_ARG;
    }

    if (result != E621_OK) {
        *out_error = goblin_copy_cstr(e621_result_to_string(result));
        return BUNNY_CORE_ERR_SITE;
    }
    return BUNNY_CORE_OK;
}

static bunny_core_result_t process_inkbunny_action(bunny_core_t *core, const bunny_db_action_t *action, int64_t external_id, char **out_error)
{
    if (action->action_type == BUNNY_DB_ACTION_VOTE || action->action_type == BUNNY_DB_ACTION_COMMENT) {
        *out_error = goblin_copy_cstr("Inkbunny has no vote/comment API");
        return BUNNY_CORE_ERR_INVALID_ARG;
    }

    bunny_db_account_t account;
    memset(&account, 0, sizeof(account));
    bunny_core_db_lock(core);
    bunny_db_result_t account_result = bunny_db_account_get(core->db, BUNNY_DB_SITE_INKBUNNY, &account);
    bunny_core_db_unlock(core);
    if (account_result != BUNNY_DB_OK) {
        *out_error = goblin_copy_cstr("no Inkbunny account configured -- favoriting needs a real login, not guest");
        return BUNNY_CORE_ERR_INVALID_ARG;
    }

    /* Everything below is network-only (client create + login + the
     * favorite/unfavorite call itself) -- no lock held. account.username/
     * .secret are independently-owned copies (bunny_db_column_text_dup),
     * safe to read after unlocking. */
    inkbunny_config_t config;
    memset(&config, 0, sizeof(config));
    config.transport = core->inkbunny_transport;
    config.min_request_interval_sec = core->min_request_interval_sec;

    inkbunny_client_t *client = inkbunny_client_create(&config);
    if (!client) {
        bunny_db_account_free(&account);
        *out_error = goblin_copy_cstr("failed to create Inkbunny client");
        return BUNNY_CORE_ERR_SITE;
    }

    inkbunny_result_t login_result = inkbunny_website_login(client, account.username, account.secret);
    bunny_db_account_free(&account);
    if (login_result != INKBUNNY_OK) {
        inkbunny_client_destroy(client);
        *out_error = goblin_copy_cstr(inkbunny_result_to_string(login_result));
        return BUNNY_CORE_ERR_SITE;
    }

    inkbunny_result_t action_result;
    if (action->action_type == BUNNY_DB_ACTION_FAVORITE_ADD) {
        cJSON *payload = action->payload ? cJSON_Parse(action->payload) : NULL;
        int stars = bunny_json_get_int_or(payload, "stars", 1);
        cJSON_Delete(payload);
        action_result = inkbunny_favorite_add(client, external_id, stars);
    } else {
        action_result = inkbunny_favorite_remove(client, external_id);
    }
    inkbunny_client_destroy(client);

    if (action_result != INKBUNNY_OK) {
        *out_error = goblin_copy_cstr(inkbunny_result_to_string(action_result));
        return BUNNY_CORE_ERR_SITE;
    }
    return BUNNY_CORE_OK;
}

/* Updates the local favorites mirror to match a just-succeeded favorite
 * action. Not itself a source of truth -- just keeps bunny_db_favorite_list
 * in sync without a round-trip to the site. */
static void apply_favorite_mirror(bunny_db_t *db, const bunny_db_action_t *action)
{
    if (action->action_type == BUNNY_DB_ACTION_FAVORITE_ADD) {
        cJSON *payload = action->payload ? cJSON_Parse(action->payload) : NULL;
        int stars = bunny_json_get_int_or(payload, "stars", -1);
        cJSON_Delete(payload);
        bunny_db_favorite_add(db, action->post_id, stars);
    } else if (action->action_type == BUNNY_DB_ACTION_FAVORITE_REMOVE) {
        bunny_db_favorite_remove(db, action->post_id);
    }
}

/* Updates the local votes mirror (M9.7.1) to match a just-succeeded vote
 * action -- e621 only has a vote concept at all, so this is a no-op for
 * anything else, same as apply_favorite_mirror's non-favorite no-op above. */
static void apply_vote_mirror(bunny_db_t *db, const bunny_db_action_t *action)
{
    if (action->action_type != BUNNY_DB_ACTION_VOTE) {
        return;
    }
    cJSON *payload = action->payload ? cJSON_Parse(action->payload) : NULL;
    int score = bunny_json_get_int_or(payload, "score", 1);
    cJSON_Delete(payload);
    bunny_db_vote_set(db, action->post_id, score);
}

/* sync_mutex is held for this entire function -- see the note on
 * sync_e621_search in sync.c. Keeps queue processing from ever running
 * concurrently with a site-facing sync (or another concurrent call to this
 * function), whether triggered by the scheduler or a manual request. */
bunny_core_result_t bunny_core_process_queue(bunny_core_t *core, bunny_core_queue_stats_t *out_stats)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }

    bunny_core_sync_lock(core);

    bunny_core_queue_stats_t stats;
    memset(&stats, 0, sizeof(stats));

    bunny_db_action_list_t actions;
    bunny_core_db_lock(core);
    bunny_db_result_t list_result = bunny_db_action_queue_list_pending(core->db, &actions);
    bunny_core_db_unlock(core);
    if (list_result != BUNNY_DB_OK) {
        bunny_core_sync_unlock(core);
        return bunny_core_map_db_result(list_result);
    }

    e621_client_t *e621_client = NULL; /* built lazily, reused across e621 actions in this pass */

    for (size_t i = 0; i < actions.count; i++) {
        const bunny_db_action_t *action = &actions.items[i];
        stats.actions_processed++;

        bunny_db_post_t post;
        bunny_core_db_lock(core);
        bunny_db_result_t post_result = bunny_db_post_get_by_id(core->db, action->post_id, &post);
        bunny_core_db_unlock(core);
        if (post_result != BUNNY_DB_OK) {
            bunny_core_db_lock(core);
            bunny_db_action_queue_mark_failed(core->db, action->id, "post not found");
            bunny_core_db_unlock(core);
            stats.actions_failed++;
            continue;
        }

        char *error = NULL;
        bunny_core_result_t action_result;
        if (post.site == BUNNY_DB_SITE_E621) {
            if (!e621_client) {
                e621_client = bunny_core_build_e621_client(core); /* locks internally for its own db read only */
            }
            if (!e621_client) {
                error = goblin_copy_cstr("failed to create e621 client");
                action_result = BUNNY_CORE_ERR_SITE;
            } else {
                action_result = process_e621_action(e621_client, action, post.external_id, &error); /* network call, no lock held */
            }
        } else {
            action_result = process_inkbunny_action(core, action, post.external_id, &error); /* db read + network, split internally */
        }
        bunny_db_post_free(&post);

        if (action_result == BUNNY_CORE_OK) {
            bunny_core_db_lock(core);
            apply_favorite_mirror(core->db, action);
            apply_vote_mirror(core->db, action);
            bunny_db_action_queue_mark_done(core->db, action->id);
            bunny_core_db_unlock(core);
            stats.actions_succeeded++;
        } else {
            bunny_core_db_lock(core);
            bunny_db_action_queue_mark_failed(core->db, action->id, error);
            bunny_core_db_unlock(core);
            stats.actions_failed++;
        }
        free(error);
    }

    if (e621_client) {
        e621_client_destroy(e621_client);
    }

    bunny_db_action_list_free(&actions);
    if (out_stats) {
        *out_stats = stats;
    }
    bunny_core_sync_unlock(core);
    return BUNNY_CORE_OK;
}
