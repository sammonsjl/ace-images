#!/usr/bin/env bash
# hack/lock.sh <image>
#
# Regenerates <image>'s lockfiles: the files Hermeto prefetches from. Run it
# after changing a *.in file or bumping the src/ submodule, and commit what
# it writes. Everything runs in the toolbox image (hack/tools/Containerfile).
#
#   requirements.in        -> requirements.txt         runtime packages, hashed
#   requirements-build.in  -> requirements-build.txt   build backends the
#                                                      wheels stage installs first
#   both of the above      -> requirements-bootstrap.txt  what it takes to build
#                                                      the backends themselves
#                                                      from sdists (prefetch only)
#   rpms.in.yaml           -> rpms.lock.yaml           every RPM, both arches
set -euo pipefail

image=${1:?usage: hack/lock.sh <image>}
root=$(cd "$(dirname "$0")/.." && pwd)
tools=localhost/ace-tools:latest

cd "$root"
podman image exists "$tools" || podman build -q -t "$tools" hack/tools >/dev/null

run() { podman run --rm -v "$root:/work:Z" -w "/work/$image" "$tools" "$@"; }
compile() { run pip-compile --quiet --generate-hashes --allow-unsafe --strip-extras --no-header -o "$2" "$1"; }

if [ -f "$image/requirements.in" ]; then
  compile requirements.in requirements.txt
fi
if [ -f "$image/requirements-build.in" ]; then
  compile requirements-build.in requirements-build.txt
  run pybuild-deps compile --generate-hashes -o requirements-bootstrap.txt \
    requirements.txt requirements-build.txt
fi
if [ -f "$image/rpms.in.yaml" ]; then
  run rpm-lockfile-prototype --outfile rpms.lock.yaml rpms.in.yaml
fi
git status --short -- "$image"
