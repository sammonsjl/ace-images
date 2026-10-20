#!/usr/bin/env python3
"""hack/check-build-deps.py <prefetched-pip-dir>

Before a build from the prefetch finds it the slow way: reads the [build-system]
requires of every sdist Hermeto prefetched, and lists the ones no prefetched
file can satisfy. Each line printed belongs in the image's
requirements-build-extra.in. (pybuild-deps misses some -- conditional
requirements, and backends that ask for more in get_requires_for_build_*.)
"""
import re
import sys
import tarfile
import tomllib
import zipfile
from pathlib import Path

from packaging.requirements import Requirement
from packaging.utils import canonicalize_name, parse_sdist_filename, parse_wheel_filename

pipdir = Path(sys.argv[1])
have = {}
for f in pipdir.iterdir():
    try:
        if f.name.endswith(".whl"):
            name, version, *_ = parse_wheel_filename(f.name)
        else:
            name, version = parse_sdist_filename(f.name)
    except Exception:
        continue
    have.setdefault(canonicalize_name(name), set()).add(version)

env = {"python_version": "3.12", "python_full_version": "3.12.12", "sys_platform": "linux",
       "platform_system": "Linux", "platform_machine": "x86_64", "implementation_name": "cpython",
       "platform_python_implementation": "CPython", "os_name": "posix"}

missing = set()
for f in sorted(pipdir.iterdir()):
    data = None
    try:
        if f.name.endswith((".tar.gz", ".tgz")):
            with tarfile.open(f) as t:
                m = next((m for m in t.getmembers() if re.fullmatch(r"[^/]+/pyproject\.toml", m.name)), None)
                data = t.extractfile(m).read() if m else None
        elif f.name.endswith(".zip"):
            with zipfile.ZipFile(f) as z:
                n = next((n for n in z.namelist() if re.fullmatch(r"[^/]+/pyproject\.toml", n)), None)
                data = z.read(n) if n else None
    except Exception:
        continue
    if not data:
        continue
    try:
        requires = tomllib.loads(data.decode()).get("build-system", {}).get("requires", [])
    except Exception:
        continue
    for r in requires:
        req = Requirement(r)
        if req.marker and not req.marker.evaluate(env):
            continue
        versions = have.get(canonicalize_name(req.name), set())
        if not any(req.specifier.contains(v, prereleases=True) for v in versions):
            missing.add(f"{req.name}{req.specifier}  # for {f.name}")
for m in sorted(missing, key=str.lower):
    print(m)
