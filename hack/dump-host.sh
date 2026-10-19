#!/usr/bin/env bash
# hack/dump-host.sh <ssh-host> <out-dir>
#
# The machine side of the parity check: the same facts hack/dump-image.sh
# collects from an image, collected over SSH from a machine AWX the Hard Way
# built by hand. Then:
#
#   hack/dump-image.sh localhost/ace-hub:dev  /tmp/parity/hub/vendor
#   hack/dump-host.sh  awx-hub                /tmp/parity/hub/ace
#   python3 hack/compare-dumps.py /tmp/parity hub
#
# A machine has no image config or labels; those parts of the comparison are
# left empty.
set -euo pipefail
host=${1:?usage: hack/dump-host.sh <ssh-host> <out-dir>}
out=${2:?usage: hack/dump-host.sh <ssh-host> <out-dir>}
mkdir -p "$out"
ssh "$host" 'sudo sh -s' < "$(dirname "$0")/facts.sh" > "$out/inside.txt" 2> "$out/inside.err"
echo '{}' > "$out/config.json"
echo '{}' > "$out/labels.json"
echo "dumped $host into $out"
