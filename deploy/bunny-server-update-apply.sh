#!/usr/bin/env bash
# Run as root via bunny-server.service's `ExecStartPre=+` -- the ONE place
# in this whole deployment with any elevated privilege, used for exactly
# one job: install an update the main, sandboxed/DynamicUser bunny_server
# process already downloaded, extracted, and verified into
# DATA_DIR/update-staging/extracted/bunny_server (see server/src/updater.c).
# That process can never write to /usr/local/bin itself (ProtectSystem=strict
# in the unit file blocks it, deliberately) -- this script, running with the
# `+` prefix's full privileges regardless of DynamicUser, is what actually
# gets to. BUNNY_SERVER_DATA_DIR is already in the unit's own Environment=,
# which ExecStartPre= inherits the same as ExecStart=.
set -euo pipefail

DATA_DIR="${BUNNY_SERVER_DATA_DIR:-/var/lib/bunny-server}"
MARKER="$DATA_DIR/update-ready"
STAGED_BINARY="$DATA_DIR/update-staging/extracted/bunny_server"
INSTALL_PATH="/usr/local/bin/bunny_server"

if [ ! -f "$MARKER" ]; then
    exit 0 # nothing staged -- normal startup, every single time this doesn't fire
fi

if [ ! -x "$STAGED_BINARY" ]; then
    echo "bunny-server-update-apply: $MARKER exists but $STAGED_BINARY is missing/not executable -- skipping install" >&2
    rm -f "$MARKER"
    exit 0 # never block startup over a bad/incomplete staged update
fi

# Copy to a temp file on the SAME filesystem as the install path (same
# directory), then rename -- rename(2) is atomic, so there's never a
# half-written /usr/local/bin/bunny_server for this same ExecStart to race
# against a moment later.
TMP_PATH="$(dirname "$INSTALL_PATH")/.bunny_server.update.$$"
cp "$STAGED_BINARY" "$TMP_PATH"
chmod 755 "$TMP_PATH"
mv "$TMP_PATH" "$INSTALL_PATH"

rm -f "$MARKER"
rm -rf "$DATA_DIR/update-staging"

echo "bunny-server-update-apply: installed update from $STAGED_BINARY" >&2
