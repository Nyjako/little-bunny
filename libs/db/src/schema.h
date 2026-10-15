#ifndef BUNNY_DB_SCHEMA_H
#define BUNNY_DB_SCHEMA_H

/* Idempotent: every statement is IF NOT EXISTS, so this is safe to run on
 * every bunny_db_open() against an already-populated database. New tables
 * can always go here directly; a change to an existing table (new column,
 * etc.) needs an ALTER TABLE instead, which IF NOT EXISTS can't express --
 * those live in db.c's bunny_db_apply_migrations(), tracked via
 * schema_migrations (defined below) so each runs exactly once. */
static const char *const BUNNY_DB_SCHEMA_SQL = "PRAGMA foreign_keys = ON;"
                                               "CREATE TABLE IF NOT EXISTS schema_migrations ("
                                               "    version INTEGER PRIMARY KEY,"
                                               "    applied_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))"
                                               ");"
                                               "CREATE TABLE IF NOT EXISTS accounts ("
                                               "    id INTEGER PRIMARY KEY,"
                                               "    site TEXT NOT NULL UNIQUE CHECK (site IN ('e621', 'inkbunny'))," /* one account per site */
                                               "    username TEXT NOT NULL,"
                                               "    secret TEXT NOT NULL," /* e621 API key, or Inkbunny password -- stored plain, see M4 in architecture.md */
                                               "    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))"
                                               ");"
                                               "CREATE TABLE IF NOT EXISTS searches ("
                                               "    id INTEGER PRIMARY KEY,"
                                               "    site TEXT NOT NULL CHECK (site IN ('e621', 'inkbunny')),"
                                               "    label TEXT NOT NULL,"
                                               "    query TEXT NOT NULL,"
                                               "    interval_hours INTEGER NOT NULL DEFAULT 24,"
                                               "    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),"
                                               "    last_run_at TEXT"
                                               ");"
                                               "CREATE TABLE IF NOT EXISTS posts ("
                                               "    id INTEGER PRIMARY KEY,"
                                               "    site TEXT NOT NULL CHECK (site IN ('e621', 'inkbunny')),"
                                               "    external_id INTEGER NOT NULL,"
                                               "    artist TEXT,"
                                               "    title TEXT,"
                                               "    description TEXT,"
                                               "    rating TEXT,"
                                               "    score INTEGER NOT NULL DEFAULT 0,"
                                               "    fav_count INTEGER NOT NULL DEFAULT 0,"
                                               "    comment_count INTEGER NOT NULL DEFAULT 0,"
                                               "    file_url TEXT,"
                                               "    file_ext TEXT,"
                                               "    file_md5 TEXT,"
                                               "    preview_url TEXT,"
                                               "    width INTEGER,"
                                               "    height INTEGER,"
                                               "    created_at_site TEXT,"
                                               "    cached_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),"
                                               "    UNIQUE (site, external_id)"
                                               ");"
                                               "CREATE TABLE IF NOT EXISTS tags ("
                                               "    id INTEGER PRIMARY KEY,"
                                               "    site TEXT NOT NULL CHECK (site IN ('e621', 'inkbunny')),"
                                               "    name TEXT NOT NULL,"
                                               "    UNIQUE (site, name)"
                                               ");"
                                               "CREATE TABLE IF NOT EXISTS post_tags ("
                                               "    post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,"
                                               "    tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,"
                                               "    PRIMARY KEY (post_id, tag_id)"
                                               ");"
                                               /* A tag's category is a global property of the tag itself (e621's own
                                                * model -- a given tag name is always the same category site-wide), not
                                                * per-post, so this keys on tag_id alone. Inkbunny keywords have no
                                                * category concept and simply never get a row here. */
                                               "CREATE TABLE IF NOT EXISTS tag_categories ("
                                               "    tag_id INTEGER PRIMARY KEY REFERENCES tags(id) ON DELETE CASCADE,"
                                               "    category TEXT NOT NULL CHECK (category IN "
                                               "        ('general', 'artist', 'copyright', 'character', 'species', 'invalid', 'lore', 'meta'))"
                                               ");"
                                               /* position preserves the site's own source ordering (sources[0] is
                                                * usually "the" canonical source) -- plain row order isn't reliable
                                                * once rows get replaced across re-syncs. */
                                               "CREATE TABLE IF NOT EXISTS post_sources ("
                                               "    post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,"
                                               "    position INTEGER NOT NULL,"
                                               "    url TEXT NOT NULL,"
                                               "    PRIMARY KEY (post_id, position)"
                                               ");"
                                               /* parent_external_id/has_active_children/child_external_id are the
                                                * *site's own* ids, not local posts.id -- a parent/child may never
                                                * have been synced locally, so there's nothing to foreign-key against.
                                                * e621 only; Inkbunny posts never get rows in any of these three
                                                * tables (no relationship/pool concept there). */
                                               "CREATE TABLE IF NOT EXISTS post_relationships ("
                                               "    post_id INTEGER PRIMARY KEY REFERENCES posts(id) ON DELETE CASCADE,"
                                               "    parent_external_id INTEGER,"
                                               "    has_active_children INTEGER NOT NULL DEFAULT 0"
                                               ");"
                                               "CREATE TABLE IF NOT EXISTS post_children ("
                                               "    post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,"
                                               "    child_external_id INTEGER NOT NULL,"
                                               "    PRIMARY KEY (post_id, child_external_id)"
                                               ");"
                                               "CREATE TABLE IF NOT EXISTS post_pools ("
                                               "    post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,"
                                               "    pool_id INTEGER NOT NULL,"
                                               "    PRIMARY KEY (post_id, pool_id)"
                                               ");"
                                               /* The medium-quality image variant (e621's "sample", Inkbunny's "screen")
                                                * -- a single nullable URL per post, same one-to-one shape as
                                                * post_relationships (the PK *is* the FK), upserted unconditionally on
                                                * every sync so a value that disappears on resync doesn't linger. */
                                               "CREATE TABLE IF NOT EXISTS post_media_variants ("
                                               "    post_id INTEGER PRIMARY KEY REFERENCES posts(id) ON DELETE CASCADE,"
                                               "    sample_url TEXT"
                                               ");"
                                               "CREATE TABLE IF NOT EXISTS search_results ("
                                               "    search_id INTEGER NOT NULL REFERENCES searches(id) ON DELETE CASCADE,"
                                               "    post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,"
                                               "    found_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),"
                                               "    PRIMARY KEY (search_id, post_id)"
                                               ");"
                                               "CREATE TABLE IF NOT EXISTS seen_posts ("
                                               "    post_id INTEGER PRIMARY KEY REFERENCES posts(id) ON DELETE CASCADE,"
                                               "    seen_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))"
                                               ");"
                                               "CREATE TABLE IF NOT EXISTS favorites ("
                                               "    post_id INTEGER PRIMARY KEY REFERENCES posts(id) ON DELETE CASCADE,"
                                               "    stars INTEGER," /* Inkbunny 1-3; NULL for e621's plain favorite */
                                               "    favorited_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))"
                                               ");"
                                               /* e621 only -- Inkbunny has no vote API. Mirrors the caller's own most
                                                * recently *successfully sent* vote direction (M9.7.1); e621's post API
                                                * has no "did I vote, and which way" field to resync this from, so this
                                                * is the only source of truth for it. */
                                               "CREATE TABLE IF NOT EXISTS votes ("
                                               "    post_id INTEGER PRIMARY KEY REFERENCES posts(id) ON DELETE CASCADE,"
                                               "    score INTEGER NOT NULL CHECK (score IN (-1, 1)),"
                                               "    voted_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))"
                                               ");"
                                               "CREATE TABLE IF NOT EXISTS downloads ("
                                               "    id INTEGER PRIMARY KEY,"
                                               "    post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,"
                                               "    file_path TEXT NOT NULL,"
                                               "    checksum_md5 TEXT,"
                                               "    checksum_verified INTEGER NOT NULL DEFAULT 0,"
                                               "    downloaded_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))"
                                               ");"
                                               "CREATE TABLE IF NOT EXISTS action_queue ("
                                               "    id INTEGER PRIMARY KEY,"
                                               "    post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,"
                                               "    action_type TEXT NOT NULL CHECK (action_type IN ('favorite_add', 'favorite_remove', 'vote', 'comment')),"
                                               "    payload TEXT," /* action-specific data, e.g. {"score":1} for a vote -- opaque to bunny_db */
                                               "    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'done', 'failed')),"
                                               "    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),"
                                               "    attempted_at TEXT,"
                                               "    error_message TEXT"
                                               ");"
                                               /* Not a foreign key into tags(id) -- a tag someone wants to blacklist
                                                * may never have been synced locally, so it has to be stored as plain
                                                * text rather than requiring a tags row to already exist (M13.3). */
                                               "CREATE TABLE IF NOT EXISTS blacklist_tags ("
                                               "    id INTEGER PRIMARY KEY,"
                                               "    site TEXT NOT NULL CHECK (site IN ('e621', 'inkbunny')),"
                                               "    tag TEXT NOT NULL,"
                                               "    UNIQUE (site, tag)"
                                               ");"
                                               /* Single-row table (id is always 1) for server-wide settings that
                                                * aren't tied to any one search or account. The INSERT OR IGNORE
                                                * seeds the one row on first open; every open after that is a no-op,
                                                * same idempotency as the CREATE TABLE above it. */
                                               "CREATE TABLE IF NOT EXISTS server_settings ("
                                               "    id INTEGER PRIMARY KEY CHECK (id = 1),"
                                               "    default_sync_interval_hours INTEGER NOT NULL DEFAULT 24"
                                               ");"
                                               "INSERT OR IGNORE INTO server_settings (id, default_sync_interval_hours) VALUES (1, 24);"
                                               "CREATE INDEX IF NOT EXISTS idx_post_tags_tag_id ON post_tags(tag_id);"
                                               "CREATE INDEX IF NOT EXISTS idx_search_results_search_id ON search_results(search_id);"
                                               "CREATE INDEX IF NOT EXISTS idx_downloads_post_id ON downloads(post_id);"
                                               "CREATE INDEX IF NOT EXISTS idx_action_queue_status ON action_queue(status);";

#endif /* BUNNY_DB_SCHEMA_H */
