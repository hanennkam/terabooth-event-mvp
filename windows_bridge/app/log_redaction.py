from __future__ import annotations

import logging
import re
from typing import Any, Iterable

# Guest delivery paths contain an HMAC token segment:
#   /d/<token>, /d/<token>/gif, /d/<token>/original/<id>, ...
_GUEST_PATH = re.compile(r"(?i)(/d/)[A-Za-z0-9._~%-]+")
_AUTH_HEADER = re.compile(r"(?i)(Authorization:\s*Bearer\s+)[^\s,]+")
_QUERY_TOKEN = re.compile(r"(?i)([?&](?:token|access_token)=)[^&\s]+")


class RedactingFormatter(logging.Formatter):
    """Redacts the fully formatted record, including exception tracebacks."""

    def __init__(self, inner: logging.Formatter, secrets: Iterable[str]):
        super().__init__()
        self._inner = inner
        self._secrets = tuple(secret for secret in secrets if secret)

    def format(self, record: logging.LogRecord) -> str:
        return redact_text(self._inner.format(record), self._secrets)


class RedactionFilter(logging.Filter):
    """Belt-and-braces redaction for handlers without the formatter wrapper."""

    def __init__(self, secrets: Iterable[str]):
        super().__init__()
        self._secrets = tuple(secret for secret in secrets if secret)

    def filter(self, record: logging.LogRecord) -> bool:
        if isinstance(record.msg, str):
            record.msg = redact_text(record.msg, self._secrets)
        if record.args:
            if isinstance(record.args, tuple):
                record.args = tuple(
                    redact_text(arg, self._secrets) if isinstance(arg, str) else arg
                    for arg in record.args
                )
            elif isinstance(record.args, dict):
                record.args = {
                    key: redact_text(value, self._secrets) if isinstance(value, str) else value
                    for key, value in record.args.items()
                }
        return True


def redact_text(text: str, secrets: Iterable[str] = ()) -> str:
    redacted = _GUEST_PATH.sub(r"\1<redacted>", text)
    redacted = _AUTH_HEADER.sub(r"\1<redacted>", redacted)
    redacted = _QUERY_TOKEN.sub(r"\1<redacted>", redacted)
    for secret in secrets:
        if secret:
            redacted = redacted.replace(secret, "<redacted>")
    return redacted


def install_log_redaction(settings: Any) -> None:
    """Install on existing Uvicorn/root handlers without changing log formats."""
    secrets = [
        getattr(settings, "api_token", None),
        getattr(settings, "delivery_secret", None),
    ]
    loggers = [
        logging.getLogger(),
        logging.getLogger("uvicorn"),
        logging.getLogger("uvicorn.access"),
        logging.getLogger("uvicorn.error"),
        logging.getLogger("fastapi"),
    ]
    for logger in loggers:
        if not any(isinstance(item, RedactionFilter) for item in logger.filters):
            logger.addFilter(RedactionFilter(secrets))
        for handler in logger.handlers:
            formatter = handler.formatter or logging.Formatter()
            if not isinstance(formatter, RedactingFormatter):
                handler.setFormatter(RedactingFormatter(formatter, secrets))
