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

# The source edits Hermeto's inject-files made (npm lockfiles pointed at the
# prefetched packages), applied for this build only; see hack/prefetch.sh.
patched=()
cleanup() {
  for sub in "${patched[@]}"; do git -C "$sub" checkout -- . ; done
  chmod -R u+w "$work"; rm -rf "$work"
}
trap cleanup EXIT
if [ -s "$prefetched/inject.patches" ]; then
  while read -r sub patch; do
    # Already applied (a build that never got to clean up) is fine.
    git -C "$sub" apply --reverse --check "$prefetched/$patch" 2>/dev/null \
      || git -C "$sub" apply "$prefetched/$patch"
    patched+=("$sub")
  done < "$prefetched/inject.patches"
fi
# Everything Hermeto wrote (deps/, and config such as .cargo/), except RPMs
# for other arches.
mkdir -p "$work/output/deps"
for d in "$prefetched"/* "$prefetched"/.[!.]*; do
  [ -e "$d" ] || continue
  [ "$(basename "$d")" = deps ] && continue
  cp -r "$d" "$work/output/"
done
for d in "$prefetched"/deps/*; do
  [ "$(basename "$d")" = rpm ] && continue
  cp -r "$d" "$work/output/deps/"
done
if [ -d "$prefetched/deps/rpm/$arch" ]; then
  mkdir -p "$work/output/deps/rpm"
  cp -r "$prefetched/deps/rpm/$arch" "$work/output/deps/rpm/"
fi
chmod -R u+w,go+rwX "$work"

# --no-cache, as Konflux builds; ACE_LAYER_CACHE=1 keeps the layer cache, for
# iterating on a Containerfile without recompiling everything above the change.
cache=(--no-cache); [ "${ACE_LAYER_CACHE:-}" = 1 ] && cache=()
args=(--network none --pull=never "${cache[@]}" -f "$image/Containerfile" -t "localhost/ace-${image}:${tag}")
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

# Base images are pulled while the network is still allowed. A FROM may name
# its image through an ARG (ansible-builder's FROM $EE_BASE_IMAGE), so ARG
# defaults are expanded; stage names are not images.
bases=$(python3 - "$image/Containerfile" "$@" <<'PY'
import re, sys
args, stages, bases = {}, set(), []
# --build-arg K=V among the extra arguments wins over the ARG default.
extra = sys.argv[2:]
for i, a in enumerate(extra):
    v = a.split("=", 1)[1] if a.startswith("--build-arg=") else (extra[i + 1] if a == "--build-arg" and i + 1 < len(extra) else None)
    if v and "=" in v:
        k, val = v.split("=", 1)
        args[k] = val
for line in open(sys.argv[1]):
    m = re.match(r'\s*ARG\s+(\w+)=["\x27]?([^"\x27\s]*)', line)
    if m:
        args.setdefault(m.group(1), m.group(2))
    m = re.match(r'\s*FROM\s+(?:--platform=\S+\s+)?(\S+)(?:\s+AS\s+(\S+))?', line, re.I)
    if m:
        ref = re.sub(r'\$\{?(\w+)\}?', lambda v: args.get(v.group(1), ''), m.group(1))
        if ref not in stages and ref != 'scratch':
            bases.append(ref)
        if m.group(2):
            stages.add(m.group(2))
print(' '.join(dict.fromkeys(bases)))
PY
)
for base in $bases; do
  case "$base" in localhost/*) continue ;; esac  # built here, nothing to pull
  podman pull -q "$base" >/dev/null
done

podman build "${args[@]}" "$@" "$image"
