#!/usr/bin/env bash
# Bootstrap the ACE gateway control-plane smoke test on a rootless-podman VM.
# Run as the unprivileged service user (NOT root) on Rocky/Alma/Fedora with
# podman >= 4.4 (quadlet). Idempotent: safe to re-run.
set -euo pipefail

QUADLET_DST="${HOME}/.config/containers/systemd"
GW_DIR="${HOME}/ace/gateway"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Checking podman/quadlet"
command -v podman >/dev/null || { echo "podman not installed"; exit 1; }
podman --version
test -x /usr/libexec/podman/quadlet || echo "WARN: quadlet generator not found; need podman >= 4.4"

echo "==> Enabling linger so user services run without an active login"
loginctl enable-linger "$(id -un)" 2>/dev/null || echo "  (enable-linger needs sudo; run: sudo loginctl enable-linger $(id -un))"

echo "==> Creating directories"
mkdir -p "$QUADLET_DST" "$GW_DIR"

echo "==> Creating podman secrets (skip if present)"
if ! podman secret exists ace_db_password 2>/dev/null; then
  openssl rand -hex 24 | tr -d '\n' | podman secret create ace_db_password - >/dev/null
  echo "  ace_db_password created"
fi
if ! podman secret exists ace_gateway_secret_key 2>/dev/null; then
  openssl rand -base64 50 | tr -d '\n' | podman secret create ace_gateway_secret_key - >/dev/null
  echo "  ace_gateway_secret_key created"
fi

echo "==> Generating self-signed TLS cert for the gateway (:8000 ssl)"
if [ ! -f "${GW_DIR}/gateway.crt" ]; then
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "${GW_DIR}/gateway.key" -out "${GW_DIR}/gateway.crt" \
    -days 825 -subj "/CN=ace-gateway" \
    -addext "subjectAltName=DNS:localhost,DNS:ace-gateway,IP:127.0.0.1" >/dev/null 2>&1
  # world-readable so the container's uid 1000 can read them under rootless userns
  chmod 0644 "${GW_DIR}/gateway.crt" "${GW_DIR}/gateway.key"
  echo "  gateway.crt / gateway.key created"
fi

echo "==> Writing container-startup.yml (admin bootstrap creds)"
if [ ! -f "${GW_DIR}/container-startup.yml" ]; then
  ADMIN_PW="$(openssl rand -base64 15 | tr -d '/+=\n')"
  cat > "${GW_DIR}/container-startup.yml" <<EOF
gateway_admin_username: admin
gateway_admin_password: ${ADMIN_PW}
EOF
  chmod 0644 "${GW_DIR}/container-startup.yml"
  echo "  admin / ${ADMIN_PW}   (also in ${GW_DIR}/container-startup.yml)"
fi

echo "==> Installing quadlet units"
cp "${SRC_DIR}/quadlet/"*.network "${SRC_DIR}/quadlet/"*.volume "${SRC_DIR}/quadlet/"*.container "$QUADLET_DST/"

echo "==> Reloading + starting"
systemctl --user daemon-reload
systemctl --user start ace-postgres.service ace-redis.service
systemctl --user start ace-gateway.service

echo
echo "Done. Watch first-boot migrations + admin password with:"
echo "  podman logs -f ace-gateway"
echo "Smoke test once it settles:"
echo "  curl -sk https://localhost:8000/api/gateway/v1/ping/ | python3 -m json.tool"
