#!/usr/bin/env bash
# hack/record-build-deps.sh <image>
#
# Finds the build requirements pybuild-deps misses, by doing the build once
# with the network on and writing down what pip actually fetched. Every
# sdist the prefetch holds is built from source, in isolation, the way the
# build from the prefetch will; each build environment pip creates logs
# "Successfully installed ...". Anything installed there that the prefetch
# does not already hold is printed as a pin, for
# <image>/requirements-build-extra.in.
#
# Slow (it compiles everything, Rust included) and only needed when a
# build from the prefetch stops at "No matching distribution found".
set -euo pipefail

image=${1:?usage: hack/record-build-deps.sh <image>}
root=$(cd "$(dirname "$0")/.." && pwd)
out_root=${ACE_OUT:-${XDG_CACHE_HOME:-$HOME/.cache}/ace-images}
tools=localhost/ace-tools:latest

cd "$root"

# One sdist at a time, so a package that fails to build cannot hide what the
# others needed.
podman run --rm -v "$out_root/$image/deps/pip:/have:ro,Z" "$tools" sh -c '
  dnf install -q -y rust cargo >/dev/null 2>&1 || true
  for f in /have/*.tar.gz /have/*.zip; do
    [ -e "$f" ] || continue
    timeout 900 python3.12 -m pip wheel -v --no-deps --no-binary :all: --wheel-dir /tmp/w "$f" 2>&1 \
      | grep -oE "Successfully installed .*" || echo "# could not build $(basename "$f")" >&2
  done | tr " " "\n" | grep -E -- "-[0-9]" | sort -u > /tmp/installed
  ls /have | sed -E "s/\.(tar\.gz|zip|whl)$//" | tr "[:upper:]_" "[:lower:]-" > /tmp/have
  while read -r nv; do
    name=${nv%-*}; version=${nv##*-}
    key=$(printf "%s-%s" "$name" "$version" | tr "[:upper:]_" "[:lower:]-")
    grep -qxF "$key" /tmp/have || echo "${name}==${version}"
  done < /tmp/installed
'
