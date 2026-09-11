#!/usr/bin/env bash
# ancestry-decision.sh — may a bump move the pin from <old> to <new>?
#
# Usage: ancestry-decision.sh <old-sha-or-empty> <new-sha> <compare-status-or-empty>
#
# <compare-status> is GitHub's `status` for GET /repos/{source}/compare/{old}...{new}:
# ahead | behind | identical | diverged. The caller fetches it; this is the pure decision,
# so it can be tested without the network.
#
#   no current pin           -> bump   (first publish of a newly consumed image)
#   old == new / identical   -> skip   (nothing to do)
#   ahead                    -> bump   (new descends from what is deployed)
#   behind                   -> skip   (a re-run of an OLDER commit must never downgrade)
#   diverged                 -> skip   (force-pushed history; a human decides)
#   anything else            -> skip   (the compare failed; refuse rather than guess)
#
# Prints `bump` or `skip<TAB><reason>`. Exit 0; 2 usage.

set -uo pipefail
[ $# -eq 3 ] || { echo "usage: ancestry-decision.sh <old> <new> <status>" >&2; exit 2; }
old="$1"; new="$2"; status="$3"
[[ "$new" =~ ^[0-9a-f]{40}$ ]] || { echo "ancestry-decision: new must be a 40-hex sha" >&2; exit 2; }

if [ -z "$old" ]; then printf 'bump\n'; exit 0; fi
if [ "$old" = "$new" ]; then printf 'skip\talready pinned to this commit\n'; exit 0; fi
case "$status" in
  ahead) printf 'bump\n' ;;
  identical) printf 'skip\tthe pinned commit and this one have identical trees\n' ;;
  behind) printf 'skip\tthis commit is OLDER than the pinned one; refusing to downgrade\n' ;;
  diverged) printf 'skip\tthis commit does not descend from the pinned one (rewritten history?); bump by hand if intended\n' ;;
  *) printf 'skip\tcould not compare the pinned commit with this one (status %s); refusing to guess\n' "${status:-<none>}" ;;
esac
