import hashlib
import io
import json
import time
from pathlib import Path

from fastapi.testclient import TestClient
from PIL import Image

from app.config import Settings
from app.main import create_app


def settings(tmp_path: Path) -> Settings:
    data = tmp_path / "data"
    data.mkdir()
    return Settings(
        data_dir=data,
        db_path=data / "test.db",
        printer_mode="mock",
        api_token=None,
        delivery_secret="test-secret",
        job_timeout_seconds=5,
        mock_delay_seconds=0,
    )


def metadata(images, key="evt-1"):
    return {
        "schema": "terabooth.print/1",
        "event_id": "evt-1",
        "session_id": "ses-1",
        "template": "strip_2x6_3up_v1",
        "copies": 1,
        "paper": "4x6",
        "cut": "2x6",
        "event_text": {"title": "Kate & Jack", "date": "14 Nov 2026"},
        "images": [
            {"id": f"img{i}", "filename": f"{i}.jpg", "sha256": hashlib.sha256(data).hexdigest(),
             "width": 900, "height": 1200}
            for i, data in enumerate(images)
        ],
        "delivery": {"required": True, "ttl_hours": 24},
    }


def post_job(client, images, key="idem-1"):
    files = [("image_" + str(i), (f"{i}.jpg", data, "image/jpeg")) for i, data in enumerate(images)]
    return client.post(
        "/v1/print-jobs",
        data={"metadata": json.dumps(metadata(images))},
        files=files,
        headers={"Idempotency-Key": key},
    )


def test_health_and_flow(tmp_path, three_images):
    app = create_app(settings(tmp_path))
    with TestClient(app) as client:
        assert client.get("/v1/health").status_code == 200
        r = post_job(client, three_images)
        assert r.status_code == 202, r.text
        body = r.json()
        job_id = body["job_id"]
        assert body["delivery_url"].startswith("http://testserver/d/")
        # duplicate
        d = post_job(client, three_images, key="idem-1")
        assert d.status_code == 200
        assert d.json()["job_id"] == job_id
        assert d.json()["duplicate"] is True
        # wait for background mock completion
        for _ in range(50):
            j = client.get(f"/v1/print-jobs/{job_id}").json()
            if j["state"] in {"completed", "failed", "unknown"}:
                break
            time.sleep(0.05)
        assert j["state"] == "completed", j
        assert j["completion"] == "confirmed"
        # delivery page and original
        token = j["delivery_url"].rsplit("/", 1)[-1]
        page = client.get(f"/d/{token}")
        assert page.status_code == 200
        assert "Your photos are ready" in page.text
        first = j["images"][0]["id"]
        img = client.get(f"/d/{token}/original/{first}")
        assert img.status_code == 200 and img.headers["content-type"] == "image/jpeg"
        qr = client.get(f"/d/{token}/qr.png")
        assert qr.status_code == 200 and qr.headers["content-type"] == "image/png"
        # artefact exact size
        art = client.get(f"/v1/print-jobs/{job_id}/artefact")
        assert art.status_code == 200
        with Image.open(io.BytesIO(art.content)) as im:
            assert im.size == (1200, 1800)
        # reprint is a new job
        rep = client.post(f"/v1/print-jobs/{job_id}/reprint", headers={"Idempotency-Key": "rep-1"})
        assert rep.status_code == 202
        assert rep.json()["job_id"] != job_id
        assert rep.json()["reprint_of"] == job_id


def test_hash_mismatch_rejected(tmp_path, three_images):
    app = create_app(settings(tmp_path))
    with TestClient(app) as client:
        files = [("image_" + str(i), (f"{i}.jpg", data, "image/jpeg")) for i, data in enumerate(three_images)]
        bad = metadata(three_images)
        bad["images"][0]["sha256"] = "0" * 64
        r = client.post("/v1/print-jobs", data={"metadata": json.dumps(bad)}, files=files,
                        headers={"Idempotency-Key": "bad-1"})
        assert r.status_code == 422


def test_requires_idempotency(tmp_path, three_images):
    app = create_app(settings(tmp_path))
    with TestClient(app) as client:
        r = post_job(client, three_images, key="")
        assert r.status_code in (400, 422)


