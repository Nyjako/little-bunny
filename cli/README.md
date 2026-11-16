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

Every command above (except `--whoami`/`--help`/`--version`) needs
standalone mode -- see the limitation below.

## Current limitation

Only standalone mode (a local database, no separate server) is actually
usable today -- `bunny_cli` already recognizes networked mode via the
handshake above, but talking to a `bunny_server` instance over its REST API
needs its own HTTP client, which hasn't been built yet. Running any command
while your app is set up in networked mode will tell you so and exit
cleanly, rather than guessing.

## Staying in sync with the app (low priority, not done yet)

`bunny_cli` speaks a specific JSON shape over the handshake protocol, tied
to whatever version of the app it's paired with -- it ships in the same
release zip as the app today, but the app's own self-update mechanism
(`UpdateApplyService`/`bunny_updater`, M23) only replaces the app's own
Flutter bundle, not `bunny_cli` sitting next to it. If the handshake
protocol ever changes between versions, a self-updated app paired with a
stale `bunny_cli` could silently break. Nothing enforces or even checks
this yet -- worth teaching the updater to also fetch/replace `bunny_cli`
when it replaces the app, or at minimum having `bunny_cli` report a clear
"protocol version mismatch" error instead of a confusing one.
