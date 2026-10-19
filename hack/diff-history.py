#!/usr/bin/env python3
"""hack/diff-history.py <ours> <theirs>

Compares the final-stage construction of two images, step by step, from
their build history (`podman image inspect`). Each step is reduced to its
shape: the instruction, and for RUN the programs it runs; for COPY, where
it copies to. That way two Containerfiles written in different words, but
built the same way, line up.

Used to hold an ace image against the Red Hat image it mirrors. The vendor
image is read from the local podman store; nothing from it is written out.
Build-system additions (Konflux's buildinfo copies and labels) are skipped.
"""
import difflib
import json
import re
import shlex
import subprocess
import sys

SKIP_DEST = ("/root/buildinfo", "/usr/share/buildinfo")
NOT_COMMANDS = {"then", "else", "fi", "do", "done", "for", "if", "while", "in", "{", "}", "(", ")"}


def history(ref):
    out = subprocess.run(["podman", "image", "inspect", ref], capture_output=True, text=True, check=True).stdout
    return [h.get("created_by") or "" for h in json.loads(out)[0].get("History", [])]


def programs(cmd):
    """The programs a shell command runs, in order, without repeats in a row."""
    found = []
    for seg in re.split(r"&&|\|\||;|\|", cmd):
        try:
            words = shlex.split(seg.strip(), posix=True)
        except ValueError:
            words = seg.split()
        words = [w for w in words if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w)]
        if not words or words[0] in NOT_COMMANDS or words[0].startswith("-"):
            continue
        prog = words[0].rsplit("/", 1)[-1]
        if prog.startswith("python3") and len(words) > 2 and words[1] == "-m":
            prog = f"python -m {words[2]}" + (f" {words[3]}" if len(words) > 3 and not words[3].startswith("-") else "")
        elif prog in ("microdnf", "dnf") and len(words) > 1:
            sub = next((w for w in words[1:] if not w.startswith("-")), "")
            prog = f"{prog} {sub}".replace("microdnf", "dnf")
        elif prog.endswith("pip") and len(words) > 1:
            prog = f"pip {words[1]}"
        if not found or found[-1] != prog:
            found.append(prog)
    return found


def shape(line):
    line = line.strip()
    if re.match(r"^\|\d+ ", line):  # "|2 A=1 B=x y /bin/sh -c ..." -> RUN with build args
        line = line[line.index("/bin/sh -c "):] if "/bin/sh -c " in line else line
    nop = re.match(r"^/bin/sh -c #\(nop\)\s+(\w+)\s*(.*)$", line, re.S)
    if nop:
        instr, rest = nop.group(1).upper(), nop.group(2)
    elif line.startswith("/bin/sh -c "):
        instr, rest = "RUN", line[len("/bin/sh -c "):]
    elif re.match(r"^[A-Z]+ ", line):
        instr, rest = line.split(" ", 1)
    else:
        return None
    if instr == "RUN":
        return "RUN " + " + ".join(programs(rest))
    if instr in ("COPY", "ADD"):
        dest = rest.rsplit(" in ", 1)[-1].strip() if " in " in rest else rest.split()[-1]
        if dest.startswith(SKIP_DEST):
            return None
        return f"COPY -> {dest}"
    if instr == "LABEL":
        if re.search(r'"?(build-date|org\.opencontainers\.image\.created|vcs-ref)"?=', rest):
            return None  # added by the build system, not the Containerfile
        return "LABEL"
    if instr in ("ARG", "ENV"):
        try:
            words = shlex.split(rest)
        except ValueError:
            words = rest.split()
        names = [w.split("=", 1)[0] for w in words if re.match(r"^[A-Za-z_][A-Za-z0-9_]*(=|$)", w)]
        return f"{instr} " + " ".join(sorted(set(names)))
    return f"{instr} {rest}".strip()


def final_stage(ref):
    steps = []
    for st in (shape(h) for h in history(ref)):
        if not st:
            continue
        # buildah records each ARG instruction with every ARG declared so far,
        # so a run of them is one declaration block: keep only the last.
        if st.startswith("ARG ") and steps and steps[-1].startswith("ARG "):
            steps[-1] = st
            continue
        steps.append(st)
    # The base image's own steps end with its CMD; everything after the last
    # CMD that is not this image's own (final) CMD belongs to the final stage.
    # A squashed vendor base leaves no steps at all, so nothing is cut there.
    cmds = [i for i, s in enumerate(steps) if s.startswith("CMD ")]
    if cmds and cmds[-1] >= len(steps) - 3:
        cmds = cmds[:-1]
    return steps[cmds[-1] + 1:] if cmds else steps


ours, theirs = final_stage(sys.argv[1]), final_stage(sys.argv[2])
width = max(len(s) for s in ours + theirs + ["ours"]) + 2
same = 0
for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(a=ours, b=theirs, autojunk=False).get_opcodes():
    a, b = ours[i1:i2], theirs[j1:j2]
    for k in range(max(len(a), len(b))):
        left = a[k] if k < len(a) else ""
        right = b[k] if k < len(b) else ""
        mark = "=" if tag == "equal" else "~"
        same += tag == "equal"
        print(f"{mark} {left:<{width}} {right}")
print(f"\n{same} of {len(theirs)} vendor final-stage steps matched in order")
