#!/usr/bin/env bash
# pr-body.sh — title and body for a deploy-bump PR on homelab.
#
# Usage: pr-body.sh title|body
# Env:   KIND (image|host-native), SUBJECT (image repo or release name), SOURCE_REPO,
#        SOURCE_SHA, OLD_REF (previous pin or empty), NEW_REF (new pin), RUN_URL,
#        ACTIONS (e.g. "compose:buzz" or empty), REFUSED (bump-image-pin's refused lines)
#
# THE ONE RULE: nothing it writes may contain `#<digits>` or an `HL-<n>` key.
# homelab's issue-transitions.yml scans PR titles, branches and commit messages for
# those and comments on the matching issues — a bump would spam unrelated issues.
# Links use full URLs instead. The body is sanitised as a last line of defence.

set -uo pipefail
: "${KIND:?}" "${SUBJECT:?}" "${SOURCE_REPO:?}" "${SOURCE_SHA:?}" "${NEW_REF:?}"
short="${SOURCE_SHA:0:7}"
name="${SUBJECT##*/}"

sanitise() { sed -E 's/#([0-9])/# \1/g; s/(^|[^A-Za-z0-9])HL-([0-9])/\1HL- \2/g'; }

case "${1:-}" in
  title)
    printf 'chore: deploy %s at %s (bump from %s)\n' "$name" "$short" "$SOURCE_REPO" | sanitise
    ;;
  body)
    {
      echo "Automated pin bump from https://github.com/${SOURCE_REPO}/commit/${SOURCE_SHA}"
      echo
      echo "| | |"
      echo "|---|---|"
      echo "| Kind | ${KIND} |"
      echo "| Artifact | \`${SUBJECT}\` |"
      echo "| From | \`${OLD_REF:-(not pinned before)}\` |"
      echo "| To | \`${NEW_REF}\` |"
      echo "| Build | ${RUN_URL:-} |"
      echo
      if [ "$KIND" = image ]; then
        echo "**Merging this deploys it.** deploy-on-green pulls the image and recreates: \`${ACTIONS:-nothing — no stack consumes it yet}\`."
        if [ -n "${REFUSED:-}" ]; then
          echo
          echo "> [!WARNING]"
          echo "> The automated deploy **refuses** this stack, so merging records the pin but a human must apply it:"
          printf '%s\n' "$REFUSED" | sed 's/^/> /'
        fi
      else
        echo "**Merging this deploys nothing.** Apply it on the host (HostReleaseDrift fires until you do):"
        echo
        echo '```'
        echo "internal/scripts/host-release.sh apply ${SUBJECT}"
        echo '```'
      fi
      echo
      echo "**Rollback:** revert this PR$( [ "$KIND" = host-native ] && echo ", then apply again (the previous release is still on disk)")."
      echo
      echo "This PR changes only pin lines; homelab CI enforces that (\`check-deploy-layer.sh --bump-diff\`). A newer publish of the same artifact replaces it rather than opening another."
      echo
      echo "<!-- deploy-bump {\"kind\":\"${KIND}\",\"subject\":\"${SUBJECT}\",\"source\":\"${SOURCE_REPO}@${SOURCE_SHA}\"} -->"
    } | sanitise
    ;;
  *) echo "usage: pr-body.sh title|body" >&2; exit 2 ;;
esac
