#!/usr/bin/env bash
# Builds bunny_server (the C server, see docs/architecture.md's "C server
# (M5)" section) on THIS machine and installs it as a systemd service. Meant
# for a fresh Linux VM with no manual TLS/proxy setup -- the server already
# generates its own self-signed certificate and bearer token on first run
# (M5.1); this script's only job is getting that binary running unattended
# and handing back the values the Flutter app's "Networked" setup screen
# needs.
#
# If the target machine isn't powerful enough to comfortably build the
# dependency chain (curl, civetweb, ...) itself, build on another machine of
# the same architecture/distro family instead (plain `make release`) and use
# install-prebuilt.sh on the target to install that binary directly, with no
# build step there at all.
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
# shellcheck source=_install-common.sh
source "$REPO_ROOT/deploy/_install-common.sh"

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

bunny_install_and_start
