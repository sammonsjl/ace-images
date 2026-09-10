# hub

galaxy_ng on pulpcore.

| | |
|---|---|
| Source | [ansible/galaxy_ng](https://github.com/ansible/galaxy_ng) |
| Base | `docker.io/pulp/base` |
| Built in | [Lab 8](../../docs/08-hub.md) |
| Status | **built and running** (2026-08-27) |

**Why built rather than pulled:** the published galaxy-ng image is amd64-only, and `pulp/pulp-galaxy-ng` is abandoned.

Refs this image builds at (resolved 2026-09-10):

```
ARG GALAXY_NG_REF=1f2b27c70398aef9976188ecd23bbb750213befb   # main @ 2026-08-27
django-ansible-base @ 3a099ee5fc4322397c79afcaf7dd1e045e2dc90c   # devel
```

> The ref previously recorded here, `04335c3a…`, is the head of **`master`** —
> the stale branch the correction below warns against, not `main`. It was
> carried forward from the July build and is why "verify before reusing" was
> written next to it. Verified and replaced 2026-09-10.

Forces `django-ansible-base` to a ref matching the gateway's, so the JWT dialect agrees. That pin needs a manual check against galaxy_ng's own `setup.py` on every refresh — an open question in Lab 8 is whether that can be made mechanical.

## Built 2026-08-27

The dependency story is the lab. galaxy_ng's setup.py declares loose ranges, and
pip explores them for a very long time without failing, so the build feeds it
galaxy_ng's own pip-compile lockfile as constraints. Two things have to be
stripped first: extras (pip refuses a constraints file that carries them) and
direct git references (a constraint must be a name and a version specifier).
django-ansible-base is then overridden to match the gateway's JWT dialect.

## Corrected 2026-08-28

Built from `main`, not `master`. `master` is a stale branch (4.11.0dev,
pulpcore 3.49.40) whose lockfile no longer resolves; `main` is the default
branch and gives 4.12.0dev on pulpcore 3.105.12 — the same platform the vendor
ships. Cross-checked against `hub-rhel9`: pulpcore and pulp-ansible match
exactly.

Config parity: named `galaxy` user, WORKDIR /, PYTHONUNBUFFERED=1 (the pulp/base
image sets it to 0, which keeps pulpcore's output out of the journal).

## Base image — corrected 2026-09-10

First attempt at pinning the base picked `pulp/base:3.105`, reasoning that the
tag should match the pulpcore galaxy_ng asks for. That is wrong, and it fails
the build outright:

    ERROR: Cannot install galaxy-ng because these package versions have
    conflicting dependencies.
        ansible-lint 26.4.0 depends on ansible-core>=2.16.14
        The user requested (constraint) ansible-core==2.21.0

The message is misleading — those two are compatible. The real cause is the
interpreter. `ansible-core==2.21.0` requires Python >= 3.12; the 3.105 line is
CentOS Stream 9 on Python 3.11, so the constraint is simply unsatisfiable and
pip reports the nearest conflicting pair instead. The giveaway in the log is
`pip is looking at multiple versions of <Python from Requires-Python>`.

**The base tag is chosen by Python version, not by pulpcore version.** 3.117 is
Stream 10 on Python 3.12.14. pulpcore is then downgraded to 3.105.x by the
lockfile constraints, which is the intended arrangement: the base gives the
platform and the interpreter, the lockfile gives the versions.

`GALAXY_NG_REF` is main as of 2026-08-27, the date this image is recorded as
built and running, rather than main's current head.

## Verified 2026-09-10

Built on `pulp/base:3.117` and confirmed in the running image:

    os        CentOS Stream 10
    python    3.12.14
    pulpcore  3.105.12     <- pulled back from the base's 3.117 by the lockfile
    galaxy-ng 4.12.0.dev0  <- main, not master's 4.11

That pulpcore line is the whole arrangement working as intended: the base
supplies the platform and the interpreter, the lockfile supplies the versions.
