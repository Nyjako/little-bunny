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
  via an unofficial route (see M2.3 below); **commenting still has no path at all**.

- [x] **M2.3 — Unofficial Inkbunny favorite/unfavorite**
  `inkbunny_website_login()`, `inkbunny_favorite_add()`, `inkbunny_favorite_remove()`
  (`inkbunny/unofficial_favorites.h`) drive the website's own internal favorite flow
  (login.php/login_process.php cookie session + a scraped CSRF token +
  `submissionfav_process.php`), since the official API has none. A deliberate, explicit
  reversal of M2's "official API only" call, made after the user asked to test it directly
  and confirmed it worked end-to-end against their own account. Fragile by nature (HTML
  markup dependent, no fixture-based tests, only live verification) — see
  `architecture.md`. `tools/inkbunny_favorite_experiment` is now a thin CLI over these
  functions for manual testing. Commenting still has no path, official or unofficial.

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
  now works for both sites (e621 officially, Inkbunny via the unofficial route in M2.3 —
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
