#!/usr/bin/env bash
# One-time init for the AWX (controller) half of the ACE control-plane test.
# Assumes bootstrap.sh already brought up ace-postgres + ace-redis. Idempotent.
# After this, start the services: systemctl --user start ace-awx-task ace-awx-web
set -euo pipefail

AWX_IMAGE="ghcr.io/ansible/awx:devel"
AWX_DIR="${HOME}/ace/awx"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADMIN_PW="${AWX_ADMIN_PASSWORD:-awxadmin123}"

echo "==> Creating awx database + role in ace-postgres"
podman exec ace-postgres psql -U gateway -d gateway -c \
  "CREATE USER awx WITH PASSWORD 'awxpass';" 2>/dev/null || echo "  (role awx exists)"
podman exec ace-postgres psql -U gateway -d gateway -c \
  "CREATE DATABASE awx OWNER awx;" 2>/dev/null || echo "  (db awx exists)"

echo "==> Staging SECRET_KEY, settings, nginx config"
mkdir -p "${AWX_DIR}/conf.d" "${AWX_DIR}/nginx"
[ -f "${AWX_DIR}/SECRET_KEY" ] || { openssl rand -base64 40 | tr -d '\n' > "${AWX_DIR}/SECRET_KEY"; }
cp "${SRC_DIR}/awx/conf.d/ace.py"      "${AWX_DIR}/conf.d/ace.py"
cp "${SRC_DIR}/awx/nginx/nginx.conf"   "${AWX_DIR}/nginx/nginx.conf"
cp "${SRC_DIR}/awx/nginx/awx.conf"     "${AWX_DIR}/nginx/awx.conf"
cp "${SRC_DIR}/awx/awx-task-run.sh"    "${AWX_DIR}/awx-task-run.sh"
chmod 0644 "${AWX_DIR}/SECRET_KEY" "${AWX_DIR}/conf.d/ace.py" "${AWX_DIR}/nginx/"*.conf
chmod 0755 "${AWX_DIR}/awx-task-run.sh"

MOUNTS="-v ${AWX_DIR}/SECRET_KEY:/etc/tower/SECRET_KEY:ro,Z -v ${AWX_DIR}/conf.d/ace.py:/etc/tower/conf.d/ace.py:ro,Z"
RUN="podman run --rm --network ace -e OPENSSL_armcap=0 ${MOUNTS} ${AWX_IMAGE}"

echo "==> Migrating AWX database"
$RUN awx-manage migrate --noinput

echo "==> Creating admin (${ADMIN_PW})"
podman run --rm --network ace -e OPENSSL_armcap=0 -e DJANGO_SUPERUSER_PASSWORD="${ADMIN_PW}" ${MOUNTS} \
  ${AWX_IMAGE} awx-manage createsuperuser --username admin --email admin@localhost --noinput \
  2>/dev/null || echo "  (admin exists)"

echo "==> Provisioning instance + registering EEs and queues"
$RUN bash -lc '
  awx-manage provision_instance --hostname=ace-awx --node_type=hybrid
  awx-manage register_default_execution_environments
  awx-manage register_queue --queuename=controlplane --instance_percent=100
  awx-manage register_queue --queuename=default --instance_percent=100
'

echo
echo "Done. Start the controller:"
echo "  cp ${SRC_DIR}/quadlet/ace-awx-*.container ~/.config/containers/systemd/"
echo "  systemctl --user daemon-reload"
echo "  systemctl --user start ace-awx-task.service ace-awx-web.service"
echo "Then: curl -s http://localhost:8013/api/v2/ping/ | python3 -m json.tool"
