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
                                               /* A folder-like way to organize saved searches in the UI (M21) -- flat,
                                                * not nested. A search's membership lives on searches.group_id
                                                * (added via migration, since it's a column on an existing table),
                                                * not here. */
                                               "CREATE TABLE IF NOT EXISTS search_groups ("
                                               "    id INTEGER PRIMARY KEY,"
                                               "    name TEXT NOT NULL,"
                                               "    pinned INTEGER NOT NULL DEFAULT 0,"
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
                                               /* Every file on a post, in Inkbunny's own submission_file_order
                                                * (M28) -- a saved search's cached posts.file_url/width/height/etc.
                                                * columns keep representing just the FIRST file, exactly as before;
                                                * this table is purely additive, storing the complete set (including
                                                * that same first file again, redundantly, same tradeoff as every
                                                * other post_* side table here) so a multi-file submission (Inkbunny
                                                * Picture Series/Comic/Portfolio/Music - Album) doesn't lose every
                                                * file after the first. Generic capability, not Inkbunny-named --
                                                * e621 posts are always structurally single-file (e621's own
                                                * multi-image concept is entirely separate posts linked via pools),
                                                * so this table simply stays empty for every e621 post, the mirror
                                                * image of post_relationships/post_children always staying empty for
                                                * Inkbunny. */
                                               "CREATE TABLE IF NOT EXISTS post_files ("
                                               "    post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,"
                                               "    position INTEGER NOT NULL,"
                                               "    file_url TEXT NOT NULL,"
                                               "    sample_url TEXT,"
                                               "    preview_url TEXT,"
                                               "    file_ext TEXT,"
                                               "    file_md5 TEXT,"
                                               "    width INTEGER NOT NULL DEFAULT 0,"
                                               "    height INTEGER NOT NULL DEFAULT 0,"
                                               "    mimetype TEXT,"
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
                                               /* Single-row cache (M40) for the tag-stats screen's unified report --
                                                * computing it (favorited/used tags, favorited pools, most-viewed
                                                * searches, each a full-table aggregate) on every page open is what
                                                * hung the screen in the first place. report_json is the whole
                                                * report, pre-serialized by bunny_core -- this table doesn't need to
                                                * know its shape, only cache it. No row at all means "never
                                                * computed." */
                                               "CREATE TABLE IF NOT EXISTS stats_report_cache ("
                                               "    id INTEGER PRIMARY KEY CHECK (id = 1),"
                                               "    computed_at TEXT NOT NULL,"
                                               "    report_json TEXT NOT NULL"
                                               ");"
                                               /* No REFERENCES posts(id) here, unlike action_queue above -- a
                                                * networked-mode client keeps its download queue in its own small
                                                * dedicated local db (M62 follow-up), which never has a populated
                                                * posts table to reference. A post_id that no longer resolves via
                                                * bunny_core_post_get is already tolerated by every caller. */
                                               "CREATE TABLE IF NOT EXISTS download_queue ("
                                               "    id INTEGER PRIMARY KEY,"
                                               "    post_id INTEGER NOT NULL,"
                                               "    status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'downloading', 'succeeded', 'checksum_mismatch', 'failed')),"
                                               "    failure_reason TEXT,"
                                               "    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))"
                                               ");"
                                               /* M51 v2: a persisted, download-backed slideshow. default_posts_per_search/
                                                * max_total_posts are nullable ("infinite"/"no cap") -- stored as plain
                                                * SQLite NULL, read back via bunny_db_slideshow_t's own has_* flags
                                                * (0 is a valid count, so a sentinel int would be ambiguous here). */
                                               "CREATE TABLE IF NOT EXISTS slideshows ("
                                               "    id INTEGER PRIMARY KEY,"
                                               "    label TEXT NOT NULL,"
                                               "    default_posts_per_search INTEGER,"
                                               "    max_total_posts INTEGER,"
                                               "    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))"
                                               ");"
                                               /* One search/pool linked into a slideshow. override_count NULL means
                                                * "use the parent slideshow's own default_posts_per_search." Deleting
                                                * the slideshow or the underlying search cascades here -- and from here
                                                * into slideshow_posts below -- so a slideshow never outlives its own
                                                * rows getting cleaned up; the app-level "also delete the downloaded
                                                * files?" question is a separate, deliberate decision made before this
                                                * row is ever removed, not something this schema can know about. */
                                               "CREATE TABLE IF NOT EXISTS slideshow_searches ("
                                               "    slideshow_id INTEGER NOT NULL REFERENCES slideshows(id) ON DELETE CASCADE,"
                                               "    search_id INTEGER NOT NULL REFERENCES searches(id) ON DELETE CASCADE,"
                                               "    override_count INTEGER,"
                                               "    added_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),"
                                               "    PRIMARY KEY (slideshow_id, search_id)"
                                               ");"
                                               /* A post currently committed to a slideshow, via a specific search_id
                                                * (so a per-search reroll/preview can scope to just this search's own
                                                * picks, and a fresh pick/reroll knows which posts to exclude from
                                                * duplicating -- see bunny_db_slideshow_all_post_ids). */
                                               "CREATE TABLE IF NOT EXISTS slideshow_posts ("
                                               "    slideshow_id INTEGER NOT NULL REFERENCES slideshows(id) ON DELETE CASCADE,"
                                               "    search_id INTEGER NOT NULL REFERENCES searches(id) ON DELETE CASCADE,"
                                               "    post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,"
                                               "    PRIMARY KEY (slideshow_id, post_id)"
                                               ");"
                                               /* Per-slideshow tag exclusion -- additive to, not a replacement for,
                                                * blacklist_tags above. Unlike that per-site table, this is NOT
                                                * exempted for a favorites- or pool-sourced search (a slideshow
                                                * auto-advances on a timer, so content that needs to be read, like a
                                                * comic, can't be consumed in time regardless of where it came
                                                * from). Same simple/complex tag-query split as blacklist_tags, just
                                                * keyed by slideshow_id instead of site; since a slideshow can mix
                                                * e621 and Inkbunny searches, rules are always stored/validated under
                                                * e621's dialect (the strict superset) -- see
                                                * bunny_core_slideshow_blacklist_add. */
                                               "CREATE TABLE IF NOT EXISTS slideshow_blacklist_tags ("
                                               "    id INTEGER PRIMARY KEY,"
                                               "    slideshow_id INTEGER NOT NULL REFERENCES slideshows(id) ON DELETE CASCADE,"
                                               "    tag TEXT NOT NULL,"
                                               "    UNIQUE (slideshow_id, tag)"
                                               ");"
                                               "CREATE INDEX IF NOT EXISTS idx_post_tags_tag_id ON post_tags(tag_id);"
                                               "CREATE INDEX IF NOT EXISTS idx_search_results_search_id ON search_results(search_id);"
                                               "CREATE INDEX IF NOT EXISTS idx_action_queue_status ON action_queue(status);"
                                               "CREATE INDEX IF NOT EXISTS idx_download_queue_status ON download_queue(status);"
                                               "CREATE INDEX IF NOT EXISTS idx_slideshow_searches_slideshow_id ON slideshow_searches(slideshow_id);"
                                               "CREATE INDEX IF NOT EXISTS idx_slideshow_posts_slideshow_search ON slideshow_posts(slideshow_id, search_id);"
                                               "CREATE INDEX IF NOT EXISTS idx_slideshow_blacklist_tags_slideshow_id ON slideshow_blacklist_tags(slideshow_id);";

#endif /* BUNNY_DB_SCHEMA_H */
