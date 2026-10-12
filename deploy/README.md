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

```sh
cd little-bunny
git pull
sudo ./deploy/install.sh --skip-deps
```

Re-running the installer rebuilds and replaces the binary, then restarts the service.
Existing data, the auth token, and the TLS certificate are untouched (nothing in
`/var/lib/bunny-server` is ever written by the installer itself, only by `bunny_server`
on its own first run).

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
