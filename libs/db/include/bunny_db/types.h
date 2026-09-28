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
    char *label;
    char *query;
    int interval_hours;
    char *created_at;
    char *last_run_at; /* NULL if this search has never run */
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

void bunny_db_search_free(bunny_db_search_t *search);
void bunny_db_search_list_free(bunny_db_search_list_t *list);
void bunny_db_post_free(bunny_db_post_t *post);
void bunny_db_post_list_free(bunny_db_post_list_t *list);
void bunny_db_tag_stat_free(bunny_db_tag_stat_t *stat);
void bunny_db_tag_stat_list_free(bunny_db_tag_stat_list_t *list);
void bunny_db_download_free(bunny_db_download_t *download);
void bunny_db_download_list_free(bunny_db_download_list_t *list);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_DB_TYPES_H */
