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
ARG GALAXY_NG_REF=0a252890010e89b0d675d5473b43eb4b175c1be0   # main
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
