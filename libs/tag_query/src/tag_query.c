#include "bunny_tag_query/tag_query.h"

#include <goblin/dyn_array.h>

#include <ctype.h>
#include <stdlib.h>
#include <string.h>

#define BUNNY_TAG_QUERY_MAX_DEPTH 10

/* e621's own real limit ("max 40 tags/search") -- a hard hint, enforced
 * here (e621 dialect only; Inkbunny has no documented cap) so the local
 * validator catches it before a real search attempt would fail remotely,
 * same reasoning as the depth-10 cap. Counts every tag anywhere in the
 * query, including nested inside groups -- it's a total, not a per-level
 * count. */
#define BUNNY_TAG_QUERY_MAX_TAGS 40

typedef enum
{
    BUNNY_TAG_QUERY_MODE_REQUIRED,
    BUNNY_TAG_QUERY_MODE_FORBIDDEN,
    BUNNY_TAG_QUERY_MODE_OR,
} bunny_tag_query_mode_t;

typedef enum
{
    BUNNY_TAG_QUERY_KIND_TAG,
    BUNNY_TAG_QUERY_KIND_GROUP,
} bunny_tag_query_kind_t;

GOBLIN_DYN_ARRAY_DECL(bunny_tag_query_node_ptr, bunny_tag_query_node_t *)

/* The AST node type is deliberately one shape at every level, including
 * the root returned by bunny_tag_query_parse (a synthetic, never-prefixed
 * KIND_GROUP wrapping the top-level terms) -- a group's own `children` is
 * exactly the same kind of term list the top level is, so evaluation
 * (see bunny_tag_query_matches) needs no separate "is this the root"
 * special case. */
struct bunny_tag_query_node
{
    bunny_tag_query_mode_t mode;
    bunny_tag_query_kind_t kind;
    char *tag;                               /* KIND_TAG only; owned; may contain '*' */
    bool has_wildcard;                       /* KIND_TAG only */
    bunny_tag_query_node_ptr_array children; /* KIND_GROUP only */
};

static bunny_tag_query_node_t *node_new_tag(const char *text, size_t len, bunny_tag_query_mode_t mode)
{
    bunny_tag_query_node_t *node = (bunny_tag_query_node_t *)calloc(1, sizeof(*node));
    if (!node) {
        return NULL;
    }
    node->kind = BUNNY_TAG_QUERY_KIND_TAG;
    node->mode = mode;
    node->tag = (char *)malloc(len + 1);
    if (!node->tag) {
        free(node);
        return NULL;
    }
    memcpy(node->tag, text, len);
    node->tag[len] = '\0';
    node->has_wildcard = memchr(text, '*', len) != NULL;
    return node;
}

static bunny_tag_query_node_t *node_new_group(bunny_tag_query_mode_t mode)
{
    bunny_tag_query_node_t *node = (bunny_tag_query_node_t *)calloc(1, sizeof(*node));
    if (!node) {
        return NULL;
    }
    node->kind = BUNNY_TAG_QUERY_KIND_GROUP;
    node->mode = mode;
    bunny_tag_query_node_ptr_array_init(&node->children);
    return node;
}

void bunny_tag_query_free(bunny_tag_query_node_t *node)
{
    if (!node) {
        return;
    }
    if (node->kind == BUNNY_TAG_QUERY_KIND_TAG) {
        free(node->tag);
    } else {
        for (size_t i = 0; i < node->children.count; i++) {
            bunny_tag_query_free(node->children.items[i]);
        }
        bunny_tag_query_node_ptr_array_free(&node->children);
    }
    free(node);
}

/* Only whitespace/'('/')'/NUL end a bare tag's text -- everything else
 * (including a literal '-'/'~'/':' in the middle of a tag, e.g.
 * "x-ray"/"rating:e") is ordinary tag-body text. A leading '-'/'~' is only
 * ever treated as a prefix, never literal tag text, matching real e621/
 * Inkbunny tag names (neither site has a tag starting with either
 * character). */
static bool is_delim(char c)
{
    return c == '\0' || c == '(' || c == ')' || isspace((unsigned char)c);
}

/* Parses one term list (a run of space-separated terms at a single grammar
 * level -- either the whole top-level query, or one group's contents)
 * starting at *pos, pushing each parsed term into group_node->children.
 * Stops at end-of-string, or (when in_group) at a ')' that properly closes
 * this level -- in that case *pos is left pointing AT the ')' (not
 * consumed), so the caller (the '(' handling branch below) can consume it
 * itself after also checking the child list isn't empty. `total_tags` is
 * shared across the entire recursion (not reset per level) -- it's how
 * BUNNY_TAG_QUERY_MAX_TAGS counts every tag in the query as one total,
 * including ones nested inside groups. */
