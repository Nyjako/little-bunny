# Shared by install.sh (builds then installs) and install-prebuilt.sh (installs
# a binary built elsewhere, e.g. on a more powerful machine than the target
# server) -- not meant to be run directly. Expects UNIT_NAME, DATA_DIR, and
# REPO_ROOT to already be set, and BINARY to point at a built bunny_server
# executable.
bunny_install_and_start() {
    echo "==> Installing binary and systemd unit"
    if systemctl is-active --quiet "$UNIT_NAME" 2>/dev/null; then
        systemctl stop "$UNIT_NAME"
    fi
    install -Dm755 "$BINARY" /usr/local/bin/bunny_server
    install -Dm755 "$REPO_ROOT/deploy/bunny-server-update-apply.sh" /usr/local/bin/bunny-server-update-apply.sh
    install -Dm644 "$REPO_ROOT/deploy/bunny-server.service" "/etc/systemd/system/$UNIT_NAME.service"

    # Catches a missing shared library (e.g. the binary was built on a
    # different distro/machine than this one, install-prebuilt.sh's main use
    # case) before it turns into an opaque "service won't start" loop in
    # journalctl -- the real check only means anything run on the actual
    # target, not wherever the binary was built.
    local missing
    missing="$(ldd /usr/local/bin/bunny_server 2>&1 | grep "not found" || true)"
    if [ -n "$missing" ]; then
        echo "error: /usr/local/bin/bunny_server is missing shared libraries on this machine:" >&2
        echo "$missing" | sed 's/^/  /' >&2
        echo "Install the matching packages (e.g. via your package manager's search for" >&2
        echo "the library name above) and re-run this script." >&2
        exit 1
    fi

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

    local auth_token fingerprint port public_ip host_display
    auth_token="$(cat "$DATA_DIR/auth_token")"
    fingerprint="$(openssl x509 -in "$DATA_DIR/server.pem" -noout -fingerprint -sha256 | cut -d= -f2)"
    port="$(systemctl show -p Environment "$UNIT_NAME" | grep -oP 'BUNNY_SERVER_PORT=\K[0-9]+' || echo 8443)"
    # Best-effort public IP lookup -- falls back to the old placeholder text
    # if ipinfo.io is unreachable (no outbound internet, firewalled, etc.).
    public_ip="$(curl -s -m 5 https://ipinfo.io/ip || true)"
    host_display="${public_ip:-<this-machine's-public-IP-or-hostname>}"

    cat <<EOF

==> bunny_server is running (systemctl status $UNIT_NAME)

Enter these into the app's Setup screen (or Settings -> Switch connection mode),
"Networked" mode:

  Server URL:   https://$host_display:$port
  Bearer token: $auth_token
  Cert SHA-256: $fingerprint

Before connecting from outside this machine, make sure the port above is open
in both this host's firewall (ufw/firewalld/iptables) and, for a cloud VM, the
provider's own ingress rules (e.g. Oracle Cloud's Security List/Network
Security Group -- its default rules block everything but SSH).

Logs:    journalctl -u $UNIT_NAME -f
Restart: systemctl restart $UNIT_NAME
EOF
}
