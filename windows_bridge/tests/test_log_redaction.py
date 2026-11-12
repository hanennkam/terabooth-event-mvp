import io
import logging

from app.log_redaction import RedactingFormatter, RedactionFilter, redact_text

TOKEN = "eyJldmVudCI6ImV2dCJ9.signature-part_123"
SECRET = "super-secret-delivery-value"
API_TOKEN = "temporary-api-token-value"


def test_redacts_guest_paths_and_keeps_endpoint_metadata():
    raw = f'GET /d/{TOKEN}/gif HTTP/1.1 200'
    out = redact_text(raw)
    assert TOKEN not in out
    assert "/d/<redacted>/gif" in out
    assert "GET" in out and "200" in out
    assert TOKEN not in redact_text(f"http://192.168.8.10:8787/d/{TOKEN}")


def test_redacts_auth_and_secrets():
    raw = f"Authorization: Bearer {API_TOKEN} token={SECRET}"
    out = redact_text(raw, [API_TOKEN, SECRET])
    assert API_TOKEN not in out
    assert SECRET not in out
    assert "Authorization" in out
    assert "<redacted>" in out


def test_uvicorn_access_formatter_and_exception_logs_do_not_leak_tokens():
    stream = io.StringIO()
    logger = logging.getLogger("uvicorn.access.test_redaction")
    logger.handlers.clear()
    logger.propagate = False
    handler = logging.StreamHandler(stream)
    handler.setFormatter(RedactingFormatter(logging.Formatter("%(message)s"), [API_TOKEN, SECRET]))
    handler.addFilter(RedactionFilter([API_TOKEN, SECRET]))
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)

    logger.info(
        '%s - "%s %s HTTP/%s" %d',
        "192.168.8.20:5000", "GET", f"/d/{TOKEN}/original/img_1", "1.1", 200,
    )
    logger.error("request failed for /d/%s with Bearer %s", TOKEN, API_TOKEN)
    try:
        raise RuntimeError(f"failure at /d/{TOKEN} using {SECRET}")
    except RuntimeError:
        logger.exception("exception")

    text = stream.getvalue()
    assert TOKEN not in text
    assert API_TOKEN not in text
    assert SECRET not in text
    assert "/d/<redacted>/original/img_1" in text
    assert "200" in text


def test_normal_diagnostic_logs_are_unchanged():
    raw = 'GET /v1/health HTTP/1.1 200 service=terabooth-print'
    assert redact_text(raw) == raw
