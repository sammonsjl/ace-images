# receptor

The execution mesh node.

| | |
|---|---|
| Source | [ansible/receptor](https://github.com/ansible/receptor), tag `v1.6.7` |
| Matches | `receptor-rhel9` from the AAP 2.7-6 containerized bundle |
| Status | **realigned** (2026-10-19) |

A Go build. Serves 27199 and owns the control socket the controller hands
signed work units to. receptor's work-command is `ansible-runner worker`, so
ansible-runner is installed here too, not only in the EE.

## Realigned to the vendor image, 2026-10-19

Rebuilt to match `receptor-rhel9` (AAP 2.7-6) as observed from the outside:
image history, RPM database, pip dist-info and the Go build info in the
binary. Nothing was copied out of the vendor image. The comparison is in the
vault: `03 Projects/ACE/(C) ace-images vs Red Hat Builds.md`.

After the rebuild, the vendor image and this one have the same 118 RPMs, the
same 9 Python packages at the same versions, the same user, entrypoint and
command, and the same `receptor --version` (`v1.6.7+gitf5b7f8f`). Both
filesystems are 263 MB. The vendor image is squashed into one layer and this
one is not, which is why `podman images` shows 267 MB against 281 MB.

What it took:

- **Base:** `ubi9-minimal`, with `microdnf --nodocs --setopt=install_weak_deps=0`.
  The packages are `python3.12`, `python3.12-pip` and **`podman-remote`**.
- **Ref:** tag `v1.6.7`, not `devel`.
- **Binary:** built with CGO on, using the Go from UBI AppStream, so crypto
  goes through the system OpenSSL and its FIPS provider. The binary is linked
  against libc, stripped, and has the version in `-ldflags`. It is built from
  a tree without `.git`, so it carries no VCS stamp. The Makefile's target is
  not used, because it forces `CGO_ENABLED=0`, and with CGO off RHEL's Go
  switches to its native FIPS module instead.
- **Wheels:** the vendor builds every wheel from its sdist, without build
  isolation, against setuptools 82.0.1 and flit_core 3.12.0 (what its `WHEEL`
  files name). Since 2026-10-20 ace-images takes PyPI's wheels instead, for
  speed (README), so those generator names no longer match; PyYAML is still
  built from source, without libyaml-devel, so it has no C loader, as in the
  vendor image. The runtime installs them with `--no-index --prefix /usr`.
- **Versions:** `requirements.in` pins the vendor's `pip freeze`.

## Built hermetically, the Konflux way (2026-10-19)

The receptor source is the `src/` submodule, pinned to tag `v1.6.7`. No
`git clone` happens during the build. Every dependency is prefetched by Hermeto
(`hack/prefetch.sh receptor`, driven by `hermeto.json`):

- Go modules for `src/`;
- Python **wheels where PyPI has them** (sdists alongside): `requirements.txt`, plus the build backends in
  `requirements-build.txt`, plus what it takes to build those backends from
  source (`requirements-bootstrap.txt`);
- every RPM in `rpms.lock.yaml`, resolved against the UBI 9 repos for x86_64
  and aarch64.

`hack/build.sh receptor` then builds with `--network none`. The prefetched
tree is mounted at `/cachi2/output`, the prefetched RPM repos replace
`/etc/yum.repos.d`, and the prefetch env reaches every RUN step as secret env
mounts. The Containerfile therefore has no prefetch plumbing in it, just as
Red Hat's history shows none.

`python3 hack/diff-history.py localhost/ace-receptor:dev <receptor-rhel9>`
lines the final stage up against the vendor's: **10 of 10 steps, in order.**
Lockfiles are regenerated with `hack/lock.sh receptor`.

## podman-remote, not podman

This image has no `podman`, only `podman-remote`. Jobs run in the **host's**
rootless podman, through its API socket. The containerized installer mounts
three things:

- the socket, at `/run/user/<uid>/podman/podman.sock`, with
  `CONTAINER_HOST` pointing at it;
- a two-line `/usr/bin/podman` wrapper that execs `podman-remote`, because
  ansible-runner calls `podman`;
- the job directories, at the **same path** on both sides, because the host
  podman resolves bind-mount paths on the host.

That is the vendor's arrangement. It replaces the in-image rootless podman
used until 2026-10-19, which needed fuse-overlayfs, an emptied `/etc/subuid`
and a pre-owned `/home/runner`.

**receptorctl is gone too**, because the vendor image has none. The installer
waits on the control socket instead of on `receptorctl status`.

Checked on 2026-10-19 on the laptop. A work unit was submitted to this image
through its control socket and ran `ansible-runner worker`, which started an
`ace-ee-minimal` container through the host's podman and returned
`hello from the EE`, `ok=1`.

## History

- 2026-08-27: built from `devel` on CentOS Stream 9 with podman in the image.
  The 2026-08-28 note claimed the vendor image had "no podman". That was
  wrong: it ships `podman-remote`.
