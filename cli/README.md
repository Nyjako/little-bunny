# bunny_cli

A pure-C command-line tool for driving LittleBunny without the Flutter app's
own UI running -- continuing a stalled download queue, running ad-hoc
searches/pool lookups, and general debugging, with colorful, leveled logs.

## How it finds your data (no `--db`/`--server` flag)

`bunny_cli` never asks you for a database path or server address directly.
Instead, it must sit in the **same directory** as the app's own executable
(`little_bunny` / `little_bunny.exe`) -- the release zip already places them
there together. On startup it briefly launches the app in a hidden mode,
which reports its currently configured repository (your standalone database
path, or your networked server's URL/token/certificate) back over a private
pipe only the two processes share, then exits immediately. That data is
never written to disk and never visible to any other process.

If you have app-lock (a PIN/password) enabled, you'll need to supply it:

```
bunny_cli --unlock <your-pin-or-password> --whoami
```

Leaving `--unlock` off and running from a real terminal prompts you for it
interactively, with the input hidden -- the same as a password prompt.
Running without a terminal attached (e.g. a scheduled script) and without
`--unlock` fails outright rather than hanging, since there's nowhere to
prompt.

## Commands

- `--whoami` -- shows which repository config bunny_cli resolved (with the
  bearer token, if any, shown only as a redacted length, never its value).
- `--search <e621|inkbunny> <query> [--page N]` -- runs a live search
  against the site (the same "fetch and cache" call the app's own
  tag-browse screen uses), dumping the resulting posts as a JSON array to
  stdout -- pipe it into `jq` or similar.
- `--pool <pool_id>` -- fetches an e621 pool's own metadata (name,
  description, post count, and every pool it cross-references in that
  description) as a JSON object to stdout. e621 only -- Inkbunny has no
  pool-metadata endpoint.
- `--stats` -- prints row counts per database table and runs an integrity
  check, same shape as `bunny_server --db-stats`/`--health`.
- `--download [--jobs N]` -- drains the whole download queue using up to
  `N` concurrent workers (default 3, capped at 8), writing files to the
  exact same folder/filename scheme the app itself uses.
- `--favorite <post_id> [--stars N]` -- favorites a post and drains the
  action queue immediately (`N` is Inkbunny's 1-3 tier; ignored on e621).
- `--unfavorite <post_id>` -- unfavorites a post, same immediate-drain
  behavior.
- `--vote <post_id> <score>` -- votes on a post (`score` is `-1`, `0`, or
  `1`). e621 only -- Inkbunny has no vote API, so a vote queued against an
  Inkbunny post always fails once processed.
- `--sync [search_id]` -- without an id, syncs every saved search that's
  currently due (same as the app's own background timer); with an id,
  forces that one search to sync right now regardless of due-ness. Prints a
  colored summary (searches checked/synced, posts upserted/new).
- `--blacklist-list <e621|inkbunny>` -- dumps a site's tag blacklist as a
  JSON array of strings.
- `--blacklist-add <e621|inkbunny> <tag>` / `--blacklist-remove <e621|inkbunny> <tag>`
  -- adds/removes one blacklist rule. `tag` is validated under that site's
  own tag-query grammar before being stored.
- `--queue-list` -- dumps the whole download queue (every row, any status)
  as a JSON array -- debugging/scripting, not meant for a human to read
  directly.
- `--help`, `--version`.

## Networked mode

If your app is set up against a `bunny_server` instance instead of a local
database, `bunny_cli` talks to it over the exact same REST surface the app's
own `HttpBunnyRepository` uses (`docs/architecture.md`'s "C server (M5)"
section) -- the server's self-signed certificate is pinned by the SHA-256
fingerprint the handshake reports (trust-on-first-use, no CA involved, same
model as the app's own certificate pinning).

Every command works over the network today **except** `--stats` -- the
server has no REST endpoint exposing table row counts/integrity (its
`/health` only smoke-tests the HTTPS listener itself). Running `--stats`
while your app is set up in networked mode tells you so and exits cleanly,
rather than guessing.

Two commands work a little differently in networked mode:

- **`--download`/`--queue-list`**: the download queue is purely client-side
  (the server never proxies binary downloads) -- in networked mode these
  operate on the app's own small local queue database (the handshake's
  `downloadQueueDbPath`, the exact same db `HttpBunnyRepository` itself
  uses), resolving each queued post's own metadata via a real `GET
  /posts/{id}` call before downloading its file straight from the site's
  CDN, same as standalone mode. This is exactly what lets you continue a
  stalled queue with the app not running at all, in either mode. If the app
  reports no queue database path at all (an app build from before this
  existed), these two fail with a clear error instead of guessing -- every
  other networked command is unaffected.
- **`--sync`**: the server's own sync (`POST /sync` or `POST
  /searches/{id}/sync`) only enqueues the work onto the server's own task
  queue and returns immediately -- the server runs it in the background on
  its own. This command just triggers it and reports whether the server
  accepted the request; it never waits for or prints sync stats the way
  standalone mode does (those are only ever visible via `GET /sync/status`
  or the app's own UI).

## Staying in sync with the app

`bunny_cli` speaks a specific JSON shape over the handshake protocol, tied
to whatever version of the app it's paired with -- this used to be a real
risk, since the app's own self-update mechanism (`UpdateApplyService`,
`app/lib/services/update_apply_service.dart`) only seemed to replace the
app's own Flutter bundle, not `bunny_cli` sitting next to it.

It's not actually a problem: on Linux, `UpdateApplyService._applyLinux`
walks *every* file inside the downloaded update's `bundle/` directory
recursively and copies each one over the matching path in the real install
directory, with no filtering by name/extension -- and `bunny_cli` now ships
packaged inside that exact same `bundle/` directory (`.github/workflows/
release.yml`'s `build-cli-linux`/`build-app-linux` jobs). So a self-update
already replaces `bunny_cli` in lockstep with the app, automatically,
executable bit and all, with zero code changes needed -- verified by
running `_extractArchive`/`_applyLinux`'s exact logic against a fake
update tarball containing a `bunny_cli` file and confirming it lands in the
install directory, updated and still executable. `_applyWindows` (`xcopy
/E /Y /I`) copies its whole extracted tree the same unfiltered way, so the
same will hold once Windows CI packaging (deferred, see the release.yml
comment) adds `bunny_cli.exe` to that zip too -- nothing else to build for
that side of it.