static bool parse_term_list(const char *text, size_t *pos, bunny_tag_query_dialect_t dialect, size_t depth, bool in_group, bunny_tag_query_node_t *group_node, size_t *total_tags, size_t *out_error_pos)
{
    bool first = true;
    for (;;) {
        size_t ws_start = *pos;
        while (isspace((unsigned char)text[*pos])) {
            (*pos)++;
        }
        bool skipped_ws = *pos > ws_start;

        if (text[*pos] == '\0') {
            if (in_group) {
                if (out_error_pos) {
                    *out_error_pos = *pos;
                }
                return false; /* unterminated group */
            }
            return true;
        }
        if (text[*pos] == ')') {
            if (!in_group) {
                if (out_error_pos) {
                    *out_error_pos = *pos;
                }
                return false; /* unmatched ')' */
            }
            if (!first && !skipped_ws) {
                if (out_error_pos) {
                    *out_error_pos = *pos;
                }
                return false; /* missing required space right before ')' */
            }
            return true;
        }
        if (!first && !skipped_ws) {
            if (out_error_pos) {
                *out_error_pos = *pos;
            }
            return false; /* two terms with no separating space */
        }

        bunny_tag_query_mode_t mode = BUNNY_TAG_QUERY_MODE_REQUIRED;
        if (text[*pos] == '-') {
            mode = BUNNY_TAG_QUERY_MODE_FORBIDDEN;
            (*pos)++;
        } else if (text[*pos] == '~') {
            if (dialect != BUNNY_TAG_QUERY_DIALECT_E621) {
                if (out_error_pos) {
                    *out_error_pos = *pos; /* '~' (OR) isn't supported on Inkbunny */
                }
                return false;
            }
            mode = BUNNY_TAG_QUERY_MODE_OR;
            (*pos)++;
        }

        if (text[*pos] == '(') {
            size_t open_pos = *pos;
            if (dialect != BUNNY_TAG_QUERY_DIALECT_E621) {
                if (out_error_pos) {
                    *out_error_pos = open_pos; /* groups aren't supported on Inkbunny */
                }
                return false;
            }
            if (depth + 1 > BUNNY_TAG_QUERY_MAX_DEPTH) {
                if (out_error_pos) {
                    *out_error_pos = open_pos;
                }
                return false;
            }
            (*pos)++;
            if (!isspace((unsigned char)text[*pos])) {
                if (out_error_pos) {
                    *out_error_pos = *pos;
                }
                return false; /* missing required space right after '(' */
            }
            bunny_tag_query_node_t *child = node_new_group(mode);
            if (!child) {
                if (out_error_pos) {
                    *out_error_pos = open_pos;
                }
                return false;
            }
            if (!parse_term_list(text, pos, dialect, depth + 1, true, child, total_tags, out_error_pos)) {
                bunny_tag_query_free(child);
                return false;
            }
            if (child->children.count == 0) {
                if (out_error_pos) {
                    *out_error_pos = open_pos;
                }
                bunny_tag_query_free(child);
                return false; /* empty group */
            }
            /* parse_term_list above returns with *pos at ')' uncomsumed. */
            (*pos)++;
            if (!bunny_tag_query_node_ptr_array_push(&group_node->children, child)) {
                bunny_tag_query_free(child);
                if (out_error_pos) {
                    *out_error_pos = open_pos;
                }
                return false;
            }
        } else {
            size_t tag_start = *pos;
            while (!is_delim(text[*pos])) {
                (*pos)++;
            }
            size_t tag_len = *pos - tag_start;
            if (tag_len == 0) {
                if (out_error_pos) {
                    *out_error_pos = tag_start;
                }
                return false; /* bare '-'/'~' with nothing after it */
            }
            if (dialect != BUNNY_TAG_QUERY_DIALECT_E621) {
                const char *star = (const char *)memchr(text + tag_start, '*', tag_len);
                if (star) {
                    if (out_error_pos) {
                        *out_error_pos = (size_t)(star - text); /* wildcards aren't supported on Inkbunny */
                    }
                    return false;
                }
            }
            bunny_tag_query_node_t *child = node_new_tag(text + tag_start, tag_len, mode);
            if (!child) {
                if (out_error_pos) {
                    *out_error_pos = tag_start;
                }
                return false;
            }
            if (!bunny_tag_query_node_ptr_array_push(&group_node->children, child)) {
                bunny_tag_query_free(child);
                if (out_error_pos) {
                    *out_error_pos = tag_start;
                }
                return false;
            }
            (*total_tags)++;
            if (dialect == BUNNY_TAG_QUERY_DIALECT_E621 && *total_tags > BUNNY_TAG_QUERY_MAX_TAGS) {
                if (out_error_pos) {
                    *out_error_pos = tag_start;
                }
                return false; /* e621's own "max 40 tags/search" limit */
            }
        }
        first = false;
    }
}

