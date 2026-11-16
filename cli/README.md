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
- `--help`, `--version`.

More commands (continuing the download queue, running searches, dumping
pool/post data as JSON, ...) are landing in follow-up changes, each
following the same pattern established here.

## Current limitation

Only standalone mode (a local database, no separate server) is actually
usable today -- `bunny_cli` already recognizes networked mode via the
handshake above, but talking to a `bunny_server` instance over its REST API
needs its own HTTP client, which hasn't been built yet. Running any command
while your app is set up in networked mode will tell you so and exit
cleanly, rather than guessing.
