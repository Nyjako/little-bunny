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

- [x] **M4 — Core sync engine**
  Credential storage, scheduled searches (24h default, configurable), seen/unseen
  tracking, an action queue that proxies favorite/vote/comment calls to the sites.
  Delivered as three sub-milestones, M4.1–M4.3 below.

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

- [x] **M4.3 — Action queue (favorite/vote/comment proxy)**
  New `action_queue` table + `bunny_db_action_queue_add/list_pending/mark_done/
  mark_failed`, plus `bunny_db_post_get_by_id` (the queue only has the local post id,
  matching `bunny_db_favorite_add`'s own convention, and needs to resolve it to
  `(site, external_id)` before calling a site API). `bunny_core_queue_favorite_add/
  remove/vote/comment` enqueue (action-specific data like a vote's score goes in a small
  JSON `payload`, built/read via cJSON — already a transitive dependency through
  `bunny_common`); `bunny_core_process_queue()` drains pending actions, builds/reuses an
  e621 client across the pass, calls the matching site function, updates the local
  favorites mirror on success, and marks each row done/failed. Vote/comment against an
  Inkbunny post always fails cleanly (Inkbunny has no API for either); Inkbunny
  favoriting requires a real stored account (the unofficial route has no guest mode) and
  fails immediately without a network call if none is configured. No retry scheduling —
  a failed action stays failed; a future scheduler (M5) can re-drive the queue on
  whatever cadence makes sense once there's an always-on process. `bunny_core_build_e621_
  client`/`build_inkbunny_client` (client-building + account lookup) were factored out of
  M4.2's sync code into a shared internal helper (`libs/core/src/site_clients.c`) since
  M4.3 needed the exact same logic.

- [x] **M5 — C server**
  Exposes the core over HTTP/JSON (embeddable HTTP server library pulled via CPM). Auth
  between GUI clients and the server. Runs on Linux. Delivered as three sub-milestones,
  M5.1–M5.3 below.

- [x] **M5.1 — Server skeleton: HTTP library, TLS, auth, config**
  New top-level `server/` executable (`bunny_server`), sibling to `libs/`/`tools/`.
  Vendored [civetweb](https://github.com/civetweb/civetweb) via CPM for HTTP/HTTPS
  (`CIVETWEB_ENABLE_ASAN OFF` — it enables its own sanitizers by default in Debug builds,
  independent of and conflicting with `BUNNY_ENABLE_ASAN`). Config comes from environment
  variables (`BUNNY_SERVER_PORT/DATA_DIR/USER_AGENT/POLL_INTERVAL_SEC`); the default data
  dir finally adopts GOBLIN's `appdirs.h` (flagged as a good fit back in M3/M4, unused
  until now). Auth is a single shared bearer token, generated once (`OpenSSL RAND_bytes`,
  32 bytes hex) and stored in the data dir; every route but `/health` must present it via
  `Authorization: Bearer`. **The server generates its own self-signed TLS certificate**
  (OpenSSL `EVP_PKEY`/`X509`, ~10yr validity) and terminates HTTPS itself — the deployment
  target (a remote host, no reverse proxy, no manual cert management) has no CA or domain
  name to lean on, so **M7's GUI must pin the certificate's fingerprint** rather than
  validate it against the system trust store, same trust-on-first-use shape as SSH host
  keys. `auth_token`, `server.pem`, and the SQLite DB file (plaintext credentials, per
  M4.1) are all written/chmod'd `0600`. A single mutex in `server_context_t` serializes
  every `bunny_core_*` call, since civetweb's worker-thread pool (and M5.3's scheduler
  thread) mean `bunny_core`/`bunny_db` — never designed for concurrent access — now have
  more than one caller. See `docs/architecture.md`'s "C server (M5)" section for the full
  writeup.

- [x] **M5.2 — REST routes over `bunny_core`**
  Full REST surface: `POST/GET/DELETE /accounts[/{site}]` (never echoes `secret` back),
  `POST/GET/DELETE /searches[/{id}]` + `GET /searches/{id}/posts?unseen_only=`,
  `POST/DELETE /posts/{id}/favorite`, `POST /posts/{id}/vote`, `POST /posts/{id}/comment`
  (all three queue actions respond `202 Accepted`, matching that they're enqueued, not
  processed), `POST /sync` and `POST /queue/process` (manual triggers, ahead of M5.3's
  scheduler). Route handlers live one file per resource
  (`routes_accounts.c`/`routes_searches.c`/`routes_queue.c`), matching `bunny_db`'s
  per-concern split; `json_helpers.c` centralizes request-body parsing and
  `bunny_core_result_t` → HTTP status mapping (400/404/502/500), and `route_utils.c`
  centralizes path-segment/id/site parsing so civetweb's prefix-matching URIs (`/a` also
  matches `/a/b`) don't need re-deriving per route. `main.c`'s startup logic was factored
  into `server_app_start()`/`server_app_stop()` (`server/src/app.c`, backing a new
  `bunny_server_lib` static library `bunny_server` and the test suite both link) so tests
  can drive a real, fully-wired server instead of re-implementing its wiring or spawning
  the built executable. Also fixed a real bug found via manual testing: a SQL foreign-key
  violation (e.g. queuing an action against a nonexistent post id) was surfacing as a 500
  "database error" instead of 400 — `bunny_core_map_db_result` now maps
  `BUNNY_DB_ERR_CONSTRAINT` to `BUNNY_CORE_ERR_INVALID_ARG`, since a constraint violation
  from bad caller input isn't a server-side fault.

- [x] **M5.3 — Background scheduler + graceful shutdown**
  `server_scheduler_start/stop()` (`server/src/scheduler.c`): a background thread that
  loops sleep(`poll_interval_sec`, default 15 min) → `bunny_core_sync_due_searches` →
  `bunny_core_process_queue` → repeat, serialized through the same `core_mutex` every
  route handler uses. Sleeps in 1-second increments so shutdown is picked up within ~1s
  rather than waiting out the full interval. `poll_interval_sec <= 0` disables the
  scheduler entirely — used by the integration test suite so its explicit `/sync`/
  `/queue/process` calls don't race a background pass consuming the fake transport's
  canned responses; a dedicated test (`test_scheduler_syncs_search_automatically`) runs
  with a 1s interval specifically to exercise the real background thread. The
  scheduler's lifecycle now lives in `server_app_start()`/`server_app_stop()`
  (`server/src/app.c`) alongside civetweb and `bunny_core` — stopped first on shutdown so
  it's done issuing `bunny_core_*` calls before civetweb and the core get torn down.
  `main.c` already had `SIGINT`/`SIGTERM` handling from M5.1; this milestone didn't need
  to add more, just make sure the scheduler thread joins cleanly as part of it. Verified
  live: a real search synced automatically against e621.net on the configured interval,
  no explicit `/sync` call needed, followed by a graceful shutdown (exit code 0) on
  `SIGTERM`.

- [x] **M6 — Flutter app skeleton**
  App shell, FFI bindings to the core for standalone mode, HTTP client for networked mode,
  both behind one repository interface so the UI layer doesn't care which is active.
  Delivered as three sub-milestones, M6.1–M6.3 below. Managed via `fvm` (`fvm flutter ...`,
  not bare `flutter`) — Flutter 3.44.0 / Dart 3.12.0, pinned in `app/.fvmrc`.

- [x] **M6.1 — App shell + repository interface**
  `app/` scaffolded via `fvm flutter create` (platforms: linux, android, windows, macos,
  ios — only Linux desktop and Android are build-verifiable in this environment, the rest
  have no local toolchain). Boots to a placeholder screen, no real UI yet (that's M7+).
  `lib/repository/bunny_repository.dart`: an `abstract interface class BunnyRepository`
  mirroring `bunny_core`'s public API 1:1 (same shape as the M5 REST surface) — account
  CRUD, search CRUD + listing a search's posts, sync/queue-process triggers, and the four
  queue-favorite/vote/comment actions. `lib/repository/bunny_models.dart`: plain Dart
  classes mirroring `bunny_db_account_t`/`search_t`/`post_t` and the two stats structs —
  `BunnyAccount` deliberately omits the secret field (the server's `GET /accounts/{site}`
  never returns it, so the future FFI implementation won't either, keeping both
  implementations behaviorally identical). No implementations yet — M6.2 (FFI) and M6.3
  (HTTP) each land independently against this stable interface.

- [x] **M6.2 — FFI bindings + standalone-mode repository**
  New top-level `bunny_core_ffi/` (`plugin_ffi` template — deprecated in favor of
  `package_ffi`'s native-assets/build-hooks system, but kept deliberately since this
  project's whole-CMake-project reuse approach doesn't map onto that newer mechanism).
  Reuses the entire existing CMake project (`bunny_core` and its whole dependency chain)
  via `add_subdirectory` instead of a second, parallel build definition, gated by the new
  `BUNNY_BUILD_SERVER` option (default `ON`; `OFF` for this plugin's build, which only
  needs `libs/`, not the C server or civetweb). `ffigen` generates
  `lib/bunny_core_ffi_bindings_generated.dart` from `bunny_core`'s and `bunny_db`'s public
  headers directly — no hand-written glue needed. Every `bunny_core_*` call (real SQLite/
  network I/O) is dispatched to one dedicated background isolate
  (`bunny_core_ffi/lib/src/bunny_core_isolate.dart`) that owns the single `bunny_core_t`
  handle for the app's lifetime, so it never blocks the UI thread and there's never
  concurrent native access to worry about (the FFI equivalent of M5's `core_mutex`).
  `lib/repository/ffi_bunny_repository.dart` implements `BunnyRepository` on top of that
  isolate. Tested against the real compiled shared library (`:memory:`-backed), both
  directly (`bunny_core_ffi/test/`) and through the repository interface
  (`app/test/repository/ffi_bunny_repository_test.dart`).
  **Known gap**: Android's NDK has no prebuilt OpenSSL, so `fvm flutter build apk` fails at
  the CMake configure step (`find_package(OpenSSL REQUIRED)`) — confirmed by direct
  reproduction, same class of problem as the existing Windows gap, deferred to M12
  alongside it. Linux desktop (this environment's only build-verifiable desktop target)
  builds and runs correctly.

- [x] **M6.3 — HTTP client + networked-mode repository, wired together**
  `lib/repository/http_bunny_repository.dart` implements `BunnyRepository` against the M5
  REST API (`docs/architecture.md`'s "C server (M5)" section) using `package:http`'s
  `IOClient` wrapping a `dart:io HttpClient` with a `badCertificateCallback` that pins the
  server's self-signed certificate by SHA-256 fingerprint (no CA to validate against
  otherwise). While building this, found and fixed a real gap: the server's
  `GET /accounts/{site}` only ever returned `site`/`username`, not `id`/`created_at`, even
  though `BunnyAccount` (M6.1) mirrors `bunny_db_account_t` 1:1 and requires both —
  extended `server/src/routes_accounts.c` to return them too (small, additive,
  backward-compatible; verified via `make test`, 11/11 still passing, plus a new assertion
  in the M5.2 integration test). `lib/repository/bunny_repository_factory.dart` is the
  actual "one repository interface" switch point the roadmap describes: a sealed
  `BunnyRepositoryConfig` (`StandaloneConfig`/`NetworkedConfig`) plus a
  `createBunnyRepository` factory, so `main.dart` only ever depends on the abstract
  `BunnyRepository` interface, never on which implementation is active. `main.dart` wires
  this through a `BunnyRepositoryScope` `InheritedWidget` (defaulting to standalone/
  `:memory:` until M7 adds real settings). Verified end-to-end against a real running
  `bunny_server` instance over a real TLS connection (account/search CRUD, cert-pinning
  accept/reject) in addition to the fake-transport unit tests.

- [x] **M7 — Auth & app-lock UI**
  Site login screens (e621 username/API key, Inkbunny username/password), app-lock via
  password/PIN/fingerprint. App-lock is a per-device, client-side setting, not tied to
  server-side credential storage (M4.1) — each device/app instance can use a different
  mechanism (e.g. password on desktop, fingerprint + PIN fallback on mobile). Delivered as
  four sub-milestones, M7.1–M7.4 below (larger than a typical milestone: it also needed a
  settings/connection-setup screen and real credential verification, neither of which
  existed after M6).

- [x] **M7.1 — Account verification (C core → FFI → HTTP → repository interface)**
  `bunny_core_account_verify` (new, `libs/core/src/verify.c`) tests username/secret against
  the real site without touching `bunny_db` — e621 has no dedicated login endpoint (auth is
  per-request Basic auth), so this makes one real authenticated call
  (`e621_list_favorites(client, NULL, ...)`, the authenticated client's own favorites) and
  checks it doesn't fail; Inkbunny already has an explicit `inkbunny_login` primitive, used
  directly. Both map any failure to the existing `BUNNY_CORE_ERR_SITE` — no new
  error-handling convention. Threaded all the way up: `bunny_core_ffi`'s isolate protocol,
  a new `POST /accounts/verify` server route (reusing the exact existing
  `server_json_respond_error` convention, so a rejected credential is the same 502 +
  generic message every other site failure already produces), and
  `BunnyRepository.verifyAccount` (throws `BunnyRepositoryException` on rejection — every
  other write-style method on this interface already just throws on failure, so this
  matches that shape rather than introducing a new "meaningful non-exceptional failure"
  case). Tested with fake transports at the C level (both sites, success + failure,
  `libs/core/tests/test_sync.c`), a fake `http.Client` for `HttpBunnyRepository`, and
  against the real compiled FFI library for `FfiBunnyRepository` — the FFI/HTTP-layer
  *failure*-path tests deliberately use bogus credentials against the real e621 API (real
  network, not a fake transport), since `bunny_core_ffi_open`'s public config has no
  transport-injection point the way the C library's own tests do; e621 rejecting fake
  Basic-auth credentials is fast and deterministic regardless of test-environment network
  conditions.

- [x] **M7.2 — Settings & connection setup**
  `app/lib/settings/`: `RepositorySettingsStore` persists which `BunnyRepositoryConfig` is
  active across restarts — non-secret bookkeeping (mode, server URL) via
  `shared_preferences`; the networked mode's bearer token and cert fingerprint via a small
  `SecretStore` interface (real backend `flutter_secure_storage`, OS-native encryption —
  Android Keystore, Linux libsecret through a running secret-service daemon). Standalone
  mode's db path is never persisted; it's resolved fresh each launch via `path_provider`'s
  `getApplicationSupportDirectory()`, the Dart equivalent of GOBLIN's `appdirs.h` used
  server-side. `SetupScreen` (`app/lib/screens/`) is shown on first launch (no persisted
  config yet): pick standalone or fill in networked mode's server URL/token/fingerprint,
  which gets a real authenticated connectivity check (`checkServerConnection`, a throwaway
  `HttpBunnyRepository.listSearches()` call — deliberately not a bare `GET /health`, since
  that needs no auth and would never catch a wrong bearer token) before anything is
  persisted. `main.dart`'s `LittleBunnyApp` is now a small stateful root that loads the
  persisted config on boot, falls back to `SetupScreen` if none exists, and otherwise
  proceeds straight to the same placeholder home page as before — plain `StatefulWidget`/
  `setState`, no new state-management dependency. Verified against a real running
  `bunny_server` instance: correct config connects, a wrong token is rejected with 401, a
  wrong certificate fingerprint fails the TLS handshake outright.

- [x] **M7.3 — Site login screens**
  `AccountsScreen` (`app/lib/screens/`) replaces M6's placeholder home page: lists both
  sites via `BunnyRepository.getAccount`, showing "Not connected" or "Logged in as
  {username}" with a remove action (confirmation dialog first, since deleting an account is
  destructive from the UI's perspective). Tapping an unconfigured site opens
  `LoginFormScreen` — e621 asks for username + API key, Inkbunny for username + password
  (obscured) — which calls M7.1's `verifyAccount` before `setAccount`, showing the
  exception's message inline on rejection without ever saving bad credentials. Tested with
  a hand-written `FakeBunnyRepository` (`app/test/fakes/`) implementing only the account
  methods these two screens actually use — no mocking framework, matching the project's
  established "fake the dependency, not the business logic" style throughout M1–M7.
  `verifyAccount`/`setAccount`/`deleteAccount`'s underlying behavior against real sites/a
  real server was already verified in M7.1; these tests only cover the UI's own orchestration
  (which state renders what, error display, confirmation flow).

- [x] **M7.4 — App-lock (completes M7)**
  `AppLockService` (`app/lib/settings/`) stores whether app-lock is enabled
  (`shared_preferences`) and the PIN/password itself directly in `SecretStore` (compared by
  string equality) — no hand-rolled hashing, since the real backend already encrypts values
  at rest and this is a local UI gate, not data-at-rest protection. `LockSetupScreen`
  (reachable from `AccountsScreen`'s app bar) enables/disables it, requiring the current
  PIN/password to disable. `LockScreen` gates the app at root whenever enabled: on Android,
  tries `local_auth` biometric first (`biometricOnly: true` — the fallback is this app's own
  PIN, not the OS device credential, per the roadmap's "per-device, client-side" wording);
  every platform falls back to PIN/password entry. `main.dart`'s `LittleBunnyApp` checks
  lock state right after loading the repository and shows `LockScreen` before
  `AccountsScreen` when needed.
  `app/android`'s `MainActivity` now extends `FlutterFragmentActivity` (not `FlutterActivity`)
  and the app's launch/normal themes inherit `Theme.AppCompat.*` instead of the plain
  platform theme — both required for `local_auth`'s `BiometricPrompt` to host its dialog
  fragment; the `USE_BIOMETRIC` permission itself needs no manual manifest edit, since
  `local_auth_android` already declares it in its own manifest, merged in automatically.
  **Known gap**: none of this is verified by any real build — `flutter build apk` already
  fails at the OpenSSL step (M6.2, deferred to M12), and `Platform.isAndroid` is false on
  this dev machine's test host anyway, so neither a real build nor the automated test suite
  exercises the biometric path. Written correctly per `local_auth`'s own reference example
  regardless, to avoid revisiting this milestone once Android builds again.

- [x] **M8 — Browse & search UI**
  Manage saved searches, post grid/list with unseen markers, post detail view with full
  metadata, viewers for supported formats (image/video/webm/gif; Flash/SWF intentionally
  unsupported). Tag autocomplete in the search box uses `bunny_db_tag_autocomplete` (M3.1).
  Delivered as four sub-milestones, M8.1–M8.4 below.

- [x] **M8.1 — Tag autocomplete + mark-seen plumbing**
  Two `bunny_db`-layer capabilities — `bunny_db_tag_autocomplete` (M3.1) and
  `bunny_db_post_mark_seen`, both used nowhere above `bunny_db` before this — get thin
  `bunny_core_tag_autocomplete`/`bunny_core_post_mark_seen` wrappers (`libs/core/src/
  searches.c`, alongside the existing search CRUD pass-throughs), then the same C-core →
  FFI → HTTP → repository plumbing M7.1 established for `bunny_core_account_verify`: new
  `server/src/routes_tags.{c,h}` (`GET /tags/autocomplete?site=&prefix=&limit=`, a new
  resource file matching the one-file-per-resource convention), `POST /posts/{id}/seen`
  added to the existing `routes_queue.c` (it already owns `/posts` dispatch), and
  `BunnyRepository.tagAutocomplete`/`markPostSeen` implemented in both `FfiBunnyRepository`
  and `HttpBunnyRepository`. Unlike M7.1's verify plumbing, none of this touches e621/
  Inkbunny site clients — it's pure `bunny_db` — so every layer's tests are fully
  deterministic (no real-network caveat needed, even at the FFI layer).
  **A real bug this surfaced**: `bunny_core_post_mark_seen` on a nonexistent post_id returns
  `BUNNY_CORE_ERR_INVALID_ARG`, not `BUNNY_CORE_ERR_NOT_FOUND` — `seen_posts.post_id`
  references `posts(id)`, so a missing post is a foreign-key violation, which
  `bunny_core_map_db_result` already treats as bad caller input (same convention documented
  for the action queue's own foreign key in M4.3).

- [x] **M8.2 — Navigation restructuring + saved search management**
  Browse/search is the app's actual daily-use surface, so a new `SearchesScreen` replaces
  `AccountsScreen` as the post-lock home; `AccountsScreen` moves to an app bar icon next to
  the existing settings icon. `SearchesScreen` lists `BunnySearch` via `listSearches`, each
  row showing a `site • every Nh` subtitle, with a delete action (confirmation dialog,
  mirroring `AccountsScreen._removeAccount`'s existing pattern) and a "new search" FAB
  opening `CreateSearchScreen` (label/site/query/interval fields; the query field's
  tag-autocomplete is a 300ms-debounced lookup against `tagAutocomplete`, e621-style —
  it only re-completes the word currently being typed, tracked as the substring after the
  last space, and appends the picked tag with a trailing space rather than replacing the
  whole query). Every new string is routed through `AppLocalizations` from the start, no
  retrofit needed.
  **A real bug this surfaced**: `AccountsScreen` had always been reached as the app's `home`
  (M7.3–M8.1), so its internal `BunnyRepositoryScope.of(context)` lookup worked because the
  scope wrapped `home` directly. Once it became a screen reached only via `Navigator.push`
  from `SearchesScreen`, that lookup started throwing a null-check error — a pushed route's
  widget subtree is a sibling of `home`'s subtree under the `Navigator`'s `Overlay`, not a
  descendant of whatever wraps `home`, so `BunnyRepositoryScope` isn't visible there. Caught
  by a widget test (`searches_screen_test.dart`'s "tapping the accounts icon" case) before it
  could ship as a live crash. Fixed by giving `AccountsScreen` an explicit
  `required BunnyRepository repository` constructor parameter instead, matching the
  convention `LoginFormScreen`/`CreateSearchScreen` already used for exactly this reason.

- [x] **M8.3 — Post grid + unseen markers**
  New `PostGridScreen` (`app/lib/screens/post_grid_screen.dart`), opened by tapping a row in
  `SearchesScreen`. Loads a search's cached posts via `listSearchPosts`, rendered as a
  `GridView` of `CachedNetworkImage(post.previewUrl)` thumbnails (new `cached_network_image`
  dependency). Unseen posts (`!post.isSeen`) get a small red dot overlay; an app bar toggle
  re-runs `listSearchPosts(search.id, unseenOnly: true)`; a refresh action calls
  `syncDueSearches()` then reloads. Tapping a post calls `markPostSeen` and reloads the grid,
  clearing its marker — the full metadata/media viewer (`PostDetailScreen`) is M8.4's scope,
  not built yet, so this is the interim "opening a post" behavior for now.
  **A real bug this surfaced**: the exact same `setState(() => future = ...)` arrow-closure
  bug M7.3 found in `AccountsScreen._refresh` (Dart's assignment-expression-evaluates-to-the-
  assigned-value semantics making the closure return a `Future`) recurred in
  `_PostGridScreenState._openPost`, caught immediately by the equivalent widget test. Fixed
  the same way, with a block body.

- [x] **M8.4 — Post detail view + media viewers (completes M8)**
  New `PostDetailScreen` (`app/lib/screens/post_detail_screen.dart`), opened by tapping a
  tile in `PostGridScreen` (which now navigates there instead of just calling `markPostSeen`
  directly). Shows full read-only metadata — artist, title, description, rating, score,
  favorite/comment counts, dimensions, site creation date — with no favorite/vote/comment
  action buttons yet (that's M9's scope). Calls `markPostSeen(post.id)` once in `initState`;
  `PostGridScreen` reloads its list on return so the cleared marker shows immediately.
  Media viewer branches on `post.fileExt`: images (jpg/png/gif/webp) via
  `CachedNetworkImage(post.fileUrl)`; videos (webm/mp4) via `video_player` + `fvp` (new
  dependencies); anything else (Flash/SWF) shows a clear "not supported" placeholder,
  matching the roadmap's own note that Flash/SWF is intentionally unimplemented.
  - **`fvp` version pin matters.** The plan called for `fvp` since `video_player` has no
    official Linux implementation, but pinning `fvp: ^0.30.0` (the version investigated
    during M8 planning) broke the build against the `video_player` version pub actually
    resolved (2.14.0) — `fvp 0.30.0`'s own code referenced `VideoPlayerController.textureId`,
    which that newer `video_player` had removed. Fixed by pinning `fvp: ^0.38.1` instead,
    the latest release, which matches the resolved `video_player` API. Confirmed by a real
    `flutter build linux` succeeding and the built bundle logging `fvp`'s underlying decoder
    (MDK 0.38.0) initializing on startup with no crash — libmpv was never actually needed;
    `fvp` bundles its own FFmpeg-based decoder (MDK), contrary to the libmpv assumption made
    during M8 planning.
  - **Testing video playback**: `flutter test` has no real platform channel implementation
    for `video_player`, so a widget test that builds `PostDetailScreen` with a video post
    needs `VideoPlayerPlatform.instance` replaced with a fake
    (`app/test/fakes/fake_video_player_platform.dart`) that reports "initialized" immediately
    without touching a network or a real decoder — per the plan, this only proves the right
    viewer widget type is chosen per file extension, not that playback actually works (that's
    covered by the real Linux build launching and by manual verification against a real
    server).

- [ ] **M8.5 — Rich post metadata, browsing UX & bug fixes**
  A hands-on pass over M8 surfaced a large batch of real feedback: three concrete bugs
  (Inkbunny 403s on search and thumbnails, incomplete sync pagination, no usable default
  sync interval) plus a long list of richness the detail/grid views were missing (categorized
  tags, sources, pool/parent/child links, settings for quality/grid size, rating badges, a
  full-screen zoomable viewer, tag-click browsing, unseen counts, bulk mark-seen, and —
  since the backend plumbing for it already exists from M4.3 — favorite/vote buttons on the
  detail page, pulling forward a thin slice of M9 without touching M9's remaining scope of
  mass actions/downloads/comments). Delivered as sequential sub-milestones, M8.5.0 onward.

- [x] **M8.5.0 — Minimal schema migration runner + score up/down split**
  `libs/db/src/schema.h` was all `CREATE TABLE IF NOT EXISTS`, re-applied on every
  `bunny_db_open()`; a `schema_migrations` table was scaffolded since M3 but never used —
  SQLite's `IF NOT EXISTS` can't add a column to an already-existing table, so a real
  migration path was needed before `posts.score` (a single total) could be split into
  separate up/down vote counts the grid can show as likes/dislikes. `bunny_db_open()` now
  calls a small `bunny_db_apply_migrations()` (`libs/db/src/db.c`): a static
  `{version, sql}` list, each checked against `schema_migrations` and run (then recorded)
  at most once. First and only migration so far: `ALTER TABLE posts ADD COLUMN score_up/
  score_down INTEGER NOT NULL DEFAULT 0`. `sync.c`'s `upsert_e621_post` now reads
  `e621_score_t.up`/`.down` (previously only `.total` was kept); Inkbunny has no vote concept
  so both stay 0. Plumbed through `bunny_db_post_t`/`bunny_db_post_upsert_t`, the shared
  `BUNNY_DB_POST_SELECT_COLUMNS` macro all post-reading queries share, FFI bindings
  (regenerated via `dart run ffigen`), the server's `post_to_json`, and `BunnyPost` in both
  repository implementations.
  **This is the project's first real schema migration** — tested by opening a real (not
  `:memory:`) database file twice across two separate `bunny_db_open()` calls, confirming the
  second open doesn't fail or re-run the `ALTER TABLE` against a database that already has
  the columns.

- [x] **M8.5.1 — Bug fixes: pagination, Inkbunny thumbnail 403, sort order**
  Three independent, user-reported bugs fixed in one sub-milestone:
  - **Pagination.** `sync_e621_search`/`sync_inkbunny_search` (`libs/core/src/sync.c`) each
    made exactly one hardcoded `page=1` request before this — a search matching hundreds of
    posts only ever cached the first ~75 (e621's default page size when no explicit limit is
    passed). Both now loop: e621 requests `limit=320` (the site's real per-request max) each
    page and stops once a page returns fewer than that; Inkbunny's search API has no
    per-page-limit parameter at all, so its loop instead keeps paging until a page comes back
    completely empty — meaning a real sync now always makes one extra "probe" request past
    the true last page to confirm there's nothing more. Both loops are capped at 20 pages so
    one sync pass can't run unboundedly long. Tested with a 320-post-then-5-post two-page
    e621 fixture (generated at test time — hand-authoring a 320-entry JSON fixture file
    wasn't practical) and an Inkbunny fixture extended with a third, empty-results page.
  - **Inkbunny thumbnail 403s.** `CachedNetworkImage(imageUrl: ...)` in `PostGridScreen`/
    `PostDetailScreen` sent no headers at all; Inkbunny's `metapix.net` CDN rejects bare
    requests. New `app/lib/util/image_headers.dart`'s `imageHeadersFor(site)` returns a
    `User-Agent`/`Referer` pair for Inkbunny posts, `null` for e621 (no such requirement
    there) — passed to every `CachedNetworkImage` and to `VideoPlayerController.networkUrl`'s
    own `httpHeaders` param for Inkbunny videos, same CDN.
  - **Sort order.** `bunny_db_search_list_posts` (`libs/db/src/posts.c`) ordered by
    `sr.found_at DESC` (when a sync linked the post to the search) rather than the post's own
    site creation date — a single sync pass can link posts spanning months all at once, so
    `found_at` didn't track actual recency. Changed to
    `ORDER BY COALESCE(p.created_at_site, p.cached_at) DESC`.
  **The Inkbunny search-by-tag/author 403 itself is still open** — investigating confirmed
  `inkbunny_search_params_t` has no author/username search field at all today (only
  `text`/`keywords_only`/`favorited_by_user_id`, the last being "list an *existing*
  favorites list," not "list a user's submissions"), and Inkbunny signals its own auth
  failures as HTTP 200 + JSON `error_code` rather than a real 403 — so this needs a live
  debugging session against a real account before a fix can be written with confidence,
  tracked separately rather than guessed at here.

- [x] **M8.5.11 — Unseen count per search**
  `bunny_db_search_list`'s SQL (`libs/db/src/searches.c`) now computes a per-search
  `unseen_count` via a correlated subquery (`search_results` rows with no matching
  `seen_posts` row), added as a new `int unseen_count` field on `bunny_db_search_t` —
  additive, not a schema change, so no migration needed. Threads through unchanged
  core/FFI/server signatures (the struct just carries more data): `BunnySearch` gains
  `unseenCount`, and `SearchesScreen`'s row shows a small colored badge next to the delete
  icon when it's greater than 0. `FakeBunnyRepository.listSearches` computes the same count
  from its own `postsBySearchId` map to stay behaviorally consistent with the real
  implementations rather than hardcoding it.

- [x] **M8.5.12 — Mark-all-seen**
  New `bunny_db_search_mark_all_seen(db, search_id)` (`libs/db/src/posts.c`, alongside
  `bunny_db_post_mark_seen`): `INSERT OR IGNORE INTO seen_posts SELECT post_id FROM
  search_results WHERE search_id = ?` — the bulk counterpart to the existing single-post
  version, same idempotent shape. `bunny_core_search_mark_all_seen` wrapper, `POST
  /searches/{id}/mark_all_seen` added to the existing `routes_searches.c` dispatch,
  `BunnyRepository.markAllSeen(int)` implemented in both `FfiBunnyRepository`/
  `HttpBunnyRepository`. `PostGridScreen`'s app bar gets an overflow menu (`PopupMenuButton`)
  with the action, reloading the grid afterward so cleared markers show immediately. Unlike
  `markPostSeen` (which rejects a nonexistent post id as a foreign-key violation),
  `markAllSeen` against a search with no linked posts — or a nonexistent search id — is a
  harmless no-op, since the underlying `INSERT` just selects zero rows; there's nothing to
  reject.

- [x] **M8.5.13 — Search creation UX: label mirrors query + default interval (completes the
  independent M8.5 wins)**
  Two small, unrelated `CreateSearchScreen`/`SettingsScreen` UX fixes bundled together since
  both are pure client-side changes with no backend plumbing:
  - **Default sync interval.** New `app/lib/settings/sync_settings_store.dart`
    (`SyncSettingsStore`, same `shared_preferences` shape as `ThemeSettingsStore`) persists a
    `defaultIntervalHours` (default 24) that `CreateSearchScreen`'s interval field now loads
    on open instead of a hardcoded `'24'`. `SettingsScreen` gained a new "Sync" section to
    edit it. Purely a client-side UX convenience — there's no equivalent backend setting,
    since the sync engine only ever reads each search's own `interval_hours`.
  - **Label mirrors query.** `CreateSearchScreen`'s label field now mirrors the query field's
    text live (e.g. query `cat -dog standing` → label defaults to the same string) until the
    user types into the label directly, after which it stops — the classic "slug follows
    title" pattern. Implemented with two guard flags: `_labelManuallyEdited` (set the first
    time the label changes for a reason other than the mirror itself) and `_mirroringLabel`
    (set only while the mirror's own programmatic `_labelController.text = ...` assignment is
    in flight, so that assignment doesn't trip `_labelManuallyEdited` and permanently disable
    mirroring on the very first query keystroke).
  Threading the new `SyncSettingsStore` through required adding it as a new constructor
  parameter on `SearchesScreen` (which passes it on to both `CreateSearchScreen` and
  `SettingsScreen`) and `LittleBunnyApp`/`main.dart` — the same "thread a new settings store
  down through the screen that needs it" shape `ThemeSettingsStore` and `AppLockService`
  already established.

- [x] **M8.5.3 — Tag categories**
  New `tag_categories` table (`libs/db/src/schema.h`): `tag_id INTEGER PRIMARY KEY REFERENCES
  tags(id), category TEXT CHECK(...)`. A tag's category is a property of the tag itself, not
  a given post — e621's own data model has a given tag name always belong to the same
  category site-wide — so this keys on `tag_id` alone and is upserted once per tag regardless
  of how many posts reference it, rather than per `(post_id, tag_id)`. Inkbunny keywords have
  no category concept at all and simply never get a row (`LEFT JOIN` in the read query — `NULL`
  means uncategorized, not "unknown"). `bunny_db_post_upsert_t` gained a parallel
  `const char **tag_categories` (same length as `tags`/`tag_count`; `NULL` entries allowed,
  or the whole array can be `NULL` when there's no category info at all). New read function
  `bunny_db_post_get_tags_by_category(db, post_id, out_list)` returns `{name, category}` pairs
  via new `bunny_db_post_tag_t`/`bunny_db_post_tag_list_t` types (same shape as
  `bunny_db_tag_stat_t`). `sync.c`'s `flatten_e621_tags` now also builds a parallel
  `categories` array (one of the 8 literal e621 category names per flattened tag, matching
  which of `e621_tags_t`'s 8 lists it came from) so `upsert_e621_post` can populate
  `tag_categories`; `upsert_inkbunny_submission` passes nothing (stays `NULL` via the existing
  `memset`). Core wrapper `bunny_core_post_get_tags_by_category`. Full plumbing: `GET
  /posts/{id}/tags` (new `BunnyPostTag` model), FFI isolate request/handler, both
  `FfiBunnyRepository`/`HttpBunnyRepository`, `FakeBunnyRepository.tagsByPostId`.
  **Plan deviation**: the original plan called for a new `server/src/routes_posts.c` file for
  this and future M8.5.4/5 read endpoints. In practice `/posts` is already a single civetweb
  route owned end-to-end by `posts_handler` in the existing `routes_queue.c` (registered via
  one `mg_set_request_handler(mg_ctx, "/posts", posts_handler, ctx)` call, dispatching
  internally by sub-path for `/favorite`, `/vote`, `/comment`, `/seen`) — civetweb has no
  concept of two handlers sharing a prefix, so a second registration for the same prefix would
  simply never be reached. `GET /posts/{id}/tags` was added as another case in that same
  dispatch chain instead, matching the identical precedent already set by M8.1's `/posts/{id}/
  seen` route and explicitly noted there for the same reason.

- [x] **M8.5.4 — Sources**
  New `post_sources` table (`libs/db/src/schema.h`): `post_id, position, url`, `PRIMARY KEY
  (post_id, position)` — `position` preserves the site's own source ordering (sources[0] is
  usually "the" canonical source), since plain row order isn't reliable once rows get replaced
  across re-syncs. New generic `bunny_db_string_list_t` type (`char **items`/`size_t count`,
  nothing existing fit a bare list of strings) + `bunny_db_string_list_free`.
  `bunny_db_post_upsert_t` gained a parallel `const char **sources`/`size_t source_count`;
  `bunny_db_post_upsert` wholesale-replaces a post's `post_sources` rows on every upsert
  (`DELETE` then re-`INSERT` with position), exactly the same pattern already used for
  `post_tags`. New read function `bunny_db_post_get_sources(db, post_id, out_list)` returns
  URLs ordered by `position ASC`. `sync.c`'s `upsert_e621_post` wires `e621_post_t.sources`
  straight through (previously parsed but discarded entirely); Inkbunny submissions have no
  source-URL field at all, so `upsert_inkbunny_submission` leaves it unset (`NULL`/`0` via the
  existing `memset`). Core wrapper `bunny_core_post_get_sources`; `GET /posts/{id}/sources`
  added to the same `routes_queue.c` `posts_handler` dispatch chain as M8.5.3's tags route (not
  a new file, for the identical civetweb-route-ownership reason documented there).
  `BunnyRepository.getPostSources(int) -> Future<List<String>>` implemented in both
  `FfiBunnyRepository`/`HttpBunnyRepository`, `FakeBunnyRepository.sourcesByPostId`. Tests at
  every layer: `:memory:` (order preservation, empty-when-none, wholesale-replace-on-resync),
  a fake-transport sync test, the server integration test's shared e621 fixture extended with
  a real source URL, and new FFI/HTTP repository tests.

- [x] **M8.5.5a — Pools + parent/child relationships (backend)**
  The original plan bundled backend plumbing and UI (a "Pools" tab + "create pool search"
  flow) into one M8.5.5 sub-milestone; split here the same way M8.5.1 was split when a plan
  item grew unwieldy — this lands the backend first, the UI as a follow-up. New tables, all
  keyed on e621's own *external* ids rather than local `posts.id` (a parent/child/pool member
  may never have been synced locally, so there's nothing to foreign-key against):
  `post_relationships(post_id PK, parent_external_id NULL-able, has_active_children)`,
  `post_children(post_id, child_external_id)`, `post_pools(post_id, pool_id)`. New generic
  `bunny_db_int64_list_t` (nothing existing fit a bare list of 64-bit ids) and
  `bunny_db_post_relationships_t {has_parent, parent_external_id, has_active_children,
  children}`. `bunny_db_post_upsert_t` gained `has_parent`/`parent_external_id`/
  `has_active_children`/`child_external_ids`+count/`pool_ids`+count; `bunny_db_post_upsert`
  always upserts the relationships row (so a resync that drops a parent reflects that, not a
  stale value) and wholesale-replaces `post_children`/`post_pools`, same pattern M8.5.4's
  sources already established. New read functions `bunny_db_post_get_relationships`/
  `bunny_db_post_get_pool_ids` return an all-empty/OK result (not `NOT_FOUND`) when a post has
  no row — "no relationships" is a normal state. `sync.c`'s `upsert_e621_post` wires
  `e621_post_t.relationships`/`.pool_ids` through; Inkbunny has no equivalent, left unset.
  New `bunny_core_fetch_and_cache_post(core, site, external_id, out_post_id)` factors the
  single-post upsert logic out of `upsert_e621_post`/`upsert_inkbunny_submission` so it's
  callable standalone against a live `e621_get_post`/`inkbunny_get_submission` call — lets a
  parent/child/pool chip that was never independently synced be fetched and cached on demand.
  New `bunny_core_pool_info_t {id, name, post_count}` + `bunny_core_fetch_pool` (a thin,
  non-persisting `e621_get_pool` wrapper, used only to auto-fill a pool search's label).
  Server: `GET /posts/{id}/relationships` and `GET /posts/{id}/pools` added to the existing
  `routes_queue.c` `posts_handler` dispatch (same civetweb-ownership precedent as M8.5.3/4);
  `POST /posts/fetch?site=&external_id=` added there too (a new sub-path, not an id route);
  new `server/src/routes_pools.c`/`.h` registers `GET /pools/{id}` — unlike `/posts`, nothing
  owns `/pools` yet, so a new dedicated resource file is the right shape here (matching
  `routes_searches.c`/`routes_tags.c`'s precedent), not a deviation. `BunnyRepository` gained
  `getPostRelationships`/`getPostPoolIds`/`fetchPost`/`fetchPool` with new
  `BunnyPostRelationships`/`BunnyPoolInfo` models, implemented in both `FfiBunnyRepository`/
  `HttpBunnyRepository`/`FakeBunnyRepository`. Tests at every layer: `:memory:`
  (relationships/pools read + wholesale-replace-on-resync), a fake-transport sync test, a
  live-fetch test for both `bunny_core_fetch_and_cache_post` and `bunny_core_fetch_pool`, the
  server integration test (made the shared fake e621 transport path-aware so it can serve a
  single-post and a pool fixture alongside the existing search fixture), and new FFI/HTTP
  repository tests. **No UI in this sub-milestone** — the "Pools" tab and "create pool search"
  flow are a separate follow-up.

- [x] **M8.5.5b — Pools tab + create-pool-search flow (completes M8.5.5)**
  The UI follow-up to M8.5.5a. `SearchesScreen` gained a `TabController`/`TabBar` with two
  tabs, "Searches" and "Pools" — a pool search is just a regular `BunnySearch` with a
  recognizable shape (`site == e621 && query.startsWith('pool:')`, reusing the finding from
  the original M8.5 plan that `pool:<id>` already works as a literal e621 tag-search query),
  so the split is a pure client-side filter over the same `listSearches()` call, not a new
  repository method. The floating action button's behavior switches with the active tab:
  "Searches" still opens the existing `CreateSearchScreen`; "Pools" opens a new `AlertDialog`
  prompting for a numeric pool id, calling `fetchPool(id)` (from M8.5.5a) to auto-fill a
  friendly label from the pool's own name, then `createSearch(site: e621, label, query:
  'pool:$id')`. A failed pool lookup (network error, deleted pool, wrong id) doesn't block
  search creation — it just falls back to a `pool:$id` label, since the pool-search mechanism
  itself needs nothing from that lookup to work. New l10n keys for the tab labels, empty
  state, dialog title/field/submit button, and the pools-tab FAB tooltip. One pre-existing
  test (`widget_test.dart`) needed updating: the new "Searches" tab label made
  `find.text('Searches')` ambiguous against the AppBar title, fixed with `findsNWidgets(2)`
  and a comment explaining why. New widget tests cover tab filtering, the pools empty state,
  and both the successful-lookup and lookup-failure paths of the create-pool-search dialog.

- [x] **M8.5.6 — Settings: preview quality + grid columns**
  New `post_media_variants(post_id PK REFERENCES posts(id) ON DELETE CASCADE, sample_url
  TEXT)` table stores the medium-quality image variant (e621's "sample", Inkbunny's "screen")
  that was already being parsed (`e621_post_t.sample.url`, `inkbunny_file_t.url_screen`) but
  previously discarded entirely. Same one-to-one shape as `post_relationships` (upserted
  unconditionally so a resync that loses a sample URL clears it), but `sample_url` is `LEFT
  JOIN`ed directly into the shared `BUNNY_DB_POST_SELECT_COLUMNS`/`FROM_JOIN` macros rather
  than needing its own read function — every post-reading query (`post_get`,
  `search_list_posts`, `favorite_list`) gets it for free, avoiding an N+1 fetch for the grid.
  `bunny_db_post_t` gained `sample_url`; server's `post_to_json` gained the matching field;
  `BunnyPost` gained `sampleUrl` through both repository implementations. New
  `app/lib/settings/display_settings_store.dart` (`DisplaySettingsStore`, same
  `shared_preferences` shape as the other settings stores): a `PreviewQuality` enum
  (thumbnail/medium, default thumbnail) and `gridColumns` (default 3, matching
  `PostGridScreen`'s pre-existing hardcoded value). `SettingsScreen` gained a "Display"
  section (a `SegmentedButton` + a number field, same controls already used for theme/sync).
  `PostGridScreen` now reads `gridColumns` into its `SliverGridDelegateWithFixedCrossAxisCount`
  and picks `sampleUrl ?? previewUrl` vs. always `previewUrl` for `CachedNetworkImage` based on
  the loaded quality — falling back to the thumbnail whenever a post has no sample URL (notably
  every Inkbunny post synced via search alone, see below). `DisplaySettingsStore` threads
  through `SearchesScreen` to both `SettingsScreen` and `PostGridScreen`, same pattern
  `SyncSettingsStore` already established.
  **Confirmed limitation, not a regression**: Inkbunny's search endpoint doesn't return a
  `"files"` array at all (already documented for `description`/`keywords`) — `sample_url`
  (like `file_url`/`file_md5`/`width`/`height`) can only ever be populated for an Inkbunny post
  via a full `inkbunny_get_submission` fetch, never a search sync alone. Caught a first-ever
  test gap for this while writing coverage: `bunny_core_fetch_and_cache_post`'s Inkbunny branch
  had no test at all until this milestone (only e621 was covered since M8.5.5a) — added one
  using a copy of `libinkbunny`'s own `submission_full.json` fixture, the first Inkbunny
  fixture in this test suite that actually includes a `"files"` array.

- [x] **M8.5.7 — Grid tile badges**
  New `app/lib/widgets/rating_badge.dart` — the app's first `widgets/` directory, pulled out
  since this is genuinely reusable UI, not screen-specific. `ratingBadgeFor(BunnySite,
  String? rating) -> (Color, String)` is a pure function (no backend changes; `BunnyPost`
  already carries `rating`/`score`/`scoreUp`/`scoreDown`/`favCount`): e621's rating is a fixed
  3-value encoding (`"s"`/`"q"`/`"e"`) mapping cleanly to green/amber/red with a single-letter
  label; Inkbunny's `rating_name` is free text with no fixed value set, so it's best-effort
  keyword-matched (general/safe → green, mature/moderate/questionable → amber, explicit/adult
  → red), falling back to a neutral grey badge showing the raw string for anything unmapped on
  either site — never hidden, never a crash. `RatingBadge` wraps it as a small colored chip.
  `PostGridScreen` tiles gained the badge (top-left, leaving the existing unseen dot at
  top-right untouched) plus a bottom overlay bar showing `score`/`favCount` with small icons.
  Unit tests for `ratingBadgeFor` cover all three e621 values, several Inkbunny strings, and
  an unmapped fallback on each site; a widget test confirms the badge and overlay render on
  grid tiles.

- [x] **M8.5.8 — Post detail redesign**
  The big UI consumer of M8.5.3/4/5/7, sequenced after all four landed. One small backend
  gap closed first: nothing exposed "fetch one cached post by its local id" to Flutter, needed
  so tapping a parent/child/pool chip (after `fetchPost` caches it by external id) can load
  and display it. Added `bunny_core_post_get_by_id` (thin wrapper around the already-existing
  `bunny_db_post_get_by_id`), `GET /posts/{id}` (bare id, added as the last dispatch branch in
  `routes_queue.c`'s existing `posts_handler` — `post_to_json` duplicated from
  `routes_searches.c`'s, matching the already-duplicated `add_optional_string` precedent
  between these two files), and `BunnyRepository.getPost(int) -> Future<BunnyPost>` across
  FFI/HTTP/Fake.
  `PostDetailScreen.build()` redesigned: media now sized via `AspectRatio` off
  `post.width`/`.height` instead of a fixed height, capped at 60% of the viewport height so a
  very tall/narrow image can't push every metadata section below the fold (found via a widget
  test regression — an uncapped `AspectRatio` at a typical test-viewport width made the media
  exactly as tall as the whole window, putting the title/metadata outside the `ListView`'s
  sliver layout+cache range entirely; `find.text` and real rendering treat that as "offstage"
  identically, since a `SliverList`'s `debugVisitOnstageChildren` only visits children within
  its laid-out+cache extent). New sections, each calling its M8.5.3-5 repository method in
  `initState`: categorized tag chips (`Wrap` per category, Inkbunny's single uncategorized
  group shown as plain "Tags" — not tappable yet, deferred to M8.5.10's tag-browse screen);
  sources as a tappable link list via a new `url_launcher` dependency (hidden entirely, not
  empty-shown, when there are none); a post-id row with `Clipboard.setData` copy-on-tap +
  `SnackBar` confirmation; e621-only parent/children chips (`getPostRelationships`) each
  tappable → `fetchPost` + `getPost` → push a new `PostDetailScreen`; e621-only pool chips
  (`getPostPoolIds`) each tappable → `fetchPool` for a label, then reuse-or-create a
  `pool:<id>` search (same mechanism as M8.5.5b's Pools tab) and navigate into it via
  `PostGridScreen`. Inkbunny posts get none of the relationships/pools sections (no such
  concept) and no prev/next sibling nav (still out of scope per the original M8.5.5 notes).
  **Test gotcha, widget-test-only**: `Clipboard.setData`'s platform channel call never resolves
  inside a `testWidgets` fake-async pump loop on the headless `flutter_tester` engine unless a
  mock handler is installed for `SystemChannels.platform` — a plain `test()` body (no
  `pumpWidget`) doesn't hit this since it isn't running inside the fake-async zone, which is
  why the gap wasn't visible until a widget test actually tapped the copy-id row.

- [x] **M8.5.9 — Full-screen zoomable viewer**
  New `photo_view` dependency, used exactly as originally planned (`PhotoViewGallery.builder`
  for pinch-zoom + swipe-between-posts together). New
  `app/lib/screens/full_screen_post_viewer_screen.dart`: a `Scaffold` wrapping
  `PhotoViewGallery.builder` over a caller-supplied `posts`/`initialIndex`, with its own
  `PageController` and an `onPageChanged` that calls `repository.markPostSeen` for whichever
  post the gallery just scrolled onto. `PostDetailScreen` gained an optional `siblingPosts`
  constructor parameter (`null` by default, e.g. when opened standalone via a parent/child/pool
  chip — falls back to a single-post gallery of just the current post); `PostGridScreen` now
  passes its currently loaded `posts` list through on every tile tap. Tapping the detail
  screen's own image media (not video — videos keep the existing in-place player and never
  route here) filters `siblingPosts` down to image-extension posts, finds the current post's
  position in that filtered list, and pushes the full-screen viewer at that index. Because
  `PostDetailScreen` already imports `post_grid_screen.dart` (for pool-chip navigation, M8.5.8)
  and `PostGridScreen` already imports `post_detail_screen.dart` (to open a tapped tile), this
  is simply one more screen in that same mutual-import pair — Dart has no cycle restriction
  between library files, so no extraction was needed. Widget tests cover the initial
  page/index and that swiping fires `markPostSeen` for the newly-visible post only (spied via
  `FakeBunnyRepository.postsBySearchId`'s in-place mutation, same pattern every other
  `markPostSeen` test in this suite already uses) — `pumpAndSettle()` after the drag timed out
  (`PhotoViewGallery`'s internal scale/gesture animations don't fully quiesce within its
  retry budget), so the test uses an explicit `pump()` + fixed-duration `pump()` instead, the
  same workaround pattern already used for `SnackBar`-involving tests in this suite.

- [x] **M8.5.10 — Tag/artist click-through browsing**
  New `bunny_core_preview_search(core, site, query, out_list)`: runs a single page of `query`
  live against `site`, upserts whatever comes back into the local post cache, and returns the
  full post list -- but creates no `searches`/`search_results` row, unlike
  `bunny_core_search_create` + sync. Implemented by collecting each upserted post's local id
  and reading it straight back via the already-existing `bunny_db_post_get_by_id` (building the
  result with a file-local `GOBLIN_DYN_ARRAY_DECL(bunny_core_post, bunny_db_post_t)` -- safe to
  declare independently of `libs/db`'s own identically-shaped array type, since the macro
  expands to `static inline` functions with no link-time visibility). New
  `server/src/routes_search.c`/`.h` (`/search`, singular, had no existing owner, unlike
  `/searches` and `/posts` -- a genuinely new resource prefix, matching the `routes_pools.c`
  precedent) registers `POST /search/preview?site=&query=`. Full plumbing: FFI binding +
  isolate wrapper, `BunnyRepository.previewSearch(site, query) -> Future<List<BunnyPost>>`
  across FFI/HTTP/Fake.
  New `app/lib/screens/tag_browse_screen.dart`: runs `previewSearch` in `initState` and shows
  the results as a grid, with an app-bar action to save the query as a real search (navigates
  to `CreateSearchScreen`, now pre-fillable via new optional `initialSite`/`initialQuery`
  constructor params, `null` by default so the existing FAB-driven blank-form flow is
  untouched). `PostGridScreen`'s tile-building `Stack` (badges/unseen-dot/score overlay, M8.5.7)
  was factored into a new `app/lib/widgets/post_grid_tile.dart` so `TagBrowseScreen` reuses it
  instead of duplicating the whole thing -- the second entry in `widgets/`, after `rating_badge.
  dart`. `PostDetailScreen`'s tag chips (previously inert, deferred from M8.5.8) and artist text
  are now tappable, both opening `TagBrowseScreen` with the tapped tag/artist name as the query
  (an e621 artist name already *is* the literal tag string for that post, so no special
  `artist:` prefix is needed). This required threading a `syncSettingsStore` parameter through
  `PostGridScreen` and `PostDetailScreen` (previously neither needed one) so `TagBrowseScreen`'s
  "add to searches" action has what it needs to construct `CreateSearchScreen` -- the same
  constructor-signature ripple this project has repeatedly hit for widely-used screens, fixed
  the same way every previous time (fix each call site, `flutter analyze` until clean).
  **Test gotcha**: a `tester.tap()` on a `PostGridTile` inside `TagBrowseScreen`'s `GridView`
  failed to hit-test in the test environment (the tile's own `GestureDetector` render object
  never appeared in the resulting hit-test chain, despite `tester.getRect`/`getCenter`
  reporting correct on-screen geometry for it) -- root cause not tracked down, and the
  equivalent tap in `PostGridScreen`'s own, structurally near-identical test passes without
  issue, so this looks specific to some difference in this screen's widget tree rather than a
  general `PostGridTile` problem. Worked around by invoking the tile's `onTap` callback directly
  instead of a synthetic `tester.tap()`, which still verifies the navigation logic under test
  (the right post opens) without depending on Flutter's hit-testing resolving correctly here.

- [x] **M8.5.14 — Favorite/vote UI on post detail**
  No new backend at all -- `queueFavoriteAdd`/`queueFavoriteRemove`/`queueVote`/`processQueue`
  have existed end-to-end since M4.3, just never had a UI calling them. `PostDetailScreen`
  gained a favorite toggle (filled/outline heart) and up/down vote `IconButton`s, placed right
  below the title/artist/description block. Vote buttons are disabled (not hidden) for Inkbunny
  posts -- no vote API exists there at all, same "grey out rather than fail silently" principle
  already stated for comments; favorite stays enabled for both sites since the unofficial
  Inkbunny favorite route (M2.2) covers it. Each tap calls the matching `queue*` method, then
  `processQueue()` immediately (so it reaches the site right away rather than waiting for the
  next scheduled drain, same reasoning M5.3's background scheduler already established), then
  optimistically updates a new mutable `_post` state field via a single `_applyOptimisticUpdate`
  helper that rebuilds a `BunnyPost` with the relevant field(s) adjusted (no `copyWith` exists
  on the model -- nothing else has needed one -- so this lists every field once, the same
  manual-reconstruction approach `FakeBunnyRepository._markedSeen` already uses). Only this one
  mutable copy is used for display; every other method in the screen still reads the original,
  never-mutated `widget.post` for fields that can't change via these actions (site, externalId,
  fileExt, ...). `FakeBunnyRepository`'s four queue methods, previously `throw
  UnimplementedError()` stubs (nothing before this needed them), now record their calls in
  simple in-memory lists/counters so widget tests can assert on them directly. Widget tests
  cover: tapping favorite (queues the right action, drains the queue, flips the icon, bumps
  `favCount`), tapping up/down vote (queues the vote, bumps `score`), and vote buttons being
  disabled -- but not hidden -- on an Inkbunny post. This was the last **M8.5** sub-milestone
  that didn't need the user present; only **M8.5.2** (the Inkbunny search 403, a live-debugging
  step against a real account) remains before M8.5 as a whole is done.

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
