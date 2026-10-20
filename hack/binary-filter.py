#!/usr/bin/env python3
"""hack/binary-filter.py <image>

Writes the `binary.packages` list into <image>/hermeto.json: every pinned
Python package that PyPI has a usable wheel for, on both architectures the
images are built for. Hermeto then prefetches those as wheels only, and the
rest as sdists only, which the build compiles.

Why a list and not ":all:": with ":all:" Hermeto fetches each package's sdist
beside its wheels, and inspects every sdist it fetches -- including ones with
Rust inside whose Cargo.lock it rejects -- although the build never compiles
them. With a list, a package is one or the other.

"Usable" means a wheel for CPython 3.12 (cp312, abi3 from an older cp3, or
pure Python) and, unless pure, a glibc manylinux tag no newer than UBI 9's
glibc 2.34, for x86_64 and for aarch64. Packages named in <image>/no-binary.txt
(one per line) always stay sdists, because the image needs them compiled here.

Run by hack/lock.sh after the pip locks; needs network (PyPI's simple index).
"""
import concurrent.futures
import json
import re
import sys
import time
import urllib.request
from pathlib import Path

ARCHES = ("x86_64", "aarch64")
GLIBC_MAX = (2, 34)
LEGACY = {"manylinux1": (2, 5), "manylinux2010": (2, 12), "manylinux2014": (2, 17)}


def canonical(name):
    return re.sub(r"[-_.]+", "-", name).lower()


def pins(path):
    for line in path.read_text().splitlines():
        m = re.match(r"^([A-Za-z0-9][A-Za-z0-9._-]*)==([^\s;\\]+)", line)
        if m:
            yield canonical(m.group(1)), m.group(2)


def python_ok(py, abi):
    pys, abis = py.split("."), abi.split(".")
    for p in pys:
        if p in ("py3", "py312") and "none" in abis:
            return True
        if p == "cp312" and ({"cp312", "abi3", "none"} & set(abis)):
            return True
        m = re.match(r"cp3(\d+)$", p)
        if m and int(m.group(1)) <= 12 and "abi3" in abis:
            return True
    return False


def arches_ok(plat):
    if plat == "any":
        return set(ARCHES)
    found = set()
    for tag in plat.split("."):
        m = re.match(r"manylinux_(\d+)_(\d+)_(\w+)$", tag)
        if m and (int(m.group(1)), int(m.group(2))) <= GLIBC_MAX:
            found.add(m.group(3))
            continue
        m = re.match(r"(manylinux1|manylinux2010|manylinux2014)_(\w+)$", tag)
        if m:
            found.add(m.group(2))
    return found & set(ARCHES)


def has_wheels(name, version):
    # The simple index (PEP 691 JSON), as pip and Hermeto read it: the JSON
    # API answers some releases with an empty body.
    req = urllib.request.Request(f"https://pypi.org/simple/{name}/",
                                 headers={"Accept": "application/vnd.pypi.simple.v1+json"})
    for attempt in range(6):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                files = json.load(r)["files"]
            break
        except Exception as e:
            if attempt == 5:
                raise RuntimeError(f"{name}=={version}: {e}") from e
            time.sleep(2 ** attempt)
    covered = set()
    for f in files:
        fn = f["filename"]
        if not fn.endswith(".whl"):
            continue
        parts = fn[:-4].split("-")
        if canonical(parts[1]) != canonical(version) and parts[1] != version:
            continue
        py, abi, plat = parts[-3], parts[-2], parts[-1]
        if python_ok(py, abi):
            covered |= arches_ok(plat)
    return covered == set(ARCHES)


def main():
    image = Path(sys.argv[1])
    cfg_path = image / "hermeto.json"
    cfg = json.loads(cfg_path.read_text())
    skip = set()
    if (image / "no-binary.txt").exists():
        skip = {canonical(l.split("#")[0].strip()) for l in (image / "no-binary.txt").read_text().splitlines()
                if l.split("#")[0].strip()}
    for entry in cfg:
        if entry.get("type") != "pip":
            continue
        root = image.parent / entry.get("path", image.name)
        files = entry.get("requirements_files", []) + entry.get("requirements_build_files", [])
        wanted = {}
        for f in files:
            for name, version in pins(root / f):
                wanted.setdefault((name, version), None)
        with concurrent.futures.ThreadPoolExecutor(8) as pool:
            results = dict(zip(wanted, pool.map(lambda nv: has_wheels(*nv), wanted)))
        # Hermeto filters by name, so a name pinned twice (runtime and build)
        # is a wheel only if every pinned version has one.
        source = sorted({n for (n, v), ok in results.items() if not ok or n in skip})
        binary = sorted({n for (n, v) in results} - set(source))
        entry["binary"] = {"packages": ",".join(binary), "arch": ",".join(ARCHES), "os": "linux", "py_version": 312}
        print(f"{image.name}: {len(binary)} as wheels, {len(source)} as sdists: {' '.join(source)}")
    cfg_path.write_text(json.dumps(cfg, indent=2) + "\n")


if __name__ == "__main__":
    main()
