# ace-images

Image factory for **ACE** — an upstream, open-source mirror of an AAP-style
automation platform. This repo builds every container image the platform runs
and publishes them to GHCR as multi-arch manifests.

Everything is built from **upstream source at pinned commits**. No files are
copied out of any vendor bundle or private image: the upstream repositories are
cloned at a fixed ref at build time, and the build replicates the *end state* of
the official images without deriving from them. See [`NOTICE`](NOTICE).

## The images

| Image | Built from | Why we build it |
|---|---|---|
| `ace-gateway` | [`jewel`](https://github.com/ansible/jewel) + [`ansible-ui`](https://github.com/ansible/ansible-ui) | Both published images are **private**. The gateway app and the unified console are baked into one image. |
| `ace-controller` | [`awx`](https://github.com/ansible/awx) | `quay.io/ansible/awx` is frozen at 24.6.1 (Jul 2024), which predates the gateway / django-ansible-base resource-server integration this platform depends on. |
| `ace-hub` | [`galaxy_ng`](https://github.com/ansible/galaxy_ng) on `pulp/base` | `quay.io/ansible/galaxy-ng` is amd64-only; `pulp/pulp-galaxy-ng` is abandoned. |
| `ace-eda` | [`eda-server`](https://github.com/ansible/eda-server) | Built from source on principle, so the whole control plane has one provenance story. |
| `ace-receptor` | [`receptor`](https://github.com/ansible/receptor) | Ships podman *in* the image, so nothing has to be bind-mounted from the host. |
| `ace-ee-minimal` | ansible-core + ansible-runner | The execution environment jobs actually run in. |
| `ace-de-supported` | ansible-rulebook + JVM | The decision environment EDA rulebooks run in. |
| `ace-git-server` | `git-daemon` on EL9 | EDA rejects `file://` and cannot shallow-clone over dumb HTTP, so labs need a `git://` origin. |

**Deliberately not built:** envoy (building it means bazel and hours — the
upstream release binary is enough), PostgreSQL, Redis, and the nginx that fronts
hub and EDA. None of them is the lesson, and all are configured by mounted files.

## Base images

Seven of the eight are `quay.io/centos/centos:stream9` end to end. `node:20`
(gateway console) and `golang` (receptor) appear only in build stages that are
thrown away, so nothing but EL9 ships.

`ace-hub` is the exception: it builds on `docker.io/pulp/base:3.105`, pulp's own
multi-arch image, pinned to the 3.105 line because that is the pulpcore
`galaxy_ng`'s lockfile requires. **Do not move it to `:latest`** — as of
2026-08-20 upstream purged their Stream 9 images, so `latest` is now CentOS
Stream 10 carrying pulpcore 3.117, which no longer matches.

## Everything is pinned

Every upstream ref is an `ARG` at the top of its Containerfile, holding a commit
SHA rather than a branch. A moving `devel` or `main` is not reproducible, and an
image that changes underneath you is the opposite of what this repo is for.

Override per build:

```bash
podman build -t localhost/ace-controller:dev \
  --build-arg AWX_REF=<sha> controller/
```

Each workflow exposes the same refs as `workflow_dispatch` inputs; leaving them
blank uses the Containerfile defaults. CI resolves whatever ref it built to a
commit and stamps it into the image as an OCI label, so `podman inspect` on any
published tag tells you exactly what is inside it.

Every directory carries a `NOTES.md` recording what was learned building that
image — why receptor empties `/etc/subuid`, why `galaxy_ng` must build from
`main` and not `master`, why AWX needs `SETUPTOOLS_SCM_PRETEND_VERSION`. Read it
before changing a Containerfile.

## Building

CI builds each image on pushes to `main` touching its directory, or on manual
dispatch; `build-all` rebuilds everything. Images are pushed to GHCR as
`ghcr.io/<owner>/ace-<name>` with both a `:latest` and a dated
`:<date>-<sha>` tag. Pin the dated tag in anything that consumes them.
