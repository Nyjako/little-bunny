#!/usr/bin/env bash
set -euo pipefail

# Defaults match deploy/bunny-server.service's systemd DynamicUser setup
# (Environment=BUNNY_SERVER_DATA_DIR=%S/bunny-server, resolving to
# /var/lib/bunny-server) -- NOT a plain user's XDG data dir, since the
# service runs as a dynamically-allocated unprivileged user, not whoever is
# running this script. Reading its files needs sudo.
DATA_DIR="${BUNNY_SERVER_DATA_DIR:-/var/lib/bunny-server}"
PORT="${BUNNY_SERVER_PORT:-8443}"

echo "data_dir: $DATA_DIR"
echo "port: $PORT"
echo

if sudo test -f "$DATA_DIR/auth_token"; then
  echo "BEARER_TOKEN=$(sudo cat "$DATA_DIR/auth_token")"
else
  echo "!! no auth_token file found at $DATA_DIR/auth_token"
fi

if sudo test -f "$DATA_DIR/server.pem"; then
  echo "CERT_SHA256=$(sudo openssl x509 -noout -fingerprint -sha256 -in "$DATA_DIR/server.pem" | cut -d= -f2 | tr -d ':')"
else
  echo "!! no server.pem found at $DATA_DIR/server.pem"
fi

echo
# hostname -I only returns the private/LAN address -- ipinfo.io gives the
# actual public IP a client outside this machine needs to connect to.
echo "SERVER_URL=https://$(curl -s -m 5 https://ipinfo.io/ip):$PORT"
