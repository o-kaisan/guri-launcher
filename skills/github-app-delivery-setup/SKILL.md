---
name: github-app-delivery-setup
description: Configure renewable GitHub App authentication for a Codex workspace while keeping the private key outside Git, refreshing hourly installation tokens, and restricting pushes to codex-cloud/* branches. Use when asked to install, repair, or explain the GitHub delivery setup, token refresh, credential helper, or pull-request command.
---

# GitHub App Delivery Setup

Install renewable GitHub credentials without adding secrets to the repository.

## Preconditions

1. Confirm the current Git branch matches `codex-cloud/*`. Create such a branch before making commits when necessary.
2. Require these setup-only environment variables:
   - `CODEX_GITHUB_APP_CLIENT_ID`: GitHub App client ID
   - `CODEX_GITHUB_REPO`: repository in `owner/name` form
   - `CODEX_GITHUB_APP_PRIVATE_KEY`: PEM private key
3. Never print, log, commit, or place the private key inside the repository.

## Install

Run the bundled installer from the repository root:

```bash
bash skills/github-app-delivery-setup/scripts/setup.sh
```

The installer copies the private key to `~/.config/codex-github/private-key.pem` with mode `0600`, installs commands in `~/.local/bin`, creates the `codex-push` remote, configures a renewable Git credential helper, and installs a pre-push branch guard.

After setup, discard the setup secret from the current shell:

```bash
unset CODEX_GITHUB_APP_PRIVATE_KEY
```

## Refresh credentials

Refresh files explicitly with:

```bash
codex-github-refresh
```

The credential helper and PR command refresh automatically when the cached token has less than five minutes remaining. To overwrite GitHub token variables in the **current** shell, source the environment command (executing a child process alone cannot change its parent's environment):

```bash
source codex-github-env
```

## Deliver changes

Push only an allowed branch and then create the PR:

```bash
git push -u codex-push HEAD
codex-pr-create --head "$(git branch --show-current)" --title "Title" --body "Body"
```

Never commit or merge directly to `main`. Treat files below `~/.config/codex-github` as secrets, even though they are outside Git.

## Verify

Run:

```bash
test "$(stat -c '%a' "$HOME/.config/codex-github/private-key.pem")" = 600
git ls-remote codex-push HEAD >/dev/null
git config --global --get-all credential.helper
```

If authentication fails, confirm the GitHub App is installed on the repository and has `contents: write` and `pull_requests: write` permissions.
