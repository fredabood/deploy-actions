#!/usr/bin/env bash
# current-pin.sh — the commit homelab currently pins for an artifact.
#
# Usage:
#   current-pin.sh image <homelab-root> <ghcr.io/fredabood/name>
#   current-pin.sh host-native <homelab-root> <release-name>
#
# Prints the 40-hex commit (from a `:sha-<40hex>@sha256:` image pin, or a lock line), or
# nothing when homelab does not pin it yet. When several stack lines pin the same image
# to different commits, prints nothing and exits 3: the ancestry guard cannot reason
# about a split pin, and a human should look.
#
# Exit: 0 (printed or nothing pinned); 2 usage; 3 inconsistent pins.

set -uo pipefail

kind="${1:-}"; root="${2:-}"; what="${3:-}"
[ -n "$kind" ] && [ -d "$root" ] && [ -n "$what" ] || { echo "usage: current-pin.sh image|host-native <homelab-root> <image|name>" >&2; exit 2; }

case "$kind" in
  image)
    [[ "$what" =~ ^ghcr\.io/fredabood/[a-z0-9._-]+$ ]] || { echo "current-pin: bad image '$what'" >&2; exit 2; }
    shas="$(ROOT="$root" IMAGE="$what" python3 - <<'PY'
import glob, os, re
image = re.escape(os.environ["IMAGE"])
pat = re.compile(r'^\s*image:\s*["\']?' + image + r':sha-([0-9a-f]{40})@sha256:[0-9a-f]{64}["\']?\s*(#.*)?$')
found = set()
for p in glob.glob(os.path.join(os.environ["ROOT"], "stacks", "*-stack.yml")):
    with open(p) as fh:
        for line in fh:
            m = pat.match(line.rstrip("\n"))
            if m:
                found.add(m.group(1))
print("\n".join(sorted(found)))
PY
)"
    ;;
  host-native)
    [[ "$what" =~ ^[a-z0-9][a-z0-9-]{1,40}$ ]] || { echo "current-pin: bad release name '$what'" >&2; exit 2; }
    lock="$root/internal/launchd/host-releases.lock"
    shas=""
    if [ -f "$lock" ]; then
      while read -r name _repo sha _rest; do
        [ "$name" = "$what" ] && shas="$sha"
      done < <(sed 's/#.*//' "$lock")
    fi
    ;;
  *) echo "current-pin: kind must be image or host-native" >&2; exit 2 ;;
esac

n="$(printf '%s' "$shas" | grep -c . || true)"
if [ "$n" -gt 1 ]; then
  echo "current-pin: $what is pinned to $n different commits across the stacks" >&2
  exit 3
fi
printf '%s' "$shas"
