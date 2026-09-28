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
