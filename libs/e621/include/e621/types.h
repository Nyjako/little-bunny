#ifndef E621_TYPES_H
#define E621_TYPES_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum
{
    E621_RATING_SAFE,
    E621_RATING_QUESTIONABLE,
    E621_RATING_EXPLICIT,
    E621_RATING_UNKNOWN,
} e621_rating_t;

typedef struct
{
    char *url; /* may be NULL if the site didn't provide one (e.g. no sample) */
    char *ext; /* may be NULL */
    char *md5; /* may be NULL; only ever set on the main "file" variant */
    int width;
    int height;
    int64_t size; /* bytes; 0 if unknown */
} e621_file_t;

typedef struct
{
    int up;
    int down;
    int total;
} e621_score_t;

typedef struct
{
    char **items;
    size_t count;
} e621_string_list_t;

typedef struct
{
    e621_string_list_t general;
    e621_string_list_t artist;
    e621_string_list_t copyright;
    e621_string_list_t character;
    e621_string_list_t species;
    e621_string_list_t invalid;
    e621_string_list_t lore;
    e621_string_list_t meta;
} e621_tags_t;

typedef struct
{
    bool has_parent;
    int64_t parent_id;
    bool has_children;
    bool has_active_children;
    int64_t *children;
    size_t child_count;
} e621_relationships_t;

typedef struct
{
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
    e621_relationships_t relationships;
} e621_post_t;

typedef struct
{
    e621_post_t *items;
    size_t count;
} e621_post_list_t;

typedef struct
{
    int64_t id;
    int64_t post_id;
    char *creator_name;
    char *body;
    char *created_at;
} e621_comment_t;

typedef struct
{
    e621_comment_t *items;
    size_t count;
} e621_comment_list_t;

typedef enum
{
    E621_POOL_CATEGORY_SERIES,
    E621_POOL_CATEGORY_COLLECTION,
    E621_POOL_CATEGORY_UNKNOWN,
} e621_pool_category_t;

typedef struct
{
    int64_t id;
    char *name;
    char *description;
    char *created_at;
    char *updated_at;
    int64_t creator_id;
    char *creator_name;
    bool is_active;
    e621_pool_category_t category;
    int64_t *post_ids; /* ordered */
    size_t post_count;
} e621_pool_t;

typedef enum
{
    E621_TAG_CATEGORY_GENERAL,
    E621_TAG_CATEGORY_ARTIST,
    E621_TAG_CATEGORY_COPYRIGHT,
    E621_TAG_CATEGORY_CHARACTER,
    E621_TAG_CATEGORY_SPECIES,
    E621_TAG_CATEGORY_INVALID,
    E621_TAG_CATEGORY_LORE,
    E621_TAG_CATEGORY_META,
    E621_TAG_CATEGORY_UNKNOWN,
} e621_tag_category_t;

typedef struct
{
    int64_t id;
    char *name;
    int post_count;
    e621_tag_category_t category;
    char *related_tags; /* raw, space-separated; e621 doesn't structure this further */
    bool is_locked;
    char *created_at;
    char *updated_at;
} e621_tag_t;

typedef struct
{
    e621_tag_t *items;
    size_t count;
} e621_tag_list_t;

typedef struct
{
    int64_t id;
    char *title;
    char *body; /* [[wiki link]]/{{author}}/`thumb #id` markup, unparsed -- see M50's shared parser */
    e621_string_list_t other_names;
    bool is_locked;
    char *created_at;
    char *updated_at;
} e621_wiki_page_t;

typedef struct
{
    int64_t id;
    char *antecedent_name;
    char *consequent_name;
    char *status;
    int post_count;
} e621_tag_alias_t;

typedef struct
{
    e621_tag_alias_t *items;
    size_t count;
} e621_tag_alias_list_t;

typedef struct
{
    int64_t id;
    char *antecedent_name;
    char *consequent_name;
    char *status;
} e621_tag_implication_t;

typedef struct
{
    e621_tag_implication_t *items;
    size_t count;
} e621_tag_implication_list_t;

void e621_string_list_free(e621_string_list_t *list);
void e621_file_free(e621_file_t *file);
void e621_post_free(e621_post_t *post);
void e621_post_list_free(e621_post_list_t *list);
void e621_comment_free(e621_comment_t *comment);
void e621_comment_list_free(e621_comment_list_t *list);
void e621_pool_free(e621_pool_t *pool);
void e621_tag_free(e621_tag_t *tag);
void e621_tag_list_free(e621_tag_list_t *list);
void e621_wiki_page_free(e621_wiki_page_t *page);
void e621_tag_alias_free(e621_tag_alias_t *alias);
void e621_tag_alias_list_free(e621_tag_alias_list_t *list);
void e621_tag_implication_free(e621_tag_implication_t *implication);
void e621_tag_implication_list_free(e621_tag_implication_list_t *list);

#ifdef __cplusplus
}
#endif

#endif /* E621_TYPES_H */
