#!/usr/bin/env bash
# Builds bunny_server (the C server, see docs/architecture.md's "C server
# (M5)" section) and installs it as a systemd service. Meant for a fresh
# Linux VM with no manual TLS/proxy setup -- the server already generates
# its own self-signed certificate and bearer token on first run (M5.1); this
# script's only job is getting that binary running unattended and handing
# back the two values the Flutter app's "Networked" setup screen needs.
#
# Usage: sudo ./deploy/install.sh [--skip-deps]
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "error: run as root (sudo $0)" >&2
    exit 1
fi

SKIP_DEPS=0
for arg in "$@"; do
    case "$arg" in
        --skip-deps) SKIP_DEPS=1 ;;
        *)
            echo "error: unknown argument: $arg" >&2
            exit 1
            ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT_NAME=bunny-server
DATA_DIR=/var/lib/bunny-server

if [ "$SKIP_DEPS" -eq 0 ]; then
    echo "==> Installing build prerequisites"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq
        apt-get install -y --no-install-recommends build-essential cmake libssl-dev ca-certificates
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y gcc make cmake openssl-devel
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm --needed base-devel cmake openssl
    else
        echo "warning: no supported package manager found (apt/dnf/pacman)." >&2
        echo "         install a C11 compiler, CMake >= 3.21, and OpenSSL dev headers" >&2
        echo "         yourself (see README.md's Building section), then re-run with --skip-deps." >&2
        exit 1
    fi
fi

echo "==> Building release binary (make release)"
make -C "$REPO_ROOT" release

BINARY="$REPO_ROOT/build-release/server/bunny_server"
if [ ! -x "$BINARY" ]; then
    echo "error: $BINARY wasn't produced by the build" >&2
    exit 1
fi

echo "==> Installing binary and systemd unit"
if systemctl is-active --quiet "$UNIT_NAME" 2>/dev/null; then
    systemctl stop "$UNIT_NAME"
fi
install -Dm755 "$BINARY" /usr/local/bin/bunny_server
install -Dm644 "$REPO_ROOT/deploy/bunny-server.service" "/etc/systemd/system/$UNIT_NAME.service"

systemctl daemon-reload
systemctl enable --now "$UNIT_NAME"

echo "==> Waiting for first-run setup (auth token + TLS certificate)"
for _ in $(seq 1 30); do
    if [ -f "$DATA_DIR/auth_token" ] && [ -f "$DATA_DIR/server.pem" ]; then
        break
    fi
    sleep 1
done

if ! systemctl is-active --quiet "$UNIT_NAME"; then
    echo "error: $UNIT_NAME failed to start -- check: journalctl -u $UNIT_NAME -n 50" >&2
    exit 1
fi

if [ ! -f "$DATA_DIR/auth_token" ] || [ ! -f "$DATA_DIR/server.pem" ]; then
    echo "error: service is running but $DATA_DIR/auth_token or server.pem never appeared" >&2
    echo "       check: journalctl -u $UNIT_NAME -n 50" >&2
    exit 1
fi

AUTH_TOKEN="$(cat "$DATA_DIR/auth_token")"
FINGERPRINT="$(openssl x509 -in "$DATA_DIR/server.pem" -noout -fingerprint -sha256 | cut -d= -f2)"
PORT="$(systemctl show -p Environment "$UNIT_NAME" | grep -oP 'BUNNY_SERVER_PORT=\K[0-9]+' || echo 8443)"

cat <<EOF

==> bunny_server is running (systemctl status $UNIT_NAME)

Enter these into the app's Setup screen (or Settings -> Switch connection mode),
"Networked" mode:

  Server URL:   https://<this-machine's-public-IP-or-hostname>:$PORT
  Bearer token: $AUTH_TOKEN
  Cert SHA-256: $FINGERPRINT

Before connecting from outside this machine, make sure the port above is open
in both this host's firewall (ufw/firewalld/iptables) and, for a cloud VM, the
provider's own ingress rules (e.g. Oracle Cloud's Security List/Network
Security Group -- its default rules block everything but SSH).

Logs:    journalctl -u $UNIT_NAME -f
Restart: systemctl restart $UNIT_NAME
Update:  re-run this script after pulling new commits
EOF
