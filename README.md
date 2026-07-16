# ace-images

Image factory for the **ACE** project — an upstream, open-source mirror of the
AAP control plane that runs as rootless podman containers on a VM. This repo
builds the container images that don't exist as usable public builds, and
pushes them to GHCR.

Everything is built from **Apache-2.0 upstream source**. No files are copied out
of Red Hat's bundle or private images — the upstream repos are cloned at pinned
commits at build time, and the build only replicates the *end state* of the
official images.

## Images

| Image | Built from | Why we build it |
|-------|-----------|-----------------|
| `ace-gateway` | [`ansible/jewel`](https://github.com/ansible/jewel) + [`ansible/ansible-ui`](https://github.com/ansible/ansible-ui) (`platform/`) | `quay.io/ansible/gateway` and `quay.io/ansible/platform-ui` are **private**. The gateway (Jewel) app plus the unified platform UI are baked into one image. |
| `ace-hub` | [`ansible/galaxy_ng`](https://github.com/ansible/galaxy_ng) on `pulp/base` | `quay.io/ansible/galaxy-ng` is **amd64-only** (no arm64 build); `pulp/pulp-galaxy-ng` is abandoned. Also forces `django-ansible-base` to `devel` so galaxy_ng's JWT dialect matches the gateway's. |

Still to do (see project notes): an `ace-controller` (AWX) image built from
`devel` — `quay.io/ansible/awx` is frozen at `24.6.1` (Jul 2024), which predates
the gateway / django-ansible-base resource-server integration.

## `ace-gateway`

`gateway/Containerfile` is a single, self-contained multi-stage build:

1. **jewel-src** — clone `ansible/jewel` at `JEWEL_REF`.
2. **ui-builder** — clone `ansible/ansible-ui` at `ANSIBLE_UI_REF`, `npm ci`,
   `cd platform && npm run build` (vite → `platform/dist`).
3. **builder** — CentOS Stream 9 venv, install the gateway's
   `requirements.txt` + `requirements_git.txt` (django-ansible-base from git).
4. **final** — assemble the runtime (nginx 1.24, supervisor, uwsgi) like
   jewel's own `tools/docker/Dockerfile`, but copy the platform UI from the
   `ui-builder` stage instead of the private `quay.io/ansible/platform-ui`.

The final stage also adopts a few behaviors observed in the real
`registry.redhat.io/ansible-automation-platform-26/gateway-rhel9` image
(dissected 2026-07-15 — see the vault note *"(N) Gateway Image Internals — RH
gateway-rhel9"*): `dumb-init` as PID 1, a named `gateway` user (uid 1000 /
gid 0), `DJANGO_SETTINGS_MODULE` set in the runtime image, and `collectstatic`
baked at build time. The jewel config contract (`/opt/aap_gateway`,
`launch-gateway`, jewel's shipped supervisord/nginx/uwsgi configs) is
unchanged — RH's hyphenated paths and installer-mounted configs are
deliberately not copied.

### Pinned versions

Both upstream refs are pinned as `ARG`s at the top of the Containerfile and can
be overridden per build:

```
docker build -f gateway/Containerfile \
  --build-arg JEWEL_REF=<sha> \
  --build-arg ANSIBLE_UI_REF=<sha> \
  -t ace-gateway:dev gateway
```

The GitHub Actions workflow (`build-gateway`) exposes the same two refs as
`workflow_dispatch` inputs; leaving them blank uses the Containerfile defaults.
It pushes `ghcr.io/<owner>/ace-gateway:latest` and a `:<date>-<sha>` tag.

## `ace-hub`

`hub/Containerfile` builds `galaxy_ng` at a pinned `GALAXY_NG_REF` on top of
the multi-arch `pulp/base` image. Unlike the gateway, the `pulpcore` /
`pulp_ansible` / `pulp-container` / `django` / `galaxy-importer` versions are
**hand-pinned** in the `RUN pip3 install` step as constraints — mirroring
galaxy_ng's own `setup.py` at that ref — to avoid pip backtracking for the
better part of an hour. **Bumping `GALAXY_NG_REF` alone is not enough**: check
galaxy_ng's `setup.py` at the new ref and update those pins to match before
building, or the install will backtrack or resolve to incompatible versions.

```
docker build -f hub/Containerfile \
  --build-arg GALAXY_NG_REF=<sha> \
  -t ace-hub:dev hub
```

The GitHub Actions workflow (`build-hub`) exposes `GALAXY_NG_REF` as a
`workflow_dispatch` input; leaving it blank uses the Containerfile default. It
pushes `ghcr.io/<owner>/ace-hub:latest` and a `:<date>-<sha>` tag.

## Building on GHCR

- `build-gateway` runs on pushes to `main` touching `gateway/**`, or manual
  `workflow_dispatch` (optionally with custom refs).
- `build-hub` runs on pushes to `main` touching `hub/**`, or manual
  `workflow_dispatch` (optionally with a custom ref).

Images are pushed to GHCR and inherit this repo's (private) visibility.
