# LittleBunny Roadmap

Each milestone is its own branch and PR against `master`. Check boxes as milestones land;
this file is the single source of truth for "what's done" across sessions.

- [x] **M1 — Roadmap, repo scaffold, `libe621`**
  CMake + CPM build, Makefile (build/test/release/clean/dockcross/windows), `bunny_common`
  HTTP transport + JSON helpers, complete `libe621` client library (search, get post,
  favorite, vote, comments) with unit tests against a fake transport.

- [x] **M2 — `libinkbunny`**
  Session-based login (`api_login.php` → SID)/logout, search submissions, submission
  details (single + batched up to 100 ids). Reuses `bunny_common` for HTTP/JSON. The
  official API has no endpoint to add/remove favorites or post/list comments (confirmed
  via the live API and official docs, see `architecture.md`) — favoriting was later added
  via an unofficial route (see M2.2 below); **commenting still has no path at all**.

- [x] **M2.1 — Pools and post relationships**
  `e621_pool_t` + `e621_get_pool()` (GET `/pools/{id}.json`); `e621_post_t` gained
  `relationships` (parent_id/has_children/has_active_children/children), confirmed live.
  `inkbunny_pool_t` gained per-submission left/right sibling navigation
  (`show_pools=yes`) — Inkbunny has no "list a whole pool" endpoint, only per-submission
  neighbors, and confirmed via the wiki docs that Inkbunny has **no parent/child concept**
  at all (only pools), so there's nothing to add there.

- [x] **M2.2 — Unofficial Inkbunny favorite/unfavorite**
  `inkbunny_website_login()`, `inkbunny_favorite_add()`, `inkbunny_favorite_remove()`
  (`inkbunny/unofficial_favorites.h`) drive the website's own internal favorite flow
  (login.php/login_process.php cookie session + a scraped CSRF token +
  `submissionfav_process.php`), since the official API has none. A deliberate, explicit
  reversal of M2's "official API only" call, made after the user asked to test it directly
  and confirmed it worked end-to-end against their own account. Fragile by nature (HTML
  markup dependent, no fixture-based tests, only live verification) — see
  `architecture.md`. `tools/inkbunny_favorite_experiment` is now a thin CLI over these
  functions for manual testing. Commenting still has no path, official or unofficial.

- [x] **M3 — SQLite schema + core DB layer**
  Vendored the sqlite amalgamation via CPM (`DOWNLOAD_ONLY` + URL/hash, since it has no
  CMake-ready repo). New `bunny_db` library (`libs/db`): schema for accounts (credential
  encryption itself is M4's job), searches, cached posts + normalized tags, search-result
  membership, seen state, a favorites mirror, downloads, plus a `bunny_db_top_favorited_tags()`
  query feeding M10's recommendation feature. CRUD API covers what M4's sync engine needs
  to build on. Tested against a real `:memory:` SQLite database (no fixtures/fake transport
  needed — SQLite itself is the test double), clean under `-DBUNNY_ENABLE_ASAN=ON`.

- [x] **M3.1 — Tag autocomplete**
  `bunny_db_tag_autocomplete(db, site, prefix, limit)`: per-site, prefix-matched, ordered
  by how many cached posts carry the tag (most-used first). Pure read on top of M3's
  schema — tags are already collected as a side effect of `bunny_db_post_upsert`. Feeds
  M8's search-box autocomplete for both e621 and Inkbunny.

- [ ] **M4 — Core sync engine**
  Credential storage, scheduled searches (24h default, configurable), seen/unseen
  tracking, an action queue that proxies favorite/vote/comment calls to the sites.

- [x] **M4.1 — Account credential storage**
  New `bunny_core` library (`libs/core`), the first to sit on top of `bunny_db` (site
  clients join in M4.2/M4.3). `bunny_db_account_set/get/delete` (one account per site) and
  thin `bunny_core_account_*` wrappers. Credentials are stored **plain**, not encrypted —
  a deliberate reversal of an initial encrypted-vault design: the server must run scheduled
  syncs unattended, so gating access behind an interactive unlock would break that. App-lock
  (password/PIN/fingerprint) is a separate per-device client concern (M7), and client↔server
  auth is M5's job — neither belongs here. See `architecture.md`'s "Core sync engine (M4)"
  section.

- [x] **M4.2 — Scheduled search sync**
  `bunny_core_sync_due_searches()`: runs every saved search whose `last_run_at` is `NULL`
  or older than its `interval_hours`, builds an e621/Inkbunny client (authenticated via the
  stored account if present, anonymous/guest otherwise), fetches results, maps each into a
  `bunny_db_post_upsert_t`, upserts it, links it to the search, and touches `last_run_at`.
  e621's 8 tag categories are flattened into one array; Inkbunny's search results carry no
  `description`/`keywords` (only `inkbunny_get_submission(s)` returns those), so those
  fields are simply left unset for now. `bunny_core_search_create/delete/list/list_posts`
  were added alongside it as thin `bunny_db` pass-throughs — `bunny_core` is the single
  entry point apps use, so it needs to expose search CRUD even though the sync engine
  itself only reads. `bunny_core_config_t` gained `min_request_interval_sec` so tests don't
  pay each site library's ~0.5s real-world rate-limit default.

- [ ] **M5 — C server**
  Exposes the core over HTTP/JSON (embeddable HTTP server library pulled via CPM). Auth
  between GUI clients and the server. Runs on Linux.

- [ ] **M6 — Flutter app skeleton**
  App shell, FFI bindings to the core for standalone mode, HTTP client for networked mode,
  both behind one repository interface so the UI layer doesn't care which is active.

- [ ] **M7 — Auth & app-lock UI**
  Site login screens (e621 username/API key, Inkbunny username/password), app-lock via
  password/PIN/fingerprint. App-lock is a per-device, client-side setting, not tied to
  server-side credential storage (M4.1) — each device/app instance can use a different
  mechanism (e.g. password on desktop, fingerprint + PIN fallback on mobile).

- [ ] **M8 — Browse & search UI**
  Manage saved searches, post grid/list with unseen markers, post detail view with full
  metadata, viewers for supported formats (image/video/webm/gif; Flash/SWF intentionally
  unsupported). Tag autocomplete in the search box uses `bunny_db_tag_autocomplete` (M3.1).

- [ ] **M9 — Actions & downloads**
  Single + mass like/favorite/download, commenting, download manager writing to
  `%artist%/%id%.%extension%`, checksum (md5) verification of downloaded files against the
  site-provided value. Downloads happen client-side, straight from the site CDN. Favorite
  now works for both sites (e621 officially, Inkbunny via the unofficial route in M2.2 —
  needs `inkbunny_website_login()` in addition to `inkbunny_login()`). Comment actions only
  apply to e621; the UI needs to reflect that (e.g. grey out commenting for Inkbunny posts)
  rather than fail silently.

- [ ] **M10 — Automation & recommendations**
  "Auto-like/auto-favorite on download" setting, most-liked/most-favorited tag stats,
  recommended new searches based on that history.

- [ ] **M11 — Backup & import**
  Export/import of our own searches. Import from "The Wolf's Stash"
  (`https://zepiwolf.se/tws/`) `.tws_plain` export format — **needs a sample export file
  from the user**, no public format spec exists.

- [ ] **M12 — Cross-platform polish**
  Responsive desktop/mobile layout, consistent theming pass, Windows cross-build via
  dockcross validated end-to-end (server + core), packaging. Needs to resolve the OpenSSL-
  for-mingw gap noted in `architecture.md` — `make windows` configures/builds fine up to
  the `find_package(OpenSSL REQUIRED)` step today.
