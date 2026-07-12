# Deploy — gateway control-plane smoke test (rootless podman + quadlet)

Bring up **postgres + redis + the ACE gateway** on a single VM and confirm the
gateway starts, migrates, and answers. This is the smallest slice that proves
the `ace-gateway` image works. AWX/controller comes after (see the bottom).

## What runs

| Unit | Image | Role |
|------|-------|------|
| `ace-postgres` | `docker.io/library/postgres:15` | gateway database |
| `ace-redis` | `docker.io/library/redis:7` | cache / channels (standalone) |
| `ace-gateway` | `ghcr.io/sammonsjl/ace-gateway:latest` | Jewel gateway + platform UI, nginx TLS on `:8000` |

All three share a rootless podman network `ace`, so they resolve each other by
container name.

## Prerequisites on the VM

- Rocky/Alma/Fedora, **podman ≥ 4.4** (quadlet), `openssl`, `python3`.
- Run everything as an **unprivileged user**, not root (the image runs as uid 1000).
- Linger on, so the services survive logout:
  `sudo loginctl enable-linger <user>`
- The image is **private on GHCR** — log in first with a PAT that has `read:packages`:
  `podman login ghcr.io -u sammonsjl`

## Run it

```bash
git clone git@github.com:sammonsjl/ace-images.git
cd ace-images/deploy
./bootstrap.sh
```

`bootstrap.sh` creates the podman secrets (DB password, Django `SECRET_KEY`),
generates a self-signed TLS cert, writes `~/ace/gateway/container-startup.yml`
with a random admin password (printed to the terminal), installs the quadlet
units to `~/.config/containers/systemd/`, and starts the three services.

## What the gateway does on first boot (automatic)

`launch-gateway` (the image entrypoint) waits for the DB, then because
`CONTAINER_NUMBER=1` it runs the whole init chain itself:

1. `aap-gateway-manage migrate --noinput`
2. `createsuperuser` using `gateway_admin_username`/`gateway_admin_password`
   from the mounted `container-startup.yml` (falls back to a random password,
   logged, if the file is missing)
3. `collectstatic --noinput`
4. `aap-gateway-manage authenticators --initialize`
5. `exec supervisord -n` → nginx, uwsgi, control-plane (grpc), dispatcher

So you do **not** run migrate/superuser by hand — just watch it happen.

## Smoke test

```bash
podman logs -f ace-gateway          # watch migrations; note the ">>> Admin password" line
curl -sk https://localhost:8000/api/gateway/v1/ping/ | python3 -m json.tool
```

`ping` should return JSON. Then open `https://<vm>:8000/` (self-signed cert
warning is expected) and log in as `admin` with the password from
`~/ace/gateway/container-startup.yml`.

### If it doesn't come up

- `systemctl --user status ace-gateway` and `podman logs ace-gateway`.
- **Permission denied on the cert/SECRET_KEY**: rootless uid-mapping. The
  bootstrap makes the cert files `0644`; podman secrets mount world-readable.
  If you tightened them, loosen or add `UserNS=keep-id` to the container unit.
- **DB auth failed**: the `ace_db_password` secret feeds both postgres
  (`POSTGRES_PASSWORD`) and the gateway (`DATABASE_PASSWORD`) — if you rotated
  one, recreate the secret and restart both.
- Reset everything: `systemctl --user stop ace-gateway ace-postgres ace-redis`,
  then `podman volume rm ace-postgres-data ace-redis-data`.

## Add the controller (AWX)

The controller image is **pulled, not built**: `ghcr.io/ansible/awx:devel`
(public, multi-arch, fresh). It runs as a web + task container pair sharing the
same postgres and redis. Everything below was validated on a Rocky 9 arm64 VM.

```bash
podman pull ghcr.io/ansible/awx:devel
cd ace-images/deploy
./awx-init.sh          # creates the awx DB, SECRET_KEY, migrates, provisions, registers queues
cp quadlet/ace-awx-*.container ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user start ace-awx-task.service ace-awx-web.service
curl -s http://localhost:8013/api/v2/ping/ | python3 -m json.tool   # capacity > 0 when healthy
```

Gotchas found while bringing AWX up (all handled by the files here):

- **SECRET_KEY** must be set from a `conf.d` file, not just `/etc/tower/SECRET_KEY`
  — `defaults.py` reads that file into the *development* dynaconf layer, but
  `awx-manage` runs in *production* (see `awx/conf.d/ace.py`).
- **`ALLOWED_HOSTS`** must be set or every request 400s with a DisallowedHost.
- The image ships only a stock `:80` nginx; **we supply an http-only `:8013`
  config** (`awx/nginx/`) with pid/logs to writable paths (uid 1000, rootless).
- **`OPENSSL_armcap=0`** — same arm64/VMware SIGILL workaround as the gateway.
- The **task** container runs the supervisor directly (`awx/awx-task-run.sh`),
  skipping `launch_awx_task.sh`'s `provision_instance` (fails outside K8s);
  `awx-init.sh` provisions the instance once with `--hostname`.

## Next: put the gateway in front of the controller (v0.2)

Both planes run independently today. To get single login through the gateway,
the remaining wiring is:

1. `aap-gateway-manage generate_service_secret controller` on the gateway →
   inject the result into AWX's `RESOURCE_SERVER` settings.
2. Register the controller service node/cluster/route via the gateway REST API
   (`ansible.platform`-style calls), as the containerized installer does.
3. Once AWX is registered: `aap-gateway-manage migrate_service_data --username=admin`.

This is the JWT/resource-server federation step — the known-tricky part — and is
not yet automated here.
