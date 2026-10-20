#!/usr/bin/env bash
# hack/prefetch.sh <image>
#
# The prefetch-dependencies step of a Konflux build: Hermeto reads
# <image>/hermeto.json (Konflux's `prefetch-input`) and downloads every
# dependency the build will need -- Python wheels (and sdists) and build backends, Go
# modules, RPMs -- into $ACE_OUT/<image> (default ~/.cache/ace-images).
# hack/build.sh then builds from what is fetched here: pip, npm, Go and dnf
# are all pointed at it. The HTTP timeouts are raised because PyPI's index
# pages for the biggest projects can take longer than Hermeto's default to
# answer from a CI runner.
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
    -e HERMETO_HTTP__CONNECT_TIMEOUT=120 -e HERMETO_HTTP__READ_TIMEOUT=600 \
    "$hermeto" "$@"
}

# Like Konflux, the source is the whole repository; the paths in
# hermeto.json are relative to its root.
run fetch-deps --source . --output /output "$(cat "${image}/hermeto.json")"

# The env file the build applies to every RUN step (PIP_FIND_LINKS,
# PIP_NO_INDEX, GOMODCACHE, ...), written for the path the build mounts the
# output at -- the same /cachi2/output Konflux uses.
run generate-env /output --format json --for-output-dir /cachi2/output -o /output/prefetch-env.json

# The same variables for a build done in place rather than in a container --
# AWX the Hard Way's build host sources this one.
run generate-env /output --format env --for-output-dir "$out" -o /output/prefetch.env

# For RPMs this writes a .repo file per arch pointing at the local repos. For
# npm it also rewrites the source tree: package-lock.json's URLs become paths
# into the prefetched output. That edit belongs to the build, not the
# checkout, so it is saved as a patch beside the output and the submodule put
# back; hack/build.sh applies it for the length of the build.
run inject-files /output --for-output-dir /cachi2/output
: > "$out/inject.patches"
for sub in $(git config --file .gitmodules --get-regexp "^submodule\.${image}/.*\.path$" | awk '{print $2}'); do
  if ! git -C "$sub" diff --quiet; then
    git -C "$sub" diff > "$out/inject-$(basename "$sub").patch"
    echo "$sub inject-$(basename "$sub").patch" >> "$out/inject.patches"
    git -C "$sub" checkout -- .
  fi
done

echo "prefetched into $out ($(du -sh "$out" | cut -f1))"
