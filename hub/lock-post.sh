#!/bin/sh
# Run by hack/lock.sh after pip-compile, from hub/. pulpcore asks for
# psycopg[binary], so pip-compile pins psycopg-binary -- which exists only as
# wheels, with no sdist a hermetic build could compile. The vendor image runs
# plain psycopg on the system libpq instead, so the pin is cut here, and the
# wheels stage builds with --no-deps (every package is pinned anyway).
set -eu
python3.12 - <<'PY'
import re
s = open("requirements.txt").read()
s = re.sub(r"^psycopg-binary==[^\n]*\n(?:[ \t]+[^\n]*\n)*", "", s, flags=re.M)
open("requirements.txt", "w").write(s)
PY
! grep -q '^psycopg-binary' requirements.txt
