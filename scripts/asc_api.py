#!/usr/bin/env python3
"""Minimal App Store Connect API client: ES256 JWT auth plus GET/POST.

Credentials come from the environment (see scripts/asc-config.sh):
  ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH

Usage:
  asc_api.py <path> [METHOD] [JSON_BODY]
"""
import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.request

import certifi
import jwt  # PyJWT

BASE = "https://api.appstoreconnect.apple.com"
SSL_CONTEXT = ssl.create_default_context(cafile=certifi.where())


def _env(name):
    value = os.environ.get(name)
    if not value:
        sys.exit(f"{name} is not set — source scripts/asc-config.sh first.")
    return value


def token():
    with open(_env("ASC_KEY_PATH")) as f:
        private_key = f.read()
    now = int(time.time())
    payload = {
        "iss": _env("ASC_ISSUER_ID"),
        "iat": now,
        "exp": now + 900,
        "aud": "appstoreconnect-v1",
    }
    return jwt.encode(
        payload,
        private_key,
        algorithm="ES256",
        headers={"kid": _env("ASC_KEY_ID"), "typ": "JWT"},
    )


def call(path, method="GET", body=None):
    url = path if path.startswith("http") else BASE + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token())
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, context=SSL_CONTEXT) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code}: {e.read().decode()}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    method = sys.argv[2] if len(sys.argv) > 2 else "GET"
    payload = json.loads(sys.argv[3]) if len(sys.argv) > 3 else None
    print(json.dumps(call(sys.argv[1], method, payload), indent=2))
