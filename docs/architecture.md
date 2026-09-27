# Architecture

LittleBunny is an e621 + Inkbunny viewer/manager with three moving parts.

## Components

1. **Server** (C, CMake, CPM, SQLite, Linux) — owns the sync state. Stores encrypted
   e621/Inkbunny credentials, runs scheduled searches (24h default), tracks seen/unseen
   posts per device, and proxies favorite/vote/comment actions to the sites so any device
   can trigger them without needing its own site session. **Inkbunny is the exception**:
   its API has no favorite/comment write actions at all (see "Inkbunny API constraints"
   below), so the server can only proxy those for e621.
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

## Inkbunny API constraints (found in M2)

Verified against the live API and the official docs while building `libinkbunny`:

- **No favorite/comment write actions.** Inkbunny's API can tell you a submission's
  `favorite`/`favorites_count`/`comments_count`, and can list an *existing* favorites list
  via `favs_user_id`, but there is no endpoint to add/remove a favorite or to post/list
  comment content. A mature third-party C# wrapper (Athari/InkBunny.Api) doesn't implement
  either, confirming this isn't just a documentation gap. Decided with the user to only
  ever use the official API (not reverse-engineer the website's internal AJAX calls), so
  `libinkbunny` simply doesn't expose those actions. This means the "mass favorite" /
  "comment on posts" features (M9) only work for e621.
- **Every numeric and boolean field is JSON-encoded as a string**, e.g. `"submission_id":
  "12345"`, `"favorite": "f"`. `libinkbunny` parses these leniently (falls back to a real
  JSON number/bool if that ever changes) via `inkbunny_field_int64()`/`inkbunny_field_bool_tf()`
  in `libs/inkbunny/src/internal.h`.
- **API-level errors come back as HTTP 200** with an `error_code`/`error_message` body
  (e.g. bad login, invalid/expired session id) rather than a non-2xx status. HTTP status is
  only meaningful for transport-level failures (5xx, etc.). "Not found" is signaled by an
  empty result array, not an error.

## Dependency management

All dependencies are pulled via [CPM](https://github.com/cpm-cmake/CPM.cmake), with one
deliberate exception: **OpenSSL**, which is required via `find_package(OpenSSL REQUIRED)`.
OpenSSL is treated as a system TLS provider — like the C compiler or CMake itself — rather
than an application dependency, because vendoring a full TLS stack (and keeping it patched
for security issues) via CPM is impractical. It must be installed on the build machine
(e.g. `libssl-dev` / `openssl-devel`).

Everything else — `curl` (HTTP client), `cJSON` (JSON parsing), `Unity` (C unit test
framework), and later the sqlite amalgamation and an embeddable HTTP server library — is
fetched and built from source via CPM, pinned to specific versions/tags.

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
