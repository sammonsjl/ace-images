# ace-images

The container images of an AAP-style automation platform, built **from
upstream source, the way Red Hat builds its AAP images**: from a prefetch, in the
manner of Konflux. Each Containerfile's final stage follows, step by step, the
final stage recorded in the history of the Red Hat image it stands in for.

It is the companion of [AWX the Hard Way](https://github.com/sammonsjl/awx-the-hard-way),
which lays the same components down on virtual machines, following the same
steps by hand. This repo is those steps written as Containerfiles.

Nothing is copied out of a vendor image or bundle. The vendor images were
read — their history, their package lists, their file layout — and these
Containerfiles were written to do the same things, in the same order, from
public sources. See [`NOTICE`](NOTICE).

## How an image is built

Red Hat builds each AAP image in Konflux, in three moves. So does this repo.

1. **Prefetch** — `hack/prefetch.sh <image>`. [Hermeto](https://github.com/hermetoproject/hermeto)
   reads `<image>/hermeto.json` and downloads every dependency up front: Python
   packages as **PyPI's wheels** for linux x86_64 and aarch64, CPython 3.12
   — every package that has one; the few that do not come as sdists, which
   the build compiles (`hack/binary-filter.py` writes the list into
   `hermeto.json`) — the tools it takes to build those, Go modules, npm
   packages, and the exact RPMs, every file checked against the hash in its
   lockfile.
2. **Build** — `hack/build.sh <image>`. `podman build`,
   with the prefetched tree mounted at `/cachi2/output`, its RPM repos mounted
   over `/etc/yum.repos.d`, and its environment (`PIP_NO_INDEX`,
   `PIP_FIND_LINKS`, `GOMODCACHE`, `CARGO_HOME`, ...) handed to every `RUN` step
   as secret env mounts — exactly as Konflux's build does it with buildah 1.44,
   which is why neither these Containerfiles nor Red Hat's history mention it.
   Builder stages compile wheels, binaries and consoles; the final stage
   installs their output with `pip install --no-index`.
   **Where this differs from Red Hat:** Konflux prefetches sdists only and
   compiles every wheel itself. ace-images takes PyPI's wheels instead,
   because compiling a few hundred packages per image takes hours. And
   Konflux builds Red Hat's images *hermetically*, with the network cut off;
   ace-images builds with it on. Every tool is still pointed at the
   prefetch, so the lockfiles are still an exact, hashed list of what went in
   and the build is reproducible; what is lost is the proof — a dependency
   missing from the lockfiles would be fetched instead of failing the build —
   and "we compiled it ourselves". Compiled here anyway: packages PyPI has no wheel for (uwsgi,
   psycopg's C extension, and a few more), lxml and xmlsec in the gateway
   (their wheels each bundle a different libxml2, and xmlsec will not load
   beside a mismatched lxml), and PyYAML in receptor (the vendor's has no C
   loader).
3. **Compare** — `python3 hack/diff-history.py localhost/ace-<image>:dev <vendor image>`
   lines the final stage up against the vendor's, step by step.

What you need: podman 6 (buildah 1.44, for the env mounts). Lockfiles are
regenerated with `hack/lock.sh <image>`, which runs pip-compile, pybuild-deps
and rpm-lockfile-prototype in a toolbox image (`hack/tools/`). Execution and
decision environments are generated from their `execution-environment.yml` by
`hack/ee-create.sh <image>`, the ansible-builder way.

## The images

| Image | Upstream (pinned submodule) | Stands in for |
|---|---|---|
| `ace-receptor` | receptor `v1.6.7` | `receptor-rhel9` |
| `ace-gateway` | jewel, ansible-ui, django-ansible-base, system-certifi | `gateway-rhel9` |
| `ace-controller` | awx, awx-plugins, awx_plugins.interfaces, django-ansible-base, system-certifi | `controller-rhel9` |
| `ace-hub` | galaxy_ng, django-ansible-base, system-certifi | `hub-rhel9` |
| `ace-eda` | eda-server, django-ansible-base, system-certifi | `eda-controller-rhel9` |
| `ace-ee-minimal` | (ansible-builder) | `ee-minimal-rhel9` |
| `ace-de-minimal` | (ansible-builder) | `de-minimal-rhel9` |
| `ace-de-supported` | (ansible-builder), FROM `ace-de-minimal` | `de-supported-rhel9` |
| `ace-git-server` | — | (a lab helper: a `git://` origin for EDA projects) |

Red Hat builds from release tags on private branches; the submodules sit at
the public commit nearest each one, found by hashing the vendor's installed
source against upstream history. `system-certifi` is Red Hat's own public
stand-in for `certifi`, which hands Python the system's CA bundle.

Every image is `ubi9-minimal` at the end, with `ubi9` builder stages. The few
build-time packages UBI lacks (`xmlsec1-devel` and friends) come from CentOS
Stream 9, restricted to exactly those names (`hack/centos-stream9.repo`).

## Layout of an image directory

```
<image>/
  Containerfile            builder stage(s) + the final stage that follows the vendor's
  src/ ...                 git submodules: upstream sources, pinned
  requirements.in/.txt     Python, pinned (and hashed in .txt)
  requirements-build*.txt  what it takes to build those from source
  rpms.in.yaml/.lock.yaml  every RPM, both arches
  hermeto.json             the prefetch input (Konflux's prefetch-input)
  lock-pre.sh / lock-post.sh   where an image's pins come from elsewhere (poetry, galaxy_ng)
  NOTES.md                 what was learned building it
```

## Refreshing an image

Bump its submodule(s) and/or `*.in` files, run `hack/lock.sh <image>`, build,
compare, commit the new lockfiles. A build that stops at "No matching
distribution" is missing a build requirement pybuild-deps could not see;
`hack/record-build-deps.sh <image>` finds it.

## CI

Each image's workflow (and `build-all`, which builds them all under one
`<date>-r<run>` tag) runs `hack/prefetch.sh` and `hack/build.sh` inside the
`hack/ci` image — Fedora 45, for its podman 6 — on native amd64 and arm64
runners, pushes by digest, and assembles a multi-arch manifest. Only `main`
moves `:latest`. Images are on `ghcr.io/sammonsjl/ace-<image>`.

**Not built here:** envoy, PostgreSQL and Redis. They are not the lesson, and
all are configured by mounted files.
