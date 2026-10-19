#!/usr/bin/env bash
# hack/prefetch.sh <image>
#
# The prefetch-dependencies step of a Konflux build: Hermeto reads
# <image>/hermeto.json (Konflux's `prefetch-input`) and downloads every
# dependency the build will need -- Python sdists and build backends, Go
# modules, RPMs -- into $ACE_OUT/<image> (default ~/.cache/ace-images).
# hack/build.sh then builds with no network, so anything not fetched here
# makes the build fail.
#
# The output lives outside the repo on purpose: Hermeto copies the whole
# source tree before it starts, and the output would be copied with it.
set -euo pipefail

image=${1:?usage: hack/prefetch.sh <image>}
root=$(cd "$(dirname "$0")/.." && pwd)
hermeto=${HERMETO_IMAGE:-ghcr.io/hermetoproject/hermeto:0.63.0}
out_root=${ACE_OUT:-${XDG_CACHE_HOME:-$HOME/.cache}/ace-images}
out="${out_root}/${image}"

cd "$root"
[ -f "${image}/hermeto.json" ] || { echo "no ${image}/hermeto.json" >&2; exit 1; }
rm -rf "$out"
mkdir -p "$out"

# Hermeto checks the source is a git checkout, and fetches its tags to work
# out Go module versions. The repo may be owned by another uid (a NAS mount,
# a CI runner), so trust it for this run only; and an SSH origin is read
# over HTTPS, since the container has no SSH keys.
run() {
  podman run --rm -v "$root:/repo:Z" -v "$out:/output:Z" -w /repo \
    -e GIT_CONFIG_COUNT=2 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' \
    -e GIT_CONFIG_KEY_1=url.https://github.com/.insteadOf -e GIT_CONFIG_VALUE_1=git@github.com: \
    "$hermeto" "$@"
}

# Like Konflux, the source is the whole repository; the paths in
# hermeto.json are relative to its root.
run fetch-deps --source . --output /output "$(cat "${image}/hermeto.json")"

# The env file the build applies to every RUN step (PIP_FIND_LINKS,
# PIP_NO_INDEX, GOMODCACHE, ...), written for the path the build mounts the
# output at -- the same /cachi2/output Konflux uses.
run generate-env /output --format json --for-output-dir /cachi2/output -o /output/prefetch-env.json

# For RPMs this writes a .repo file per arch pointing at the local repos.
run inject-files /output --for-output-dir /cachi2/output

echo "prefetched into $out ($(du -sh "$out" | cut -f1))"
