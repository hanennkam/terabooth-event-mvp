from __future__ import annotations

import base64
import hashlib
import hmac
import json
import time
from typing import Any


def _b64e(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _b64d(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(value + padding)


def make_access_token() -> str:
    """Opaque, unguessable guest access token (128 bits)."""
    import secrets
    return secrets.token_urlsafe(24)


def make_token(secret: str, payload: dict[str, Any]) -> str:
    body = _b64e(json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8"))
    signature = hmac.new(secret.encode("utf-8"), body.encode("ascii"), hashlib.sha256).digest()
    return f"{body}.{_b64e(signature)}"


def verify_token(secret: str, token: str, now: int | None = None) -> dict[str, Any] | None:
    try:
        body, signature = token.split(".", 1)
        expected = hmac.new(secret.encode("utf-8"), body.encode("ascii"), hashlib.sha256).digest()
        if not hmac.compare_digest(_b64d(signature), expected):
            return None
        payload = json.loads(_b64d(body).decode("utf-8"))
        if int(payload.get("exp", 0)) < (now if now is not None else int(time.time())):
            return None
        return payload
    except Exception:
        return None


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()