bool bunny_tag_query_parse(const char *text, bunny_tag_query_dialect_t dialect, bunny_tag_query_node_t **out_root, size_t *out_error_pos)
{
    if (out_root) {
        *out_root = NULL;
    }
    if (!text || !out_root) {
        if (out_error_pos) {
            *out_error_pos = 0;
        }
        return false;
    }

    bunny_tag_query_node_t *root = node_new_group(BUNNY_TAG_QUERY_MODE_REQUIRED);
    if (!root) {
        if (out_error_pos) {
            *out_error_pos = 0;
        }
        return false;
    }

    size_t pos = 0;
    size_t total_tags = 0;
    if (!parse_term_list(text, &pos, dialect, 0, false, root, &total_tags, out_error_pos)) {
        bunny_tag_query_free(root);
        return false;
    }

    *out_root = root;
    return true;
}

bool bunny_tag_query_validate(const char *text, bunny_tag_query_dialect_t dialect, size_t *out_error_pos)
{
    bunny_tag_query_node_t *root = NULL;
    bool ok = bunny_tag_query_parse(text, dialect, &root, out_error_pos);
    if (root) {
        bunny_tag_query_free(root);
    }
    return ok;
}

static bool evaluate_term_list(const bunny_tag_query_node_t *group, const char *const *tags, size_t tag_count);

/* A wildcarded tag matches by comparing only the text before the first
 * '*' as a prefix -- e621's own convention (e.g. "african_*") has the
 * wildcard trailing in practice; this doesn't special-case where in the
 * tag text the '*' sits, it just always prefix-matches up to it. */
static bool tag_matches_one(const bunny_tag_query_node_t *node, const char *tag)
{
    if (!node->has_wildcard) {
        return strcmp(node->tag, tag) == 0;
    }
    const char *star = strchr(node->tag, '*');
    size_t prefix_len = (size_t)(star - node->tag);
    return strncmp(node->tag, tag, prefix_len) == 0;
}

static bool atom_matches(const bunny_tag_query_node_t *node, const char *const *tags, size_t tag_count)
{
    if (node->kind == BUNNY_TAG_QUERY_KIND_TAG) {
        for (size_t i = 0; i < tag_count; i++) {
            if (tag_matches_one(node, tags[i])) {
                return true;
            }
        }
        return false;
    }
    return evaluate_term_list(node, tags, tag_count);
}

/* Partitions `group`'s own children into required/forbidden/or sets and
 * applies e621's AND/OR/NOT semantics: every required atom must match,
 * no forbidden atom may match, and -- only if the or-set is non-empty --
 * at least one or-set atom must match. An empty children list (the
 * degenerate "vacuous" case -- an empty top-level query, never an empty
 * group, which the parser rejects outright) evaluates to true. */
static bool evaluate_term_list(const bunny_tag_query_node_t *group, const char *const *tags, size_t tag_count)
{
    bool any_or = false;
    bool or_matched = false;
    for (size_t i = 0; i < group->children.count; i++) {
        const bunny_tag_query_node_t *child = group->children.items[i];
        switch (child->mode) {
            case BUNNY_TAG_QUERY_MODE_REQUIRED:
                if (!atom_matches(child, tags, tag_count)) {
                    return false;
                }
                break;
            case BUNNY_TAG_QUERY_MODE_FORBIDDEN:
                if (atom_matches(child, tags, tag_count)) {
                    return false;
                }
                break;
            case BUNNY_TAG_QUERY_MODE_OR:
                any_or = true;
                if (atom_matches(child, tags, tag_count)) {
                    or_matched = true;
                }
                break;
        }
    }
    return !any_or || or_matched;
}

bool bunny_tag_query_matches(const bunny_tag_query_node_t *root, const char *const *tags, size_t tag_count)
{
    if (!root) {
        return false;
    }
    return evaluate_term_list(root, tags, tag_count);
}
