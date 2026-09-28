#ifndef INKBUNNY_TYPES_H
#define INKBUNNY_TYPES_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct
{
    int64_t file_id;
    char *file_name;
    char *url_full;
    char *url_screen;
    char *url_preview;
    char *mimetype;
    char *md5; /* full_file_md5 */
    int full_width;
    int full_height;
    int order; /* submission_file_order */
} inkbunny_file_t;

typedef struct
{
    inkbunny_file_t *items;
    size_t count;
} inkbunny_file_list_t;

typedef struct
{
    int64_t keyword_id;
    char *keyword_name;
    bool contributed;
    int submissions_count;
} inkbunny_keyword_t;

typedef struct
{
    inkbunny_keyword_t *items;
    size_t count;
} inkbunny_keyword_list_t;

/* A "Rating Tag": fine-grained sex/violence content classification (e.g.
 * Nudity, Violence), distinct from the single rating_id/rating_name pair
 * on inkbunny_submission_t below. */
typedef struct
{
    int64_t content_tag_id;
    char *name;
    char *description;
    int rating_id;
} inkbunny_content_rating_t;

typedef struct
{
    inkbunny_content_rating_t *items;
    size_t count;
} inkbunny_content_rating_list_t;

typedef struct
{
    int64_t pool_id;
    char *name;
    char *description;
    int count;
    /* Adjacent submission ids for navigating this pool from the current
     * submission; 0 if there's no submission on that side. Inkbunny has no
     * endpoint to list an entire pool's submissions at once (unlike e621) -
     * only this per-submission left/right neighbor. */
    int64_t left_submission_id;
    int64_t right_submission_id;
} inkbunny_pool_t;

typedef struct
{
    inkbunny_pool_t *items;
    size_t count;
} inkbunny_pool_list_t;

typedef struct
{
    int64_t submission_id;
    char *username;
    int64_t user_id;
    char *title;
    char *description; /* only populated when fetched via inkbunny_get_submission(s) */
    int rating_id;
    char *rating_name;
    inkbunny_content_rating_list_t content_ratings;
    inkbunny_keyword_list_t keywords;
    inkbunny_file_list_t files;
    inkbunny_pool_list_t pools;
    char *thumbnail_url; /* thumbnail_url_large_noncustom; convenience for list/grid views */
    int submission_type_id;
    char *type_name;
    bool is_favorite;
    int favorites_count;
    int comments_count; /* count only -- see inkbunny/client.h for why comment content isn't available */
    int views;
    char *created_at;
} inkbunny_submission_t;

typedef struct
{
    inkbunny_submission_t *items;
    size_t count;
} inkbunny_submission_list_t;

void inkbunny_file_free(inkbunny_file_t *file);
void inkbunny_file_list_free(inkbunny_file_list_t *list);
void inkbunny_keyword_free(inkbunny_keyword_t *keyword);
void inkbunny_keyword_list_free(inkbunny_keyword_list_t *list);
void inkbunny_content_rating_free(inkbunny_content_rating_t *rating);
void inkbunny_content_rating_list_free(inkbunny_content_rating_list_t *list);
void inkbunny_pool_free(inkbunny_pool_t *pool);
void inkbunny_pool_list_free(inkbunny_pool_list_t *list);
void inkbunny_submission_free(inkbunny_submission_t *submission);
void inkbunny_submission_list_free(inkbunny_submission_list_t *list);

#ifdef __cplusplus
}
#endif

#endif /* INKBUNNY_TYPES_H */
