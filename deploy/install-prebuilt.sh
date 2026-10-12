#!/usr/bin/env bash
# Installs an already-built bunny_server binary as a systemd service --
# no compiler, CMake, or OpenSSL dev headers needed on this machine at all.
# For when the target server isn't powerful enough to comfortably build the
# dependency chain (curl, civetweb, ...) itself: build on another machine of
# the same CPU architecture and Linux distro family with `make release`
# (see README.md's Building section), copy build-release/server/bunny_server
# over (scp, rsync, whatever), then run this against that copy.
#
# Usage: sudo ./deploy/install-prebuilt.sh <path-to-bunny_server-binary>
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "error: run as root (sudo $0)" >&2
    exit 1
fi

if [ "$#" -ne 1 ]; then
    echo "usage: sudo $0 <path-to-bunny_server-binary>" >&2
    exit 1
fi

BINARY="$1"
if [ ! -f "$BINARY" ]; then
    echo "error: $BINARY doesn't exist" >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT_NAME=bunny-server
DATA_DIR=/var/lib/bunny-server
# shellcheck source=_install-common.sh
source "$REPO_ROOT/deploy/_install-common.sh"

bunny_install_and_start
