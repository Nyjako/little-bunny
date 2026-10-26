# LittleBunny

[![Test](https://github.com/Nyjako/little-bunny/actions/workflows/test.yml/badge.svg?branch=dev)](https://github.com/Nyjako/little-bunny/actions/workflows/test.yml)
[![Release](https://github.com/Nyjako/little-bunny/actions/workflows/release.yml/badge.svg)](https://github.com/Nyjako/little-bunny/actions/workflows/release.yml)
[![Latest release](https://img.shields.io/github/v/release/Nyjako/little-bunny)](https://github.com/Nyjako/little-bunny/releases/latest)

An e621 + Inkbunny viewer and manager: saved searches that update on a schedule, mark
unseen posts, mass like/favorite/download, comment, and keep everything in sync across
devices — with a fully offline standalone mode too.

See [docs/architecture.md](docs/architecture.md) for how the pieces fit together and
[docs/ROADMAP.md](docs/ROADMAP.md) for the milestone-by-milestone plan and current
progress.

## Layout

- `libs/common` — shared HTTP transport + JSON helpers used by the site client libraries.
- `libs/e621` — standalone, reusable e621 API client library.
- `libs/inkbunny` — standalone, reusable Inkbunny API client library.
- `server/` — the C server that owns sync state for networked mode.
- `app/` — the Flutter GUI (desktop + mobile).
- `deploy/` — systemd service + install script for running `bunny_server` on a VM.

## Building

Prerequisites: a C11 compiler, CMake (>= 3.21), and OpenSSL development headers
(`libssl-dev` on Debian/Ubuntu, `openssl-devel` on Fedora). Every other dependency
(curl, cJSON, Unity, ...) is fetched and built from source via
[CPM](https://github.com/cpm-cmake/CPM.cmake) — no other manual installs needed.

```sh
make build            # debug build (C server + libs) with tests enabled
make test             # test-c + test-flutter -- the full suite, same split test.yml runs in CI
make test-c           # build + run just the C test suite (ctest)
make test-flutter     # build libbunny_core_ffi.so + run bunny_core_ffi's and app's Flutter tests
                       # (requires Flutter via fvm, pinned by app/.fvmrc, and the Linux desktop
                       # build deps: ninja-build libgtk-3-dev pkg-config libsecret-1-dev)
make release          # optimized build, tests disabled -- pass BUNNY_BUILD_NUMBER=N to stamp
                       # a version (release.yml does this with the CI run number)
make release-portable # like release, but built inside a pinned Ubuntu 22.04 container
                       # (Docker required) for a binary that runs on other Linux machines --
                       # see "Deploying the server" below
make windows           # cross-compile the server for Windows from Linux (see below)
make dockcross         # fetch the dockcross windows-static-x64 helper script (used by `windows`)
make tools             # debug build with BUNNY_BUILD_TOOLS=ON (one-off maintenance/debug tools)
make app-linux         # flutter build linux (release) for app/
make app-android       # flutter build apk (release) for app/
make format            # clang-format every C/C++ source in place
make format-check      # clang-format --dry-run --Werror -- what CI runs, fails on any diff
make clean             # remove every build directory this Makefile can produce (C, Windows,
                       # FFI, and the Flutter app's own build/ output)
```

### Cross-compiling for Windows

Requires Docker. Uses [dockcross](https://github.com/dockcross/dockcross)'s
`windows-static-x64` image to produce a statically-linked Windows build from Linux:

```sh
make windows
```

## Deploying the server

For networked mode (multiple devices syncing against one server instead of each using its
own standalone/offline database), `bunny_server` can be installed as a systemd service with
one command on a fresh Linux VM:

```sh
git clone https://github.com/Nyjako/little-bunny.git
cd little-bunny
sudo ./deploy/install.sh
```

This installs build prerequisites, runs `make release`, installs the binary to
`/usr/local/bin/bunny_server`, installs the systemd unit, and starts the service -- printing
the server URL, bearer token, and certificate fingerprint to enter into the app's "Networked"
setup screen.

If the target machine isn't powerful enough to build on comfortably, build elsewhere
(`make release-portable` -- not plain `make release`, unless the build machine runs the
exact same distro/version as the target, since glibc/OpenSSL symbol compatibility only
goes one direction) and install just the resulting binary instead -- no compiler needed on
the target at all:

```sh
sudo ./deploy/install-prebuilt.sh /path/to/bunny_server
```

See [`deploy/README.md`](deploy/README.md) for the full walkthrough, firewall notes, and how
to uninstall it.

### Operator CLI

`bunny_server` doubles as its own ops tool -- run any of these against an already-deployed
`data_dir` (defaults to `/var/lib/bunny-server` if `BUNNY_SERVER_DATA_DIR` isn't set, matching
the systemd unit) without needing to stop the live service first, except where noted:

```
bunny_server --help       # usage, build number, and this flag list
bunny_server --version    # print the build number and exit
bunny_server --qr         # print a connection QR code for the app's "Networked" setup
bunny_server --status     # data dir/port/token/cert/public IP info -- safe while the service is live
bunny_server --health     # pass/fail sanity checks, exit 0/1 -- safe while the service is live,
                           # suitable for cron/monitoring
bunny_server --db-stats   # row counts per database table -- safe while the service is live
bunny_server --update     # check for and stage an update right now (see "Updating" below) --
                           # needs root, stops/restarts the bunny-server service itself
                           # (Linux/systemd only)
```

### Updating

Two ways to pick up a new release, both Linux/systemd only:

- **Automatic (default, no action needed).** The running service checks GitHub for a new
  release once a day as part of its own scheduler tick; if one's out, it downloads, verifies,
  and stages it in the background, then exits cleanly so systemd (`Restart=always`) brings it
  back up on the new binary. Watch it happen with `journalctl -u bunny-server -f`.
- **On demand**, as root, to update right now instead of waiting for the daily check:

  ```sh
  sudo bunny_server --update
  ```

  This stops the `bunny-server` service, runs the same check/download/verify/stage sequence
  the automatic path uses, and always restarts the service again afterward regardless of the
  outcome (up to date, staged, or errored) -- so it's never left stopped by a failed check.

See [`deploy/README.md`](deploy/README.md#updating) if outbound internet to GitHub is blocked
and you need to rebuild from a `git pull` instead.
