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
4. **final** — assemble the runtime (nginx 1.22, supervisor, uwsgi) exactly like
   jewel's own `tools/docker/Dockerfile`, but copy the platform UI from the
   `ui-builder` stage instead of the private `quay.io/ansible/platform-ui`.

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

## Building on GHCR

The `build-gateway` workflow runs on:
- pushes to `main` touching `gateway/**`
- manual `workflow_dispatch` (optionally with custom refs)

Images are pushed to GHCR and inherit this repo's (private) visibility.
