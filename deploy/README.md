# Deploying `bunny_server`

`bunny_server` (see [`docs/architecture.md`](../docs/architecture.md)'s "C server (M5)"
section) is a single self-contained binary: no reverse proxy, no manually-issued TLS
certificate, no separate database server. On first run it generates its own self-signed
certificate and a bearer token, both under its data directory. This directory turns that
into a one-command install on a fresh Linux VM (the confirmed target is an Oracle Cloud
free-tier instance, but any systemd-based distro works).

## Install

On the target machine, as root:

```sh
git clone https://github.com/Nyjako/little-bunny.git
cd little-bunny
sudo ./deploy/install.sh
```

This installs build prerequisites (a C compiler, CMake, OpenSSL headers -- pass
`--skip-deps` if you've already got them), runs `make release`, installs the resulting
binary to `/usr/local/bin/bunny_server`, installs [`bunny-server.service`](bunny-server.service)
to `/etc/systemd/system/`, and starts it via `systemctl enable --now`. At the end it
prints the server URL, bearer token, and certificate fingerprint -- enter those into the
Flutter app's Setup screen (or Settings -> "Switch connection mode") under "Networked".

**Before connecting from outside the machine**, open the port (8443 by default) in:
- the host's own firewall (`ufw allow 8443`, `firewall-cmd --add-port=8443/tcp
  --permanent && firewall-cmd --reload`, or the equivalent `iptables` rule), and
- your cloud provider's ingress rules -- Oracle Cloud's default Security List/Network
  Security Group blocks everything but SSH out of the box.

## Installing a binary built elsewhere

If the target machine isn't powerful enough to comfortably compile the dependency chain
(curl, civetweb, ...) itself, build on another machine first and copy just the binary
over. Use `make release-portable`, **not** plain `make release`, unless the build machine
is running the exact same distro/version as the target:

```sh
# on the build machine (requires Docker; the host's own compiler/CMake/OpenSSL are
# never used -- the whole build runs inside an ubuntu:22.04 container)
git clone https://github.com/Nyjako/little-bunny.git
cd little-bunny
make release-portable
scp build-release-portable/server/bunny_server you@target:/tmp/bunny_server
```

**Why not plain `make release`**: glibc and OpenSSL's symbol versioning is
forward-compatible only -- a binary built against a *newer* glibc/OpenSSL than the target
has can't run there at all (`error while loading shared libraries: ...: version
'GLIBC_2.43' not found`), even on the same CPU architecture. This bit us for real building
on a rolling-release desktop (glibc 2.43) and deploying to an Oracle Cloud Ubuntu instance
(glibc nowhere near that new). `make release-portable` builds inside a pinned `ubuntu:22.04`
container instead (glibc 2.35, OpenSSL 3.0.x) -- old enough that the resulting binary runs
on effectively every currently-supported Ubuntu/Debian release, new enough to share the
same OpenSSL 3.x SONAME every current distro ships. curl's own optional extras this app
never uses (SCP/SFTP via libssh2, IDN domains via libidn2, HTTP/2 via nghttp2) are also
explicitly disabled in the build, so they're never a concern either way; either way,
`install-prebuilt.sh` also runs `ldd` on the installed binary before starting the service
and fails with a clear message naming any library that's still missing on the target,
rather than leaving you to dig through `journalctl` for an opaque "exit code 127".

```sh
# on the target machine
git clone https://github.com/Nyjako/little-bunny.git   # just for deploy/, nothing is built here
cd little-bunny
sudo ./deploy/install-prebuilt.sh /tmp/bunny_server
```

`install-prebuilt.sh` never touches a compiler or installs build dependencies -- it only
installs the given binary, the systemd unit, starts the service, and prints the same
server URL/bearer token/fingerprint summary `install.sh` does.

## Operating

```sh
systemctl status bunny-server     # is it running
journalctl -u bunny-server -f     # tail logs
systemctl restart bunny-server    # restart
```

Data (SQLite database, TLS cert, auth token) lives in `/var/lib/bunny-server`, a systemd
`StateDirectory` tied to the unit's lifecycle -- it survives service restarts and
upgrades, but is removed if the unit itself is ever `systemctl clean`ed or the state
directory is deleted by hand.

## Updating

As of M23, this happens automatically: the server checks GitHub for a new release once
a day (as part of its existing scheduler tick), and if one's out, downloads, extracts,
and verifies it in the background, then exits cleanly to let systemd (`Restart=always`)
restart it -- `bunny-server-update-apply.sh`, installed as root via the unit's
`ExecStartPre=+`, is what actually swaps the new binary into `/usr/local/bin` right
before the restarted process starts (the main server process itself never has
permission to write there, by design -- see `server/src/updater.c`). Nothing to do;
`journalctl -u bunny-server -f` shows `updater: ...` log lines when it runs.

To update manually anyway (or if outbound internet to GitHub is blocked):

```sh
cd little-bunny
git pull
sudo ./deploy/install.sh --skip-deps
```

Re-running the installer rebuilds and replaces the binary, then restarts the service.
Existing data, the auth token, and the TLS certificate are untouched (nothing in
`/var/lib/bunny-server` is ever written by the installer itself, only by `bunny_server`
on its own first run). If you're building elsewhere, the same idea applies to
`install-prebuilt.sh`: rebuild, re-copy the binary over, re-run it.

## Uninstalling

```sh
sudo systemctl disable --now bunny-server
sudo rm /etc/systemd/system/bunny-server.service /usr/local/bin/bunny_server
sudo systemctl daemon-reload
sudo rm -rf /var/lib/bunny-server   # irreversible -- deletes the database, cert, and token
```

## Changing the port or sync interval

Edit `/etc/systemd/system/bunny-server.service`, uncomment/adjust the relevant
`Environment=BUNNY_SERVER_*` line (see [`bunny-server.service`](bunny-server.service) for
the full list, or `server/src/config.c` for everything the binary reads), then:

```sh
sudo systemctl daemon-reload
sudo systemctl restart bunny-server
```
