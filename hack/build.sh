#!/usr/bin/env bash
# hack/build.sh <image> [tag] [-- extra podman build args, e.g. --label k=v]
#
# The build step of a Konflux build, done the way konflux-build-cli does it
# (konflux-ci/konflux-build-cli, pkg/commands/build.go):
#
#   - base images are pulled first, then the build runs with NO network;
#   - the prefetched dependencies (hack/prefetch.sh) are mounted at
#     /cachi2/output, and this arch's prefetched RPM repos are mounted over
#     /etc/yum.repos.d, so dnf/microdnf can only install locked packages;
#   - the prefetch env vars (PIP_FIND_LINKS, PIP_NO_INDEX, GOMODCACHE, ...)
#     reach every RUN step as secret env mounts, so the Containerfile needs
#     no `. /cachi2/cachi2.env` lines and its history stays clean -- which is
#     why Red Hat's image history shows none;
#   - build-date / architecture / vcs-* labels are added at build time.
#
# The output is a local image, localhost/ace-<image>:<tag> (default: dev).
set -euo pipefail

image=${1:?usage: hack/build.sh <image> [tag]}
tag=${2:-dev}
shift $(( $# < 2 ? $# : 2 )); [ "${1:-}" = "--" ] && shift
root=$(cd "$(dirname "$0")/.." && pwd)
out_root=${ACE_OUT:-${XDG_CACHE_HOME:-$HOME/.cache}/ace-images}
prefetched="${out_root}/${image}"
arch=$(uname -m)

cd "$root"
[ -f "$prefetched/prefetch-env.json" ] || { echo "run hack/prefetch.sh ${image} first" >&2; exit 1; }

# Konflux builds from a copy of the prefetch output that every build user
# can write to, holding only this arch's RPMs.
work=$(mktemp -d "${out_root}/build-${image}.XXXXXX")
trap 'chmod -R u+w "$work"; rm -rf "$work"' EXIT
mkdir -p "$work/output/deps"
for d in "$prefetched"/deps/*; do
  [ "$(basename "$d")" = rpm ] && continue
  cp -r "$d" "$work/output/deps/"
done
if [ -d "$prefetched/deps/rpm/$arch" ]; then
  mkdir -p "$work/output/deps/rpm"
  cp -r "$prefetched/deps/rpm/$arch" "$work/output/deps/rpm/"
fi
chmod -R u+w,go+rwX "$work"

args=(--network none --pull=never --no-cache -f "$image/Containerfile" -t "localhost/ace-${image}:${tag}")
args+=(--volume "$work/output:/cachi2/output:z")
repos="$work/output/deps/rpm/$arch/repos.d"
[ -d "$repos" ] && args+=(--volume "$repos:/etc/yum.repos.d:z")

# One secret per env var, mounted into every RUN as that variable.
i=0
while IFS=$'\t' read -r name value; do
  printf '%s' "$value" > "$work/env-$i"
  args+=(--secret "id=prefetch-env-$i,src=$work/env-$i" --mount "type=secret,id=prefetch-env-$i,env=$name")
  i=$((i + 1))
done < <(python3 -c 'import json,sys
for e in json.load(open(sys.argv[1])): print(e["name"] + "\t" + e["value"])' "$prefetched/prefetch-env.json")

args+=(--label "build-date=$(date -u +%Y-%m-%dT%H:%M:%S)" --label "architecture=$arch" --label vcs-type=git)
args+=(--label "vcs-ref=$(git rev-parse HEAD)")

# Base images are pulled while the network is still allowed.
for base in $(grep -iE '^\s*FROM' "$image/Containerfile" | sed -E 's/--platform=\S+//I' | awk '{print $2}' | sort -u); do
  case "$base" in scratch) continue ;; esac
  grep -qiE "^\s*FROM\s.*\sAS\s+${base}\s*$" "$image/Containerfile" && continue
  podman pull -q "$base" >/dev/null
done

podman build "${args[@]}" "$@" "$image"
