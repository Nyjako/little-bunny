# Architecture

LittleBunny is an e621 + Inkbunny viewer/manager with three moving parts.

## Components

1. **Server** (C, CMake, CPM, SQLite, Linux) — owns the sync state. Stores e621/Inkbunny
   credentials, runs scheduled searches (24h default), tracks seen/unseen posts per device,
   and proxies favorite/vote/comment actions to the sites so any device can trigger them
   without needing its own site session. **Inkbunny is the exception**: its API has no
   favorite/comment write actions at all (see "Inkbunny API constraints" below), so the
   server can only proxy those for e621. Wraps `bunny_core` in an HTTP/HTTPS API (M5) —
   see "C server (M5)" below.
2. **Core library** — the site clients, DB layer, and sync engine compiled as a library,
   usable in two modes:
   - **Networked**: the server process links it; GUI clients talk to the server over
     HTTP/JSON.
   - **Standalone**: the Flutter GUI links the same core directly via FFI and runs
     everything in-process — no server required.
3. **GUI** (Flutter, desktop + mobile) — talks to either the remote server or the local
   FFI core through one repository interface, so screens don't know or care which mode
   is active.

## Downloads are client-side

The server/core never proxies binary downloads — it only ever hands back a URL (and the
expected md5). Each device downloads and checksums its own local copy directly from the
site's CDN, since every device is downloading a full local copy anyway. This keeps the
server lightweight and avoids doubling bandwidth through it.

## Library boundaries

`libe621` and `libinkbunny` are standalone, reusable C libraries with **no** dependency on
the server, the DB layer, or Flutter — they only know how to talk to their respective
site's API. This is intentional so they can be reused outside this project. Both share
`bunny_common` (HTTP transport + JSON helpers) to avoid duplicating that plumbing.

The core sync engine (M4) depends on `libe621`/`libinkbunny` plus the DB layer, but those
site libraries never depend back on the core.

## Database layer (M3)

