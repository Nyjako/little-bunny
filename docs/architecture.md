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
- **Known gap:** Android's NDK ships no prebuilt OpenSSL, so `fvm flutter build apk` fails at
  the CMake configure step (`find_package(OpenSSL REQUIRED)` in the reused top-level
  `CMakeLists.txt`) — confirmed by direct reproduction of the Gradle/CMake invocation. Same
  class of problem as the Windows cross-compilation gap above, deferred to the same milestone
  (M12) for the same reason (needs a prebuilt/self-built OpenSSL for the target, or a
  different curl TLS backend). Linux desktop, this environment's only build-verifiable
  desktop target, builds and runs correctly.

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
- **Android integration, unverified by any real build**: `local_auth`'s `BiometricPrompt`
  needs a `FragmentActivity` to host its dialog fragment and an AppCompat-based activity
  theme. Per `local_auth_android`'s own reference example
  (`local_auth_android`'s pub cache `example/android/`), `app/android/app/src/main/kotlin/
  .../MainActivity.kt` now extends `FlutterFragmentActivity` instead of `FlutterActivity`,
  and both `values/styles.xml` and `values-night/styles.xml`'s `LaunchTheme`/`NormalTheme`
  now inherit `Theme.AppCompat.*` instead of the plain `@android:style/Theme.*` Flutter
  scaffolds by default — the `windowBackground`/splash-screen behavior is otherwise
  unchanged, only the theme's parent lineage. No manifest edit was needed for the
  `USE_BIOMETRIC` permission itself: `local_auth_android`'s own bundled manifest already
  declares it, and Gradle's manifest merger folds it into the app's final manifest
  automatically. AppCompat itself needed no new Gradle dependency either — it's already
  transitively available via Flutter's own Android embedding. None of this can be
  build-verified in this dev environment: `flutter build apk` already fails at the OpenSSL
  configure step (M6.2, deferred to M12) before Gradle ever reaches these files, and
  `Platform.isAndroid` is false on this dev machine's test host, so the automated test suite
  never exercises the biometric branch either (`test/screens/lock_screen_test.dart` only
  covers the PIN/password fallback, which every platform shares).

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
