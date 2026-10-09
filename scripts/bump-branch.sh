#!/usr/bin/env bash
# bump-branch.sh — the homelab branch a bump PR lives on: one per source repo AND artifact.
#
# Usage: bump-branch.sh <source-repo> <subject>
#   source-repo  owner/name of the publishing repo (github.repository), e.g. fredabood/incubator
#   subject      kind=image: ghcr.io/fredabood/<name>; kind=host-native: the release name
#
# Prints:  deploy-bump/<repo-short>-<subject-short>
#   fredabood/homelab   + ghcr.io/fredabood/buzz-notifier  ->  deploy-bump/homelab-buzz-notifier
#   fredabood/incubator + ghcr.io/fredabood/wikipedia      ->  deploy-bump/incubator-wikipedia
#   fredabood/omnigent  + omnigent (host-native)           ->  deploy-bump/omnigent-omnigent
#
# Why per artifact: a repo that publishes several images (incubator) used to share one
# deploy-bump/<repo> branch, so each publish force-replaced the other image's open bump.
# A newer publish of the SAME artifact still replaces its own PR, which is the point.
#
# The name is lower-cased and everything outside [a-z0-9-] becomes '-'. That keeps it a
# valid git ref whatever the inputs (no '..', no leading '.', no '.lock' suffix), and it
# keeps the one rule pr-body.sh holds for titles: homelab's issue-transitions workflow
# scans the branch for upper-case keys such as LAB-<n> or HL-<n>, and '#' never survives.
# homelab only matches the deploy-bump/ prefix, so the suffix is free to change.
#
# Exit: 0 printed; 2 usage error (missing or empty argument, nothing left after cleaning).

set -euo pipefail
[ $# -eq 2 ] || { echo "usage: bump-branch.sh <source-repo> <subject>" >&2; exit 2; }
repo="${1##*/}"
subject="${2##*/}"
[ -n "$repo" ] && [ -n "$subject" ] || { echo "bump-branch.sh: empty source repo or subject" >&2; exit 2; }

clean() { tr '[:upper:]' '[:lower:]' <<<"$1" | sed -E 's/[^a-z0-9-]+/-/g; s/-+/-/g; s/^-//; s/-$//'; }
r="$(clean "$repo")"
s="$(clean "$subject")"
[ -n "$r" ] && [ -n "$s" ] || { echo "bump-branch.sh: '$1' / '$2' leave nothing after cleaning" >&2; exit 2; }
printf 'deploy-bump/%s-%s\n' "$r" "$s"