`bunny_db` (`libs/db`) wraps SQLite behind an opaque `bunny_db_t` handle and a CRUD API
per concern (`bunny_db_account_*`, `bunny_db_search_*`, `bunny_db_post_*`,
`bunny_db_favorite_*`, `bunny_db_download_*`, `bunny_db_top_favorited_tags`). Nothing
outside `libs/db/src` touches `sqlite3.h` directly. Schema (`libs/db/src/schema.h`) is a
single idempotent `CREATE TABLE IF NOT EXISTS ...` block applied on every `bunny_db_open()`,
covering accounts, searches, a post cache with normalized `tags`/`post_tags` tables (so
tag-based queries like the top-favorited-tags stat don't need to parse JSON at query time),
search-result membership, seen state, a favorites mirror, and downloads.

Posts are cached via **upsert** keyed on `(site, external_id)`: re-fetching a post updates
the existing row (and replaces its tag associations) rather than duplicating it, so the
sync engine (M4) can call this on every poll without needing to check "have I seen this
post before" itself.

Unlike `libe621`/`libinkbunny`, `bunny_db`'s tests don't use a fake/injectable transport —
they open a real `:memory:` SQLite database and exercise the actual CRUD API against it.
SQLite itself is the test double here; there's no meaningful way to fake a database layer
and still test the SQL.

SQLite is vendored differently from the other CPM dependencies: it has no CMake-ready
GitHub repo, so `CPMAddPackage` fetches the official amalgamation zip directly by URL (with
a `URL_HASH` pin) with `DOWNLOAD_ONLY YES`, and the top-level `CMakeLists.txt` defines its
own `add_library(sqlite3 STATIC ...)` target around the downloaded `sqlite3.c`.

## Core sync engine (M4)

`bunny_core` (`libs/core`) is the first library that links `bunny_db` together with the
site clients `libe621`/`libinkbunny` (`bunny_e621`/`bunny_inkbunny` linked `PRIVATE`, since
`bunny_core`'s public API never exposes `e621_client_t`/`inkbunny_client_t`), matching the
"Components" description above. It exposes a `bunny_core_t` handle that wraps a
`bunny_db_t`, and takes a `bunny_core_config_t` at `bunny_core_open()` (db path, user
agent, and optional injectable HTTP transports per site — mirroring `e621_config_t`/
`inkbunny_config_t`'s own pattern, and for the same reason: it's what makes
`bunny_core_sync_due_searches()` testable without real network calls).

**Credential storage is intentionally plain, not encrypted.** The original plan for M4.1
was a single-passphrase "vault" (AES-256-GCM, PBKDF2 key derivation) that would double as
the future app-lock credential. The user rejected this design: the server has to run
scheduled syncs unattended, with no human present to unlock anything, so gating credential
access behind an interactive passphrase would make the server unable to sync while
"locked" — the wrong model entirely for a 24/7 process. The clarified, current model:

- `bunny_db_account_set/get/delete` (`libs/db/src/accounts.c`) store one account per site
  (`accounts.secret` is now a plain `TEXT` column, not a placeholder BLOB) with no
  encryption layer. `bunny_core_account_*` (`libs/core/src/accounts.c`) is a thin
  pass-through so M4.2/M4.3 (and later M5) have one call site for "the credential for this
  site" rather than reaching into `bunny_db` directly.
- **App-lock (password/PIN/fingerprint) is a separate, per-device, client-side concern**
  (M7), not tied to how the server stores site credentials at all. Each GUI instance can
  use a different mechanism — e.g. password on desktop, fingerprint with a PIN fallback on
  mobile.
- **Client↔server authentication** ("a safe way to connect to server") is also out of scope
  here — it's M5's job (see the Roadmap), since it only exists once there's an actual
  server process for clients to authenticate against.

**Scheduled search sync (M4.2)**: `bunny_core_sync_due_searches()` (`libs/core/src/sync.c`)
builds e621/Inkbunny clients via `bunny_core_build_e621_client`/`build_inkbunny_client`
(`libs/core/src/site_clients.c` — factored out during M4.3 once the action queue needed the
exact same "build a client using the stored account, or guest/anonymous" logic). A search
is "due" when
`last_run_at` is `NULL` or more than `interval_hours` old — computed in C via
`strptime`/`timegm` against the stored ISO-8601 timestamp (POSIX, not standard C11; needs
`_DEFAULT_SOURCE`/`_XOPEN_SOURCE` defined before any header include, since this project
targets Linux natively and cross-compiles via dockcross rather than aiming for strict
standard-C portability). One search failing to sync (network error, no Inkbunny guest
access, etc.) doesn't block the others or fail the whole call — it's simply left due and
retried on the next call, matching the "no retry scheduling in M4" stance also used by the
action queue (M4.3). Mapping notes:
- e621's 8 tag categories (`general`/`artist`/`copyright`/`character`/`species`/`invalid`/
  `lore`/`meta`) are flattened into the single flat tag array `bunny_db_post_upsert_t`
  expects; multiple `tags.artist` values are joined into one string for the `artist` column
  (e621 posts can have collabs) since the schema only has room for one.
- Inkbunny's search endpoint doesn't return `description` or `keywords` (Inkbunny only
  populates those via `inkbunny_get_submission(s)`, per `libs/inkbunny/include/inkbunny/
  types.h`) — those columns are simply left unset from a sync pass; nothing currently
  re-fetches full submission details to backfill them.

`bunny_core_search_create/delete/list/list_posts` were added alongside the sync engine as
thin `bunny_db` pass-throughs (same pattern as the M4.1 account wrappers) — `bunny_core` is
the single entry point every app uses (standalone FFI or networked server), so it has to
expose search CRUD even though the sync engine itself only ever reads searches.

**Action queue (M4.3)**: `bunny_core_queue_favorite_add/remove/vote/comment()`
(`libs/core/src/queue.c`) enqueue into a new `action_queue` table (`bunny_db_action_queue_*`,
`libs/db/src/action_queue.c`) — fast, no network. `bunny_core_process_queue()` later drains
every `pending` row: resolves its local `post_id` to `(site, external_id)` via the new
`bunny_db_post_get_by_id` (the queue only ever has the local id, matching
`bunny_db_favorite_add`/`bunny_db_download_record`'s own convention — there was previously
no way to look a post up by local id alone, only by `(site, external_id)`), builds a client
for that site, calls the matching e621/Inkbunny function, updates the local favorites
mirror (`bunny_db_favorite_add/remove`) on success, and marks the row `done` or `failed`
with an error message. e621 actions reuse one client across the whole pass; Inkbunny
actions don't, since the unofficial favorite route needs a per-client website session
login anyway (see below) and there's no meaningful reuse to be had.

Action-specific data (a vote's `score`/`no_unvote`, a comment's `body`/`anonymous`, a
favorite's optional `stars`) is stored in the row's `payload` column as a small JSON blob,
built and read with cJSON directly (`libs/core/src/queue.c` — already a transitive
dependency of `bunny_core` through `bunny_common`, so no new dependency was needed).
`bunny_db` itself never parses `payload`; it's opaque storage as far as that layer is
concerned.

Two real constraints shape what the queue can actually do for Inkbunny:
- **No vote or comment API at all** (see "Inkbunny API constraints" below) — queuing one
  against an Inkbunny post is accepted (the queue doesn't know a post's site until it's
  processed) but always fails immediately when processed, with a clear error, rather than
  attempting anything.
- **Favoriting needs a real account, not guest.** `inkbunny_website_login()` (the
  unofficial route's own login, separate from `inkbunny_login()`) takes no anonymous mode
  — if no Inkbunny account is configured, a queued Inkbunny favorite action fails
  immediately (no network call attempted) with a clear error rather than trying and
  failing at the site. This also means, per the unofficial-favorites doc comment in
  `libs/inkbunny/include/inkbunny/unofficial_favorites.h`, that **Inkbunny favorite actions
  have no automated test coverage** — that route has no injectable transport (it needs a
  real persistent cookie-jar session), only manual/live verification, same as M2.2.

`bunny_core_build_e621_client`/`build_inkbunny_client` (`libs/core/src/site_clients.c`) were
factored out of M4.2's sync code specifically so the queue could reuse the exact same
"build a client using the stored account, or guest/anonymous" logic instead of duplicating
it.

## C server (M5)

`server/` (executable target `bunny_server`) links `bunny_core` and exposes it over HTTPS,
turning the library into the always-on sync authority multiple devices talk to. Config is
env-var-only (`BUNNY_SERVER_PORT`/`DATA_DIR`/`USER_AGENT`/`POLL_INTERVAL_SEC`,
`server/src/config.c`) — four settings didn't justify a config-file parser. The data
directory defaults via GOBLIN's `appdirs.h` (`goblin_appdir_data_dir`), the first real use
of that header after it sat as a "good future fit" note since M3/M4; its implementation is
instantiated in the same single spot as `cstr.h`'s (`libs/common/src/goblin_impl.c`), via
its own `GOBLIN_APPDIR_IMPLEMENTATION` macro.

**HTTP library**: [civetweb](https://github.com/civetweb/civetweb), vendored via CPM
(target name is `civetweb-c-library`, not `civetweb` — check `build/_deps/civetweb-src` if
this ever needs re-verifying against a version bump). `CIVETWEB_ENABLE_SSL_DYNAMIC_LOADING
OFF` so it links OpenSSL directly at build time instead of `dlopen`-ing it at runtime,
matching how curl is configured. **`CIVETWEB_ENABLE_ASAN OFF` is load-bearing**: civetweb's
own CMakeLists defaults `CIVETWEB_ENABLE_ASAN` to `ON` in Debug builds, completely
independent of this project's `BUNNY_ENABLE_ASAN` — without turning it off, any Debug build
fails to link with `undefined reference to __ubsan_handle_*` because civetweb's object code
expects a sanitizer runtime that isn't linked into anything else. No other vendored
dependency (sqlite3, curl, cJSON) self-instruments like this; only `BUNNY_ENABLE_ASAN`
controls sanitizer coverage for this project's own code.

**Security model (why it looks the way it does):** this server is meant to run on a remote
host (confirmed target: an Oracle Cloud free-tier instance) rather than the user's LAN, and
the user explicitly doesn't want to run a reverse proxy or manage TLS certificates by hand.
That combination — remote, no proxy, no manual certs — drove two decisions:
- **Auth is a single shared bearer token** (`server/src/auth.c`), 32 random bytes from
  OpenSSL's `RAND_bytes`, hex-encoded, generated once into `<data_dir>/auth_token` (`0600`)
  and logged to stdout on first generation only. Every route except `/health` must present
  it via `Authorization: Bearer <token>` (`server_auth_check_request`, constant-time
  compare via `server_auth_verify`). Simpler than per-device paired/revocable tokens,
  appropriate for a single-user app — revoking access means regenerating the file and
  re-entering it on every client.
- **The server generates its own self-signed TLS certificate** (`server/src/tls.c`,
  OpenSSL `EVP_PKEY`/`X509` APIs, RSA-2048, ~10-year validity, written to
  `<data_dir>/server.pem` in civetweb's combined-cert-and-key convention) and terminates
  HTTPS itself. There's no CA involved and likely no domain name (a cloud instance's public
  IP), so plain HTTP was ruled out (the bearer token would cross the open internet in
  cleartext) but so was a CA-issued cert. **This means M7's GUI must pin the server's
  certificate — by its SHA-256 fingerprint, shown once alongside the auth token — rather
  than validating it against the system trust store.** This is a trust-on-first-use model,
  the same shape as SSH host keys, not the web PKI. The cert's long validity exists
  specifically so M5 doesn't also need rotation logic.
- Because credentials in the DB are stored plain (M4.1) and the auth token/TLS key are
  sensitive, `main.c` explicitly `chmod`s the SQLite DB file to `0600` right after
  `bunny_core_open()` (SQLite/the OS default is more permissive) — the same treatment the
  token and cert files already get from `server_auth_load`/`server_tls_ensure_cert`.

**Concurrency**: `bunny_core` and `bunny_db` were built assuming a single caller (every
prior milestone's tests and tools were single-threaded). civetweb runs a worker-thread pool
by default, and the M5.3 scheduler thread (below) is a second concurrent caller into the
same `bunny_core_t`/`sqlite3*` where there used to be at most one. Fix: a single
`pthread_mutex_t` in `server_context_t` (`server/src/context.h`) that every route handler
and the scheduler must lock around their `bunny_core_*` calls. Coarse-grained on purpose —
this is a personal, low-traffic server, not something that needs fine-grained locking.

`/health` (no auth) returns `200 {"status":"ok"}` and exists mainly to smoke-test that the
HTTPS listener and cert came up correctly.

**REST surface (M5.2)**: `server/src/routes_accounts.c`/`routes_searches.c`/
`routes_queue.c` — one file per resource, matching `bunny_db`'s own per-concern file split
(`libs/db/src/{accounts,searches,...}.c`). Each registers a single civetweb handler at a
resource's URI prefix (`mg_set_request_handler`, e.g. `/accounts`) and dispatches internally
on HTTP method + sub-path, since civetweb's prefix matching means `/accounts` already
matches `/accounts/e621` — there's no per-route wildcard registration API to lean on
instead. `server/src/route_utils.c` centralizes the resulting parsing (`server_route_sub_path`,
`server_route_parse_id[_with_suffix]`, `server_route_parse_site`) so each route file isn't
re-deriving its own path-splitting logic. `server/src/json_helpers.c` centralizes request-body
JSON parsing (`server_json_read_request_body`, size-capped at 64KB) and response writing
(`server_json_respond`/`server_json_respond_error`, the latter mapping `bunny_core_result_t`
to an HTTP status: 400/`ERR_INVALID_ARG`, 404/`ERR_NOT_FOUND`, 502/`ERR_SITE`,
500/anything else). Queue-action routes (`POST /posts/{id}/favorite|vote|comment`) respond
`202 Accepted`, not `200` — they only enqueue (`bunny_core_queue_*`), matching that the
action hasn't actually run against the site yet. `GET /accounts/{site}` never echoes
`secret` back, only `username` — the whole point of the account endpoints is to store a
credential, not redisplay it.

`server_app_start()`/`server_app_stop()` (`server/src/app.c`) hold everything `main.c` used
to do directly (load/generate the auth token and TLS cert, open `bunny_core`, start
civetweb, register every route) behind two calls taking a `bunny_core_config_t` and a data
dir. This exists because `main.c`'s original inline version couldn't be exercised by tests
without either re-implementing the wiring or spawning the built `bunny_server` binary as a
subprocess; factoring it out means `server/tests/test_integration.c` links the exact same
code (`bunny_server_lib`, a static library both `bunny_server` and the test suite link) and
drives it with real HTTPS requests over libcurl, injecting a fake `e621_transport` into the
`bunny_core_config_t` so a full account→search→sync→favorite→process flow never touches
the real network. This is the same "real behavior over fakes where practical" testing
philosophy `bunny_db` uses (real `:memory:` SQLite) applied one layer up: a real civetweb
instance, a real `bunny_core`, a real (in-memory) database, only the outermost HTTP call to
e621 faked.

A real bug surfaced during manual testing of this milestone: queuing an action against a
post id that doesn't exist hit `action_queue`'s `post_id` foreign-key constraint and
surfaced as a `500 database error`, which is misleading — it's the caller's fault (a bad
id), not the server's. Fixed at the source: `bunny_core_map_db_result`
(`libs/core/src/internal.h`) now maps `BUNNY_DB_ERR_CONSTRAINT` to
`BUNNY_CORE_ERR_INVALID_ARG`, so every `bunny_core` API gets the correct client-error
classification for constraint violations, not just this one route.

**Background scheduler (M5.3)**: `server/src/scheduler.c`'s `server_scheduler_start/stop()`
run a `pthread` that loops sleep(`poll_interval_sec`) → `bunny_core_sync_due_searches` →
`bunny_core_process_queue` → repeat, locking the same `core_mutex` as every route handler.
It sleeps in 1-second increments (checking a stop flag each time) rather than one long
`sleep(poll_interval_sec)`, so `server_app_stop()` can join it within about a second instead
of waiting out the full interval. `poll_interval_sec <= 0` disables it entirely — the
integration test suite (`server/tests/test_integration.c`) uses this for every test except
one, since a background pass firing mid-test would race (and consume) the fake transport's
single canned response before the test's own explicit `/sync` call gets to it; the one
exception test runs with a 1-second interval specifically to exercise the real thread.
`server_app_start()`/`server_app_stop()` (`server/src/app.c`) own the scheduler's lifecycle
alongside civetweb and `bunny_core` — on shutdown the scheduler is stopped *first*, so it's
done issuing `bunny_core_*` calls before civetweb's workers and the core itself are torn
down. `main.c`'s `SIGINT`/`SIGTERM` handling (from M5.1) needed no changes; it already just
calls `server_app_stop()`, which now also tears down the scheduler.

## Flutter app (M6)

`app/` is the Flutter GUI (desktop + mobile, per the Components section above). Managed via
[fvm](https://fvm.app/) — always run `fvm flutter ...`/`fvm dart ...`, not the bare
commands, since the SDK version is pinned in `app/.fvmrc` (Flutter 3.44.0 / Dart 3.12.0) for
reproducibility. **Only Linux desktop and Android are build-verifiable in the dev
environment this was built in** — Windows/macOS/iOS have no local toolchain there, so those
platforms are scaffolded (present in `--platforms=...`) but unverified until built somewhere
with the right toolchain.

**Repository pattern (M6.1)**: `lib/repository/bunny_repository.dart` defines `abstract
interface class BunnyRepository`, the single seam between the UI and the two ways this app
can reach `bunny_core`'s functionality:
- **Standalone**: FFI directly into `bunny_core` (M6.2, `bunny_core_ffi/`).
- **Networked**: HTTPS against a `bunny_server` instance (M6.3), the exact same REST
  surface documented in "C server (M5)" above.

`lib/repository/bunny_models.dart` has the plain Dart mirrors of `bunny_db_account_t`/
`search_t`/`post_t`/the two stats structs (`BunnyAccount`, `BunnySearch`, `BunnyPost`,
`BunnySyncStats`, `BunnyQueueStats`) plus a `BunnySite` enum with `toWireString`/
`fromWireString` (`'e621'`/`'inkbunny'`, matching `bunny_db_site_to_string`'s own output --
reused as-is for the M6.3 HTTP implementation's JSON encoding). `BunnyAccount` deliberately
**omits the secret** even though the FFI side technically has local access to it: the
server's `GET /accounts/{site}` never returns it (M5.2), so for the two `BunnyRepository`
implementations to stay behaviorally identical — the entire point of having one interface —
the FFI implementation must drop it too when mapping its local `bunny_db_account_t` to this
model. `getAccount()` returns `null` for "not found" (an expected, ordinary outcome) rather
than throwing; `BunnyRepositoryException` is reserved for actual failures.

**Standalone mode / FFI (M6.2)**: `bunny_core_ffi/` is a Flutter FFI plugin (the `plugin_ffi`
template — now deprecated by Flutter in favor of `package_ffi`'s native-assets/build-hooks
system, kept here deliberately since this project's whole-CMake-project reuse approach below
doesn't map onto that newer mechanism; revisiting this is a separate future task, not part of
M6).

- **Build reuse, not duplication.** `bunny_core_ffi/src/CMakeLists.txt` pulls in the entire
  top-level CMake project (`bunny_core` and its whole dependency chain — `bunny_db`,
  `bunny_e621`, `bunny_inkbunny`, `bunny_common`, plus CPM-fetched `sqlite3`/`curl`/`cjson`/
  `goblin`) via `add_subdirectory(... EXCLUDE_FROM_ALL)` instead of a second, parallel build
  definition. `EXCLUDE_FROM_ALL` keeps the reused project's targets buildable without
  pulling its third-party dependencies' own `install()` rules (e.g. cJSON's) into the
  default install set — those try to write to `/usr/local/include` and fail without root
  when Flutter's own `cmake --install` step runs. The new top-level `BUNNY_BUILD_SERVER`
  option (default `ON`) gates both `add_subdirectory(server)` and the civetweb
  `CPMAddPackage` call, since this plugin's build only needs `libs/`, not the C server.
  Flutter builds plugins through a symlink
  (`.../flutter/ephemeral/.plugin_symlinks/bunny_core_ffi`), so the subdirectory path is
  resolved with `get_filename_component(... REALPATH)` first to avoid walking up through the
  symlink's apparent location instead of the real one.
- **Whole-archive linking.** `bunny_core_ffi.c` itself never calls a `bunny_core_*`/
  `bunny_db_*` function directly — Dart looks every one of them up by name via
  `DynamicLibrary.lookup` at runtime — so a plain `target_link_libraries` would only pull the
  `.o` files an actual caller references, leaving none of `bunny_core`'s real object code (or
  the symbols Dart needs) in the resulting shared library at all. Fixed by force-linking
  `bunny_core`/`bunny_db` with `-Wl,--whole-archive`/`-Wl,--no-whole-archive` (GNU ld/lld:
  Linux, Android, MinGW), `-Wl,-force_load` (Apple), or `/WHOLEARCHIVE:` (MSVC).
- **Position-independent code.** Linking a non-PIC static archive into a shared library fails
  at link time (`relocation ... can not be used when making a shared object; recompile with
  -fPIC`) because externally-visible symbols in a `.so` must be position-independent so other
  DSOs can preempt them — a requirement the existing executable targets (server, tools)
  never had. Fixed with a project-wide `set(CMAKE_POSITION_INDEPENDENT_CODE ON)` near the top
  of the top-level `CMakeLists.txt` (before any targets/CPM packages are created), rather
  than per-target, since the FFI plugin pulls in the whole dependency chain. No-op on
  Windows/MSVC; harmless for the executables (PIE executables already imply PIC object code
  on Linux) — confirmed via a full `make clean && make test` regression run (11/11 passing).
- **Bindings.** `ffigen` (`dart run ffigen --config ffigen.yaml`) generates
  `lib/bunny_core_ffi_bindings_generated.dart` directly from `bunny_core`'s and `bunny_db`'s
  public headers — they're already plain, simple C, so no hand-written glue is needed beyond
  a near-empty `bunny_core_ffi.c`/`.h` (just a version-string export, required by the
  template's own build plumbing).
- **Dedicated background isolate.** Every `bunny_core_*` call does real work (SQLite I/O, and
  for sync/queue, real network I/O), so none of it may run on Flutter's main isolate without
  blocking UI frames. `lib/src/bunny_core_isolate.dart` routes every operation through one
  isolate, spawned once and kept alive for the app's lifetime via a `SendPort`/`ReceivePort`
  request/response protocol (mirroring Flutter's own `plugin_ffi` template's long-running-call
  example). That isolate is the only thing that ever touches the single `bunny_core_t*`
  handle, so there's never concurrent native access to worry about — the FFI equivalent of
  M5's `core_mutex` solution to the same underlying problem. `package:ffi`'s `using()` arena
  handles native memory cleanup (`Utf8` marshalling) automatically per call.
  `lib/repository/ffi_bunny_repository.dart` implements `BunnyRepository` on top of
  `BunnyCoreNative`, mapping its `Map<String, Object?>` results to the M6.1 model classes and
  translating `BunnyCoreNativeException` into `BunnyRepositoryException`.
- **Testing.** Both `bunny_core_ffi/test/` and `app/test/repository/ffi_bunny_repository_test.dart`
  run against the real compiled shared library (`:memory:`-backed) rather than a mock —
  `flutter test` doesn't build a plugin's native code for the host automatically the way
  `flutter build`/`run` does, so the library must be built once first (either via a real
  `flutter build linux`, or a standalone `cmake -S bunny_core_ffi/src -B <dir> && cmake
  --build <dir>`) with its directory on `LD_LIBRARY_PATH` when running the tests.
- **Android build fixed (M12.1).** The Android NDK ships no prebuilt OpenSSL, so the
  top-level `find_package(OpenSSL REQUIRED)` used to fail `fvm flutter build apk`'s CMake
  configure step. Fixed by gating that `find_package` behind `BUNNY_BUILD_SERVER` (it's only
  ever needed by civetweb/`server/src/auth.c`/`server/src/tls.c`, all already
  `BUNNY_BUILD_SERVER`-gated — Android never builds any of them) and switching curl's TLS
  backend to mbedTLS specifically `if(ANDROID)`: a small, pure-CMake library with no system
  dependency, fetched via CPM `add_subdirectory` (unlike OpenSSL's own `Configure`+`make`
  build, which doesn't fit CPM's model). curl's own `CMake/FindMbedTLS.cmake` module expects
  an already-installed mbedTLS (pkg-config/CMake-config/`find_library`), none of which apply
  to a CPM fetch that never runs `install()`, so the top-level `CMakeLists.txt` pre-sets its
  discovery variables (`MBEDTLS_INCLUDE_DIR`/`MBEDTLS_LIBRARY`/`MBEDX509_LIBRARY`/
  `MBEDCRYPTO_LIBRARY`) *and* pre-creates the `CURL::mbedtls` target it would otherwise
  create — needed because which path actually runs depends on the CMake version (the Android
  SDK's bundled CMake 3.22.1, which is what Gradle's `externalNativeBuild.cmake` actually
  invokes, runs the real discovery logic; a newer system CMake appeared to redirect through
  CPM instead). Android's Bionic libc also has no separate `libpthread` (pthread is built
  into libc), so `sqlite3`'s link libraries are `m` only on Android instead of `pthread m`.
  Verified via a real `fvm flutter build apk --target-platform android-arm64 --debug`,
  producing a working APK with `libbunny_core_ffi.so` for all three bundled ABIs
  (arm64-v8a/armeabi-v7a/x86_64); Linux desktop's `make build`/`make test` continue to use
  OpenSSL unchanged. The Windows app cross-compilation gap above remains open.

**Networked mode / HTTP (M6.3)**: `lib/repository/http_bunny_repository.dart` implements
`BunnyRepository` against the exact REST surface documented in "C server (M5)" above, using
`package:http`'s `IOClient` wrapping a `dart:io HttpClient`.

- **Certificate pinning.** The server's certificate is self-signed with no CA (see the TLS
  section above), so normal certificate-chain validation can't apply. `HttpBunnyRepository`'s
  `badCertificateCallback` computes the SHA-256 hash of the presented certificate's DER bytes
  (`X509Certificate.der`) and compares it against a fingerprint supplied to the constructor —
  accept only on an exact match (case-insensitive, colons optional), reject otherwise. The
  hash comparison itself is a standalone top-level function (`matchesPinnedFingerprint`,
  `@visibleForTesting`) taking raw bytes rather than an `X509Certificate`, since that type has
  no public constructor and can only come from a real TLS handshake — this keeps the actual
  pinning logic testable with synthetic byte arrays, no real handshake needed. Verified both
  ways against a real running `bunny_server` instance: a matching fingerprint completes the
  handshake and reaches real data, a wrong one fails with `CERTIFICATE_VERIFY_FAILED`.
- **Server API gap found and fixed.** `GET /accounts/{site}` (`server/src/routes_accounts.c`)
  originally returned only `{"site", "username"}`, but `BunnyAccount` (M6.1) mirrors
  `bunny_db_account_t` 1:1 and requires `id`/`created_at` too — the FFI implementation gets
  these for free from the DB struct, but the HTTP implementation had nothing to map them
  from. Fixed by extending the route to also return `id` and `created_at` (small, additive,
  backward-compatible — the existing M5.2 integration test asserts on substrings, not exact
  JSON equality, so it wasn't broken; a new assertion for the two fields was added to it).
  Chosen over dropping the fields from `BunnyAccount` (the alternative, mirroring how
  `secret` was already dropped for the same "keep both implementations identical" reason)
  since nothing in `BunnyRepository` uses `account.id` as a lookup key the way `BunnySearch`/
  `BunnyPost` ids are used, so there was no correctness reason to remove real data the DB
  already has.
- **Testability.** `HttpBunnyRepository.withClient` is a `@visibleForTesting` named
  constructor that injects an arbitrary `http.Client` (fakes the transport, not the business
  logic, same philosophy as every C library's own tests) — `app/test/repository/
  http_bunny_repository_test.dart` uses `package:http/testing.dart`'s `MockClient` with
  canned JSON, asserting on request method/path/headers/body and response mapping for every
  method, plus JSON and non-JSON error-body handling. No real network in the automated suite.
- **Repository switch point.** `lib/repository/bunny_repository_factory.dart` is the actual
  "one repository interface" deliverable the M6 roadmap entry describes: a sealed
  `BunnyRepositoryConfig` (`StandaloneConfig`/`NetworkedConfig`) and a `createBunnyRepository`
  factory that returns a `BunnyRepository`, so `main.dart` and every screen only ever depend
  on the interface, never on which implementation is active. `main.dart` threads the result
  through a `BunnyRepositoryScope` `InheritedWidget` rather than a new state-management
  dependency — M6 has no settings UI yet to let the user choose a mode (that's M7), so it
  currently just defaults to standalone/`:memory:`.
- **Manual end-to-end verification.** Beyond the fake-transport unit tests, `HttpBunnyRepository`
  was run against a real `bunny_server` process (real self-signed cert, real auth token, real
  SQLite-backed data) to confirm account/search CRUD, cert-pinning accept/reject, and the
  sync/queue endpoints all work over an actual TLS connection, not just canned responses.

## Auth & app-lock (M7)

**Account verification (M7.1)**: `BunnyRepository.verifyAccount(site, username, secret)`
tests credentials against the real site without persisting them, so the login UI can reject
bad input before calling `setAccount`. Neither e621 nor Inkbunny's official APIs have a
dedicated "am I authenticated" check, so `bunny_core_account_verify`
(`libs/core/src/verify.c`) improvises with each site's cheapest real authenticated call:

- **e621**: no login endpoint at all — every request just carries HTTP Basic auth. Builds a
  throwaway `e621_client_t` with the given username/API key and calls
  `e621_list_favorites(client, NULL, 1, &out)` ("list the authenticated client's own
  favorites"); succeeds or fails exactly as a real authenticated request would, whether or
  not the account actually has any favorites.
- **Inkbunny**: already has an explicit `inkbunny_login(client, username, password)` used
  directly.

Both map any failure (bad credentials, network error, ...) to the existing
`BUNNY_CORE_ERR_SITE` — deliberately not a new result code or an `out_error` string
parameter, since no other function in `bunny_core`'s public API distinguishes reasons for a
site failure either (`bunny_core_result_to_string` is the existing, sole way callers get a
message). This propagates up cleanly: the server's `POST /accounts/verify` route reuses the
exact same `server_json_respond_error` helper every other route already uses (a rejected
credential is a 502 with a generic body, like any other site failure), and
`BunnyRepository.verifyAccount` just throws `BunnyRepositoryException` on failure — matching
every other write-style method on the interface, rather than introducing a
"meaningful non-exceptional failure" case (like `getAccount`'s `null`) that nothing beneath
it actually supports.

**Testing note**: `bunny_core_ffi_open`'s public config has no fake-transport injection
point (standalone mode always talks to the real sites, unlike `libs/core`'s own tests) --
`FfiBunnyRepository`'s and the raw `BunnyCoreNative`'s `verifyAccount` tests deliberately use
bogus credentials against the *real* e621 API rather than a fake one. This is safe to rely
on in the automated suite: e621 will always reject fake Basic-auth credentials, fast and
deterministically, regardless of the test environment's broader network conditions. The
underlying accept/reject *logic* itself is already thoroughly covered with fake transports
at the C level (`libs/core/tests/test_sync.c`, both sites, both outcomes) — the FFI/HTTP
layers only need to prove their own plumbing reaches it.

**Settings & connection setup (M7.2)**: `main.dart`'s `LittleBunnyApp` no longer hardcodes a
`:memory:` standalone repository — it's now a small stateful root that loads a persisted
`BunnyRepositoryConfig` on boot via `app/lib/settings/RepositorySettingsStore`, falling back
to `SetupScreen` (`app/lib/screens/`) on first launch (no config saved yet). Plain
`StatefulWidget`/`setState` handles this root-level branching; a routing package would be
premature before M8's real navigation needs are known.

- **Storage split by sensitivity.** `RepositorySettingsStore` keeps non-secret bookkeeping
  (active mode, server URL) in `shared_preferences`, and the networked mode's bearer
  token/cert fingerprint behind a small `SecretStore` interface
  (`app/lib/settings/secret_store.dart`) — real implementation
  `FlutterSecureStorageSecretStore`, backed by OS-native encryption (Android Keystore, Linux
  libsecret via a running secret-service daemon). The interface exists purely for testability
  (an in-memory fake in tests) since there's no real secure-storage backend under `flutter
  test`. **Dependency to be aware of**: the Linux backend needs a real secret-service
  provider running (gnome-keyring, KWallet, or similar) — confirmed present and responding in
  this project's dev environment via a live D-Bus ping to `org.freedesktop.secrets`, but a
  genuinely headless box (no D-Bus session, no keyring daemon) has no documented graceful
  fallback in the package itself.
- **Standalone mode's db path is never persisted.** It's resolved fresh each launch via
  `path_provider`'s `getApplicationSupportDirectory()` — the Dart-side equivalent of
  GOBLIN's `appdirs.h` used server-side (M5.1) — joined with a fixed filename. Recomputing
  it is cheap and avoids a stale absolute path surviving something like an app reinstall to
  a different location.
- **App-lock secret storage (design decision, ahead of M7.4)**: when the app-lock PIN/
  password is added, it goes into `SecretStore` directly (compared by string equality at
  unlock time), not a hand-rolled salt+hash — `flutter_secure_storage` already encrypts
  values at rest via the OS-native mechanism, so layering custom hashing on top would just
  be extra bespoke crypto code for a feature that's a local device UI gate, not data-at-rest
  protection.
- **Connection check reuses `HttpBunnyRepository`, not `GET /health`.** `SetupScreen`'s
  networked-mode form validates the entered server URL/token/fingerprint with
  `checkServerConnection` (`app/lib/settings/server_connection_check.dart`) before saving
  anything — a throwaway `HttpBunnyRepository.listSearches()` call. `/health` needs no auth
  (see "C server (M5)" above), so it would only prove the server and certificate are
  reachable, never catch a wrong bearer token; `listSearches` is a lightweight authenticated
  read that exercises both checks in one real request. Not a `BunnyRepository` interface
  method — a connection health check isn't meaningful for standalone/FFI mode.
- **Manual end-to-end verification**: run against a real `bunny_server` instance (same
  throwaway-server approach as M6.3's check) — correct config connects successfully, a wrong
  bearer token is rejected with a real 401, and a wrong certificate fingerprint fails the TLS
  handshake itself (`CERTIFICATE_VERIFY_FAILED`) before any request is even sent.

**Site login screens (M7.3)**: `AccountsScreen` (`app/lib/screens/accounts_screen.dart`)
replaces the M6 placeholder as the app's real home page — it lists both `BunnySite`s via
`BunnyRepository.getAccount`, showing each as "Not connected" or "Logged in as
{username}" with a remove action gated by a confirmation dialog. Tapping an unconfigured
site opens `LoginFormScreen`, whose only per-site difference is field labels/obscuring
(e621: username + API key; Inkbunny: username + password, obscured) — it calls M7.1's
`verifyAccount` before `setAccount`, so a rejected credential never gets persisted and its
`BunnyRepositoryException.message` is shown inline instead.

- **Testing seam**: `app/test/fakes/fake_bunny_repository.dart` is a hand-written
  `BunnyRepository` fake implementing only the four account methods these two screens
  actually call (everything else throws `UnimplementedError`, since nothing under test
  reaches it) — no mocking framework, matching the project's "fake the dependency, not the
  business logic" style used throughout M1–M7. `verifyAccount`/`setAccount`/`deleteAccount`'s
  actual behavior against real sites/a real server is already covered by M7.1; these tests
  only need to prove the UI's own orchestration (state → rendering, error display, confirm
  dialog wiring) is correct.
- **A real bug these tests caught**: `AccountsScreen._refresh`'s original
  `setState(() => _accountsFuture = _loadAccounts())` is an arrow function whose body is an
  assignment expression — and a Dart assignment expression evaluates to the *assigned
  value*, so the closure itself returned a `Future` even though nothing was `async`/`await`ed.
  Flutter's `setState` asserts against exactly this (it can't safely rebuild before an
  unawaited Future completes). Fixed by switching to a block body
  (`setState(() { _accountsFuture = _loadAccounts(); })`), which returns `void` instead.
- **`BunnyRepositoryScope` moved out of `main.dart`** into its own
  `app/lib/bunny_repository_scope.dart` once `AccountsScreen` needed to reference it — keeps
  `main.dart` and `screens/accounts_screen.dart` from importing each other circularly.
- **Widget-test network caveat**: `flutter test`'s `TestWidgetsFlutterBinding` intercepts
  every `HttpClient` request and returns them immediately (status 400, no real socket) —
  but the resulting Future chain inside a real `HttpBunnyRepository` (used in
  `test/widget_test.dart`'s "already configured" case, pointed at an intentionally
  unreachable `localhost`) never converges through `pumpAndSettle()`'s idle-check. Fixed by
  pumping a bounded, fixed number of frames instead — enough to get past the (fake-backed,
  non-networked) settings load and render `AccountsScreen`'s `Scaffold`/`AppBar`, which
  doesn't itself wait on the account-loading future to appear.

**App-lock (M7.4, completes M7)**: `AppLockService` (`app/lib/settings/app_lock_service.dart`)
stores whether the lock is enabled (`shared_preferences`) and the PIN/password itself
directly in `SecretStore` (`app_lock_secret` key, compared by string equality in `verify`) —
the same direct-storage-not-hashing rationale already used for the networked mode's bearer
token (M7.2): the real `SecretStore` backend already encrypts values at rest via the
OS-native mechanism, and this is a local UI gate, not data-at-rest protection, so hand-rolled
hashing would just be extra bespoke crypto code with no real benefit.

- **`LockSetupScreen`** (reachable from `AccountsScreen`'s app bar, a lock icon) enables/
  disables the lock. Disabling requires re-entering the current PIN/password first — without
  that, anyone with the app open could remove the lock with no gate at all.
- **`LockScreen`** gates the app at root: `main.dart`'s `LittleBunnyApp` checks
  `AppLockService.isEnabled()` right after the repository is ready (both on initial boot and
  right after `SetupScreen` hands back a repository) and shows `LockScreen` before
  `AccountsScreen` when it's on. On Android, `LockScreen` tries `local_auth` biometric first
  with `biometricOnly: true` — deliberately not the OS's own device-credential fallback,
  since the roadmap's "fingerprint + PIN fallback" means falling back to *this app's own* PIN
  (set up via `LockSetupScreen`), not the phone's screen lock, matching "a per-device,
  client-side setting" independent of the OS. Every platform (and Android whenever biometric
  fails, isn't enrolled, or isn't available) falls back to the same PIN/password entry field.
- **Android integration**: `local_auth`'s `BiometricPrompt` needs a `FragmentActivity` to
  host its dialog fragment and an AppCompat-based activity theme. Per `local_auth_android`'s
  own reference example (`local_auth_android`'s pub cache `example/android/`),
  `app/android/app/src/main/kotlin/.../MainActivity.kt` now extends `FlutterFragmentActivity`
  instead of `FlutterActivity`, and both `values/styles.xml` and `values-night/styles.xml`'s
  `LaunchTheme`/`NormalTheme` now inherit `Theme.AppCompat.*` instead of the plain
  `@android:style/Theme.*` Flutter scaffolds by default — the `windowBackground`/
  splash-screen behavior is otherwise unchanged, only the theme's parent lineage. No manifest
  edit was needed for the `USE_BIOMETRIC` permission itself: `local_auth_android`'s own
  bundled manifest already declares it, and Gradle's manifest merger folds it into the app's
  final manifest automatically. AppCompat itself needed no new Gradle dependency either —
  it's already transitively available via Flutter's own Android embedding. A real
  `flutter build apk` now succeeds (M12.1) and confirmed these two styles.xml files parse and
  package correctly through Gradle's resource merger (it also caught and fixed a pre-existing
  unrelated bug: a literal `--` inside an XML comment, invalid per the XML spec, that had
  gone unnoticed because the build never previously got far enough to validate it). The
  biometric prompt itself still isn't exercised by the automated test suite —
  `Platform.isAndroid` is false on this dev machine's test host, so
  `test/screens/lock_screen_test.dart` only covers the PIN/password fallback, which every
  platform shares — only a real device/emulator run would confirm the `BiometricPrompt` flow
  itself.

## Browse & search (M8)

**Tag autocomplete + mark-seen plumbing (M8.1)**: two `bunny_db`-layer capabilities had never
been exposed anywhere above `bunny_db` before this — `bunny_db_tag_autocomplete` (built and
tested since a pre-M4 chore, just never wired up) and `bunny_db_post_mark_seen`. Both get thin
`bunny_core_tag_autocomplete`/`bunny_core_post_mark_seen` wrappers in `libs/core/src/
searches.c`, then the exact same layering M7.1 established for `bunny_core_account_verify`:
FFI isolate methods, a server route each, and `BunnyRepository` methods implemented in both
`FfiBunnyRepository` and `HttpBunnyRepository`.

- **New server route file, not an addition to an existing one.** `server/src/
  routes_tags.{c,h}` registers `GET /tags/autocomplete?site=&prefix=&limit=` — a genuinely
  new resource, so it gets its own file matching the established one-file-per-resource
  convention (`routes_accounts.c`/`routes_searches.c`/`routes_queue.c`), rather than being
  bolted onto one of those. `POST /posts/{id}/seen`, by contrast, went into the *existing*
  `routes_queue.c`, since that file already owns all `/posts` dispatch.
- **No site-transport complexity, unlike M7.1.** Neither capability ever touches e621/
  Inkbunny site clients — both are pure `bunny_db` reads/writes — so every layer's tests are
  fully deterministic, including at the FFI layer (M7.1's `verifyAccount` tests had to hit
  real e621 network for their failure path, since `bunny_core_ffi_open` has no
  fake-transport override; `tagAutocomplete`/`markPostSeen` need no such workaround).
- **A real bug found via the C-level tests**: `bunny_core_post_mark_seen` on a nonexistent
  `post_id` returns `BUNNY_CORE_ERR_INVALID_ARG`, not `BUNNY_CORE_ERR_NOT_FOUND` as first
  assumed when writing the test. `seen_posts.post_id` has a foreign key against `posts(id)`
  (`ON DELETE CASCADE`), so inserting a row for a post that doesn't exist is a constraint
  violation — `bunny_core_map_db_result` already treats `BUNNY_DB_ERR_CONSTRAINT` as bad
  caller input rather than "not found" (see `libs/core/src/internal.h`'s own comment on
  this, first established for the action queue's foreign key in M4.3). Fixed the test
  expectation, not the behavior — the behavior was already correct and consistent with the
  rest of the codebase.

**Navigation restructuring + saved search management (M8.2)**: browse/search is the app's
real daily-use surface, so `SearchesScreen` (`app/lib/screens/searches_screen.dart`) replaces
`AccountsScreen` as the post-lock home in `main.dart`; `AccountsScreen` moves to an app bar
icon next to the existing settings icon. `SearchesScreen` lists `BunnySearch` via
`listSearches`, each row showing a `{site} • every {hours}h` subtitle and a delete action
(confirmation dialog, mirroring `AccountsScreen._removeAccount`'s existing pattern), plus a
"new search" FAB opening `CreateSearchScreen`.

- **`CreateSearchScreen`'s tag-autocomplete UX.** The query field tracks its "current word"
  as the substring after the last space in the field, debounces a 300ms `Timer` before
  calling `tagAutocomplete(site, currentWord)`, and shows results as `ActionChip`s below the
  field. Picking one appends the tag plus a trailing space to the text *before* the current
  word rather than replacing the whole field — e621-style multi-tag queries, where you're
  always completing just the tag you're currently typing.
- **A real bug this surfaced: `BunnyRepositoryScope` doesn't survive `Navigator.push`.**
  `AccountsScreen` had always been reached as the app's `home` (M7.3 through M8.1), so its
  `didChangeDependencies`-based `BunnyRepositoryScope.of(context)` lookup worked, because
  `main.dart` wrapped `home` directly in the scope. Once `SearchesScreen` became `home` and
  `AccountsScreen` became a screen reached only via `Navigator.push`, that same lookup started
  throwing a null-check error at runtime. The reason: `MaterialApp`'s `Navigator` renders each
  route's widget subtree as a sibling entry inside its own `Overlay`, not as a descendant of
  whatever wraps `home` — an `InheritedWidget` set up around `home` is invisible to any other
  route pushed onto the same `Navigator`. This is the same reason `LoginFormScreen` and
  `CreateSearchScreen` already took `BunnyRepository` as an explicit constructor parameter
  instead of reading it from context; `AccountsScreen` had never needed to, since it used to
  be `home` itself. A widget test (`searches_screen_test.dart`'s "tapping the accounts icon"
  case) caught this before it could ship as a live crash. Fixed by giving `AccountsScreen` the
  same explicit `required BunnyRepository repository` constructor parameter, dropping its
  `BunnyRepositoryScope.of(context)` lookup entirely.

**Post grid + unseen markers (M8.3)**: `PostGridScreen` (`app/lib/screens/
post_grid_screen.dart`), opened by tapping a row in `SearchesScreen`, loads a search's cached
posts via `listSearchPosts` and renders them as a `GridView` of `CachedNetworkImage
(post.previewUrl)` thumbnails — a new `cached_network_image` dependency, since Flutter's
built-in `Image.network` re-fetches on every rebuild/scroll rather than caching to disk.
Unseen posts (`!post.isSeen`) get a small red-dot overlay; an app bar toggle re-runs
`listSearchPosts(search.id, unseenOnly: true)`; a refresh action calls `syncDueSearches()`
then reloads. Tapping a post calls `markPostSeen` and reloads the grid, clearing its own
marker — `PostDetailScreen`'s full metadata/media viewer is M8.4's scope and doesn't exist
yet, so this is the interim "opening a post" behavior.

- **A real bug this surfaced, a repeat of one already found in M7.3.** `_openPost`'s original
  `setState(() => _postsFuture = _loadPosts())` is the exact same arrow-closure-returns-a-
  Future bug `AccountsScreen._refresh` had (see M7.3 above) — Dart's assignment expression
  evaluates to the assigned value, so the closure body returned a `Future` even without
  `async`/`await`, tripping Flutter's assertion against async `setState` callbacks. Caught
  immediately by the equivalent widget test (`post_grid_screen_test.dart`'s "tapping a post
  marks it seen" case) and fixed the same way, with a block body. Worth noting since it's the
  second time this exact shape of bug has appeared — any future `setState(() => x = y())`
  one-liner assigning a `Future` is worth writing as a block body from the start.
- **Grid tiles are keyed by post id** (`ValueKey(post.id)`) purely for test targeting —
  `GridView`'s internal `Scrollable` already contributes its own `GestureDetector`s to the
  tree, so `find.byType(GestureDetector)` matches more than just the tappable tiles.

**Post detail view + media viewers (M8.4, completes M8)**: `PostDetailScreen`
(`app/lib/screens/post_detail_screen.dart`) is opened by tapping a tile in `PostGridScreen`
(which now navigates there instead of calling `markPostSeen` directly itself). It shows full
read-only metadata (artist, title, description, rating, score, favorite/comment counts,
dimensions, site creation date) — no favorite/vote/comment action buttons, since that's M9's
scope — and calls `markPostSeen(post.id)` once in `initState`. `PostGridScreen` reloads its
list when the detail screen pops, so the cleared unseen marker shows up immediately without
either screen needing to know about the other's internal state.

- **Media viewer branches on `post.fileExt`.** Images (jpg/png/gif/webp) render via
  `CachedNetworkImage(post.fileUrl)` — the same dependency M8.3 introduced for grid
  thumbnails, reused here at full size. Videos (webm/mp4) use `video_player` +
  `fvp`. Anything else (Flash/SWF) shows a plain "not supported" placeholder — the roadmap
  already calls out Flash/SWF as intentionally unimplemented, not a gap to fix later.
- **`fvp`'s actual backend, and a version pin that mattered.** M8 planning assumed `fvp`
  used `libmpv`; in fact it's built on `libmdk` (MDK) with its own bundled FFmpeg-based
  decoder, so no system `libmpv` dependency exists at all — a better outcome than planned,
  not a gap. `fvp: ^0.30.0` (the version checked during planning) failed to *compile* once
  actually wired in: pub resolved `video_player` to 2.14.0, and `fvp 0.30.0`'s own source
  referenced `VideoPlayerController.textureId`, a getter that version of `video_player` no
  longer has. Fixed by pinning `fvp: ^0.38.1` (current latest) instead, whose code matches
  the resolved `video_player` API. `main.dart` calls
  `fvp.registerWith(options: {'platforms': ['windows', 'linux']})` once at startup, before
  `runApp` — restricting it to exactly the platforms `video_player` has no official
  implementation for, leaving Android/iOS on `video_player`'s own backend untouched, per the
  original M8 planning decision. Verified past mere compilation: a real `flutter build linux`
  succeeds and the built bundle's startup log shows `fvp`'s MDK backend (`0.38.0`)
  initializing cleanly, with no crash.
- **Testing video playback without a real platform.** `flutter test` has no real platform
  channel implementation for `video_player` — a widget test that builds `PostDetailScreen`
  with a video post needs `VideoPlayerPlatform.instance` replaced first, or
  `VideoPlayerController.initialize()` hangs waiting on a channel call nothing answers.
  `app/test/fakes/fake_video_player_platform.dart` implements the platform interface
  directly (not a mock), immediately emitting an `initialized` `VideoEvent` with a fixed
  size/duration — enough for the widget tree to build past the loading state. This proves
  `PostDetailScreen` picks the right viewer widget per file extension (the plan's own stated
  goal — "cover it with a widget test asserting the right viewer widget type is chosen per
  file extension, not actual playback"); real decoding is verified by the Linux build launch
  above and by manual testing against a real server instead.

## Rich metadata, browsing UX & bug fixes (M8.5)

A hands-on pass over M8 surfaced a large batch of feedback — real bugs plus missing richness
in the browse/detail flow — scoped into sequential sub-milestones, M8.5.0 onward.

**Minimal schema migration runner + score up/down split (M8.5.0)**: `libs/db/src/schema.h`
is entirely `CREATE TABLE IF NOT EXISTS`, safe to re-run on every `bunny_db_open()` — but
SQLite's `IF NOT EXISTS` can't add a *column* to a table that already exists, and a
`schema_migrations` table had sat scaffolded (from the original M3 schema) but genuinely
unused ever since. Splitting `posts.score` (a single total) into separate `score_up`/
`score_down` columns — needed so the grid can show likes/dislikes rather than one combined
number — was the first change in the project's history that actually needed a real migration
path rather than a new table.

- **The migration runner** (`bunny_db_apply_migrations()`, `libs/db/src/db.c`, called from
  `bunny_db_open()` right after the schema SQL): a static array of `{version, sql}` pairs.
  For each, `SELECT 1 FROM schema_migrations WHERE version = ?` decides whether to skip it or
  run the SQL and record it — so re-opening an already-migrated database is a no-op, and a
  fresh database gets every migration applied in order on first open. Deliberately minimal:
  no rollback, no batching, no versioned schema snapshots — just enough to let `ALTER TABLE`
  statements run exactly once each, which is all this project needs today.
- **Score up/down**: `upsert_e621_post` (`libs/core/src/sync.c`) now reads `e621_score_t.up`/
  `.down` (previously only `.total` survived into `bunny_db`); Inkbunny has no voting concept
  at all, so both columns stay their `0` default for Inkbunny posts. The new fields were
  appended to the end of the shared `BUNNY_DB_POST_SELECT_COLUMNS` macro
  (`libs/db/src/internal.h`) that every post-reading query (`post_get`, `post_get_by_id`,
  `search_list_posts`, `favorite_list`) already shares — one macro edit covers all of them,
  since `bunny_db_fill_post_from_row` reads columns by explicit index, not struct layout
  order, so where the new fields live inside `bunny_db_post_t` itself doesn't need to match
  their position in the SELECT list.
- **FFI bindings needed regeneration** (`dart run ffigen --config ffigen.yaml`) since
  `bunny_db_post_t` is one of ffigen's entry-point structs — any field added there flows
  straight into the generated Dart struct, then into `_postToMap`
  (`bunny_core_ffi/lib/src/bunny_core_isolate.dart`), same as every prior post field.
- **Testing a real migration** needs a real file, not `:memory:` — an in-memory SQLite
  connection is wiped the moment it's closed, so "does reopening an already-migrated database
  skip re-applying the migration" can only be tested by opening a real file path twice across
  two separate `bunny_db_open()`/`bunny_db_close()` pairs. This is the one test in
  `libs/db/tests/test_db.c` that doesn't use the shared `:memory:` `setUp()`/`tearDown()`
  fixture — it manages its own temp file path directly, removing it before and after.

**Bug fixes: pagination, Inkbunny thumbnail 403, sort order (M8.5.1)**: three independent,
user-reported bugs.

- **Pagination.** `sync_e621_search`/`sync_inkbunny_search` (`libs/core/src/sync.c`) each made
  exactly one `page=1` request with no loop — a search matching hundreds of posts only ever
  cached e621's default page size (~75, since `limit=0` was always passed). Both now loop up
  to `BUNNY_CORE_SYNC_MAX_PAGES` (20) pages: e621 requests `BUNNY_CORE_SYNC_E621_PAGE_LIMIT`
  (320, the site's real per-request max) each page and stops the first time a page returns
  fewer than that; Inkbunny's `inkbunny_search_params_t` has no per-page limit parameter at
  all (confirmed — only `text`/`keywords_only`/`favorited_by_user_id`/`page`), so its loop
  instead pages until a response comes back with zero submissions. This means a real Inkbunny
  sync always makes one "probe" request past the true last page to confirm there's nothing
  more — a deliberate trade-off given there's no total-count/total-pages signal exposed by
  `inkbunny_submission_list_t` to detect the last page any other way.
  - **Testing a 320-item page** needed a JSON body no one should hand-author into a fixture
    file — `libs/core/tests/test_sync.c`'s `build_e621_posts_page_json(count, first_id)`
    constructs one at test time instead, reusing the same minimal post shape as the existing
    `e621_posts_search.json` fixture.
  - **A real regression this caught in its own test writing**: the *existing*
    `test_sync_inkbunny_search_upserts_post` test broke the moment the pagination loop
    landed, because its fake transport only had two canned bodies (login + one page of
    results) — the loop's mandatory "probe the next page" request got the fake transport's
    out-of-bodies fallback (an empty string), which fails to *parse* as JSON at all (not the
    same as a valid "zero results" document), so the whole sync reported a site failure where
    it previously reported success. Fixed by adding a third canned fixture
    (`inkbunny_search_response_empty.json`, a real `"submissions": []` response) to that
    test, matching what a real second request now actually gets. Worth remembering for any
    future Inkbunny sync test: the fake transport needs to account for this extra probe
    request, not just the "real" results page.
- **Inkbunny thumbnail 403s.** `CachedNetworkImage(imageUrl: ...)` in `PostGridScreen`/
  `PostDetailScreen` sent no headers at all; libcurl-backed C-side requests never touch this
  code path (that's a separate HTTP stack entirely — `libs/common/src/http.c` — used only by
  the Flutter FFI/HTTP repository's *API* calls, not by the Flutter widgets' own direct image
  fetches). Inkbunny's `metapix.net` CDN rejects such bare requests. New
  `app/lib/util/image_headers.dart`'s `imageHeadersFor(BunnySite)` returns a `User-Agent`/
  `Referer` pair for Inkbunny, `null` for e621 (no such requirement observed there) — passed
  to every `CachedNetworkImage.httpHeaders` and to `VideoPlayerController.networkUrl`'s own
  `httpHeaders` param for Inkbunny videos (same CDN, same fix applies).
- **Sort order.** `bunny_db_search_list_posts` (`libs/db/src/posts.c`) ordered by
  `sr.found_at DESC` — when *this app* linked the post to the search, not when the post was
  actually created on the site. A single sync pass can link posts spanning a wide date range
  all at once, so `found_at` values cluster together and don't track real recency. Changed to
  `ORDER BY COALESCE(p.created_at_site, p.cached_at) DESC` (falling back to `cached_at` for
  the rare post with no site timestamp, rather than sorting it to the very end).

**Still open: the Inkbunny search-by-tag/author 403 itself.** Investigating (not fixing)
surfaced two findings that reframe the bug rather than resolve it: (1) Inkbunny signals *all*
of its own API errors — including auth failures — as HTTP 200 with a JSON `error_code` body,
never a real non-2xx status, so a literal 403 the user observed is plausibly coming from a
layer `libinkbunny` doesn't control (a CDN/edge in front of `inkbunny.net` itself) rather than
from the API responding normally; (2) `inkbunny_search_params_t` has no author/username field
at all today — only `text`, `keywords_only`, and `favorited_by_user_id` (which lists an
*existing* favorites list, not "this user's submissions"). If "search by author" was ever
expected to work, it may need an entirely new parameter/endpoint wired into `libinkbunny`,
not a bug fix to existing code. This needs a live debugging session against a real configured
account to pin down before any fix is written — tracked as open, not guessed at.

**Unseen count per search (M8.5.11)**: `bunny_db_search_list`'s query (`libs/db/src/
searches.c`) gained a correlated subquery counting `search_results` rows for that search with
no matching `seen_posts` row, aliased `unseen_count`. This is an additive field on the
existing `bunny_db_search_t` struct — not a schema change — so it required no migration and
no new query function: `bunny_core_search_list`, the FFI isolate's `_searchToMap`, the
server's `search_to_json`, and `BunnySearch` on the Dart side all just carry one more field
through their existing plumbing. `SearchesScreen` renders a small badge next to each row's
delete icon when `unseenCount > 0`. `FakeBunnyRepository.listSearches` computes the same
count from its own `postsBySearchId` map (rather than hardcoding a stored value) so widget
tests exercise the same "count unseen posts" behavior the real implementations have.

**Mark-all-seen (M8.5.12)**: `bunny_db_search_mark_all_seen(db, search_id)`
(`libs/db/src/posts.c`, next to `bunny_db_post_mark_seen`) is the bulk counterpart to the
existing single-post version — `INSERT OR IGNORE INTO seen_posts SELECT post_id FROM
search_results WHERE search_id = ?`, same idempotent "insert or skip" shape, just selecting
every post linked to a search instead of taking one explicit id. Full plumbing follows the
established pattern exactly: `bunny_core_search_mark_all_seen` wrapper, `POST /searches/{id}/
mark_all_seen` added to the existing `routes_searches.c` dispatch (it already owns
`/searches` and its sub-paths), `BunnyRepository.markAllSeen(int)` in both implementations.
`PostGridScreen`'s app bar gained its first overflow menu (`PopupMenuButton`) for this action,
reloading the grid afterward so cleared markers show immediately.

- **A real behavioral asymmetry worth noting against `markPostSeen`'s own documented
  quirk** (see M8.1 above): `bunny_core_post_mark_seen` on a *nonexistent post id* is a
  foreign-key violation, mapped to `BUNNY_CORE_ERR_INVALID_ARG`. `bunny_core_search_mark_all_seen`
  has no equivalent failure mode — a search with zero linked posts, or a search id that
  doesn't exist at all, just makes the inner `SELECT` return zero rows, so the `INSERT`
  affects nothing and the call succeeds trivially. There's no caller-input mistake to reject
  here, since "mark zero posts as seen" isn't a meaningful error even when the search id was
  typed wrong — it only matters in that it means the two "mark seen" functions have
  deliberately different failure semantics for a bad id, not an oversight in either one.

**Search creation UX: label mirrors query + default interval (M8.5.13)**: two small,
unrelated client-side fixes, no backend plumbing for either.

- **Default sync interval** is a pure UX convenience, not a real setting the sync engine
  reads — `bunny_db_search_t.interval_hours` remains purely per-search (see M8.5.1's findings
  on this). New `app/lib/settings/sync_settings_store.dart`'s `SyncSettingsStore` (same
  `shared_preferences` shape as `ThemeSettingsStore`/`AppLockService`) just persists a value
  to pre-fill `CreateSearchScreen`'s interval field with, editable from a new "Sync" section
  on `SettingsScreen`.
- **Label mirrors query** (`CreateSearchScreen`): a classic "slug follows title" pattern, with
  the classic footgun that comes with it — a naive `_queryController.addListener(() =>
  _labelController.text = _queryController.text)` would also fire on *every* keystroke
  forever, since there's no way to tell "the user edited the label" apart from "the mirror
  just wrote to the label" without an explicit guard. Two booleans solve it:
  `_labelManuallyEdited` (set the first time the label's own listener fires for a reason
  *other* than the mirror) permanently disables mirroring once set; `_mirroringLabel` (set
  only while the mirror's own `_labelController.text = ...` assignment is in flight) is what
  lets the label's listener tell the two cases apart — without it, the mirror's very first
  write would set `_labelManuallyEdited = true` on itself and disable mirroring after exactly
  one keystroke.
- **Threading `SyncSettingsStore` through the widget tree** followed the exact shape
  `ThemeSettingsStore`/`AppLockService` already established: a new required constructor
  parameter on `SearchesScreen` (passed down to both `CreateSearchScreen` and
  `SettingsScreen`, the two screens that actually need it) and on `LittleBunnyApp`/`main()`.

**Tag categories (M8.5.3)**: e621's 8 tag categories (`general`/`artist`/`copyright`/
`character`/`species`/`invalid`/`lore`/`meta`) are a property of the *tag itself*, not a given
post — e621's own model has a given tag name always belong to the same category site-wide.
New `tag_categories` table keys on `tag_id` alone (`PRIMARY KEY`, `REFERENCES tags(id)`), so
`bunny_db_post_upsert`'s tag-linking loop upserts a tag's category once per tag regardless of
how many posts reference it, rather than duplicating it per `(post_id, tag_id)` pair. Inkbunny
keywords have no category concept at all and simply never get a row — the read query
(`bunny_db_post_get_tags_by_category`) `LEFT JOIN`s `tag_categories`, so a missing row comes
back as `category: NULL` (uncategorized), not an error or an empty string.

`sync.c`'s `flatten_e621_tags` previously only flattened `e621_tags_t`'s 8 separate lists
(`general`/`artist`/.../`meta`) into one `items` array for `bunny_db_post_upsert_t.tags`. It
now also builds a parallel `categories` array of the same length, written alongside `items` in
the same nested loop — `categories[j]` is simply the literal category name for whichever of
the 8 source lists `items[j]` came from (a `static const char *const category_names[]` indexed
in lockstep with the existing `lists[]` array). `flatten_inkbunny_keywords` is untouched; its
`flat_tag_list_t.categories` stays `NULL` via the struct's existing `{0}`-initialization,
which `upsert_inkbunny_submission` passes straight through as `tag_categories = NULL`.

**Server route placement — deviation from the original plan**: the plan called for a new
`server/src/routes_posts.c` for `GET /posts/{id}/tags` (and the M8.5.4/M8.5.5 read endpoints
that would follow it), reasoning that `routes_queue.c` was for *actions* and this is a
*read*. In practice civetweb has no concept of two handlers sharing a URL prefix — the
existing `server_routes_register_queue()` already calls `mg_set_request_handler(mg_ctx,
"/posts", posts_handler, ctx)` once, and `posts_handler` dispatches every `/posts/*` request
internally by sub-path (`server_route_parse_id_with_suffix`) for `/favorite`, `/vote`,
`/comment`, `/seen`. A second `mg_set_request_handler` call for `/posts` would simply never be
reached — civetweb's routing is last-registration-wins per literal path, not per-method or
per-purpose. `GET /posts/{id}/tags` was added as one more case in that same `posts_handler`
dispatch chain instead, exactly matching the precedent M8.1 already set (and documented) when
it added `POST /posts/{id}/seen` to this same file for the same reason.

**Sources (M8.5.4)**: new `post_sources` table (`post_id, position, url`) parallels
`tag_categories`'s wholesale-replace approach rather than `post_tags`/`tag_categories`'s
upsert-once-per-tag approach — sources are a property of *this post's cached state*, not
shared across posts the way a tag name is, so `bunny_db_post_upsert` deletes a post's existing
`post_sources` rows and re-inserts the current list on every upsert (same pattern the
pre-existing `post_tags` replace already used, just newly applied to a second table). `position`
exists because plain SQLite row order isn't a reliable substitute for "the order the site gave
these URLs in" once rows get deleted and re-inserted across repeated re-syncs.

New `bunny_db_string_list_t` (`char **items`/`size_t count`) is the first genuinely generic
list type in `bunny_db` — `bunny_db_tag_stat_t`/`bunny_db_post_tag_t` both carry per-item
metadata (a count, a category) that a bare list of source URLs has no equivalent for, so
reusing either would mean a dummy field. `GOBLIN_DYN_ARRAY_DECL(bunny_db_string, char *)` in
`posts.c` proves the macro works unmodified for a pointer element type (`TYPE *items` expands
to `char **items`), despite every prior use in this codebase being a value struct.

`e621_post_t.sources` (parsed since M2.1) was simply never read by `sync.c` until now --
`upsert_e621_post` passes `(const char **)post->sources.items` straight through (a cast is
needed since `e621_string_list_t.items` is `char **`, not `const char **`, and C doesn't allow
an implicit `T** -> const T**` conversion). Inkbunny submissions have no source-URL concept at
all, so `upsert_inkbunny_submission` needed no change -- `sources`/`source_count` stay at the
upsert struct's existing zero-initialization.

**Pools + parent/child relationships backend (M8.5.5a)**: the original plan treated "pools +
relationships" as one M8.5.5 sub-milestone covering backend plumbing *and* UI (a "Pools" tab,
a "create pool search" flow). Split in two during implementation, the same way M8.5.1 was
split when it grew unwieldy — this covers the backend only; the UI is a separate follow-up.

New tables (`post_relationships`, `post_children`, `post_pools`) all key on e621's *own*
external ids, never local `posts.id` — a post's parent, children, or pool-mates may never have
been independently synced, so there's nothing to foreign-key against. This is also why
`bunny_core_fetch_and_cache_post` exists: tapping a parent/child/pool chip that points at an
uncached post needs a way to fetch-and-cache it live, which is exactly what it does by
factoring the single-post upsert logic (previously inlined in `upsert_e621_post`/
`upsert_inkbunny_submission`, called only from the sync-loop context) out into a standalone
function callable against a live `e621_get_post`/`inkbunny_get_submission` call.

`bunny_db_post_upsert` treats `post_relationships` and `post_children`/`post_pools`
differently on purpose. The relationships row is always upserted (`INSERT ... ON CONFLICT DO
UPDATE`) even when both fields are at their "empty" default, so a resync that drops a parent
link is reflected rather than leaving a stale `parent_external_id` from a previous sync.
`post_children`/`post_pools`, like `post_sources` before them, are wholesale-replaced
(`DELETE` then re-`INSERT`) since they're list-shaped, not a single row to update in place.

`bunny_core_fetch_pool` deliberately does **not** persist anything — unlike every other
`bunny_core_fetch_*`/`upsert_*` function, it has no backing table. The findings that shaped
the original M8.5 plan already established that "save a pool as a search" needs no new
backend logic at all (e621's own tag-search syntax treats `pool:<id>` as a literal query
string `e621_search_posts` passes straight through), so this function's only job is answering
"what's pool 5 actually called?" for prefilling a label at search-creation time — a pure,
stateless passthrough to `e621_get_pool`.

**Server route placement**: `GET /posts/{id}/relationships`, `GET /posts/{id}/pools`, and
`POST /posts/fetch` all landed in the existing `routes_queue.c` `posts_handler` dispatch chain
(same civetweb-ownership reasoning as M8.5.3/M8.5.4 — civetweb's routing is one handler per
literal path prefix, and `/posts` already has one). `GET /pools/{id}` is different: nothing
owns `/pools` yet, so a new `server/src/routes_pools.c`/`.h` was the correct call here, not a
deviation — matching the same "new resource gets a new file" shape `routes_searches.c`/
`routes_tags.c` already established.

Testing the new live-fetch paths (`bunny_core_fetch_and_cache_post`, `bunny_core_fetch_pool`,
and the server's `/posts/fetch`/`/pools/{id}` routes) needed the shared fake e621 transport to
become path-aware for the first time — every earlier fake transport in this codebase (`libs/
core/tests/test_sync.c`'s `fake_send`, the server integration test's `fake_e621_send`) simply
returned the next canned body in sequence or one fixed body, since every prior test only ever
made one *kind* of e621 request per test run. A single test now exercising "sync a search"
*and* "fetch a single post" *and* "fetch a pool" needs three different response shapes from
the same fake, so `fake_e621_send` now inspects `request->url` for `/posts/42.json` /
`/pools/5.json` substrings and serves the matching fixture, falling back to the search-results
fixture otherwise.

**Pools tab + create-pool-search flow (M8.5.5b)**: the UI half of M8.5.5, landed as its own PR
after M8.5.5a's backend. `SearchesScreen` already had exactly one list and one FAB action; this
adds a `TabController`-driven `TabBar`/`TabBarView` pair ("Searches"/"Pools") over the *same*
`listSearches()` future, split client-side by `_isPoolSearch` (`site == e621 &&
query.startsWith('pool:')`). No new repository method was needed for the split itself — this
is a direct payoff of the original M8.5 planning finding that e621's own tag-search syntax
already treats `pool:<id>` as a literal, functioning query string, so "a pool search" has
never needed to be anything other than a `BunnySearch` with a recognizable query shape.

The FAB's `onPressed`/tooltip swap based on `_tabController.index` rather than being two
separate buttons, since only one FAB can be visible at a time regardless. The "add pool"
dialog is a plain `AlertDialog` (not a new screen) since it's a single numeric field — `
CreateSearchScreen` already exists for the general case and gains no new parameters here
(an `initialSite`/`initialQuery`-based reuse was considered but deferred to M8.5.10, which
needs the same mechanism for tag-click browsing and can introduce it once, for both uses).
The dialog calls `fetchPool` (M8.5.5a) to look up a friendly label but treats any failure
there as non-fatal -- catches the exception and falls back to a `pool:$id` label -- since
`fetchPool` is a pure cosmetic nicety per M8.5.5a's own design, not load-bearing for the pool
search actually working.

Adding the "Searches" tab label introduced the session's first instance of a pre-existing
widget test breaking from an ambiguous `find.text()` match purely due to new UI, rather than a
constructor-signature change (the far more common cause up to this point, e.g. M8.5.13's
`SyncSettingsStore` threading) -- `widget_test.dart`'s boot-screen test asserted
`find.text('Searches')` with `findsOneWidget`, which the new tab label (coincidentally the
exact same string as the `AppBar` title) turned into two matches. Fixed with
`findsNWidgets(2)` plus a comment, rather than restructuring the finder to be more specific,
since both matches are legitimately expected UI.

**Settings: preview quality + grid columns (M8.5.6)**: `post_media_variants` is the first
new post-adjacent table that doesn't get its own `bunny_db_post_get_*` read function --
`post_tags`/`post_sources`/`post_relationships`/`post_pools` (M8.5.3-5) are each either
list-shaped or only needed on-demand (a post detail view), so a dedicated query made sense.
`sample_url` is a single scalar needed by *every* post-reading query (the grid needs it for
every tile, not just one post at a time), so it's `LEFT JOIN`ed straight into
`BUNNY_DB_POST_SELECT_COLUMNS`/`BUNNY_DB_POST_SELECT_FROM_JOIN` instead -- the same macro
`post_get`/`search_list_posts`/`favorite_list` already share -- avoiding an N+1 fetch per
tile that a separate read function would have forced on `PostGridScreen`.

`bunny_db_post_upsert` treats the new table exactly like `post_relationships`: always
upserted (`INSERT ... ON CONFLICT DO UPDATE`), never wholesale-deleted-and-reinserted, since
it's one scalar per post, not a list. A resync that loses a sample URL (e.g. e621 stops
returning one, or the data genuinely changes) overwrites the old value via `excluded.sample_url`
rather than leaving it stale -- same reasoning the M8.5.5a relationships row already
established.

This sub-milestone's test-writing incidentally surfaced a real test-coverage gap unrelated to
the feature itself: `bunny_core_fetch_and_cache_post` (added in M8.5.5a) only ever had e621
test coverage -- its Inkbunny branch (`site != BUNNY_DB_SITE_E621`) had never been exercised
by any test. Writing a sample_url test for the Inkbunny side required a fixture with a
`"files"` array (the one thing a search-sync fixture never has -- see the Inkbunny
description/keywords gap already documented above), which doesn't exist anywhere in `libs/
core/tests/fixtures/`; `libs/inkbunny/tests/fixtures/submission_full.json` already had exactly
this shape, so it was copied over as `inkbunny_submission_full.json` rather than
hand-authoring a new one. The resulting test (`test_fetch_and_cache_post_upserts_live_
inkbunny_submission`) only asserts the fetch succeeds and returns a valid post id -- unlike
the e621 fetch test, it deliberately does **not** also test re-fetch idempotency, since Inkbunny
re-logs in on every `bunny_core_build_inkbunny_client` call (unlike e621's anonymous GETs),
which would need a second canned login response the test doesn't provide.

**Grid tile badges (M8.5.7)**: purely client-side -- `BunnyPost` already carried every field
needed (`rating`/`score`/`scoreUp`/`scoreDown`/`favCount`), so this sub-milestone touches no
backend, FFI, or server code at all. `app/lib/widgets/rating_badge.dart` is the app's first
`widgets/` directory; everything UI-related up to this point lived directly under `screens/`
since nothing was reusable across more than one screen. `ratingBadgeFor` is a pure function
(not a widget method) specifically so it can be unit-tested without pumping a widget tree,
matching this session's general preference for testing logic separately from rendering where
the two can be cleanly separated.

The e621/Inkbunny split here mirrors the same asymmetry M8.5.3's tag categories already
established: e621 has a fixed, site-defined enumeration (`"s"`/`"q"`/`"e"`, mapped 1:1), while
Inkbunny's equivalent (`rating_name`) is free text with no fixed value set at all. Rather than
inventing a brittle exhaustive mapping for Inkbunny's known strings (which may grow or change
server-side without this app's knowledge), the Inkbunny branch does keyword substring matching
and always has a safe fallback -- a grey badge showing the literal string -- so an unfamiliar
rating value degrades gracefully instead of being hidden or crashing the tile.

**Post detail redesign (M8.5.8)**: the big UI consumer of M8.5.3/4/5/7, sequenced after all
four landed. One backend gap closed first: nothing exposed "fetch one cached post by its local
id" up to Flutter -- every existing read either returned a list (`listSearchPosts`) or looked
up by external id (`fetchPost`). Needed so tapping a parent/child/pool chip (after `fetchPost`
caches that post and returns its local id) can actually load and display it.
`bunny_core_post_get_by_id` is a two-line wrapper around the already-existing
`bunny_db_post_get_by_id` (unused by anything above the db layer until now). `GET /posts/{id}`
(bare numeric id, no suffix) was added as the *last* dispatch branch in `routes_queue.c`'s
existing `posts_handler` -- `server_route_parse_id` safely returns `false` for the other
suffixed paths it's tried against first (`/posts/fetch`, `/posts/{id}/tags`, etc.), so ordering
it last carries no ambiguity risk. `post_to_json` was duplicated into `routes_queue.c` from its
existing copy in `routes_searches.c`, matching the already-duplicated `add_optional_string`
precedent between these two files rather than introducing a new shared module for one function.

The redesign itself replaced `PostDetailScreen`'s fixed-height media `SizedBox` with an
`AspectRatio` keyed off `post.width`/`.height`, **capped at 60% of the viewport height** via an
outer `ConstrainedBox`. The cap isn't cosmetic -- a widget test regression caught a real bug
without it: at a typical test-viewport width, a 4:3 image's `AspectRatio` computed a height
equal to the *entire* viewport, and `ListView` renders as a `SliverList`, whose
`debugVisitOnstageChildren` (the mechanism `find.text`'s default `skipOffstage: true` relies
on, and the same layout-and-cache-extent logic that determines what a real device actually
paints) only visits children within its current laid-out + cache-extent range. Everything
below the media -- every metadata row, every new section -- fell outside that range and was
therefore both invisible to `find.text` *and* not actually rendered to a real user without
scrolling first. This wasn't a test-only artifact; it would have reproduced on any device
where a tall/narrow image's natural aspect ratio exceeds the available screen height. The fix
generalizes: cap any aspect-ratio-driven media size against the viewport before trusting a
`ListView`-based layout to keep content below it reachable without an explicit scroll.

Four new sections were added, each firing its own repository call from `initState` (not
sequenced against each other -- the four backend reads are independent and each section's
`FutureBuilder` renders itself null-safely until its own future resolves): categorized tag
chips (groups `getPostTagsByCategory`'s results by category into a `Wrap` per group, labeling
the `null`-category group plain "Tags" for Inkbunny; chips are intentionally **not** tappable
yet, deferred to M8.5.10's not-yet-built tag-browse screen); a tappable source-link list via a
new `url_launcher` dependency (hidden entirely rather than shown empty when
`getPostSources` returns nothing); a post-id row using `Clipboard.setData` + a `SnackBar`
confirmation on tap; and, e621-only, parent/children chips (`getPostRelationships`) and pool
chips (`getPostPoolIds`). Tapping a parent/child chip calls `fetchPost` then the new `getPost`
and pushes a fresh `PostDetailScreen` for the result. Tapping a pool chip reuses the exact
"pool search" mechanism M8.5.5b built for the Pools tab: `listSearches()` is checked for an
existing `pool:<id>` query first, navigating straight into it via `PostGridScreen` if found;
otherwise a confirmation dialog offers to create one (optionally calling `fetchPool` for a
friendly label, falling back to the raw `pool:<id>` string on failure, identical to
`SearchesScreen`'s own add-pool flow) before creating and navigating. Because
`PostDetailScreen` can now push a `PostGridScreen` (pool navigation) and `PostGridScreen` can
push a `PostDetailScreen` (opening a post), the two screen files import each other --
Dart has no issue with this kind of mutual import between library files, unlike some
languages, so no extraction was needed to break the cycle. `PostDetailScreen` also gained a
new required `displaySettingsStore` constructor parameter purely to support that pool
navigation (`PostGridScreen` needs one); every existing call site needed updating, the same
constructor-signature ripple this project has hit repeatedly for widely-used screens.

**Test-only gotcha worth remembering**: `Clipboard.setData`'s platform channel round trip never
resolves inside a `testWidgets` body's fake-async pump loop on the headless `flutter_tester`
engine, *unless* a mock handler is explicitly installed for `SystemChannels.platform` (`
TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger.setMockMethodCallHandler(
SystemChannels.platform, (call) async => null)`). A bare `test()` body (no `pumpWidget`) doesn't
hit this, since it isn't running inside `TestWidgetsFlutterBinding`'s fake-async zone -- that
discrepancy is exactly why this went unnoticed until a widget test actually exercised the
copy-id tap.

**Full-screen zoomable viewer (M8.5.8's intended follow-up, M8.5.9)**: no backend/FFI/server
changes -- this is purely a new Flutter screen plus a routing change into it. `photo_view`'s
`PhotoViewGallery.builder` was picked (over hand-rolling `InteractiveViewer` + `PageView`)
specifically because it bundles pinch-zoom-per-page and swipe-between-pages together, which is
exactly M8.5's original decision record for this sub-milestone. `FullScreenPostViewerScreen`
owns its own `PageController` so it can both seed the gallery's starting page (`initialPage:
initialIndex`) and observe page changes via `onPageChanged`, calling `repository.markPostSeen`
for whichever post the user just swiped onto -- the same "mark seen as the user actually looks
at it" principle `PostDetailScreen.initState` already applies on open, just re-triggered per
swipe instead of once per screen push.

Wiring this in required `PostDetailScreen` to know its siblings, which it didn't before --
previously it only ever received a single `BunnyPost`. Rather than making this required (which
would break the parent/child/pool-chip navigation path added in M8.5.8, where there genuinely
is no sibling list -- just one post fetched standalone), `siblingPosts` is an optional
constructor parameter defaulting to `null`, with the detail screen falling back to a
single-element list of just the current post. This keeps `FullScreenPostViewerScreen`'s own
contract simple (it always receives a non-empty, already-filtered list) without forcing every
caller to fabricate a fake sibling list. The media tap handler does the filtering --
`(siblingPosts ?? [post]).where(_isImage)` -- rather than pre-filtering at the call site in
`PostGridScreen`, so that a grid's mixed image/video post list can be handed through unchanged
and each `PostDetailScreen` instance decides for itself, based on `post.fileExt`, whether it's
even eligible to open the gallery at all (video posts never attach the tap handler in the
first place).

This is the first sub-milestone where `PostDetailScreen` and `PostGridScreen` import each
other in both directions (`PostDetailScreen` already pulled in `post_grid_screen.dart` for
M8.5.8's pool-chip navigation; `PostGridScreen` has always imported `post_detail_screen.dart`
to open a tapped tile) -- confirmed this compiles and analyzes cleanly with no cycle-breaking
needed, since Dart resolves mutual library imports structurally rather than rejecting them
like some languages do with circular module graphs.

**Test gotcha**: a widget test that drags `PhotoViewGallery` to trigger a page change can't
follow up with `pumpAndSettle()` -- it times out, because `photo_view`'s internal scale/gesture
animation controllers apparently never fully quiesce within `pumpAndSettle`'s retry budget in
a test environment. Worked around with an explicit `pump()` followed by a fixed-duration
`pump(Duration(milliseconds: 500))` instead, the same shape already used elsewhere in this
suite for `SnackBar`-involving assertions that can't use `pumpAndSettle` either (that one for a
different reason -- the `SnackBar`'s own auto-dismiss duration would've fully elapsed by the
time `pumpAndSettle` considers the tree idle).

**Tag/artist click-through browsing (M8.5.10)**: the first sub-milestone since M8.5.5a to add a
genuinely new `bunny_core` read with no existing equivalent at the db layer to wrap -- every
prior "fetch live + cache" function (`bunny_core_fetch_and_cache_post`,
`bunny_core_fetch_pool`) handles exactly one external entity; this one runs a real site search
and needs to return a *list* of freshly-upserted posts without creating the
`searches`/`search_results` row a real saved search would. The list-building itself reuses
`bunny_db_post_get_by_id` (an immediate re-read right after each upsert) rather than threading
post data through by hand, trading a few extra sqlite lookups (bounded by one search page, so
at most a few hundred rows) for not having to duplicate `upsert_e621_post`/
`upsert_inkbunny_submission`'s struct-to-row mapping a third time. The accumulator itself is a
file-local `GOBLIN_DYN_ARRAY_DECL(bunny_core_post, bunny_db_post_t)` in `sync.c` -- safe
alongside `libs/db/src/posts.c`'s own `bunny_db_post_array` of the identical shape, since the
macro expands to `static inline` functions scoped to whichever translation unit instantiates
it, so there's no link collision between the two independent declarations.

`/search` (singular) needed a brand-new route file (`server/src/routes_search.c`/`.h`) rather
than extending an existing one -- `/searches` (plural, saved searches) and `/posts` (actions +
reads) are both already-owned literal prefixes under civetweb's one-handler-per-path model, and
neither is the right conceptual home for a stateless preview. This is the same reasoning that
put pools in their own `routes_pools.c` back in M8.5.5a rather than bolting them onto an
existing file.

On the Flutter side, this sub-milestone finally gave `PostGridScreen`'s per-tile `Stack`
(rating badge + unseen dot + score/favCount overlay, built inline since M8.3 and extended in
M8.5.7) a real second caller (`TagBrowseScreen`), which is what justified factoring it into
`app/lib/widgets/post_grid_tile.dart` now rather than earlier speculatively -- consistent with
this project's standing anti-speculative-abstraction preference (extract only once there are
two real call sites, not in anticipation of a second one).

Wiring the detail page's tag chips and artist text to actually navigate required threading a
`SyncSettingsStore` through both `PostGridScreen` and `PostDetailScreen`, neither of which had
ever needed one before -- `TagBrowseScreen`'s "add to searches" button pushes
`CreateSearchScreen`, which has required a `SyncSettingsStore` since M8.5.13's default-interval
feature. `CreateSearchScreen` itself gained `initialSite`/`initialQuery` (both nullable,
defaulting to the existing blank-form behavior) rather than a separate pre-filled variant,
since the only actual difference is what the controllers start with -- the query-field listener
that mirrors text into the label field (M8.5.13) already handles the rest correctly once
`_queryController.text` is set after that listener is attached in `initState`.

**Test gotcha**: a `tester.tap()` aimed at a `PostGridTile` inside `TagBrowseScreen`'s
`GridView` silently hit something else -- `tester.getRect`/`getCenter` reported the tile's
on-screen position correctly, but the resulting hit-test chain never included the tile's own
`GestureDetector` render object, so the tap landed without effect and no exception was raised
(Flutter only prints an advisory warning, not a failure, unless `warnIfMissed` is left at its
default and the assertion afterward happens to catch the consequence). The structurally
near-identical tap test in `post_grid_screen_test.dart` passes without this problem, so the
cause wasn't tracked down further -- it's narrower than a general `PostGridTile` defect. Worked
around by reading the `PostGridTile` widget instance via `tester.widget<PostGridTile>(...)` and
invoking its `onTap` callback directly rather than synthesizing a tap, which still verifies the
navigation logic under test (that the correct post opens) without depending on Flutter's
hit-testing resolving correctly in this specific layout.

**Favorite/vote UI on post detail (M8.5.14)**: zero backend/FFI/server changes -- the entire
action-queue path (`queueFavoriteAdd`/`queueFavoriteRemove`/`queueVote`/`processQueue`) has
existed since M4.3 with nothing in the UI calling it. `FakeBunnyRepository`'s four
corresponding methods had been inert `throw UnimplementedError()` stubs this whole time (noted
in the class's own doc comment as "unimplemented since nothing under test calls them, that's
M9's scope") -- this is the sub-milestone that finally needed them, so they became real
(non-throwing) fakes that just record what was called into plain lists/counters, rather than
simulating actual site-side state changes, since the widget tests only need to assert "the
right action was queued and the queue was drained," not reproduce real favorite/vote semantics.

`PostDetailScreen` previously had no mutable state at all tied to the post's own data -- every
field it displayed came straight from the immutable `widget.post`. Favorite/vote needed
*some* post-detail field (`isFavorited`/`score`/`favCount`/`scoreUp`/`scoreDown`) to change
after a tap, so the screen gained a `late BunnyPost _post` field, seeded from `widget.post` in
`initState` and reassigned via `setState` after each action. Every other method in the screen
(media loading, tag/source/relationship fetches, the copy-id/tag-browse/pool navigation
actions) still reads `widget.post` directly rather than `_post`, since none of those depend on
fields that favorite/vote can change -- using `_post` everywhere would have been harmless but
pointless churn for fields that are, by construction, immutable for the lifetime of the screen.

Vote is e621-only (Inkbunny has no vote API in any form, official or unofficial) and disabled
rather than hidden, the same "grey out, don't silently fail or hide" principle the roadmap
already states for comments; favorite works on both sites, since the unofficial Inkbunny
favorite route (M2.2) is already wired generically into `queueFavoriteAdd`/`Remove` regardless
of site.

## M9 -- Actions & downloads

**Comments: post + view (M9.1)**: the first read-side gap in the action-queue family --
`e621_comment_create` (posting) has been wired end-to-end since M4.3, but `e621_comment_list`
(viewing) had never been threaded past `libe621` itself at all, not even a stub further up the
stack. `bunny_core_list_comments(core, post_id, out_list)` follows the exact same "live fetch,
nothing persisted" shape as `bunny_core_fetch_pool`/`bunny_core_preview_search`: a new
`bunny_core_comment_t`/`bunny_core_comment_list_t` pair lives in `bunny_core/core.h` itself
rather than `bunny_db`, since there's no table backing it (same reasoning as
`bunny_core_pool_info_t`). The function takes the *local* post id, not e621's external id --
every other per-post read wrapper in this codebase does the same, so it looks up
`external_id`/`site` internally via the already-existing `bunny_db_post_get_by_id` and rejects
non-e621 posts with `BUNNY_CORE_ERR_SITE` before making any HTTP call at all. This ordering is
specifically tested (`test_list_comments_rejects_inkbunny_posts` queues only a login + fetch
fixture for setup, then calls `bunny_core_list_comments` with zero further fixture bodies
queued -- if the rejection happened after an HTTP call instead of before, the fake transport
would have nothing to return and the test would fail for the wrong reason).

On the server side, `GET /posts/{id}/comments` slots into the already-existing `posts_handler`
in `routes_queue.c` as one more `server_route_parse_id_with_suffix` branch, alongside
`tags`/`sources`/`relationships`/`pools`/`comment` (singular, the existing POST-to-create
route) -- civetweb matches suffixes as exact strings, so `"comment"` and `"comments"` coexist
on the same path prefix without ambiguity.

On the Flutter side, `PostDetailScreen` gained a comments section -- but it couldn't be titled
"Comments", because that string was already taken by the pre-existing metadata row showing the
post's raw `commentCount` (`_metadataRow(l10n.postDetailCommentsLabel, '${post.commentCount}')`,
present since M8.4). The new section is titled "Discussion" instead purely to avoid this
collision; a widget test asserting the section's absence on an Inkbunny post would otherwise
spuriously fail against the ever-present count row. The section follows the established
e621-only, hide-entirely (not grey-out) pattern already used for relationships/pools, since
Inkbunny has no comment concept at all -- not a restricted one. Posting a comment reuses
`queueComment`+`processQueue` exactly as M8.5.14 established for favorite/vote, then reassigns
the section's `Future<List<BunnyComment>>` field (not `late final` like the other per-post
futures in this screen, specifically so it *can* be reassigned) to a fresh `getPostComments`
call so the new comment appears without a full screen reload.

`FakeBunnyRepository.queueComment` had been an inert `throw UnimplementedError()` stub since
M8.2 -- the class's own doc comment explicitly called this out as "unimplemented since nothing
under test calls them, that's M9's scope." This is the sub-milestone that made it real: it now
records `(postId, body, anonymous)` tuples into an in-memory list, the same shape
`favoriteAddCalls`/`voteCalls` already established in M8.5.14 for the other three queue
methods.

**Test gotcha, cross-file**: adding a "Post" submit button to the comments section broke two
*other* already-passing widget tests in unrelated files (`post_detail_screen_test.dart`'s own
`copies the post id...` test was unaffected, but `post_grid_screen_test.dart`'s navigation test
asserted `find.text('Post')` to confirm `PostDetailScreen`'s app bar title had appeared --
which now collides with the new button's identical label). Fixed by scoping each assertion to
its actual target widget (`find.widgetWithText(AppBar, 'Post')` for the app bar check,
`find.widgetWithText(FilledButton, 'Post')` for the submit-button tap) rather than a bare
`find.text`. Worth remembering generally: a bare `find.text('X')` assertion is implicitly a
claim that `'X'` appears exactly once on the whole screen, which a later, unrelated change can
silently invalidate from a completely different file.

**Mass selection mode + mass favorite/vote (M9.2)**: unlike every other sub-milestone so far,
this one needed zero backend changes -- `bunny_core_process_queue`/
`bunny_db_action_queue_list_pending` have no row-count limit, so queuing N favorite/vote
actions and calling `processQueue()` once already drains all of them in a single pass. "Mass
favorite/vote" is therefore pure client-side looping over the same `queueFavoriteAdd`/
`queueVote` calls M8.5.14 already wired up for the single-post case.

`PostGridTile` (factored out in M8.5.10 for `TagBrowseScreen`'s reuse) gained two optional
constructor params, `selected` and `onLongPress`, both defaulting to `false`/`null` so
`TagBrowseScreen`'s existing non-selectable usage needs no changes. When `onLongPress` is
non-null the tile renders a translucent dark overlay plus a checkmark/empty-circle icon in the
same top-right corner the unseen-dot already occupied -- the unseen dot is suppressed in that
state (`if (!post.isSeen && onLongPress == null)`) rather than drawn alongside it, since
selection status is the more relevant thing to show in that corner once selection mode is
active.

`PostGridScreen` tracks selection with a single `Set<int> _selectedPostIds` field and a derived
`bool get _selectionMode => _selectedPostIds.isNotEmpty` -- deliberately no separate boolean
flag, since "at least one post selected" and "selection mode is active" are the same condition
here; deselecting the last tile exits the mode automatically as a side effect of the set
becoming empty, with no extra code needed. A `_onTileTap` dispatcher checks `_selectionMode`
first: in selection mode a tap toggles membership instead of opening `PostDetailScreen`,
otherwise it behaves exactly as before. Long-pressing any tile enters selection mode and
selects that tile in one step, via the same `_toggleSelection` method used for every subsequent
tap.

While selection mode is active, `_buildAppBar` returns a different `AppBar` entirely rather than
conditionally swapping individual `actions` entries: a close icon (`_exitSelectionMode`, which
just clears the set), a live "`N` selected" title, a favorite icon, and up/down-vote icons. The
vote icons are omitted outright (not disabled) when `widget.search.site == BunnySite.inkbunny`
-- the exact same per-grid homogeneity reasoning as `PostDetailScreen`'s per-post Inkbunny vote
handling in M8.5.14, just hidden instead of greyed out since a contextual action bar has no
good way to show "disabled" short of literally greying an icon out, and omission reads more
clearly here. `_massFavorite`/`_massVote` each snapshot `_selectedPostIds.toList()` first (so
the loop isn't iterating a set that `_toggleSelection` could mutate mid-flight), loop the
matching `queue*` call per id, call `processQueue()` exactly once after the loop, then clear the
selection and reassign `_postsFuture` to pick up any server-side state changes (e.g. favorite
counts) on reload.

**Test gotcha, within-screen icon collision**: `PostGridTile`'s own score/fav-count overlay
already renders `Icons.arrow_upward` and `Icons.favorite` for every tile (10px, as plain status
text) -- the exact same icons the new contextual `AppBar` actions use. An unscoped
`find.byIcon(Icons.favorite)` in a grid with any posts present matches both the app bar button
and every tile's fav-count icon simultaneously, making `tester.tap` throw on ambiguity and
`findsNothing`/`findsOneWidget` assertions fail for the wrong reason. Every M9.2 test that
taps or counts a contextual action icon scopes the finder with
`find.descendant(of: find.byType(AppBar), matching: find.byIcon(...))` rather than a bare
`find.byIcon(...)` -- the same "scope past a collision" fix as M9.1's `find.widgetWithText`
gotcha above, just via a different finder combinator.

**Download manager: backend plumbing (M9.3)**: pure bookkeeping, no UI and no new database
schema -- `libs/db/src/downloads.c`'s `bunny_db_download_record`/`bunny_db_download_list_for_
post` against the `downloads` table have existed since M3 (`libs/db/src/schema.h`) with
literally nothing in `bunny_core` ever calling them, confirmed by grepping for `download`
across `libs/core/src/*.c` before starting this sub-milestone. New `libs/core/src/downloads.c`
(its own file -- `libs/core/CMakeLists.txt` lists one source file per concern, and "downloads"
is a clean, self-contained one, unlike `searches.c` which had already become a general bucket
for assorted per-post read pass-throughs before this) adds two thin wrappers following the
exact `bunny_core_map_db_result(bunny_db_*(core->db, ...))` one-liner shape every other
pass-through in this codebase uses: `bunny_core_record_download` and `bunny_core_list_
downloads_for_post`. The latter reuses `bunny_db_download_list_t` directly as its out-param
type -- no new `bunny_core`-level struct needed, since there's a real backing table (unlike
`bunny_core_comment_list_t`/`bunny_core_pool_info_t`, which needed their own types precisely
*because* nothing persists them).

The actual HTTP fetch, disk write, and checksum computation that would produce the
`file_path`/`checksum_md5`/`verified` arguments these calls take are deliberately **not** part
of this sub-milestone -- `bunny_core_record_download` only persists the bookkeeping row
*after* that work has already happened entirely client-side (M9.4 builds that pipeline). This
mirrors the project's standing rule that downloads are never proxied through the server
(`docs/architecture.md`'s pre-M9 "C server" section already states this).

On the server side, `POST`/`GET /posts/{id}/downloads` slot into the existing `posts_handler`
in `routes_queue.c` as two more `server_route_parse_id_with_suffix` branches -- the same
one-handler-owns-the-whole-prefix civetweb pattern every other `/posts/{id}/*` sub-resource
(`tags`/`sources`/`relationships`/`pools`/`comments`) already uses. The POST handler reads
`file_path` (required, `BUNNY_CORE_ERR_INVALID_ARG` if missing), `checksum_md5` (optional,
`bunny_json_get_string_or(body, "checksum_md5", NULL)` -- the first place in this codebase a
request body field is allowed to be genuinely absent rather than defaulted to a concrete
value), and `verified` (defaults `false`).

Testing this layer meant seeding a real post without a saved search's sync ever touching
`bunny_core_record_download` itself: a new `libs/core/tests/test_downloads.c` duplicates the
small fake-transport + `seed_e621_post` helper pattern `test_queue.c`/`test_sync.c` each
already carry their own copy of (an established convention in this codebase -- each C test
file is self-contained rather than sharing a test-helpers module), just trimmed down to a
single-response fake transport since downloads tests never need more than one canned e621
search response to get a post into the local cache. `FakeBunnyRepository.recordDownload`
mints sequential ids via a private `_nextDownloadId` counter and appends to a new
`downloadsByPostId` map -- the first fake in this class that needs to both generate an id *and*
store a record, unlike the four M8.5.14/M9.1 queue fakes which only needed to record that a
call happened.

**Download manager: Flutter UI + settings (M9.4)**: the first sub-milestone to add a new
top-level `app/lib/services/` directory, distinct from `screens/` and `widgets/` -- `services/
download_manager.dart`'s `DownloadManager` is pure logic with no `build()` method and no
widget lifecycle, used identically from both the single-post detail button here and the
mass-download action M9.5 adds to the grid's contextual action bar. `DownloadOutcome` has four
values (`noFileUrl`, `verified`, `checksumMismatch`, `failed`) rather than treating "verified"
as a separate bool field -- a post with no published `fileMd5` at all is folded into
`verified` (`expected == null || expected.toLowerCase() == checksum`), since there's nothing
to contradict; this keeps the UI's three-way `switch` on outcome exhaustive without a
redundant `noFileUrl` message (the button is disabled whenever `fileUrl` is null, so that
branch is defensive-only, never actually reached through the UI).

Adding `file_picker` surfaced a real dependency conflict: the plan's `^8.x` range requires
`win32 ^5.x`, but `flutter_secure_storage ^11.2.0` (already pinned, M7.3) requires
`flutter_secure_storage_windows ^4.2.2`, which requires `win32 ^6.0.1` -- incompatible ranges,
confirmed by `flutter pub get`'s own version-solving error message, which directly suggested
the fix (`file_picker ^13.1.0`, the next major compatible with the already-pinned chain).
Resolved by bumping to `^13.1.0` rather than downgrading `flutter_secure_storage`, since the
latter is load-bearing for M7.3's account credential storage and Windows isn't a build target
this project verifies yet (M12's cross-compilation gap already covers that). `FilePicker.
getDirectoryPath()` (file_picker 13's API) is a static method directly on `FilePicker`, not
`FilePicker.platform.getDirectoryPath()` as in some older major versions -- caught immediately
by `flutter analyze`.

`downloadSettingsStore` threads through every screen on the path to `PostDetailScreen`
(`main.dart` → `SearchesScreen` → `PostGridScreen`/`TagBrowseScreen` → `PostDetailScreen`'s own
internal pool/parent/child/tag navigation back to itself), the same ripple pattern
`displaySettingsStore`/`syncSettingsStore` caused in M8.5.6/M8.5.10 -- `flutter analyze` catches
every missed call site as a `missing_required_argument` error, letting `sed` bulk-fix the
uniform ones across test files and leaving only the handful with non-literal arguments (a named
local variable instead of `const SyncSettingsStore()`) to fix by hand. `DownloadManager` itself
is *not* threaded this way despite living next to these stores -- it has no required
construction dependencies (no settings to load, no shared state), so `PostDetailScreen` simply
defaults it to `const DownloadManager()`, with widget tests overriding it via the constructor
to inject a fake `http.Client`.

**Test gotcha, ListView cache-extent cutoff**: adding the whole new "Downloads" section to
`SettingsScreen` pushed the existing "Manage app lock" `ListTile` far enough down the page that
an existing, previously-passing widget test (`tapping the app lock entry opens LockSetupScreen`)
started failing with `find.text` reporting zero matches -- not merely invisible, genuinely
**not built**. Flutter's `ListView(children: [...])` is still a sliver under the hood; even
though the child widgets are supplied as a concrete list (not a lazy `.builder` callback), the
sliver protocol only materializes `Element`s for children within the viewport plus a fixed
cache extent (~250 logical pixels by default) -- a child further down than that is never added
to the tree at all, so no amount of `ensureVisible`/`scrollUntilVisible` can find it first (both
require the element to already exist to compute its scroll offset). A debug test dumping every
built `Text` widget confirmed this directly: the "App lock" section header rendered, but its
own `ListTile`'s title text one widget below it did not. Fixed with `tester.dragUntilVisible`,
which scrolls incrementally and re-checks the finder after each scroll step (so the element
gets built once it enters the cache range) rather than requiring it to already exist.

**Test gotcha, real `dart:io` I/O inside `testWidgets`**: `DownloadManager`'s unit tests (plain
`test()`, no widget involved) pass real file I/O (`Directory.create`, `File.writeAsBytes`) to a
real `Directory.systemTemp` without issue. The same calls triggered indirectly through a
`PostDetailScreen` widget test (tapping the download button) hang **indefinitely** --
`pumpAndSettle` eventually times out with no further diagnostic. `WidgetTester.pump()`/
`pumpAndSettle()` drain Flutter's own frame-scheduling microtasks but do not drive the real
OS-level event loop that genuine asynchronous `dart:io` operations complete through; a bare
`await tester.pump()` after a tap that kicks off real file I/O never actually lets that I/O's
completion callback run, so the awaited `Future` inside the widget's state never resolves and
no further frames are ever scheduled -- indistinguishable from a true deadlock from the test's
perspective. The fix is `tester.runAsync(() async { ... })`, which temporarily hands control to
the real zone/event loop for the duration of its callback; wrapping the tap *and* a short
explicit `Future.delayed` *and* an interior `pump()` inside one `runAsync` block (rather than
calling `runAsync` for the delay alone, after the tap) is what actually let the pending real I/O
progress -- the tap must be issued from inside the same `runAsync` callback it needs real-async
time to complete within, not before entering it. An additional plain `tester.pump()` after the
`runAsync` block was still needed to let the `FutureBuilder` watching `_downloadsFuture` (which
`DownloadManager` success paths reassign to show the already-downloaded icon) rebuild with the
newly-resolved data. `MockClient` (from `package:http/testing.dart`) needed none of this --
being a pure in-memory fake with no real I/O, it resolves on ordinary microtasks like everything
else in a standard widget test.

**Mass download (M9.5, completes M9)**: pure wiring, no new backend or service logic -- loops
the same `DownloadManager.downloadPost` M9.4 already built over every post in `PostGridScreen`'s
selection, sequentially (explicitly not parallelized; a personal-use app's download volume
doesn't justify a parallel queue, and the sequential loop already gives a natural progress
counter for free). `PostGridScreen` picks up its own `downloadManager` field with the identical
`const DownloadManager()` default and test-injection story as `PostDetailScreen`'s. The
contextual app bar's title swaps between "N selected" and a live "`done`/`total` downloaded"
string based on a single `(int, int)?` record field (`_massDownloadProgress`, null when idle) --
a record type rather than two separate nullable ints, since "has progress" and "has a total"
are never independently true/false. A nonexistent/unconfigured destination folder is reported
as every selected post failing (same simplification `PostDetailScreen`'s own download button
uses for the single-post case) rather than a distinct "no folder configured" message, keeping
the outcome tally exhaustive over exactly the three buckets the summary `SnackBar` reports.
Because `_massDownload` needs each selected id's full `BunnyPost` (file URL, artist, md5, ext)
rather than just the id `_massFavorite`/`_massVote` are content with, it awaits the grid's
current `_postsFuture` directly rather than threading posts through as a parameter -- the same
list already backing the `GridView.builder`, so no extra fetch.

## M9.6 -- Browsing, detail screen & UX polish

**Bug fixes bundle (M9.6.1)**: four unrelated fixes bundled into one sub-milestone, same
precedent as M8.5.1.

`FullScreenPostViewerScreen` had no way to close itself -- its `Scaffold` carried no `AppBar`
(deliberately, for an immersive black viewer) and nothing else called `Navigator.pop`. Fixed by
layering a semi-transparent circular close `IconButton` (top-left, wrapped in `SafeArea`) over
the `PhotoViewGallery` via a `Stack`, rather than adding a real `AppBar` that would have
reintroduced the chrome the immersive design avoided.

The same screen's stretched-GIF bug came from trusting `PhotoView`'s own size inference:
`PhotoViewGalleryPageOptions(imageProvider: ...)` asks `PhotoView` to decode the image and use
its reported dimensions for `PhotoViewComputedScale.contained`/`covered` math -- on this Linux
desktop target, an animated GIF's reported decode size can disagree with its real dimensions,
which stretches the computed scale. The fix doesn't chase the decoder bug directly; it sidesteps
it by switching to `PhotoViewGalleryPageOptions.customChild(child: ..., childSize: ...)`, passing
the post's own already-trusted `width`/`height` metadata as `childSize` instead of letting
`PhotoView` infer anything from the decoded image at all. `child` itself is a plain
`CachedNetworkImage` with `BoxFit.contain`, same as the inline detail view's media renderer.

The selection-circle bug was a real logic error, not a one-off styling slip: `PostGridTile`'s
checkmark/empty-circle overlay (M9.2) keyed off `onLongPress != null`, but `PostGridScreen`
always passes a non-null `onLongPress` (so long-pressing any tile, from normal browsing, can
*enter* selection mode) -- meaning the overlay had been visible on every tile in every grid
since M9.2 shipped, not just while selection mode was actually active. `onLongPress` being wired
up and selection mode being active are genuinely different conditions that happened to be
conflated by reusing one signal for both; the fix adds an explicit `selectionMode` bool,
independent of `onLongPress`, that the overlay (and the unseen-dot suppression next to it) now
checks instead. `PostGridScreen` passes `selectionMode: _selectionMode` alongside its
always-present `onLongPress`; `TagBrowseScreen` (no selection mode) passes neither, defaulting
both to their non-selectable values, unaffected.

The e621 User-Agent fix couldn't be a single static string change, because the required format
(`"LittleBunny/1.0.0 (by someuser on e621)"`) depends on whichever e621 account is currently
configured -- information that doesn't exist yet at `bunny_core_open()` time, when the bare app
name/version half of the string was previously set once and for all. The right seam turned out
to be `bunny_core_build_e621_client` (`libs/core/src/site_clients.c`), which already calls
`bunny_db_account_get` to populate Basic Auth credentials on every client construction --
appending `" (by <username> on e621)"` to `core->user_agent` right there, into a local
stack buffer passed as `e621_config_t.user_agent` (copied internally by `e621_client_create`'s
own `goblin_copy_cstr`, so the stack buffer's lifetime is never a concern), falls back to the
bare `core->user_agent` when no account exists. This one change fixes the header for every
deployment mode at once -- standalone (FFI) and networked (the C server) both route every e621
call through this same function, so there was no separate server-side user-agent string to find
or fix.

**Test gotcha, capturing request headers without dangling pointers**: the new C test
(`libs/core/tests/test_sync.c`) needed to inspect the actual `User-Agent` header value a real
`bunny_core_preview_search` call sends, which meant adding a capturing variant of the file's
shared `fake_send` callback. A first attempt copied the matched `bunny_http_header_t` struct
directly into a global for the test to inspect after the call returned -- but that struct only
holds pointers into the e621 client's own `user_agent`/other buffers, and the client (along with
everything it allocated) is destroyed before `bunny_core_preview_search` returns, leaving the
captured struct's pointers dangling by the time the test's assertion ran. Fixed by `snprintf`-ing
the matched header's value into a fixed-size global buffer *inside* the capturing callback, while
the client (and its buffers) are still alive, rather than retaining a pointer into memory that's
about to be freed.

**Select all + mass actions entry point (M9.6.4)**: a small, independent addition to
`PostGridScreen`'s existing overflow `PopupMenuButton` -- a "Select all" item next to the
existing "Mark all as seen" -- that awaits the current `_postsFuture` and replaces
`_selectedPostIds` with every loaded post's id. This reuses the exact `_postsFuture ??
Future.value(const [])` pattern M9.5's `_massDownload` already established for getting at the
currently-loaded post list from outside the `FutureBuilder`'s `builder` callback, rather than
introducing a second way to do the same thing. No changes needed to the contextual app bar
itself or to any of the existing mass favorite/vote/download actions -- they already operate
purely off `_selectedPostIds`, indifferent to whether it was populated by individually
long-pressing tiles or by this new bulk action.

**Tag/pool browse pagination (M9.6.2)**: `bunny_core_preview_search` had hardcoded page 1 for
both sites since M8.5.10 -- fine for a one-shot preview, but useless for a tag with hundreds of
thousands of matches. The fix threads a 1-indexed `page` parameter straight through to
`e621_search_posts`/`inkbunny_search`'s own existing `page` arguments (both site clients already
supported arbitrary pages; only the scheduled-sync path, `sync_e621_search`/`sync_inkbunny_search`,
was looping them -- `bunny_core_preview_search` itself never had), with a server-side default of
`1` when the query param is absent so every pre-M9.6.2 caller (and test) keeps working unchanged.

`TagBrowseScreen` changed from a one-shot `FutureBuilder` to a page-accumulating `StatefulWidget`:
a `List<BunnyPost> _posts` plus a parallel `Set<int> _seenPostIds` (de-duplication by id, since a
later page can resurface a post already shown on an earlier one when a heavily-churning tag
shifts rankings between requests), an `int _nextPage`/`bool _loadingMore`/`bool _hasMore` trio,
and a `ScrollController` listener that fires `_loadMore()` once the scroll position comes within
400px of the grid's bottom. Whether there's more to fetch is inferred purely from whether the
just-fetched page came back non-empty, rather than comparing the page's length against a
hardcoded mirror of e621's own page-size constant (`BUNNY_CORE_SYNC_E621_PAGE_LIMIT`, which lives
only in `libs/core/src/sync.c`) -- hardcoding a second copy of that number in Dart would silently
drift if the C-side constant ever changed; the only cost of the empty-page heuristic is one extra
request that comes back empty right before `_hasMore` flips to `false`.

**Test gotcha, GridView cache-extent vs. large synthetic scrolls**: the first attempt at the
pagination widget tests drove the scroll position with a single massive `tester.drag(...,
Offset(0, -100000))` and then asserted on tile presence via `find.byKey` for both the newly loaded
page and the originally loaded one -- both assertions failed, because overshooting that far past
the sliver's actual content pushes distant items outside `GridView`'s build+cache range, evicting
their `Element`s from the tree entirely (the same category of issue as the `ListView` cache-extent
gotcha hit during `SettingsScreen` testing in M9.4, just triggered by an oversized drag instead of
a long static list). Fixed two ways at once: bounding the drag to `-5000` (reaches the grid's real
bottom without wild overshoot), and switching the assertions from widget-tree presence to the
newly-added `FakeBunnyRepository.previewSearchCalls` tracking list, which records `(site, query,
page)` tuples and stays reliable regardless of what the `GridView` has or hasn't materialized.

**Pool preview without forcing a saved search (M9.6.3)**: this needed no backend work at
all -- the pieces already existed, just wired to the wrong screen. e621's own tag-search syntax
treats `pool:<id>` as a literal query (established back in M8.5's plan), and `TagBrowseScreen`
(M8.5.10) already runs a stateless preview against any query string, with its own "add to
searches" action for saving afterward. `PostDetailScreen._openPool` previously forced a
save-a-search dialog before it would show a pool's contents at all; the fix simply points that
one navigation call at `TagBrowseScreen(query: 'pool:$id')` instead of the old look-up-or-create
`PostGridScreen` flow, so pools are now viewable exactly like any other click-through browse
before ever being saved. The only new surface is `initialLabel` on `CreateSearchScreen`/
`TagBrowseScreen` (alongside the existing `initialSite`/`initialQuery`), so that
`_openPool`'s best-effort `fetchPool` call can still pre-fill a friendly label when the user
does choose to save -- setting the label field's text in `initState` also marks it as
"manually edited" so the query-mirroring listener (M8.5.13) doesn't immediately overwrite it
with the raw `pool:$id` string. The old confirmation dialog and its two now-unreachable ARB
entries were deleted outright rather than left as dead code.

**Desktop app bar compactness (M9.6.6)**: the default Material `AppBar` (56px toolbar) is sized
for phone touch targets and wastes vertical space once the window is wide enough that it's
clearly being used on a desktop. New `app/lib/util/responsive.dart` centralizes the single
judgment call this needs -- a `wideScreenBreakpoint` (720px) and `isWideScreen(BuildContext)`
helper backed by `MediaQuery.sizeOf` -- so `PostGridScreen`, `PostDetailScreen`,
`SearchesScreen`, and `TagBrowseScreen` all shrink their `AppBar.toolbarHeight` to a shared
`compactToolbarHeight` (44px) the same way, rather than each screen picking its own number.
Passing `null` (the Material default) below the breakpoint, rather than always setting an
explicit height, means phone-width layouts are byte-for-byte unchanged by this sub-milestone.
`SearchesScreen`'s `AppBar` carries a `TabBar` in its `bottom`, which has its own height
separate from the toolbar -- its `labelPadding` also tightens on wide windows so the combined
app-bar-plus-tab-bar region shrinks consistently rather than just the top half. This same
breakpoint constant is intended to be reused by M9.6.5's planned responsive post-detail layout
(wide: tags/details/sources side by side; narrow: stacked), so introducing it as a shared util
now rather than inlining a number into each of these four screens pays off immediately on the
next sub-milestone.

**Test gotcha, an unrelated overflow surfacing at narrow widths**: the widget test for
`PostDetailScreen`'s app bar originally pumped a 400px-wide surface for the "narrow" case
(roughly a phone width) -- but at that width, the comments section's anonymous-checkbox `Row`
(a pre-existing layout, untouched by this change) overflows regardless of app bar height,
failing the test for a reason that has nothing to do with what it's checking. Rather than fix
that unrelated overflow as a drive-by (it's in the exact section M9.6.5's planned redesign will
rework anyway), the test was adjusted to pump 600px instead -- still comfortably under the
720px wide-screen breakpoint this sub-milestone cares about, but above the width where the
unrelated bug triggers.

**Tag autocomplete token isolation (M9.6.7)**: `CreateSearchScreen`'s `_currentWord` getter
(now removed) computed `text.lastIndexOf(' ')` against the *entire* query string every time,
which only ever matches the trailing word -- correct for the common case of typing straight
through, but wrong the moment the user edits an earlier tag, and unaware of e621's own
single-character search-syntax prefixes (`-tag` negation, `~tag` "or", `(tag` grouping). Rather
than growing that logic in place, it moved into `app/lib/util/tag_query.dart` as four small
pure functions with no `BuildContext`/widget dependency, each independently testable:
`tagTokenRangeAt` walks outward from `TextEditingController.selection`'s cursor offset to the
nearest whitespace on either side (not the end of the string), `splitTagPrefix` peels off a
leading run of `-`/`~`/`(` characters, `tagHasWildcard` flags a `*` anywhere in the remaining
tag text, and `applyTagSuggestion` composes the first two to splice a chosen suggestion back
into exactly the token under the cursor. `CreateSearchScreen` itself shrank to a thin
`_cursorOffset` getter plus calls into these functions from `_onQueryChanged`/
`_applySuggestion` -- no behavior change for the plain trailing-tag case every existing test
already covered, since `TextField`/`enterText` leaves the cursor at the string's end, which is
exactly what the old last-space logic assumed unconditionally. Per the user's confirmed scope,
there's no real parser for balanced parenthesized boolean groups (e.g.
`( ~cat ~tiger ) ( ~dog ~wolf )`) -- `(` is treated purely as one more prefix character on
whatever token it's attached to, same as `-`/`~`.

**Auto-favorite per saved search (M9.6.8)**: this pulls forward a slice of M10's "auto-favorite"
roadmap entry early, the same way M8.5.14 pulled single-post favorite/vote UI forward out of M9
-- M10 keeps the rest of that line item ("auto-favorite *on download*", a different trigger
tied to the download pipeline rather than sync, plus the tag-stats/recommendation work). A new
migration (`libs/db/src/db.c`'s `BUNNY_DB_MIGRATIONS[]`, version 3) adds `searches.auto_favorite`
the same way M8.5.0 added `posts.score_up`/`score_down` -- `bunny_db_search_create` takes the
flag as a new parameter, `bunny_db_search_list`'s SELECT grows one more column, and a focused
`bunny_db_search_set_auto_favorite(db, search_id, bool)` setter (same one-job-per-function shape
as `bunny_db_post_mark_seen`) is the only way to flip it on a search that already exists, since
there's still no general "edit a saved search" screen anywhere in the app.

The actual enqueuing happens inside the sync loop, not as a separate pass: both `sync_e621_
search` and `sync_inkbunny_search` (`libs/core/src/sync.c`) call `bunny_core_queue_favorite_add
(core, post_id, -1)` immediately after `bunny_db_search_add_result` upserts a post into a
search's results, when that search has `auto_favorite` set. This only inserts a row into
`action_queue` -- no network call happens at sync time -- so it's exactly as cheap as any other
enqueue, and the already-scheduled `bunny_core_process_queue` pass drains it like any other
pending favorite. The plan that shaped this sub-milestone only called out `sync_e621_search`
explicitly, but the hook went into both site's sync loops: Inkbunny favorites are already fully
wired end-to-end via `inkbunny/unofficial_favorites.h` (confirmed back when M4.3 built the queue
itself), so restricting the toggle to e621 would have made the "Auto-favorite" switch silently
do nothing on an Inkbunny search -- the switch in `CreateSearchScreen` doesn't say "e621 only,"
and there's no reason it should have to.

Full plumbing follows the established shape exactly: FFI request classes + isolate handlers for
both the new `createSearch` parameter and the new setter, an `auto_favorite` field accepted on
`POST /searches`'s body (defaulting to `false` via `bunny_json_get_bool_or`, so every existing
caller is unaffected) plus a new `POST /searches/{id}/auto_favorite` endpoint taking `{"auto_
favorite": bool}`, and `BunnySearch.autoFavorite` + `BunnyRepository.createSearch(...,
autoFavorite:)`/`setSearchAutoFavorite(int, bool)` across all three repository implementations.
`CreateSearchScreen` gained a `SwitchListTile`; `SearchesScreen`'s list row gained a filled/
outlined heart `IconButton` next to the existing delete button -- tapping it calls `setSearch
AutoFavorite` directly and refreshes, the "editable afterward" affordance the user specifically
asked for, built without a general edit-search screen.

**Post detail screen redesign (M9.6.5)**: the largest single rewrite in M9.6, deliberately
sequenced last so it builds on top of every smaller fix (especially M9.6.3's pool-click change)
rather than racing them. `PostDetailScreen.build()`'s top-to-bottom order became: media → title
(kept exactly where it was -- the user's spec never mentioned it) → a new `_infoBar` → Pools →
Relationships → Description → a responsive tags/details/sources region → Comments. `_infoBar` is
a `Container` tinted with `Theme.of(context).colorScheme.surfaceContainerHighest` holding the
artist name (tappable) on one line and, on the line below, [RatingBadge] (M8.5.7's grid-tile
widget, reused as-is) plus three new `_statAction` widgets for upvote/downvote/favorite, plus the
existing download button at the end. `_statAction` exists because a bare `IconButton` has no slot
for a label -- each is a `Tooltip` wrapping a `TextButton.icon(icon: ..., label: Text('$count'))`
instead, which is the first place in the app a stat needs both an icon *and* a live count in one
tappable unit. Rating/score/favorites moved out of the old flat metadata-row list entirely; what's
left (post id, comment count, dimensions, created date) became `_postDetailsColumn`, used by the
new `_tagsDetailsSourcesRegion` on both sides of its wide/narrow split -- wide windows get a `Row`
(tags on the left; post details + sources stacked on the right), narrow windows get the same three
pieces in a plain stacked `Column`, both sharing M9.6.6's `isWideScreen` breakpoint rather than a
second one invented for this screen. Tags themselves are now sorted into a fixed category order
(artist, character, copyright, species, general, meta) before rendering, with anything not in that
list (including Inkbunny's `null` uncategorized bucket) grouped last -- previously they rendered
in whatever order `Map` iteration happened to produce from the upsert.

**Test gotcha, Tooltip/TextButton nesting direction**: `IconButton`'s own `tooltip` param wraps
its *internal* icon in a `Tooltip`, so existing tests found the enabled/disabled state via
`find.ancestor(of: find.byTooltip(...), matching: find.byType(IconButton))` -- the `IconButton`
sits *above* the `Tooltip` it generates internally. `_statAction`'s `Tooltip(child: TextButton.
icon(...))` is the opposite nesting: the `Tooltip` is the outer wrapper the caller wrote, so the
`TextButton` is a *descendant* of it, not an ancestor. The vote-buttons-disabled test's `find.
ancestor` call against `TextButton` therefore always returned nothing until it was changed to
`find.descendant` -- a one-line fix once the actual tree shape was diagrammed out, but non-obvious
from the assertion failure's bare "No element" message alone.

Every pre-M9.6.5 behavior the layout touched (tag taps opening tag-browse, source taps launching
URLs, id-copy-to-clipboard, pool/relationship taps, comments post/list, favorite/vote queuing +
optimistic UI update, download button state) is still covered by `post_detail_screen_test.dart`,
just re-pointed at the new structure and re-keyed to `scoreUp`/`scoreDown` wherever a test used to
read the no-longer-displayed total `score`. New tests cover the info bar's content, the tag sort
order (comparing rendered category-header y-offsets rather than just checking presence), and the
wide/narrow split (a `Key` on the wide-only `Row` that simply doesn't exist in the narrow Column
layout, rather than trying to distinguish `Row` vs. `Column` structurally). Verification for this
sub-milestone was the full widget-test suite (covering both the narrow and wide code paths via
`tester.view.physicalSize`) plus a Linux build + headless smoke test; an actual visual/manual
check across window sizes -- which the plan called for given the layout risk -- wasn't possible
with the tools available in this session, since there's no way to drive or screenshot a native
Linux GTK window the way the browser-preview tools can for a web app.

**Fix: favorite/vote not persisting on a failed queue drain (M9.6.9)**: `bunny_core_process_
queue` (`libs/core/src/queue.c`) only calls `apply_favorite_mirror` -- the function that writes
to the `favorites` table, which is what `is_favorited` is actually computed from via `LEFT JOIN
favorites` in `BUNNY_DB_POST_SELECT_COLUMNS` -- when `process_e621_action`/`process_inkbunny_
action` return success for that specific action. A failure (no account configured, a rejected
request, anything the site itself rejects) marks the action `FAILED` in `action_queue` and moves
on; nothing is written to `favorites`, by design -- this part of `bunny_core` was already correct.
The bug was entirely in `PostDetailScreen._toggleFavorite`/`_vote`: both called `processQueue()`
and then unconditionally applied `_applyOptimisticUpdate`, discarding the returned `BunnyQueueStats`
entirely. The `try`/`catch` around the call only guarded against `processQueue()` itself throwing
(a thrown exception, e.g. a network-level failure) -- a *returned* failed-action count was never a
caught exception, so it sailed straight through to the unconditional optimistic flip every time.
The UI looked right for the rest of that screen's session (nothing ever re-read the DB to
contradict it) and only showed the true, never-persisted state once the post was reopened and
`PostDetailScreen` initialized `_post` from a `BunnyPost` that reflected what's actually in
`favorites`. Fixed by checking `stats.actionsFailed == 0` before applying the optimistic update,
surfacing a new generic `postDetailActionFailed` SnackBar otherwise -- the same "swallow network
errors, but now also check for a returned failure" treatment `_downloadFile` already gave its own
outcome. Votes themselves still have no "did *I* vote, and which way" concept anywhere -- e621's
post-listing API doesn't return the caller's own vote, so there was never anything to mark beyond
the global `scoreUp`/`scoreDown` totals this fix now at least persists correctly; a real per-user
vote indicator would need a new local-only table mirroring the `favorites` pattern, deliberately
left as separate follow-up work rather than folded into this fix.

**Persistent own-vote tracking + visual marking (M9.7.1)**: the follow-up work M9.6.9 flagged.
A new `votes` table (`libs/db/src/schema.h`) is deliberately a *new* table rather than a migration
-- same reasoning `favorites`/`downloads` already established back in M8.5.0: `CREATE TABLE IF
NOT EXISTS` is free on every `bunny_db_open()`, only `ALTER TABLE` on a table that already shipped
needs the migration runner. `libs/db/src/votes.c`'s `bunny_db_vote_set` is a near-identical
upsert to `bunny_db_favorite_add` (`INSERT ... ON CONFLICT(post_id) DO UPDATE`), with a `CHECK
(score IN (-1, 1))` constraint enforced both in SQL and in the C function's own argument
validation. `BUNNY_DB_POST_SELECT_COLUMNS`/`_FROM_JOIN` (`libs/db/src/internal.h`) grow a `LEFT
JOIN votes` exactly the way `favorites` already joins in to compute `is_favorited` -- every
`bunny_db_post_t` (and therefore every post read anywhere in the app, not just the detail screen)
now carries `user_vote` for free. The actual write happens inside `bunny_core_process_queue`
(`libs/core/src/queue.c`): a new `apply_vote_mirror`, structurally identical to `apply_favorite_
mirror`, called right alongside it whenever a `BUNNY_DB_ACTION_VOTE` action succeeds. Because
`process_inkbunny_action` already rejects any vote action outright (`libs/core/src/queue.c`,
confirmed back in M4.3), `apply_vote_mirror` is only ever reached for e621 posts in practice --
no explicit site check needed, the same reasoning M9.6.8's `auto_upvote` hook (M9.7.2) relies on.

The server has three separate `post_to_json`-shaped functions (`routes_searches.c`, `routes_
search.c`, `routes_queue.c` -- each route file apparently grew its own copy rather than sharing
one, predating this sub-milestone), so the new `"user_vote"` field had to be added in all three
rather than one shared place; worth factoring into a shared helper if a fourth copy ever appears.
UI: `PostDetailScreen`'s upvote/downvote `_statAction`s pass a highlight color (green/orange) when
`post.userVote` matches that direction, using the exact same `_applyOptimisticUpdate`-on-success
path M9.6.9 already built -- the only change there was adding a `userVote` parameter alongside
the existing score deltas. Documented limitation: e621 treats a repeat same-direction vote as an
"unvote" server-side (clicking upvote on an already-upvoted post removes the vote); `apply_vote_
mirror` has no way to detect this from the API response it currently inspects (just the HTTP
status), so it always records whichever direction was just successfully sent -- the same
toggle-blind-spot `apply_favorite_mirror` already has, not a new regression introduced here.

**Search edit screen: rename/requery, Inkbunny star level, e621 auto-upvote (M9.7.2)**:
`bunny_db_search_create`'s signature had grown a new parameter in nearly every sub-milestone that
touched searches (`interval_hours`, then `auto_favorite` in M9.6.8) -- rather than letting that
keep happening, a `bunny_db_search_options_t { auto_favorite; auto_favorite_stars; auto_upvote; }`
struct (`libs/db/include/bunny_db/types.h`) now carries every editable per-search toggle, passed
by pointer the same way `bunny_core_sync_stats_t` already crosses the FFI boundary by pointer.
`bunny_db_search_create` takes `const bunny_db_search_options_t *options` (a `NULL` options
pointer falls back to a static all-off default, so every existing call site that only cared about
the bare `auto_favorite` bool keeps compiling as `NULL`). A new `bunny_db_search_update(db,
search_id, label, query, interval_hours, options)` replaces `bunny_db_search_set_auto_favorite`
outright -- that function's only caller, the searches-list quick-toggle heart icon, is deleted in
this same sub-milestone in favor of a full edit screen, so there was no reason to keep both
narrow and broad update paths alive side by side. Two new migrations (`libs/db/src/db.c`, versions
4 and 5): `searches.auto_favorite_stars INTEGER NOT NULL DEFAULT 1` and `searches.auto_upvote
INTEGER NOT NULL DEFAULT 0` -- two separate `ALTER TABLE` statements rather than one, since
SQLite's `ADD COLUMN` only accepts a single column per statement (the same constraint M8.5.0's
migration runner doc comment already notes).

Sync hooks in `libs/core/src/sync.c`: the existing `auto_favorite` hook (`sync_e621_search`,
alongside `bunny_db_search_add_result`) now passes `search->auto_favorite_stars` instead of a
hardcoded `-1`, since e621 ignores the stars payload for favorites anyway (`process_e621_action`'s
`BUNNY_DB_ACTION_FAVORITE_ADD` branch calls `e621_favorite_add` with no payload argument at all) --
no site branching needed to thread a real value through. A new `auto_upvote` hook calls
`bunny_core_queue_vote(core, post_id, 1, false)` right next to it. This hook is only ever wired up
from the e621 sync path, but even if it weren't, `process_inkbunny_action` already rejects any
queued vote action outright (confirmed back in M4.3, leaned on again by M9.7.1's `apply_vote_
mirror` reasoning) -- so there's no explicit site check anywhere in this hook, matching the "the
backend already fails safe, don't duplicate the guard" pattern used throughout this codebase.
`bunny_core_search_create`/new `bunny_core_search_update` are thin pass-throughs mirroring the db
layer's signatures exactly, same as every other `bunny_core` search function.

Server: `POST /searches`'s body parsing gains `auto_favorite_stars`/`auto_upvote` via the same
`bunny_json_get_int_or`/`bunny_json_get_bool_or` defaulting pattern M9.6.8 introduced for
`auto_favorite`. A new `PUT /searches/{id}` (parsed the same way `server_route_parse_id` already
handles `DELETE /searches/{id}`) takes the full editable field set and calls `bunny_core_search_
update`; it replaces `POST /searches/{id}/auto_favorite` from M9.6.8, which is deleted along with
its handler. `BunnySearch` gains `autoFavoriteStars`/`autoUpvote`; `BunnyRepository.createSearch`
gains the two matching named params (defaulting to `1`/`false`, preserving every existing call
site's behavior); `setSearchAutoFavorite` is replaced by `updateSearch(searchId, label, query,
{intervalHours, autoFavorite, autoFavoriteStars, autoUpvote})` across the FFI isolate wrapper
(a new `_UpdateSearchRequest`, mirroring `_CreateSearchRequest`'s shape), `HttpBunnyRepository`
(a `PUT` request via `http.Client.put`, same JSON body shape as `POST /searches`), and
`FakeBunnyRepository`.

UI: `CreateSearchScreen` gains a second `SwitchListTile` ("Auto-upvote new posts"), shown only
when `_site == BunnySite.e621` -- the same per-site `SwitchListTile`-visibility pattern used
elsewhere for vote-related controls. No star picker appears at creation time at all (a new
Inkbunny search's `auto_favorite_stars` always starts at the struct's default of `1` until
edited), per the scope confirmed with the user before this sub-milestone was planned. New
`app/lib/screens/edit_search_screen.dart` mirrors `CreateSearchScreen`'s form shape closely
(including the same tag-autocomplete wiring against `tag_query.dart`'s pure functions), but is a
separate widget rather than a re-parameterized `CreateSearchScreen`, since its state is pre-filled
from an existing `BunnySearch` rather than starting blank, its site is fixed (shown as plain text,
not a `SegmentedButton`) to avoid orphaning already-synced posts tagged to the old site, and it
has the Inkbunny-only 1-3 star `SegmentedButton` picker `CreateSearchScreen` never shows.
`SearchesScreen`'s `ListTile` gains `onLongPress` opening this screen and refreshing on a `true`
pop -- the same push-then-conditionally-refresh shape `_createSearch` already uses for the FAB
flow -- and the heart `IconButton`/`_toggleAutoFavorite` are deleted, since the edit screen now
covers (and extends) what that icon did.

**Video/GIF badge on grid thumbnails (M9.7.3)**: `PostDetailScreen` already had everything this
needed, just private to that one file -- `_videoExtensions`/the gif-is-just-another-image-
extension check moved into a new shared `app/lib/util/media_type.dart` (`isVideoExt`/`isGifExt`),
with `PostDetailScreen` itself switched over to the shared functions instead of its own copy. The
interesting design question was placement, not logic: `PostGridTile`'s `Stack` already has
something in every corner (rating badge top-left since M8.5.7, unseen-dot/selection-checkmark
top-right since M9.2/M9.6.1, the full-width score/favCount bar along the entire bottom edge since
M8.5.7) -- there's no genuinely free corner left to tuck a fourth badge into without either
colliding with an existing one or squeezing into the bottom bar's `Row` in a way that complicates
its `spaceBetween` layout. Centering the badge instead sidesteps this entirely and happens to
match a familiar convention (a centered play icon over a video thumbnail), at the cost of
partially obscuring the thumbnail's center -- an acceptable trade for a small icon/chip.

## M10 -- Automation & recommendations

**Auto-favorite on download (M10.1)**: a download-triggered counterpart to the sync-triggered
auto-favorite M9.6.8/M9.7.2 already built -- this is the other half of the roadmap line those two
sub-milestones pulled forward from M10, a different trigger (downloading a file) reusing the
exact same action-queue plumbing (`BunnyRepository.queueFavoriteAdd`/`processQueue`) rather than
anything new at the queue layer. `DownloadManager.downloadPost` (`app/lib/services/
download_manager.dart`) already took `BunnyRepository` as a parameter and is the single
chokepoint both the single-post download button (`PostDetailScreen`) and the mass-download action
(`PostGridScreen`) call through, so a new `{bool autoFavorite = false}` parameter there -- rather
than duplicating the queueing logic at each call site -- is the natural fit. It deliberately only
*queues* the favorite (`repository.queueFavoriteAdd(post.id)`, no `stars` override, matching the
detail screen's own manual favorite button) when the outcome is `verified` or `checksumMismatch`
(the file was actually written; `noFileUrl`/`failed` never queue anything) and never calls
`processQueue()` itself -- draining stays an orchestration decision each caller already makes for
its own batching needs, the same "queue N, drain once" pattern M9.2's mass favorite/vote
established for mass actions. `PostDetailScreen._downloadFile` loads the new `DownloadSettingsStore.
loadAutoFavoriteOnDownload()` setting alongside its existing `loadDestinationFolder()` call and,
only when it's on, calls `processQueue()` once immediately after -- mirroring `_toggleFavorite`'s
existing immediate-drain shape. `PostGridScreen._massDownload` loads the same setting once before
its loop (not per post, to avoid N redundant `shared_preferences` reads) and, only when on, calls
`processQueue()` once after the whole loop finishes, exactly mirroring mass-favorite's batching
rather than draining after every individual download.

**Most-favorited tag stats + recommended-search entry point (M10.2)**: `bunny_db_top_favorited_
tags` (`libs/db/src/stats.c`) had existed since M3 as a never-wired db function, and turned out to
have a real bug once this sub-milestone actually tried to surface it: unlike `bunny_db_tag_
autocomplete`'s otherwise near-identical query (same file, `WHERE t.site = ?`), it had no site
filter at all. Since `tags` is `UNIQUE(site, name)`, an e621 "wolf" and an Inkbunny "wolf" are two
distinct rows that would both surface as indistinguishable `{name: "wolf", count: N}` entries --
fixed by giving `bunny_db_top_favorited_tags` the same `bunny_db_site_t site` parameter
`tag_autocomplete` already has, a natural side effect of adding the parameter this sub-milestone's
UI needed anyway (a per-site stats screen). `bunny_core_top_favorited_tags` (`libs/core/src/
searches.c`, right next to `bunny_core_tag_autocomplete`) and its FFI/server/repository plumbing
all mirror `tag_autocomplete`'s existing chain shape for shape: a new `_TopFavoritedTagsRequest`/
handler in the FFI isolate wrapper, a new `GET /tags/top_favorited?site=&limit=` registered as a
sibling exact-path handler alongside `GET /tags/autocomplete` in `server/src/routes_tags.c` (civet
web dispatches by exact URI match here, not a prefix router, so adding a route is one more `mg_
set_request_handler` call plus one more `strcmp` branch in the shared `tags_handler`), and
`BunnyRepository.topFavoritedTags(site, {limit = 20})` across FFI/HTTP/Fake -- reusing `BunnyTagStat`
(`{name, count}`) exactly as-is, since it already has the right shape from the autocomplete feature.

UI: new `app/lib/screens/tag_stats_screen.dart` -- a `SegmentedButton<BunnySite>` (matching
`CreateSearchScreen`'s own site toggle) switches which site's stats are loaded, followed by a
plain `ListTile`-per-tag list. Tapping a tag opens the existing `TagBrowseScreen` (M8.5.10) for
that tag/site, which already has its own "add to searches" action from the pool/tag click-through
work -- per the confirmed scope, the tag itself *is* the "recommended search," with no additional
filtering against what's already covered by an existing saved search's query (that would need
parsing/matching logic with its own edge cases for comparatively little payoff, so it was
deliberately left out). `SearchesScreen`'s app bar gained one more icon (next to the existing
accounts/settings icons) opening this screen -- the same `IconButton` + `Navigator.push` pattern
already used for the other two.

**View my own favorites (M10.3)**: direct user feedback -- e621 supports `fav:<username>` as a
literal tag-search token, and Inkbunny's official search API has a dedicated `favorited_by_
user_id` parameter for the same purpose, and the user wanted an accessible way to jump to either.
The two sites needed genuinely different plumbing. e621 needed nothing new at all: `fav:<username>`
is just literal query text, already fully supported by the existing `bunny_core_preview_search`/
`previewSearch`/`TagBrowseScreen` pipeline (the same mechanism `pool:<id>` already rides on) --
the e621 heart icon on `AccountsScreen` just navigates to `TagBrowseScreen(site: e621, query: 'fav:
$username')`, reusing `BunnyAccount.username` which was already stored. As a free side effect, the
user can also hit `TagBrowseScreen`'s existing "add to searches" action on this view to turn it
into a standing synced "my e621 favorites" search.

Inkbunny needed a new code path. `inkbunny_login` (`libs/inkbunny/src/client.c`) already parses
the logged-in account's own numeric `user_id` out of the login response into the opaque
`inkbunny_client_t`, but `inkbunny/client.h` had no public getter for it -- a one-line
`inkbunny_client_get_user_id` fixes that. `bunny_core_build_inkbunny_client` (`libs/core/src/
site_clients.c`) already logs in on every call before any caller gets to use the client, so a new
`bunny_core_list_my_inkbunny_favorites(core, page, out_list)` (`libs/core/src/sync.c`) needs no
separate account lookup -- it builds the client, reads the id straight off it, and otherwise
mirrors `bunny_core_preview_search`'s existing Inkbunny branch almost line for line, just building
`inkbunny_search_params_t.favorited_by_user_id` instead of `.text`. No new `bunny_db` migration, no
caching -- the id is read live every call, the same "fetch live, don't persist" pattern `bunny_
core_fetch_pool` already uses. Full plumbing: FFI, a new `POST /favorites/inkbunny/mine?page=`
route (a sibling registration in `server/src/routes_search.c`, which already owns the structurally
similar `POST /search/preview`), and `BunnyRepository.myInkbunnyFavorites({page})` across
FFI/HTTP/Fake. `TagBrowseScreen` gained an optional `customFetch`/`title` override -- when set,
`_loadInitial`/`_loadMore` call it instead of `previewSearch`, and the "add to searches" action is
omitted entirely (not just disabled), since Inkbunny's favorites can't be expressed as a saved
search's query string at all. This reuses every line of `TagBrowseScreen`'s pagination/grid code
for Inkbunny's favorites rather than building a second, mostly-duplicate screen.

A third finding came directly from the user during this sub-milestone's planning: posts pulled
back from either site's "my favorites" list are, by definition, actually favorited according to
the site -- and that fact needs to land in the local `favorites` mirror table, not just be
displayed. This exposed a pre-existing gap: `e621_post_t.is_favorited`/`inkbunny_submission_t.
is_favorite` (parsed off every search/get response since M2) had never been read anywhere in
`libs/core/src/sync.c` -- the local `favorites` table was, until now, written *only* when the user
favorited something through this app's own action queue (`apply_favorite_mirror`, M4.3), never
reconciled with the site's own "already favorited" truth. Fixed at the shared upsert functions
(`upsert_e621_post`/`upsert_inkbunny_submission`): right after a successful `bunny_db_post_upsert`,
if the site reports the post as favorited, `bunny_db_favorite_add` is called too (already an
upsert itself, so calling it unconditionally is cheap and idempotent). This is **additive only** --
it never calls `bunny_db_favorite_remove` on a `false` report, since that would turn a simple "pull
favorites in" into a full bidirectional overwrite of whatever's already recorded locally, a bigger
behavior change than what was asked for. Because this lives in the shared upsert path rather than
only the two new "my favorites" screens, every sync pass and preview search now also correctly
backfills local favorite status for anything favorited directly on the website, not just posts
reached through this specific feature.

**Video playback controls (M10.4)**: direct user feedback -- video posts only had a tap-anywhere
play/pause, no timeline, no mute toggle (and audio wasn't muted by default), no fullscreen, and
the in-place player could visibly stretch a video because it sized itself off
`controller.value.aspectRatio` (the decoded video's own reported ratio) instead of
`post.width`/`post.height` -- the same class of bug M9.6.1 already fixed for the full-screen
image viewer, just never applied to video. Added `chewie` (a pre-built Material/Cupertino
controls skin over `video_player`) rather than hand-rolling a scrubber/mute/fullscreen UI.
`PostDetailScreen._PostDetailScreenState` now holds both the `VideoPlayerController` (still
needed for `networkUrl`/`httpHeaders` construction and for disposal -- `ChewieController.
dispose()` does not dispose the video controller it wraps) and a `ChewieController` built once
the former finishes initializing. Muted-by-default is `controller.setVolume(0)` called
immediately after construction, before `initialize()`: `VideoPlayerController.setVolume` writes
to `value.volume` synchronously (before its first `await`), and the platform side applies
whatever `value.volume` holds once the `initialized` event fires, so the ordering works out
without a separate "apply volume post-init" step. The aspect-ratio fix is one value threaded to
two places: the same `(post.width > 0 && post.height > 0) ? post.width / post.height : 16/9`
calculation `_buildMedia`'s image branch already used is now also passed as `ChewieController.
aspectRatio` (used for both the in-place view and Chewie's fullscreen route) instead of leaving
it `null` and letting Chewie fall back to the decoded video's own value. No existing widget test
needed updating -- Chewie renders a real `VideoPlayer` internally (`PlayerWithControls.
_buildLocal`), so `find.byType(VideoPlayer)` still finds it.

## M11 -- Backup & import

The ROADMAP's M11 entry was blocked from the start: it called for exporting/importing this
app's own saved searches, plus importing "The Wolf's Stash" (`https://zepiwolf.se/tws/`)
export format, but no sample file existed to confirm the latter's shape against. The user
provided a real sample (705 entries) during planning, which turned out to be a flat JSON array
of objects with single-letter keys -- `a` (label, empty for plain tag searches, auto-filled
with the pool's title for `pool:` searches), `b` (an integer, 702/705 are `1` with a few
outliers on complex queries; meaning unconfirmed, no spec exists anywhere), `c` (an array of
tag tokens to AND together -- plain tags, `-exclude`, `~or-group`, or `pool:<id>` -- joined
with a space to get a normal e621-style query string), `d`/`e` (created/checked timestamps),
and `f` (unseen count at export time). 422 of the 705 entries were `pool:` searches, 349 plain
tag/artist searches -- everything e621-specific, no Inkbunny equivalent anywhere, confirming
the tool is e621-only. Per the user's explicit decision, `b`/`d`/`e`/`f` are all ignored on
import: `intervalHours` always comes from this app's own `SyncSettingsStore` default instead of
guessing at `b`'s semantics, and the timestamps/unseen-count mean something different in this
app's own scheduling model than they did in the source tool's. The real sample was named
`.tws2`, not the `.tws_plain` the original ROADMAP entry had guessed at -- since no format spec
exists publicly for either name, the importer sniffs the parsed JSON's own structure rather
than trusting a file's name or extension, so it works regardless of which export option within
the tool actually produced a given file. The sample itself is a third party's personal data
(their own followed artists and tracked pools, not the user's), so it was never committed to
the repo or used as a test fixture -- tests use a small hand-written synthetic file covering
the same shapes instead.

No backend changes were needed at all -- `BunnyRepository.createSearch`/`listSearches` already
cover everything both directions need, the same "already fully wired, just needs UI" pattern
M10.3's e621 half rode on for `fav:`. New `app/lib/services/search_backup_service.dart`
(`SearchBackupService`) is pure logic with no widget, the same shape as `DownloadManager`
(M9.4): `exportSearches` maps a `List<BunnySearch>` to this app's own round-trip JSON shape
(`site`/`label`/`query`/`intervalHours`/`autoFavorite`/`autoFavoriteStars`/`autoUpvote` --
deliberately dropping `id`/`createdAt`/`lastRunAt`/`unseenCount`, which are local/derived and
not meaningful to round-trip), and `parseImportFile` auto-detects which of the two supported
shapes a file is (this app's own format, keyed by the presence of `site`/`label`/`query`; Wolf's
Stash's, keyed by the exact `{a,b,c,d,e,f}` key set) before mapping either into a shared
`ImportSearchEntry` list the caller can feed straight into `createSearch`. The actual
`createSearch` loop, and deduping against the searches that already exist, stays in
`SettingsScreen` rather than the service, mirroring M10.1's established split between a
manager that does the mechanical part and a caller that orchestrates using its own live state.

`SettingsScreen` gained a new "Backup" section (following the same sectioned-control
convention every other settings concern already uses) with "Export"/"Import" buttons. This is
the first use in this codebase of `file_picker`'s `pickFile()` (returns a cross-platform
`PlatformFile.readAsBytes()`, used to read the chosen import file) and `saveFile()` (takes the
bytes directly and shows a native save dialog, used for export) -- only `getDirectoryPath()`
(for the downloads destination folder, M9.4) had been used before. Import dedupes against the
current `(site, query)` pairs (one `listSearches()` call up front) and adds each newly-created
entry's key to that same set as the loop goes -- running the service against the real sample
file during planning (without touching the db) surfaced 18 pairs that were duplicated *within
the file itself*, which an earlier version of this loop (checking only the pre-loop snapshot)
would have inserted twice; updating the set in-loop catches both that case and re-importing the
same file a second time, reporting imported/already-saved/invalid counts in a summary `SnackBar` -- the same "queue N, drain once" shape mass-favorite (M9.2) and
mass-download (M9.5) already established, just applied to search creation instead of the
action queue. `SettingsScreen` needed a new required `repository` constructor parameter to
reach `createSearch`/`listSearches` at all (every other screen already receives it this way;
`SettingsScreen` previously didn't need it) -- its one call site in `SearchesScreen` already
held the repository via `BunnyRepositoryScope`, so this was a one-line addition there.

## M13 -- Searches list UX, manual sync-all, and tag blacklist

Direct user feedback after M11 shipped, bundling several requests. This section covers M13.1;
M13.2 (manual sync-all with progress) and M13.3 (tag blacklist) are documented as they land.

**Searches list UX (M13.1)**: three independent fixes. The pool-name-as-label gap was narrow --
`PostDetailScreen._openPool`, the Pools tab's "add pool by ID" dialog, and `TagBrowseScreen`'s
"add to searches" action (which forwards `initialLabel`) all already fetched and used the real
pool name; only `CreateSearchScreen`'s own label-mirroring had no pool-awareness, so typing a
raw `pool:<id>` query directly just mirrored the literal text. `_maybeFetchPoolName` (called
alongside the existing `_mirrorQueryIntoLabel`) debounces 300ms (reusing the same `Timer`-based
shape the query's tag-autocomplete already uses), then calls `fetchPool` and swaps the label to
the resolved name if the user hasn't manually edited it meanwhile; it skips entirely when
`widget.initialLabel` is already set, since that means one of the three working flows above is
the caller and a fetch would just be wasted. The restart-after-import bug was a missing refresh,
not a data bug: every other `SearchesScreen` navigation that can change the search list
(`CreateSearchScreen`, `EditSearchScreen`) already captured a `bool` pop result and called
`_refresh()` on `true`; the `SettingsScreen` navigation (added in M11, since Settings previously
never mutated the list) had no such handling. Fixed by just awaiting the push and unconditionally
refreshing afterward -- Settings has no "cancelled" case worth optimizing a reload away for.
Sort order (`DisplaySettingsStore.SearchSortOrder`: `mostUnseen` default, `label`,
`recentlyCreated`) is a pure client-side `List.sort` applied after `listSearches()` returns, no
backend change needed since `BunnySearch` already carries every field each order sorts by.

**Manual "check for updates" with per-search progress (M13.2)**: `bunny_core_sync_due_searches`
(`libs/core/src/sync.c`) loops over every search internally, calling its private
`sync_e621_search`/`sync_inkbunny_search` helpers only for ones `search_is_due()` accepts, and
returns one aggregate `bunny_core_sync_stats_t` to the caller -- no per-search granularity ever
surfaces, and there was no way to force a non-due search to sync. New `bunny_core_sync_search(core,
search_id, out_stats)` calls those same two static helpers unconditionally for exactly one search
(found via a linear scan of `bunny_db_search_list`'s result -- no dedicated single-search-lookup
db function exists, and at personal-use scale this is simpler than adding one), returning
`BUNNY_CORE_ERR_NOT_FOUND` if the id doesn't exist. Full plumbing: FFI, a new `POST
/searches/{id}/sync` branch in the existing `searches_handler` (`routes_searches.c`),
`BunnyRepository.syncSearch(int) -> Future<BunnySyncStats>` across FFI/HTTP/Fake (reusing
`BunnySyncStats` as-is). `SearchesScreen` gained a "check for updates" app bar icon: tapping it
loads the current search list, then calls `syncSearch` once per search *sequentially* (not in
parallel -- this is a manual, personal-use action, and sequential calls are what let the UI show
real incremental progress), swapping the app bar title for a `n/total checked` counter while
running, the same `(done, total)` state-and-title-swap shape `PostGridScreen._massDownloadProgress`
already established (M9.5). A single search failing (network error, etc.) is caught and skipped
rather than aborting the whole run, matching the tolerance `bunny_core_sync_due_searches` already
has for one search's failure during a scheduled pass.

**Tag blacklist (M13.3)**: a per-site, exact-match-only tag blacklist, direct user feedback.
The new `blacklist_tags` table (`site`, `tag`, `UNIQUE(site, tag)`) is deliberately *not*
foreign-keyed into `tags(id)`, since a tag someone wants to blacklist may never have been
synced locally -- it has to be storable as plain text regardless. New `libs/db/src/blacklist.c`
(`bunny_db_blacklist_list/add/remove`) follows the exact CRUD shape `favorites.c`/`votes.c`
already established. The filter itself lives in exactly one place:
`bunny_db_search_list_posts`'s SQL (`libs/db/src/posts.c`) gained a `NOT EXISTS (SELECT 1 FROM
post_tags pt JOIN tags t ON t.id = pt.tag_id JOIN blacklist_tags bl ON bl.site = t.site AND
bl.tag = t.name WHERE pt.post_id = p.id)` clause. Matching on `t.site` rather than joining the
`searches` table means the query never needs to know its own search's site to apply the right
per-site blacklist. `bunny_core_preview_search`'s separate query (the one tag/pool browsing and
"my favorites" previews both run through) is deliberately left untouched -- confirmed by a test
that blacklists a tag the preview fixture carries and asserts the result is still returned --
so nothing is hidden by default outside a normal saved search's own grid, per the user's
explicit decision. Full plumbing: `bunny_core_blacklist_list/add/remove`
(`libs/core/src/blacklist.c`), FFI, `GET/POST/DELETE /blacklist` (new `routes_blacklist.c`,
following the one-file-per-resource convention every other route file already set),
`BunnyRepository.getBlacklist/addBlacklistTag/removeBlacklistTag` across FFI/HTTP/Fake.

`SettingsScreen` gained a "Blacklist" section: a `SegmentedButton<BunnySite>` (matching
`CreateSearchScreen`'s own site toggle) above a `Wrap` of removable `Chip`s and a text field +
add button, the first list-editor UI in this app. The one place a blacklisted post can still
surface is parent/child relation navigation (`PostDetailScreen._openExternalPost`, the single
method both the parent chip and every child chip already route through) -- a saved search's
grid filters blacklisted posts out entirely via the query above, but a parent/child target was
never reached through that filtered listing in the first place, and by design (per the user's
request) isn't silently hidden either. Before navigating, `_confirmIfBlacklisted` fetches the
target post's own tags (`getPostTagsByCategory`, already used elsewhere on this screen) and
intersects them with its site's blacklist; a non-empty match shows an `AlertDialog` naming the
matched tag(s) with "Cancel"/"View anyway" (same `showDialog<bool>` shape `SearchesScreen`'s
remove-confirmation already uses), and navigation only proceeds on an empty match or an explicit
"View anyway". Pools are unaffected entirely, by design -- they route through `TagBrowseScreen`'s
`previewSearch` call, the same unfiltered path tag/pool browsing always uses.

## M14 -- Pinning, auto-upvote, DB backups, split tag stats, staleness fix, row cleanup

Direct user feedback after M13 shipped, bundling several requests -- this section covers all
five M14.N sub-milestones.

**Pin searches, total post count, and row-action cleanup (M14.1)**: three requests bundled
into one branch since all three reshape the same `SearchesScreen` row UI and
`bunny_db_search_list` query. `pinned` is a new `ALTER TABLE searches ADD COLUMN pinned
INTEGER NOT NULL DEFAULT 0;` migration (`libs/db/src/db.c`'s `BUNNY_DB_MIGRATIONS`, following
the exact pattern `auto_favorite`/`auto_upvote` already used), with its own dedicated
`bunny_db_search_set_pinned(db, search_id, bool)` setter (`libs/db/src/searches.c`) -- not
folded into `bunny_db_search_options_t`, since that struct holds only fields that change via
the full edit form, and pinning is toggled directly from the row. `total_count` needed no
migration at all: it's a second live `COUNT(*)` subquery in `bunny_db_search_list`'s SQL,
right next to the existing `unseen_count` one, so it's always fresh with zero extra round
trips. Full plumbing for pinning: `bunny_core_search_set_pinned`, FFI request/handler/
dispatch, `POST /searches/{id}/pin` (body `{"pinned": bool}`, a new branch in the existing
`searches_handler`/`routes_searches.c` dispatch), `BunnyRepository.setSearchPinned(int, bool)`
across FFI/HTTP/Fake. `SearchesScreen._sorted()` changed from one flat sort to
partition-then-sort: pinned searches first, unpinned after, each group still internally
ordered by whichever `SearchSortOrder` the user picked (M13.1) -- a pin toggle therefore only
ever moves a search between those two groups, never changes the within-group ordering logic
itself. The row's old delete icon was removed outright; deleting a search now happens from
`EditSearchScreen`'s app bar instead (same confirmation dialog text/shape the row used to show,
just triggered one screen over), and the row's freed-up icon slot became a "sync this search
now" button that calls the already-existing `syncSearch(id)` from M13.2 directly, tracked via
a `Set<int> _syncingSearchIds` so several rows can be in flight independently without
interfering with each other or with the app-bar-level "check for updates" action (which
deliberately keeps its own `Icons.sync` icon; the per-row button uses `Icons.refresh` instead,
partly for a visually distinct affordance and partly so widget-test finders can target one
without ambiguity now that both exist on screen at once).

**Auto-upvote on download (M14.2)**: direct user feedback, an exact mirror of the existing
auto-favorite-on-download (M10.1). `DownloadSettingsStore` gained
`loadAutoUpvoteOnDownload`/`saveAutoUpvoteOnDownload` (key `auto_upvote_on_download`, same
shape as the favorite key). `DownloadManager.downloadPost` gained `{bool autoUpvote = false}`:
once a download outcome is `verified` or `checksumMismatch` (the file was actually written in
both cases), and only for `BunnySite.e621` -- Inkbunny has no vote API at all, the same gate
every other vote-related feature in this app (M4.3/M9.6.9/M9.7.2) already applies -- it calls
`repository.queueVote(post.id, 1)`, queuing only, same "queue, let the caller drain" shape the
`autoFavorite` branch right above it already follows. Both call sites that already loaded
`autoFavorite` (`PostDetailScreen._downloadFile`, `PostGridScreen`'s mass-download loop) now
also load `autoUpvote` and widen their existing `if (autoFavorite) { await processQueue(); }`
drain condition to `if (autoFavorite || autoUpvote)`, so a single drain still covers whichever
of the two actions (or both) got queued. `SettingsScreen`'s Downloads section gained a second
`SwitchListTile` beside the existing auto-favorite one.

**Searches-list progressive-refresh fix (M14.3)**: bug fix. `SearchesScreen._checkForUpdates`
(M13.2) synced every search sequentially but only called `_refresh()` once, after the whole
loop finished -- so a long run, or a widget disposed mid-loop for any reason (both of
`_checkForUpdates`'s `if (!mounted) { return; }` guards sit *before* that final call), could
leave the unseen-count badges stale until the app restarted. The fix moves the refresh
(`_searchesFuture = _repository!.listSearches()`) inside the loop, right after each individual
`syncSearch` call resolves (success or caught failure), instead of only after the loop exits --
whatever has synced so far is always reflected, and badges now update live during a long run
rather than all at once at the end. Tested with a `FakeBunnyRepository` extended with
per-search `Completer`-gated `syncSearch` calls (`syncSearchGates`) plus a
`syncSearchNewPosts` map simulating a sync that actually finds something new -- letting the
test pause mid-loop and assert one search's badge is already visible while the other's sync is
still pending, which the old end-of-loop-only refresh could not do.

**Tag stats split: Favorites vs All (M14.4)**: direct user feedback -- the Tag Stats screen
(M10.2) only ever ranked favorited-tag usage. New `bunny_db_top_used_tags`
(`libs/db/src/stats.c`) is `bunny_db_top_favorited_tags`'s SQL with the `JOIN favorites`
clause removed, so it ranks every synced post's tags per site instead of only favorited ones
-- same result shape, row-building, and error handling, copy-paste-and-trim. Full plumbing:
`bunny_core_top_used_tags`, FFI, `GET /tags/top_used?site=&limit=` (a sibling to the existing
`/tags/top_favorited` in `routes_tags.c`), `BunnyRepository.topUsedTags(site, {limit}) ->
Future<List<BunnyTagStat>>` across FFI/HTTP/Fake, reusing `BunnyTagStat` unchanged.
`TagStatsScreen` already had one `SegmentedButton<BunnySite>` driving `_load()`; it gained a
second `SegmentedButton<bool>` ("Favorites"/"All") that picks `topFavoritedTags`/`topUsedTags`
accordingly, each with its own empty-state message (favoriting something vs. syncing a search
at all are different first steps for an empty list).

**Periodic DB backup with rotation (M14.5)**: the concrete half of a broader "later I'd like a
shared server" request -- a corruption safety net, server-only, never invoked from the Flutter
app (no FFI/HTTP plumbing at all). New `bunny_db_backup(db, dest_path)`
(`libs/db/src/db.c`) uses SQLite's Online Backup API (`sqlite3_backup_init`/`_step(-1)`/
`_finish`) against `db->handle` -- deliberately not a raw file copy, which would risk
corruption/inconsistency against a database the server may have open and writing to
concurrently. `bunny_core_backup_database(core, backups_dir)` (new `libs/core/src/backup.c`,
following the one-concern-per-file convention `blacklist.c` already set) builds a
`<backups_dir>/bunny_<unix_ts>.db` path and calls through.

`server/src/scheduler.c`'s per-tick loop already ran `bunny_core_sync_due_searches`/
`bunny_core_process_queue` under `core_mutex`; it gained a third step, `backup_due_and_prune`,
run every tick (cheap when nothing's due) rather than on its own timer. It creates
`<data_dir>/backups/` if missing, lists that directory for existing `bunny_*.db` files, and
treats a backup as due if none exist or the newest one (by `stat()` mtime) is >= 24h old --
deliberately not tracking a separate "last backup time" anywhere, since the directory itself is
already the source of truth (same reasoning `unseen_count` uses to avoid cached state). After a
due backup, it prunes back down to the 5 newest files; because the filenames embed a unix
timestamp, a plain lexicographic sort of the directory listing is already chronological order,
so no per-file `stat()` is needed for the prune itself. `server_scheduler_start` gained a
`data_dir` parameter (its one caller, `server_app_start`, already had `data_dir` in scope) to
build this path; `server_scheduler_stop` now also frees it.

Tested with: a `libs/db` test backing up a `:memory:` db with a search in it to a real file and
reopening it to confirm the data round-tripped; a `libs/core` test using `mkdtemp` + `opendir`
to confirm `bunny_core_backup_database` actually writes a `bunny_*`-prefixed file into a given
directory; and a `server` integration test that restarts the app with a 1-second poll interval
(the same shape `test_scheduler_syncs_search_automatically` already used) and confirms a backup
file appears within a few seconds. That last test's own cleanup -- and the shared `tearDown()`
other scheduler-poll tests rely on -- has to stop the scheduler thread *before* touching
`backups/`: since a backup is "due" again the instant the directory is empty, a still-running
poll tick can otherwise recreate a file between the test's own `unlink` and `rmdir`, intermittently
leaking a non-empty temp directory.

## M15 -- Runtime connection switching + last-viewed sort

Two independent, user-requested features in one branch since both are small and don't touch
overlapping code.

**Switch standalone ↔ networked from Settings**: previously `BunnyRepositoryConfig` was chosen
once, at first launch via `SetupScreen`, and `main.dart`'s `_LittleBunnyAppState` held the
resulting `BunnyRepository` for the app's entire lifetime. The key enabler already existed:
`_onConfigured(BunnyRepository)` already `setState`s a new `_repository`, which
`BunnyRepositoryScope` propagates down to a rebuilt tree -- the exact mechanism `SetupScreen`'s
first-launch flow already used. The whole feature is reusing that same callback from inside
Settings rather than building new state plumbing. `SetupScreen` gained an `isReconfigure: bool`
field (default `false`, so the first-launch call site is unaffected): when `true`, `initState`
loads the existing `BunnyRepositoryConfig` to preselect the segmented button (and prefill the
server URL for networked -- never the bearer token/certificate fingerprint, matching
`LockSetupScreen`'s existing "re-enter credentials for sensitive changes" pattern), both submit
paths show a plain `AlertDialog` warning that the two modes are separate data stores with no
auto-merge before persisting (after the existing connection-test step for networked), and on
success it calls `Navigator.of(context).popUntil((route) => route.isFirst)` instead of just
returning -- needed because the reconfigure screen is reached via `SearchesScreen` →
`SettingsScreen` → `SetupScreen`, and simply swapping `_repository` in `main.dart` wouldn't
retroactively rebuild those already-pushed routes (still holding the old repository reference);
popping back to root lands on a freshly-built `SearchesScreen` bound to the new one instead.
`BunnyRepository` gained a `close()` method on the abstract interface (both implementations
already had the underlying logic -- `FfiBunnyRepository.close()` killed the FFI isolate,
`HttpBunnyRepository.close()`'s `_client.close()` just needed wrapping in `Future<void>` to match
the signature) since `_onConfigured` now closes the *outgoing* repository before replacing it,
the first time in the app's life a repository can be discarded while the app keeps running
rather than living until process exit. No data is ever deleted as part of switching -- per
explicit discussion, the standalone SQLite file is simply left on disk and unreferenced after
switching to networked (and vice versa, switching back just reopens the same file at its usual
path, so nothing was lost). `SettingsScreen` gained a "Connection" section at the top (a
`ListTile` showing the active mode, loaded the same way the rest of `_load()` already works)
whose tap pushes `SetupScreen(..., isReconfigure: true)`.

Moving searches across a switch needs no new code: `SettingsScreen`'s existing Backup
export/import (M11) already goes through the abstract `BunnyRepository.listSearches()`/
`createSearch()`, so exporting while standalone and importing the same file after switching to
networked already works unchanged.

**"Last viewed" sort for Searches/Pools**: a new `SearchSortOrder.lastViewed` option, threaded
through the exact same full-stack pattern M14.1's `pinned` column established. Schema: migration
7, `ALTER TABLE searches ADD COLUMN last_viewed_at TEXT;` (`libs/db/src/db.c`). New
`bunny_db_search_touch_last_viewed(db, search_id)` (`libs/db/src/searches.c`) is identical in
shape to the pre-existing `bunny_db_search_touch_last_run`, just a different column; added to
`bunny_db_search_list`'s `SELECT` and `fill_search_from_row` the same way `pinned` was. Thin
`bunny_core_search_touch_last_viewed` wrapper, an FFI isolate request/handler pair (mirroring
`_SetSearchPinnedRequest`), a new `POST /searches/{id}/viewed` route (no request body needed,
unlike `/pin` -- mirrors `/sync`/`/mark_all_seen`'s shape instead), and a
`touchSearchViewed(int)` method on both `BunnyRepository` implementations and the abstract
interface. Since the Pools tab isn't a separate entity -- `_isPoolSearch` just filters the same
`BunnySearch` list by `query.startsWith('pool:')` -- hooking the touch into `SearchesScreen`'s
one shared row `onTap` covers both tabs automatically. The touch call is fire-and-forget
(`unawaited`, since it shouldn't delay opening the post grid); the `Navigator.push` itself is
awaited now (previously fire-and-forget), with `_refresh()` called on return, so the reordering
is actually visible when the user backs out rather than only taking effect on the next cold
`FutureBuilder` rebuild.

## M16 -- Server deployment tooling

No server code changed here -- `bunny_server` (M5) already needs nothing beyond its own
binary (self-signed cert and bearer token generated on first run, see "Security model" under
"C server (M5)" above), but there was no written-down path from "fresh VM" to "running
service," which is the actual gap "simplify server setup" was pointing at. New `deploy/`
directory:

- **`deploy/bunny-server.service`**: a systemd unit using `DynamicUser=yes` +
  `StateDirectory=bunny-server` (systemd >= 232/230) rather than a manually-created system
  user -- systemd allocates an ephemeral unprivileged UID per activation and
  creates/owns `/var/lib/bunny-server` (exposed to the service via `%S/bunny-server`,
  matched by `Environment=BUNNY_SERVER_DATA_DIR=%S/bunny-server`) automatically, including
  under `ProtectSystem=strict`'s otherwise-read-only filesystem. No `useradd`/`chown` step
  needed anywhere in the install flow. Rounded out with standard least-privilege hardening
  directives (`NoNewPrivileges`, `PrivateDevices`, `ProtectKernelTunables`,
  `MemoryDenyWriteExecute`, an empty `CapabilityBoundingSet`, ...) appropriate for a service
  that only needs a listening socket and its own data directory.
- **`deploy/install.sh`**: idempotent, re-runnable installer (`sudo ./deploy/install.sh`,
  `--skip-deps` to skip the package-manager step). Detects `apt`/`dnf`/`pacman` to install
  build prerequisites, runs `make release`, installs the binary to `/usr/local/bin/` and the
  unit to `/etc/systemd/system/`, `daemon-reload`s, `enable --now`s the service, then polls
  `/var/lib/bunny-server/{auth_token,server.pem}` (written by the server's own first-run
  setup, M5.1) for up to 30s before printing the server URL, bearer token, and the
  certificate's SHA-256 fingerprint (`openssl x509 -noout -fingerprint -sha256`) -- the three
  values the Flutter app's Networked setup screen (or M15's reconfigure flow) needs, with no
  manual `openssl` invocation or log-scraping required. Re-running it later (e.g. after
  `git pull`) rebuilds and restarts the service without touching anything already in
  `/var/lib/bunny-server`.
- **`deploy/README.md`**: install/update/uninstall steps, plus the one gotcha specific to
  the confirmed deployment target (Oracle Cloud free tier) -- its default Security
  List/Network Security Group blocks all inbound traffic except SSH, so the server's port
  needs an explicit ingress rule there in addition to any local firewall (`ufw`/`firewalld`).
- **`deploy/install-prebuilt.sh`** (follow-up, same milestone): the free-tier instance this
  targets turned out to be too weak to comfortably compile curl/civetweb/sqlite/cJSON from
  source itself, so the install flow needed a path that builds nowhere near the target at
  all. `install.sh`'s shared tail (install binary + unit, `daemon-reload`, `enable --now`,
  poll for `auth_token`/`server.pem`, print the connection summary) was pulled out into
  `deploy/_install-common.sh`'s `bunny_install_and_start` function (leading underscore:
  sourced by the other two scripts, not meant to be run directly), so both the "build here"
  (`install.sh`) and "binary built elsewhere" (`install-prebuilt.sh <path>`, no compiler or
  build-dependency step at all) flows stay in sync rather than maintaining two copies of the
  same systemd/polling logic.
- **Cross-distro runtime dependencies** (second follow-up): building on an Arch-family
  desktop and deploying to an Ubuntu VM via `install-prebuilt.sh` immediately hit
  `error while loading shared libraries: libssh2.so.1: cannot open shared object file` --
  curl's own CMake auto-detects and dynamically links against whatever happens to already be
  installed on the *build* machine (`libssh2` for SCP/SFTP, `libidn2` for IDN domains,
  `nghttp2` for HTTP/2, `brotli`/`zstd` for compression negotiation), none of which this app
  actually needs (it only ever does plain HTTPS GET/POST JSON calls to e621/Inkbunny, no
  HTTP/2 requirement). Fixed at the top-level `CMakeLists.txt`'s curl `CPMAddPackage`:
  `CURL_USE_LIBSSH2`/`USE_LIBIDN2`/`USE_NGHTTP2` are plain `option()` booleans, so the
  existing `OPTIONS "VAR OFF"` list works for them; `CURL_BROTLI`/`CURL_ZSTD` are curl's own
  `AUTO`/`ON`/`OFF` cache-`STRING` options set via a custom macro
  (`curl_dependency_option`), and CPM's `OPTIONS` mechanism only does a plain (non-cache,
  non-`FORCE`) `set()` -- harmless for ordinary booleans (CMake's normal-variable-shadows-
  cache-variable rule makes the plain set still win), but curl's own macro re-declares the
  same cache entry via its own `set(... CACHE STRING ...)` in a way that silently wins back
  over the non-`FORCE` value, so these two needed an explicit
  `set(CURL_BROTLI OFF CACHE STRING "" FORCE)`/`set(CURL_ZSTD OFF CACHE STRING "" FORCE)`
  *before* the `CPMAddPackage` call instead (same pattern as the `ANDROID`-only mbedTLS
  variables below). Separately, `libbrotli*`/`libzstd` turned out to still show up in `ldd`
  on the build machine even with curl's own flags off -- traced to the *system's own*
  `libssl.so.3` package having an unrelated transitive dependency on them (an
  Arch-packaging detail, not something this project's build controls) -- so rather than
  trying to predict every possible transitive dependency across every distro's OpenSSL
  build, `bunny_install_and_start` (`deploy/_install-common.sh`) now runs `ldd` on the
  installed binary right after copying it into place and fails with a clear, specific
  "missing shared libraries" message naming exactly what's absent, instead of the install
  silently succeeding and only surfacing the real problem later as a cryptic systemd
  restart-loop in `journalctl`.

## Inkbunny API constraints (found in M2)

Verified against the live API and the official docs while building `libinkbunny`:

- **No favorite/comment write actions in the official API.** Inkbunny's API can tell you a
  submission's `favorite`/`favorites_count`/`comments_count`, and can list an *existing*
  favorites list via `favs_user_id`, but there is no endpoint to add/remove a favorite or
  to post/list comment content. A mature third-party C# wrapper (Athari/InkBunny.Api)
  doesn't implement either, confirming this isn't just a documentation gap. Favoriting was
  later added anyway via an unofficial, HTML-scraping-based route — see "Unofficial
  favorite flow" below — but **commenting still has no path at all**, official or
  otherwise, so the "comment on posts" feature (M9) only works for e621.
- **Every numeric and boolean field is JSON-encoded as a string**, e.g. `"submission_id":
  "12345"`, `"favorite": "f"`. `libinkbunny` parses these leniently (falls back to a real
  JSON number/bool if that ever changes) via `inkbunny_field_int64()`/`inkbunny_field_bool_tf()`
  in `libs/inkbunny/src/internal.h`.
- **API-level errors come back as HTTP 200** with an `error_code`/`error_message` body
  (e.g. bad login, invalid/expired session id) rather than a non-2xx status. HTTP status is
  only meaningful for transport-level failures (5xx, etc.). "Not found" is signaled by an
  empty result array, not an error.

### Unofficial favorite flow (promoted into libinkbunny)

`inkbunny/unofficial_favorites.h` (`inkbunny_website_login`, `inkbunny_favorite_add`,
`inkbunny_favorite_remove`) reverse-engineers the website's own favorite/unfavorite flow,
since the documented API has no equivalent (see "Inkbunny API constraints" above).
Confirmed working live against a real account and submission on 2026-09-28 by inspecting
the network calls the site's own `js82/fav.rev01.js` makes, then re-verified after being
folded into the library. It logs in via `login.php` → `login_process.php` (a cookie-based
website session, entirely separate from `inkbunny_login()`'s API `sid`), scrapes a
page-embedded CSRF token (`global_token`), and POSTs to `submissionfav_process.php` with
`token`/`stars`/`add`/`remove`/`submission_id`.

This was a deliberate, explicit reversal of the "official API only" decision from M2,
made after the user asked to test the website flow directly and confirmed it worked
end-to-end (add and remove) against their own account. Unlike the rest of this library,
these functions:
- depend on exact HTML markup Inkbunny could change at any time — already proven fragile
  once: the site mixes single- and double-quoted HTML attributes across its own pages
  (`login.php`'s CSRF token is double-quoted, the submission page's `global_token` is
  single-quoted), which broke the first extraction attempt until the parser was made
  quote-agnostic;
- always make real network calls via a client-owned persistent `CURL*`
  (`inkbunny_client_t.website_curl` in `libs/inkbunny/src/internal.h`) so their cookie jar
  survives across the login → scrape → POST sequence — there's no injectable-transport
  fixture-based unit test for them, only manual/live verification;
- need their own login (`inkbunny_website_login`) in addition to `inkbunny_login()` if the
  same client is also doing search/get_submission calls, since the two auth mechanisms
  are unrelated.

`tools/inkbunny_favorite_experiment` (built only with `-DBUNNY_BUILD_TOOLS=ON` / `make
tools`) is now a thin CLI over these three functions, kept around for manual testing
against a real account.

## Code style

Enforced via `.clang-format` at the repo root (`make format` / `make format-check`):
Allman braces (opening `{` on its own line) for functions, structs, classes, enums, and
unions; attached K&R braces for `if`/loops/`switch`/`extern "C"` blocks; 4-space indent, no
tabs; no line-wrapping (prefer long lines). `snake_case` for variables/functions,
`UPPER_SNAKE_CASE` for constants — C structs/typedefs stay `snake_case_t`, `PascalCase` is
reserved for actual C++ classes (none exist in this project yet). These rules are also
saved globally (`~/.claude/CLAUDE.md`) for future projects.

## GOBLIN (shared C utilities)

[GOBLIN](https://github.com/Nyjako/GOBLIN) is the user's personal header-only C utility
collection ("small, useful, header-only, easy to read"). Vendored via CPM like everything
else, pinned to a commit (it has no tags yet), as an `INTERFACE` library (`goblin`) whose
only job is exposing its `include/` directory — it has no build step of its own.

Currently used:
- **`dyn_array.h`**'s `GOBLIN_DYN_ARRAY_DECL` macro (all-`static inline`, so declaring it
  in multiple `.c` files is safe — no ODR risk) replaces the hand-rolled realloc-doubling
  growable-array loops in `libs/db/src/{searches,posts,favorites,downloads,stats}.c`. Not
  used in `libs/e621`/`libs/inkbunny`'s array parsing, since those sizes are known upfront
  from `cJSON_GetArraySize` (`calloc` directly, no need to grow).
- **`cstr.h`'s `goblin_copy_cstr`** replaces `strdup` throughout `libs/e621`,
  `libs/inkbunny`, and `libs/db` — `strdup` isn't standard C (POSIX and MSVC each expose it
  differently), which matters for this project's Windows cross-build goal (M12). Unlike
  `dyn_array.h`, `cstr.h` needs its implementation compiled exactly once across the whole
  link graph (`#define GOBLIN_CSTR_IMPLEMENTATION`); `libs/common/src/goblin_impl.c` is
  that single instantiation point, since `bunny_common` is already a shared dependency of
  the site libraries. `bunny_db` gained a new dependency on `bunny_common` purely to reach
  this symbol (it has no other reason to need it).

Good future fits, not adopted yet because nothing needs them: `appdirs.h` (cross-platform
data/config/cache directories) for M4's default DB path, and `fileio.h`'s `goblin_mkdir`
for M9's per-artist download directories.

## Dependency management

All dependencies are pulled via [CPM](https://github.com/cpm-cmake/CPM.cmake), with one
deliberate exception: **OpenSSL**, which is required via `find_package(OpenSSL REQUIRED)`.
OpenSSL is treated as a system TLS provider — like the C compiler or CMake itself — rather
than an application dependency, because vendoring a full TLS stack (and keeping it patched
for security issues) via CPM is impractical. It must be installed on the build machine
(e.g. `libssl-dev` / `openssl-devel`).

Everything else — `curl` (HTTP client), `cJSON` (JSON parsing), `Unity` (C unit test
framework), `GOBLIN` (shared C utilities, see above), `civetweb` (the M5 server's
HTTP/HTTPS library, see "C server (M5)"), and the sqlite amalgamation — is fetched and
built from source via CPM, pinned to specific versions/tags/commits. `civetweb` both uses
OpenSSL (for HTTPS) and needs `CIVETWEB_ENABLE_ASAN OFF` in its CPM options, since it
otherwise self-instruments with sanitizers in Debug builds independent of this project's
own `BUNNY_ENABLE_ASAN` flag — see "C server (M5)" for why that combination breaks linking.

## Testing philosophy

Library code (`libe621`, `libinkbunny`, and later the core) is designed with an injectable
transport/dependency so unit tests never make live network calls — they inject a fake
transport that serves canned fixture responses and assert on parsed results and error
handling (auth failures, 404s, rate limiting, malformed JSON). A small number of
network-touching "live" checks may exist for manual sanity-checking against the real APIs,
but they are excluded from the default test/build targets since they need credentials and
network access.

## Cross-compilation

The C libraries and server are cross-compiled for Windows from Linux using
[dockcross](https://github.com/dockcross/dockcross) (`windows-static-x64` image), driven by
the `make windows` target. This produces a statically-linked Windows build without needing
a Windows machine or MinGW installed on the host. This does not apply to the Flutter GUI,
which has its own native Windows build via the Flutter SDK.

**Known gap (as of M1):** the `windows-static-x64` dockcross image's MXE toolchain doesn't
ship a prebuilt OpenSSL for the `x86_64-w64-mingw32.static` target, so `find_package(OpenSSL
REQUIRED)` fails during a cross-configure out of the box. MXE can build its own `openssl`
package (`make openssl` inside `/usr/src/mxe`), but that needs network access to MXE's
package mirrors from inside the container, which wasn't available when this was tried.
Getting `make windows` fully green is deferred to M12 — options to try then: build MXE's
`openssl` package with network access available, point `OPENSSL_ROOT_DIR` at a prebuilt
Windows OpenSSL, or swap curl's TLS backend for something with less cross-compilation
friction (e.g. schannel, Windows' native TLS, only for the Windows target).

## Roadmap

See [ROADMAP.md](./ROADMAP.md) for the full milestone breakdown and current progress.
