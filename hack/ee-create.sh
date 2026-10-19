#!/usr/bin/env bash
# hack/ee-create.sh <image>
#
# Turns <image>/execution-environment.yml into its build context with
# ansible-builder (Containerfile + _build/), the way Red Hat's EE and DE
# images start out. Commit the result; hack/build.sh builds it.
#
# Two edits after generating, matching what the vendor's image history shows:
#
#   - the final stage starts from the base image itself, not from
#     ansible-builder's `base` stage, so python, ansible-core and
#     ansible-runner reach the final image only as RPMs and wheels from the
#     builder (install-from-bindep);
#   - the `base` stage does not pip-install ansible-core and ansible-runner.
#     The builder inherits `base`, and a package already installed there is
#     never built into a wheel -- so the final stage, with no compilers,
#     would have to build it from source. ansible-core and ansible-runner are
#     in the image's requirements.in instead, and come as wheels like
#     everything else.
set -euo pipefail

image=${1:?usage: hack/ee-create.sh <image>}
root=$(cd "$(dirname "$0")/.." && pwd)
tools=localhost/ace-tools:latest

cd "$root"
podman image exists "$tools" || podman build -q -t "$tools" hack/tools >/dev/null
rm -rf "$image/_build" "$image/Containerfile"
podman run --rm -v "$root:/work:Z" -w "/work/$image" "$tools" \
  ansible-builder create -f execution-environment.yml -c . --output-filename Containerfile
sed -i 's/^FROM base AS final$/FROM $EE_BASE_IMAGE AS final/' "$image/Containerfile"
sed -i '/^RUN \$PYCMD -m pip install --no-cache-dir \$ANSIBLE_INSTALL_REFS$/d' "$image/Containerfile"
! grep -q 'ANSIBLE_INSTALL_REFS$' "$image/Containerfile"
grep -q '^FROM \$EE_BASE_IMAGE AS final$' "$image/Containerfile"