def test_mock_failure_and_unknown_are_terminal(tmp_path, three_images):
    from app.config import Settings
    for flag, expected in (({"mock_fail": True}, "failed"), ({"mock_unknown": True}, "unknown")):
        data = tmp_path / ("d_" + expected)
        data.mkdir()
        s = Settings(data_dir=data, db_path=data / "t.db", printer_mode="mock",
                     delivery_secret="s", job_timeout_seconds=5, mock_delay_seconds=0, **flag)
        app = create_app(s)
        with TestClient(app) as client:
            r = post_job(client, three_images, key="k-" + expected)
            assert r.status_code == 202, r.text
            jid = r.json()["job_id"]
            for _ in range(50):
                j = client.get(f"/v1/print-jobs/{jid}").json()
                if j["state"] in {"completed", "failed", "unknown"}:
                    break
                time.sleep(0.05)
            assert j["state"] == expected, j
            assert j["state"] != "completed"


def test_invalid_and_expired_delivery_token(tmp_path, three_images):
    s = settings(tmp_path)
    s = Settings(**{**s.__dict__, "token_ttl_hours": 0})
    app = create_app(s)
    with TestClient(app) as client:
        r = post_job(client, three_images, key="exp-1")
        assert r.status_code == 202
        token = r.json()["delivery_url"].rsplit("/", 1)[-1]
        assert client.get("/d/not-a-token").status_code == 404
        time.sleep(1.1)
        assert client.get(f"/d/{token}").status_code == 404


def test_api_token_is_enforced(tmp_path):
    s = settings(tmp_path)
    s = Settings(**{**s.__dict__, "api_token": "secret"})
    app = create_app(s)
    with TestClient(app) as client:
        assert client.get("/v1/health").status_code == 401
        assert client.get("/v1/health", headers={"Authorization": "Bearer secret"}).status_code == 200


def test_delivery_original_content_type_matches_png(tmp_path):
    import io
    from PIL import Image

    images = []
    for color in ((10, 20, 30), (40, 50, 60), (70, 80, 90)):
        im = Image.new("RGB", (900, 1200), color)
        buf = io.BytesIO()
        im.save(buf, "PNG")
        images.append(buf.getvalue())
    s = settings(tmp_path)
    s = Settings(**{**s.__dict__, "mock_delay_seconds": 0})
    with TestClient(create_app(s)) as client:
        r = post_job(client, images, key="png-mime")
        assert r.status_code == 202, r.text
        j = r.json()
        token = j["delivery_url"].rsplit("/", 1)[-1]
        original = client.get(f"/d/{token}/original/{j['images'][0]['id']}")
        assert original.status_code == 200
        assert original.headers["content-type"].startswith("image/png")
        assert original.content[:8] == b"\x89PNG\r\n\x1a\n"
        assert original.headers.get("content-disposition", "").endswith('.png"')


def test_delivery_db_expiry_is_rejected_even_with_future_hmac(tmp_path, three_images):
    import sqlite3
    s = settings(tmp_path)
    with TestClient(create_app(s)) as client:
        r = post_job(client, three_images, key="db-expiry")
        token = r.json()["delivery_url"].rsplit("/", 1)[-1]
        conn = sqlite3.connect(s.db_path)
        conn.execute("UPDATE delivery_tokens SET expires_at=0")
        conn.commit(); conn.close()
        assert client.get(f"/d/{token}").status_code == 404
        assert client.get(f"/d/{token}/gif").status_code == 404


def test_preview_job_defers_print_and_reprint_uses_selected_copies(tmp_path, three_images):
    import time

    s = settings(tmp_path)
    with TestClient(create_app(s)) as client:
        meta = metadata(three_images)
        meta["print_now"] = False
        files = [("image_" + str(i), (f"{i}.jpg", data, "image/jpeg"))
                 for i, data in enumerate(three_images)]
        response = client.post(
            "/v1/print-jobs", data={"metadata": json.dumps(meta)}, files=files,
            headers={"Idempotency-Key": "preview-1"},
        )
        assert response.status_code == 202, response.text
        job_id = response.json()["job_id"]
        for _ in range(50):
            job = client.get(f"/v1/print-jobs/{job_id}").json()
            if job["state"] in {"completed", "failed", "unknown"}:
                break
            time.sleep(0.05)
        assert job["state"] == "completed"
        assert job["completion"] == "preview"
        assert job["print_now"] is False

        reprint = client.post(
            f"/v1/print-jobs/{job_id}/reprint?copies=2",
            headers={"Idempotency-Key": "print-2"},
        )
        assert reprint.status_code == 202, reprint.text
        assert reprint.json()["copies"] == 2
        assert reprint.json()["print_now"] is True
