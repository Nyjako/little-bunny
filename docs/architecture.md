# Architecture

LittleBunny is an e621 + Inkbunny viewer/manager with three moving parts.

## Components

1. **Server** (C, CMake, CPM, SQLite, Linux) — owns the sync state. Stores e621/Inkbunny
   credentials, runs scheduled searches (24h default), tracks seen/unseen posts per device,
   and proxies favorite/vote/comment actions to the sites so any device can trigger them
   without needing its own site session. **Inkbunny is the exception**: its API has no
   favorite/comment write actions at all (see "Inkbunny API constraints" below), so the
   server can only proxy those for e621.
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
framework), `GOBLIN` (shared C utilities, see above), and the sqlite amalgamation — is
fetched and built from source via CPM, pinned to specific versions/tags/commits.

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
