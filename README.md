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

`ace-hub` is the exception: it builds on `docker.io/pulp/base:3.117`, pulp's own
multi-arch image — CentOS Stream 10 on Python 3.12.

**Pin it, and pin it for the interpreter, not the pulpcore version.** `:latest`
moves daily and must not be used. But the tag to pin to is decided by Python:
`galaxy_ng`'s lockfile pins `ansible-core==2.21.0`, which requires Python 3.12,
so the Stream 9 / Python 3.11 lines (3.105 and earlier) cannot satisfy it at
all. The base then ships pulpcore 3.117 and the lockfile constraints pull it
back to the 3.105.x galaxy_ng wants — the base supplies the platform and the
interpreter, the lockfile supplies the versions.

## Pinned by default, latest on demand

Every upstream ref is an `ARG` at the top of its Containerfile, holding a commit
SHA rather than a branch, so an image built on its own is reproducible. The one
deliberate exception is `build-all`, which exists to pick up whatever upstream
has merged since — see [Building](#building).

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
dispatch, from the Containerfile's pinned refs. Those builds are tagged
`:<date>-<sha>` (this repo's commit) and `:latest`.

**`build-all` rebuilds everything from the latest upstream.** Run it by hand
whenever you want fresh images. Its first job reads the current head of every
upstream branch once — `jewel`, `ansible-ui`, `awx`, `galaxy_ng`, `eda-server`,
`receptor` and `django-ansible-base` — and all eight images are built from
those same commits. The gateway and the hub are given the **same** DAB commit,
because the hub has to accept the tokens the gateway signs. The run's summary
lists every commit, and each image carries its own in the `ace.source.ref` label.

A `build-all` run tags every image with one shared `:<date>-r<run number>`, plus
`:latest`. The run number keeps the tag unique: two "latest" builds on the same
day are different images and must never share a tag. Pin that one tag in
anything that consumes the images — the containerized installer's
`ace_image_tag`, or the operator's `ace_image_tag` / per-image `image:` fields.
