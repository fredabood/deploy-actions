#!/usr/bin/env bash
# bump-lock.sh — set one release's commit in homelab's internal/launchd/host-releases.lock.
#
# Usage: bump-lock.sh <lock-file> <name> <fredabood/repo> <sha40>
#
# Replaces the line for <name> in place, or appends one. Comments and every other line are
# untouched. homelab's host-release.sh validates the whole file; this validates its inputs
# with the same rules so a bump can never write a line homelab will reject.
#
# Prints `changed` or `unchanged`. Exit: 0; 2 invalid input or a missing lock file.

set -uo pipefail

lock="${1:-}"; name="${2:-}"; repo="${3:-}"; sha="${4:-}"
[ $# -eq 4 ] || { echo "usage: bump-lock.sh <lock-file> <name> <fredabood/repo> <sha40>" >&2; exit 2; }
[ -f "$lock" ] || { echo "bump-lock: $lock not found (homelab must carry host-releases.lock)" >&2; exit 2; }
[[ "$name" =~ ^[a-z0-9][a-z0-9-]{1,40}$ ]] || { echo "bump-lock: invalid name '$name'" >&2; exit 2; }
[[ "$repo" =~ ^fredabood/[A-Za-z0-9._-]+$ ]] || { echo "bump-lock: repo must be fredabood/<name>, got '$repo'" >&2; exit 2; }
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "bump-lock: sha must be 40 hex, got '$sha'" >&2; exit 2; }

LOCK="$lock" NAME="$name" LINE="$name $repo $sha" python3 - <<'PY'
import os
path, name, new = os.environ["LOCK"], os.environ["NAME"], os.environ["LINE"]
with open(path) as fh:
    lines = fh.read().split("\n")
out, replaced, changed = [], False, False
for line in lines:
    fields = line.split("#", 1)[0].split()
    if fields and fields[0] == name:
        if replaced:
            changed = True          # drop a duplicate; homelab rejects duplicates anyway
            continue
        replaced = True
        if line.strip() != new:
            line, changed = new, True
    out.append(line)
if not replaced:
    while out and out[-1] == "":
        out.pop()
    out += [new, ""]
    changed = True
if changed:
    tmp = path + ".bump-tmp"
    with open(tmp, "w") as fh:
        fh.write("\n".join(out))
    os.replace(tmp, path)
print("changed" if changed else "unchanged")
PY
