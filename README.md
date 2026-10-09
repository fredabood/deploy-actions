# deploy-actions

Shared GitHub Actions for **code repos that homelab deploys**. A code repo builds and publishes its
artifact; these actions open a pull request on `fredabood/homelab` that moves one pin; a human merges
it; homelab's deploy pulls and runs it. Merging the bump is the deploy, and reverting it is the rollback.

Design and contract: `fredabood/homelab` → `docs/development/code-repo-contract.md`
(programme: homelab#1845).

| Piece | What it does |
|---|---|
| `.github/actions/publish-image` | buildx `linux/arm64` → `ghcr.io/<owner>/<name>:sha-<commit>` (no `:latest`, no attestation index), pulls it back by digest, checks it is arm64, optional smoke command. Outputs the literal pin `image:sha-…@sha256:…`. |
| `.github/actions/bump-homelab-pin` | As the `fredabood-homelab-deploy` GitHub App: checks out homelab, refuses to move a pin backwards (ancestry compare), rewrites the pin **with homelab's own** `bump-image-pin.sh` (or the `host-releases.lock` line), and force-updates a single `deploy-bump/<repo>-<artifact>` PR (e.g. `deploy-bump/homelab-buzz-notifier`; name from `scripts/bump-branch.sh`). Never merges. |
| `.github/workflows/publish-and-bump.yml` | Reusable workflow chaining the two for an image. |
| `templates/publish.yml` | What a code repo copies. |

## Enrolling a repo

1. Meet the contract (arm64, non-root, env-only config, CI on PRs).
2. Give it the App key once:
   ```bash
   op document get "GitHub App homelab-deploy private key" --vault Homelab \
     | gh secret set HOMELAB_BUMP_APP_KEY -R fredabood/<repo>
   ```
3. Copy `templates/publish.yml` and fill in the image name and context.
4. Make homelab consume the image with a literal pin once by hand; from then on bumps are automatic.

## Why these choices

- **A GitHub App, not a PAT.** It is installed on `fredabood/homelab` only, can write contents and
  pull requests but **not workflows**, and its commits are visibly a bot's. The branch ruleset has no
  bypass, so it cannot merge.
- **One branch per source repo and artifact** (`deploy-bump/<repo>-<image or release>`, since v1.1.0;
  `deploy-bump/<repo>` before). A newer publish of the same artifact replaces its open bump instead of
  stacking a second one, and a repo that publishes several images (incubator) gets one PR, and one
  rollback, per image instead of each publish overwriting the other's bump. The publish concurrency
  group is keyed the same way.
- **No `#<n>` anywhere.** homelab's `issue-transitions.yml` comments on every issue referenced in a PR's
  title, branch or commits; a bump must not trigger that.
- **Public repo, no secrets.** Callers pass the App key; nothing here is sensitive.
