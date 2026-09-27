#ifndef E621_TYPES_H
#define E621_TYPES_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    E621_RATING_SAFE,
    E621_RATING_QUESTIONABLE,
    E621_RATING_EXPLICIT,
    E621_RATING_UNKNOWN,
} e621_rating_t;

typedef struct {
    char *url;    /* may be NULL if the site didn't provide one (e.g. no sample) */
    char *ext;    /* may be NULL */
    char *md5;    /* may be NULL; only ever set on the main "file" variant */
    int width;
    int height;
    int64_t size; /* bytes; 0 if unknown */
} e621_file_t;

typedef struct {
    int up;
    int down;
    int total;
} e621_score_t;

typedef struct {
    char **items;
    size_t count;
} e621_string_list_t;

typedef struct {
    e621_string_list_t general;
    e621_string_list_t artist;
    e621_string_list_t copyright;
    e621_string_list_t character;
    e621_string_list_t species;
    e621_string_list_t invalid;
    e621_string_list_t lore;
    e621_string_list_t meta;
} e621_tags_t;

typedef struct {
    int64_t id;
    char *created_at;
    e621_file_t file;
    e621_file_t preview;
    e621_file_t sample;
    e621_score_t score;
    int fav_count;
    bool is_favorited;
    e621_rating_t rating;
    e621_tags_t tags;
    e621_string_list_t sources;
    char *description;
    int comment_count;
    int64_t *pool_ids;
    size_t pool_count;
} e621_post_t;

typedef struct {
    e621_post_t *items;
    size_t count;
} e621_post_list_t;

typedef struct {
    int64_t id;
    int64_t post_id;
    char *creator_name;
    char *body;
    char *created_at;
} e621_comment_t;

typedef struct {
    e621_comment_t *items;
    size_t count;
} e621_comment_list_t;

void e621_string_list_free(e621_string_list_t *list);
void e621_file_free(e621_file_t *file);
void e621_post_free(e621_post_t *post);
void e621_post_list_free(e621_post_list_t *list);
void e621_comment_free(e621_comment_t *comment);
void e621_comment_list_free(e621_comment_list_t *list);

#ifdef __cplusplus
}
#endif

#endif /* E621_TYPES_H */
