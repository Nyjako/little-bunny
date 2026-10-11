#ifndef BUNNY_DB_TYPES_H
#define BUNNY_DB_TYPES_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum
{
    BUNNY_DB_SITE_E621,
    BUNNY_DB_SITE_INKBUNNY,
} bunny_db_site_t;

const char *bunny_db_site_to_string(bunny_db_site_t site);

typedef struct
{
    int64_t id;
    bunny_db_site_t site;
    char *username;
    char *secret;
    char *created_at;
} bunny_db_account_t;

/* Editable settings shared by bunny_db_search_create and bunny_db_search_update
 * (M9.7.2) -- kept as one struct instead of ever-more positional bool/int
 * params, since this set has grown with nearly every sub-milestone that's
 * touched searches. */
typedef struct
{
    bool auto_favorite;      /* queue a favorite for every post this search finds during sync */
    int auto_favorite_stars; /* Inkbunny favorite level (1-3); ignored by e621, which has no stars concept */
    bool auto_upvote;        /* e621 only -- queue an upvote for every post this search finds during sync */
} bunny_db_search_options_t;

typedef struct
{
    int64_t id;
    bunny_db_site_t site;
    char *label;
    char *query;
    int interval_hours;
    char *created_at;
    char *last_run_at;       /* NULL if this search has never run */
    int unseen_count;        /* posts linked to this search with no seen_posts row */
    int total_count;         /* posts linked to this search, seen or not */
    bool auto_favorite;      /* queue a favorite for every post this search finds during sync */
    int auto_favorite_stars; /* Inkbunny favorite level (1-3); ignored by e621 */
    bool auto_upvote;        /* e621 only -- queue an upvote for every post this search finds during sync */
    bool pinned;             /* shown first in SearchesScreen, ahead of the normal sort order */
} bunny_db_search_t;

typedef struct
{
    bunny_db_search_t *items;
    size_t count;
} bunny_db_search_list_t;

typedef struct
{
    int64_t id; /* local db id, stable across syncs */
    bunny_db_site_t site;
    int64_t external_id; /* the site's own post/submission id */
    char *artist;
    char *title;
    char *description;
    char *rating;
    int score;
    int score_up;   /* 0 for Inkbunny -- no vote concept there */
    int score_down; /* 0 for Inkbunny -- no vote concept there */
    int fav_count;
    int comment_count;
    char *file_url;
    char *file_ext;
    char *file_md5;
    char *preview_url;
    int width;
    int height;
    char *created_at_site; /* the site's own created_at timestamp */
    char *cached_at;       /* when we last upserted this row */
    bool is_seen;
    bool is_favorited;
    char *sample_url; /* medium-quality variant (e621's "sample", Inkbunny's "screen"); may be NULL */
    int user_vote;    /* -1, 0 (no vote), or 1 -- always 0 for Inkbunny (M9.7.1) */
} bunny_db_post_t;

typedef struct
{
    bunny_db_post_t *items;
    size_t count;
} bunny_db_post_list_t;

typedef struct
{
    char *name;
    int count;
} bunny_db_tag_stat_t;

typedef struct
{
    bunny_db_tag_stat_t *items;
    size_t count;
} bunny_db_tag_stat_list_t;

/* One of a post's tags, with its category (e621: general/artist/copyright/
 * character/species/invalid/lore/meta; NULL for Inkbunny keywords, which
 * have no category concept at all). Feeds a post detail view's sectioned
 * tag display. */
typedef struct
{
    char *name;
    char *category; /* may be NULL */
} bunny_db_post_tag_t;

typedef struct
{
    bunny_db_post_tag_t *items;
    size_t count;
} bunny_db_post_tag_list_t;

/* A generic ordered list of strings -- feeds bunny_db_post_get_sources
 * (position-ordered source URLs), and anything else that just needs "a list
 * of strings" without per-item metadata. */
typedef struct
{
    char **items;
    size_t count;
} bunny_db_string_list_t;

/* A generic list of 64-bit ids -- feeds bunny_db_post_get_pool_ids and
 * bunny_db_post_relationships_t.children below. */
typedef struct
{
    int64_t *items;
    size_t count;
} bunny_db_int64_list_t;

/* e621 parent/child post relationships (site's own external ids -- a parent
 * or child post may never have been synced locally, so these aren't local
 * posts.id values). has_active_children mirrors e621's own flag: a post can
 * have_children=false in e621's model while a deleted child still exists, so
 * "active" is the meaningful signal for whether to show a children link at
 * all. Always all-false/empty for Inkbunny, which has no such concept. */
typedef struct
{
    bool has_parent;
    int64_t parent_external_id; /* valid only when has_parent */
    bool has_active_children;
    bunny_db_int64_list_t children; /* child external ids */
} bunny_db_post_relationships_t;

typedef struct
{
    int64_t id;
    int64_t post_id;
    char *file_path;
    char *checksum_md5;
    bool checksum_verified;
    char *downloaded_at;
} bunny_db_download_t;

typedef struct
{
    bunny_db_download_t *items;
    size_t count;
} bunny_db_download_list_t;

typedef enum
{
    BUNNY_DB_ACTION_FAVORITE_ADD,
    BUNNY_DB_ACTION_FAVORITE_REMOVE,
    BUNNY_DB_ACTION_VOTE,
    BUNNY_DB_ACTION_COMMENT,
} bunny_db_action_type_t;

const char *bunny_db_action_type_to_string(bunny_db_action_type_t action_type);

typedef enum
{
    BUNNY_DB_ACTION_STATUS_PENDING,
    BUNNY_DB_ACTION_STATUS_DONE,
    BUNNY_DB_ACTION_STATUS_FAILED,
} bunny_db_action_status_t;

typedef struct
{
    int64_t id;
    int64_t post_id;
    bunny_db_action_type_t action_type;
    char *payload; /* may be NULL; action-specific data, opaque to bunny_db */
    bunny_db_action_status_t status;
    char *created_at;
    char *attempted_at;  /* may be NULL if still pending */
    char *error_message; /* may be NULL */
} bunny_db_action_t;

typedef struct
{
    bunny_db_action_t *items;
    size_t count;
} bunny_db_action_list_t;

void bunny_db_account_free(bunny_db_account_t *account);
void bunny_db_search_free(bunny_db_search_t *search);
void bunny_db_search_list_free(bunny_db_search_list_t *list);
void bunny_db_post_free(bunny_db_post_t *post);
void bunny_db_post_list_free(bunny_db_post_list_t *list);
void bunny_db_tag_stat_free(bunny_db_tag_stat_t *stat);
void bunny_db_tag_stat_list_free(bunny_db_tag_stat_list_t *list);
void bunny_db_post_tag_free(bunny_db_post_tag_t *tag);
void bunny_db_post_tag_list_free(bunny_db_post_tag_list_t *list);
void bunny_db_string_list_free(bunny_db_string_list_t *list);
void bunny_db_int64_list_free(bunny_db_int64_list_t *list);
void bunny_db_post_relationships_free(bunny_db_post_relationships_t *relationships);
void bunny_db_download_free(bunny_db_download_t *download);
void bunny_db_download_list_free(bunny_db_download_list_t *list);
void bunny_db_action_free(bunny_db_action_t *action);
void bunny_db_action_list_free(bunny_db_action_list_t *list);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_DB_TYPES_H */
