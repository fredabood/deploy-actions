#!/usr/bin/env bash
# scripts.test.sh — tests for the pure helpers behind bump-homelab-pin.
#
# The action itself needs GitHub (an App token, a real homelab checkout); these helpers do
# not, and they hold the decisions that matter: never downgrade a pin, never write a lock
# line homelab rejects, never put an issue reference where homelab's issue-transitions
# workflow would act on it.
#
# Run: bash scripts/tests/scripts.test.sh

set -u
DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
SANDBOX="$(mktemp -d)"; trap 'rm -rf "$SANDBOX"' EXIT
ok() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }
eq() { if [ "$1" = "$2" ]; then ok "$3"; else no "$3 (got '$1', want '$2')"; fi; }

A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
D=sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc

echo "=== ancestry-decision ==="
d() { bash "$DIR/ancestry-decision.sh" "$@" | cut -f1; }
eq "$(d '' "$B" '')" bump "no current pin: bump"
eq "$(d "$B" "$B" '')" skip "same commit: skip"
eq "$(d "$A" "$B" ahead)" bump "new descends from pinned: bump"
eq "$(d "$A" "$B" behind)" skip "older commit: skip (never downgrade)"
eq "$(d "$A" "$B" diverged)" skip "rewritten history: skip"
eq "$(d "$A" "$B" identical)" skip "identical trees: skip"
eq "$(d "$A" "$B" '')" skip "compare failed: skip, do not guess"
bash "$DIR/ancestry-decision.sh" "$A" nope ahead >/dev/null 2>&1; eq "$?" 2 "a non-sha new commit is a usage error"

echo "=== current-pin ==="
H="$SANDBOX/homelab"; mkdir -p "$H/stacks" "$H/internal/launchd"
printf 'services:\n  a:\n    image: ghcr.io/fredabood/demo:sha-%s@%s  # c\n  b:\n    image: "ghcr.io/fredabood/demo:sha-%s@%s"\n  c:\n    image: ghcr.io/fredabood/demo-jobs:sha-%s@%s\n' "$A" "$D" "$A" "$D" "$B" "$D" > "$H/stacks/demo-stack.yml"
eq "$(bash "$DIR/current-pin.sh" image "$H" ghcr.io/fredabood/demo)" "$A" "reads the pinned commit (two services agree)"
eq "$(bash "$DIR/current-pin.sh" image "$H" ghcr.io/fredabood/demo-jobs)" "$B" "a prefix-sharing image is its own pin"
eq "$(bash "$DIR/current-pin.sh" image "$H" ghcr.io/fredabood/new)" "" "an unconsumed image has no pin"
printf 'services:\n  z:\n    image: ghcr.io/fredabood/demo:sha-%s@%s\n' "$B" "$D" > "$H/stacks/other-stack.yml"
bash "$DIR/current-pin.sh" image "$H" ghcr.io/fredabood/demo >/dev/null 2>&1; eq "$?" 3 "split pins across stacks refuse (exit 3)"
rm "$H/stacks/other-stack.yml"
printf '# comment\nomnigent fredabood/omnigent %s\nother fredabood/other %s # trailing\n' "$A" "$B" > "$H/internal/launchd/host-releases.lock"
eq "$(bash "$DIR/current-pin.sh" host-native "$H" omnigent)" "$A" "reads a lock entry"
eq "$(bash "$DIR/current-pin.sh" host-native "$H" other)" "$B" "a lock entry with a trailing comment"
eq "$(bash "$DIR/current-pin.sh" host-native "$H" absent)" "" "an absent release has no pin"

echo "=== bump-lock ==="
L="$H/internal/launchd/host-releases.lock"
eq "$(bash "$DIR/bump-lock.sh" "$L" omnigent fredabood/omnigent "$B")" changed "replaces an existing entry"
grep -qx "omnigent fredabood/omnigent $B" "$L" && ok "the new line is written" || no "the new line is written"
grep -q '^# comment$' "$L" && grep -q "^other fredabood/other $B # trailing$" "$L" && ok "comments and other entries are untouched" || no "comments and other entries are untouched"
eq "$(bash "$DIR/bump-lock.sh" "$L" omnigent fredabood/omnigent "$B")" unchanged "idempotent"
eq "$(bash "$DIR/bump-lock.sh" "$L" fresh fredabood/fresh "$A")" changed "appends a new entry"
[ "$(tail -c1 "$L" | od -An -c | tr -d ' ')" = '\n' ] && ok "the file still ends with a newline" || no "the file still ends with a newline"
for bad in "BAD fredabood/x $A" "ok someone/x $A" "ok fredabood/x abc"; do
  # shellcheck disable=SC2086
  bash "$DIR/bump-lock.sh" "$L" $bad >/dev/null 2>&1; eq "$?" 2 "rejects: $bad"
done

echo "=== pr-body ==="
export KIND=image SUBJECT=ghcr.io/fredabood/demo SOURCE_REPO=fredabood/demo SOURCE_SHA=$B \
  NEW_REF="ghcr.io/fredabood/demo:sha-$B@$D" OLD_REF="ghcr.io/fredabood/demo:sha-$A" \
  RUN_URL=https://github.com/fredabood/demo/actions/runs/123 ACTIONS="compose:demo" \
  REFUSED="refused data-platform: see issue #1784 and HL-12"
title="$(bash "$DIR/pr-body.sh" title)"; body="$(bash "$DIR/pr-body.sh" body)"
case "$title" in chore:*) ok "title uses an allow-listed no-ticket prefix" ;; *) no "title uses an allow-listed no-ticket prefix ($title)" ;; esac
if grep -qE '#[0-9]|(^|[^A-Za-z0-9])HL-[0-9]' <<<"$title$body"; then no "no issue reference survives into title or body"; else ok "no issue reference survives into title or body"; fi
grep -qF "compose:demo" <<<"$body" && ok "body names what merging deploys" || no "body names what merging deploys"
grep -qF "refuses" <<<"$body" && ok "body warns about a refused stack" || no "body warns about a refused stack"
KIND=host-native SUBJECT=omnigent NEW_REF=$B OLD_REF=$A body="$(KIND=host-native SUBJECT=omnigent bash "$DIR/pr-body.sh" body)"
grep -qF "host-release.sh apply omnigent" <<<"$body" && ok "host-native body gives the apply command" || no "host-native body gives the apply command"

echo; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
