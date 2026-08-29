#!/usr/bin/env bash
set -euo pipefail
set +x
umask 077

: "${CODEX_GITHUB_APP_CLIENT_ID:?CODEX_GITHUB_APP_CLIENT_ID is required}"
: "${CODEX_GITHUB_REPO:?CODEX_GITHUB_REPO is required}"
: "${CODEX_GITHUB_APP_PRIVATE_KEY:?CODEX_GITHUB_APP_PRIVATE_KEY is required}"

case "$CODEX_GITHUB_REPO" in
    */*) ;;
    *) echo "CODEX_GITHUB_REPO must use owner/name format." >&2; exit 2 ;;
esac

CFG="$HOME/.config/codex-github"
BIN="$HOME/.local/bin"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$CFG" "$BIN"
chmod 700 "$CFG" "$BIN"

python3 -m pip install --user --quiet PyJWT cryptography
printf '%s\n' "$CODEX_GITHUB_APP_PRIVATE_KEY" > "$CFG/private-key.pem"
chmod 600 "$CFG/private-key.pem"
python3 - "$CFG/config.json" <<'PY'
import json
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])
path.write_text(json.dumps({
    "client_id": os.environ["CODEX_GITHUB_APP_CLIENT_ID"],
    "repo": os.environ["CODEX_GITHUB_REPO"],
}) + "\n")
path.chmod(0o600)
PY

install -m 700 "$SCRIPT_DIR/refresh_token.py" "$BIN/codex-github-refresh"

cat > "$BIN/codex-github-credential" <<'PY'
#!/usr/bin/env python3
import sys
from pathlib import Path

sys.path.insert(0, str(Path.home() / ".local" / "bin"))
from importlib.machinery import SourceFileLoader

if len(sys.argv) > 1 and sys.argv[1] == "get":
    module = SourceFileLoader("codex_refresh", str(Path.home() / ".local/bin/codex-github-refresh")).load_module()
    print("username=x-access-token")
    print(f"password={module.refresh()}")
PY
chmod 700 "$BIN/codex-github-credential"

cat > "$BIN/codex-github-env" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
"$HOME/.local/bin/codex-github-refresh" >/dev/null
token="$(<"$HOME/.config/codex-github/installation-token")"
printf 'export GH_TOKEN=%q\nexport GITHUB_TOKEN=%q\n' "$token" "$token"
SH
chmod 700 "$BIN/codex-github-env"

cat > "$BIN/codex-pr-create" <<'PY'
#!/usr/bin/env python3
import argparse
import json
import subprocess
import urllib.request
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--head", required=True)
parser.add_argument("--base", default="main")
parser.add_argument("--title", required=True)
parser.add_argument("--body", default="")
args = parser.parse_args()
if not args.head.startswith("codex-cloud/"):
    parser.error("--head must be a codex-cloud/* branch")

subprocess.run([str(Path.home() / ".local/bin/codex-github-refresh")], check=True, stdout=subprocess.DEVNULL)
cfg = Path.home() / ".config/codex-github"
repo = json.loads((cfg / "config.json").read_text())["repo"]
payload = json.dumps({"title": args.title, "head": args.head, "base": args.base, "body": args.body}).encode()
request = urllib.request.Request(
    f"https://api.github.com/repos/{repo}/pulls",
    data=payload,
    method="POST",
    headers={
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {(cfg / 'installation-token').read_text().strip()}",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "codex-cloud-worker",
        "Content-Type": "application/json",
    },
)
with urllib.request.urlopen(request, timeout=30) as response:
    print(json.load(response)["html_url"])
PY
chmod 700 "$BIN/codex-pr-create"

git config --local credential.helper ""
git config --local --add credential.helper "!$BIN/codex-github-credential"
git remote remove codex-push 2>/dev/null || true
git remote add codex-push "https://github.com/${CODEX_GITHUB_REPO}.git"
git config --local user.name "Codex Cloud Worker"
git config --local user.email "codex-cloud-worker@users.noreply.github.com"

HOOK="$(git rev-parse --git-path hooks/pre-push)"
mkdir -p "$(dirname "$HOOK")"
cat > "$HOOK" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
while read -r _local_ref local_sha remote_ref _remote_sha; do
    case "$remote_ref" in
        refs/heads/codex-cloud/*) ;;
        *) echo "BLOCKED: Codex may push only codex-cloud/* branches." >&2; exit 1 ;;
    esac
    if [[ "$local_sha" =~ ^0+$ ]]; then
        echo "BLOCKED: Remote branch deletion is not allowed." >&2
        exit 1
    fi
done
SH
chmod 700 "$HOOK"

case ":$PATH:" in
    *":$BIN:"*) ;;
    *) printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.bashrc" ;;
esac

"$BIN/codex-github-refresh" --force
git ls-remote codex-push HEAD >/dev/null
echo "GitHub delivery setup completed. Run: unset CODEX_GITHUB_APP_PRIVATE_KEY"
