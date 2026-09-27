# LittleBunny Roadmap

Each milestone is its own branch and PR against `master`. Check boxes as milestones land;
this file is the single source of truth for "what's done" across sessions.

- [x] **M1 — Roadmap, repo scaffold, `libe621`**
  CMake + CPM build, Makefile (build/test/release/clean/dockcross/windows), `bunny_common`
  HTTP transport + JSON helpers, complete `libe621` client library (search, get post,
  favorite, vote, comments) with unit tests against a fake transport.

- [x] **M2 — `libinkbunny`**
  Session-based login (`api_login.php` → SID)/logout, search submissions, submission
  details (single + batched up to 100 ids). Reuses `bunny_common` for HTTP/JSON. **Does
  not** implement adding/removing favorites or posting/listing comments — confirmed via
  the live API and official docs that Inkbunny's API has no endpoints for either (see
  `architecture.md`); only read-only counts/flags and an existing-favorites-list lookup
  (`favs_user_id`) are available.

- [ ] **M3 — SQLite schema + core DB layer**
  Vendor the sqlite amalgamation via CPM (`DOWNLOAD_ONLY`). Schema for accounts, searches,
  cached posts, seen/unseen state, favorites mirror, downloads, tags stats.

- [ ] **M4 — Core sync engine**
  Encrypted credential storage, scheduled searches (24h default, configurable), seen/unseen
  tracking, an action queue that proxies favorite/vote/comment calls to the sites.

- [ ] **M5 — C server**
  Exposes the core over HTTP/JSON (embeddable HTTP server library pulled via CPM). Auth
  between GUI clients and the server. Runs on Linux.

- [ ] **M6 — Flutter app skeleton**
  App shell, FFI bindings to the core for standalone mode, HTTP client for networked mode,
  both behind one repository interface so the UI layer doesn't care which is active.

- [ ] **M7 — Auth & app-lock UI**
  Site login screens (e621 username/API key, Inkbunny username/password), app-lock via
  password/PIN/fingerprint.

- [ ] **M8 — Browse & search UI**
  Manage saved searches, post grid/list with unseen markers, post detail view with full
  metadata, viewers for supported formats (image/video/webm/gif; Flash/SWF intentionally
  unsupported).

- [ ] **M9 — Actions & downloads**
  Single + mass like/favorite/download, commenting, download manager writing to
  `%artist%/%id%.%extension%`, checksum (md5) verification of downloaded files against the
  site-provided value. Downloads happen client-side, straight from the site CDN. Favorite
  and comment actions only apply to e621 — Inkbunny's API doesn't support them (M2); the UI
  needs to reflect that (e.g. grey out those actions for Inkbunny posts) rather than fail
  silently.

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
