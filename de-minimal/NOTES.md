# de-minimal

The minimal decision environment: python, ansible-core, ansible-runner,
ansible-rulebook and the Drools engine it drives through a JVM.

| | |
|---|---|
| Built with | `ansible-builder` (`execution-environment.yml` → `hack/ee-create.sh de-minimal`) |
| Stands in for | `de-minimal-rhel9`, the base Red Hat builds `de-supported-rhel9` FROM |
| Status | new 2026-10-19 |

Red Hat does not ship `de-minimal-rhel9` in the containerized bundle, but its
name is in the build history of `de-supported-rhel9` (`EE_BASE_IMAGE=…/de-minimal-rhel9`),
and its contents are what that image has before its own steps: python 3.12,
the JVM, ansible-core 2.16, ansible-runner 2.4.2, ansible-rulebook, drools-jpy,
jpy, dumb-init, and ansible-builder's entrypoint. This image is that, so
`ace-de-supported` can be built FROM it the same way.

ansible-rulebook is 1.3.0, the release Red Hat's `1.3.0.dev1` became. It pins
drools-jpy 0.4.0 (Red Hat's dev build had 0.4.1).

Like `ee-minimal`, the final stage starts from `ubi9-minimal` itself rather
than from ansible-builder's `base` stage, and gets everything from the
builder as wheels — see `hack/ee-create.sh`.
