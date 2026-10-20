#!/usr/bin/env bash
# hack/lock.sh <image>
#
# Regenerates <image>'s lockfiles: the files Hermeto prefetches from. Run it
# after changing a *.in file or bumping the src/ submodule, and commit what
# it writes. Everything runs in the toolbox image (hack/tools/Containerfile).
#
#   requirements*.in       -> requirements*.txt        runtime packages, hashed
#   requirements-build.in  -> requirements-build.txt   build backends a wheels
#                                                      stage installs first (builds
#                                                      without isolation), and
#                             requirements-bootstrap.txt  what it takes to build
#                                                      those backends from sdists
#   no requirements-build.in -> requirements-build.txt  every package's own build
#                                                      backends (builds with isolation)
#   rpms.in.yaml           -> rpms.lock.yaml           every RPM, both arches
#   lock-pre.sh            runs first, if the image has one
#   lock-post.sh           runs after the pip locks, if the image has one
#   hermeto.json           binary.packages: what comes as a wheel (hack/binary-filter.py)
set -euo pipefail

image=${1:?usage: hack/lock.sh <image>}
root=$(cd "$(dirname "$0")/.." && pwd)
tools=localhost/ace-tools:latest

cd "$root"
podman image exists "$tools" || podman build -q -t "$tools" hack/tools >/dev/null

run() { podman run --rm -v "$root:/work:Z" -w "/work/$image" "$tools" "$@"; }
compile() { run pip-compile --quiet --generate-hashes --allow-unsafe --strip-extras --no-header -o "$2" "$1"; }

# An image whose pins come from somewhere else (eda's poetry.lock) generates
# its requirements*.in first.
if [ -f "$image/lock-pre.sh" ]; then
  run sh ./lock-pre.sh
fi

# Runtime requirements: every requirements*.in except the build one.
runtime=()
for f in "$image"/requirements*.in; do
  [ -e "$f" ] || continue
  name=$(basename "$f" .in)
  case "$name" in requirements-build|requirements-build-extra) continue ;; esac
  compile "$name.in" "$name.txt"
  runtime+=("$name.txt")
done
if [ -f "$image/requirements-build.in" ]; then
  # Builds without isolation: the backends are installed first, pinned.
  compile requirements-build.in requirements-build.txt
  run pybuild-deps compile --generate-hashes -o requirements-bootstrap.txt \
    "${runtime[@]}" requirements-build.txt
elif [ ${#runtime[@]} -gt 0 ]; then
  # Builds with isolation: every package's own backends, as pip would fetch them.
  run pybuild-deps compile --generate-hashes -o requirements-build.txt "${runtime[@]}"
fi
# Build requirements pybuild-deps cannot see (conditional ones, such as
# maturin's puccinialin), pinned on their own.
if [ -f "$image/requirements-build-extra.in" ]; then
  compile requirements-build-extra.in requirements-build-extra.txt
fi
# ...and may trim what pip-compile pulled in.
if [ -f "$image/lock-post.sh" ]; then
  run sh ./lock-post.sh
fi
# Which packages Hermeto fetches as PyPI wheels (all that have one for both
# arches), and which as sdists the build compiles.
if [ -f "$image/hermeto.json" ]; then
  python3 hack/binary-filter.py "$image"
fi
if [ -f "$image/rpms.in.yaml" ]; then
  run rpm-lockfile-prototype --outfile rpms.lock.yaml rpms.in.yaml
fi
git status --short -- "$image"
