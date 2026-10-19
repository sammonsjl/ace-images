"""hack/compare-dumps.py <dir> <name> -- compare <dir>/<name>/vendor with <dir>/<name>/ace
(dumps written by hack/dump-image.sh or hack/dump-host.sh)."""
import json, os, re, sys

base, name = sys.argv[1], sys.argv[2]


def sections(path):
    secs, cur = {}, None
    for line in open(path, errors="replace"):
        line = line.rstrip("\n")
        if line.startswith("### "):
            cur = line[4:]
            secs[cur] = []
        elif cur:
            secs[cur].append(line)
    return secs


def pythons(lines):
    envs, cur = {}, None
    for l in lines:
        if l.startswith("## "):
            parts = l[3:].split()
            cur = parts[1] if len(parts) > 1 else parts[0]
            envs.setdefault(cur, {})
        elif cur and "==" in l:
            n, v = l.split("==", 1)
            envs[cur][re.sub(r"[-_.]+", "-", n).lower()] = v
    return envs


def load(side):
    d = os.path.join(base, name, side)
    s = sections(os.path.join(d, "inside.txt"))
    return {
        "cfg": json.load(open(os.path.join(d, "config.json"))),
        "labels": json.load(open(os.path.join(d, "labels.json"))),
        "rpms": dict(l.split(" ", 1) for l in s.get("rpms", []) if " " in l),
        "os": s.get("os", []),
        "py": pythons(s.get("pythons", [])),
        "inst": s.get("installer", []),
        "bin": s.get("usr-bin", []),
        "layout": s.get("layout", []),
        "passwd": s.get("passwd", []),
    }


v, a = load("vendor"), load("ace")
print(f"# {name}\n")
print("## OS")
print("vendor:", " ".join(v["os"]))
print("ace:   ", " ".join(a["os"]))
print("\n## Config")
for k in sorted(set(v["cfg"]) | set(a["cfg"])):
    if k == "Env":
        ve = {e.split("=", 1)[0]: e.split("=", 1)[1] for e in v["cfg"].get(k) or []}
        ae = {e.split("=", 1)[0]: e.split("=", 1)[1] for e in a["cfg"].get(k) or []}
        for e in sorted(set(ve) | set(ae)):
            if ve.get(e) != ae.get(e):
                print(f"  Env {e}: vendor={ve.get(e)!r} ace={ae.get(e)!r}")
    elif v["cfg"].get(k) != a["cfg"].get(k):
        print(f"  {k}: vendor={v['cfg'].get(k)!r} ace={a['cfg'].get(k)!r}")
print("\n## Version label:", v["labels"].get("version"), "| ace.source.ref:", a["labels"].get("ace.source.ref"))
vr, ar = set(v["rpms"]), set(a["rpms"])
print(f"\n## RPMs: vendor {len(vr)}, ace {len(ar)}, shared {len(vr & ar)}")
print("vendor only:", " ".join(sorted(vr - ar)))
print("ace only:   ", " ".join(sorted(ar - vr)))
print("\n## Python environments")
for side, d in (("vendor", v), ("ace", a)):
    for env, pk in d["py"].items():
        print(f"  {side} {env}: {len(pk)} packages")
print("  installer vendor:", "; ".join(x.strip() for x in v["inst"]))
print("  installer ace:   ", "; ".join(x.strip() for x in a["inst"]))
# Compare the biggest env on each side.
ve = max(v["py"].values(), key=len, default={})
ae = max(a["py"].values(), key=len, default={})
print(f"\n## Main env: vendor {len(ve)} pkgs, ace {len(ae)} pkgs, shared names {len(set(ve) & set(ae))}")
same = [k for k in set(ve) & set(ae) if ve[k] == ae[k]]
print(f"  same version: {len(same)}")
diff = sorted(k for k in set(ve) & set(ae) if ve[k] != ae[k])
print("  different version:", ", ".join(f"{k} {ve[k]}→{ae[k]}" for k in diff))
print("  vendor only:", ", ".join(f"{k}=={ve[k]}" for k in sorted(set(ve) - set(ae))))
print("  ace only:   ", ", ".join(f"{k}=={ae[k]}" for k in sorted(set(ae) - set(ve))))
print("\n## /usr/bin entrypoints")
print("vendor only:", " ".join(sorted(set(v["bin"]) - set(a["bin"]))))
print("ace only:   ", " ".join(sorted(set(a["bin"]) - set(v["bin"]))))
print("\n## Users")
print("vendor:", " | ".join(v["passwd"][-4:]))
print("ace:   ", " | ".join(a["passwd"][-4:]))
