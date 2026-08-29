#!/usr/bin/env python3
"""Create or reuse a short-lived GitHub App installation token."""

import argparse
import json
import os
import tempfile
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import jwt


CFG = Path.home() / ".config" / "codex-github"
API_VERSION = "2022-11-28"


def write_secret(path: Path, value: str) -> None:
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(value)
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def parse_expiry(value: str) -> float:
    return datetime.fromisoformat(value.strip().replace("Z", "+00:00")).timestamp()


def cached_token_is_fresh() -> bool:
    try:
        return parse_expiry((CFG / "expires-at").read_text()) > time.time() + 300
    except (FileNotFoundError, ValueError):
        return False


def api_request(url: str, app_jwt: str, *, payload: dict | None = None) -> dict:
    data = json.dumps(payload).encode() if payload is not None else None
    request = urllib.request.Request(
        url,
        data=data,
        method="POST" if data is not None else "GET",
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {app_jwt}",
            "X-GitHub-Api-Version": API_VERSION,
            "User-Agent": "codex-cloud-worker",
            **({"Content-Type": "application/json"} if data is not None else {}),
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def refresh(force: bool = False) -> str:
    CFG.mkdir(parents=True, exist_ok=True, mode=0o700)
    if not force and cached_token_is_fresh():
        return (CFG / "installation-token").read_text().strip()

    settings = json.loads((CFG / "config.json").read_text(encoding="utf-8"))
    repo = settings["repo"]
    now = int(time.time())
    app_jwt = jwt.encode(
        {"iat": now - 60, "exp": now + 540, "iss": settings["client_id"]},
        (CFG / "private-key.pem").read_bytes(),
        algorithm="RS256",
    )
    installation = api_request(f"https://api.github.com/repos/{repo}/installation", app_jwt)
    result = api_request(
        f"https://api.github.com/app/installations/{installation['id']}/access_tokens",
        app_jwt,
        payload={
            "repositories": [repo.split("/", 1)[1]],
            "permissions": {"contents": "write", "pull_requests": "write"},
        },
    )
    write_secret(CFG / "installation-token", result["token"] + "\n")
    write_secret(CFG / "expires-at", result["expires_at"] + "\n")
    return result["token"]


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    refresh(args.force)
    expiry = (CFG / "expires-at").read_text().strip()
    print(f"GitHub App installation token is valid until {expiry}.")
