# LittleBunny

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
make build            # debug build with tests enabled
make test             # build + run the test suite
make release          # optimized build, tests disabled
make release-portable # like release, but built inside a pinned Ubuntu 22.04 container
                       # (Docker required) for a binary that runs on other Linux machines --
                       # see "Running the server" below
make clean            # remove all build directories
```

### Cross-compiling for Windows

Requires Docker. Uses [dockcross](https://github.com/dockcross/dockcross)'s
`windows-static-x64` image to produce a statically-linked Windows build from Linux:

```sh
make windows
```

## Running the server

For networked mode (multiple devices syncing against one server instead of each using its
own standalone/offline database), `bunny_server` can be installed as a systemd service with
one command on a fresh Linux VM:

```sh
sudo ./deploy/install.sh
```

If the target machine isn't powerful enough to build on comfortably, build elsewhere
(`make release-portable` -- not plain `make release`, unless the build machine runs the
exact same distro/version as the target, since glibc/OpenSSL symbol compatibility only
goes one direction) and install just the resulting binary instead -- no compiler needed on
the target at all:

```sh
sudo ./deploy/install-prebuilt.sh /path/to/bunny_server
```

See [`deploy/README.md`](deploy/README.md) for details, firewall notes, and how to update
or uninstall it.
