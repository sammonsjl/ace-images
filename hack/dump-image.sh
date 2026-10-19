#!/usr/bin/env bash
# hack/dump-image.sh <image-ref> <out-dir>
# Writes the structural facts of one image -- RPMs, Python packages per
# interpreter, users, key paths -- so two images, or an image and a machine
# (hack/dump-host.sh), can be compared with hack/compare-dumps.py.
set -euo pipefail
img=$1 out=$2
mkdir -p "$out"

podman image inspect "$img" > "$out/inspect.json"
python3 -I - "$out" <<'EOF'
import json, sys, os
out = sys.argv[1]
i = json.load(open(os.path.join(out, "inspect.json")))[0]
c = i.get("Config", {})
json.dump(c.get("Labels") or {}, open(os.path.join(out, "labels.json"), "w"), indent=1, sort_keys=True)
keep = {k: c.get(k) for k in ("User", "Entrypoint", "Cmd", "Env", "WorkingDir", "ExposedPorts", "Volumes", "StopSignal")}
json.dump(keep, open(os.path.join(out, "config.json"), "w"), indent=1, sort_keys=True)
with open(os.path.join(out, "history.txt"), "w") as f:
    for h in i.get("History", []):
        f.write((h.get("created_by") or "").strip() + "\n")
EOF

# Everything else is read from inside the image, as root, without its entrypoint.
podman run --rm --user 0 --entrypoint /bin/sh --net none -v "$(cd "$(dirname "$0")" && pwd)/facts.sh:/tmp/facts.sh:ro,Z" "$img" /tmp/facts.sh > "$out/inside.txt" 2> "$out/inside.err" || true

podman run --rm --user 0 --entrypoint /bin/sh --net none "$img" -c \
  'cat /root/buildinfo/content-sets.json 2>/dev/null; ls -la /root/buildinfo /usr/share/buildinfo 2>/dev/null' > "$out/buildinfo.txt" 2>/dev/null || true
echo "done $img"
