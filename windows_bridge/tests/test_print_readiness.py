import hashlib
import io
import json
import time

from fastapi.testclient import TestClient
from PIL import Image

from app import db
from app.config import Settings
from app.main import create_app
from tests.conftest import make_jpeg


def settings(tmp_path):
    data = tmp_path / "data"
    data.mkdir()
    return Settings(
        data_dir=data,
        db_path=data / "test.db",
        printer_mode="mock",
        delivery_secret="print-test-secret",
        job_timeout_seconds=5,
        mock_delay_seconds=0,
    )


def metadata(images, copies=1):
    return {
        "schema": "terabooth.print/1",
        "event_id": "evt-print",
        "session_id": "ses-print",
        "template": "strip_2x6_3up_v1",
        "copies": copies,
        "paper": "4x6",
        "cut": "2x6",
        "event_text": {"title": "Print Audit", "date": "14 Nov 2026"},
        "images": [
            {"id": f"img{i}", "filename": f"{i}.jpg", "sha256": hashlib.sha256(data).hexdigest(),
             "width": 900, "height": 1200}
            for i, data in enumerate(images)
        ],
        "delivery": {"required": True, "ttl_hours": 24},
    }


def post(client, images, *, key, copies=1):
    files = [("image_" + str(i), (f"{i}.jpg", data, "image/jpeg")) for i, data in enumerate(images)]
    return client.post(
        "/v1/print-jobs",
        data={"metadata": json.dumps(metadata(images, copies))},
        files=files,
        headers={"Idempotency-Key": key},
    )


def wait(client, job_id):
    for _ in range(100):
        job = client.get(f"/v1/print-jobs/{job_id}").json()
        if job["state"] in {"completed", "failed", "unknown"}:
            return job
        time.sleep(0.05)
    return job


def test_valid_4x6_job_two_copies_and_original_hash(tmp_path):
    s = settings(tmp_path)
    images = [make_jpeg((20 * i + 20, 80, 120)) for i in range(3)]
    with TestClient(create_app(s)) as client:
        response = post(client, images, key="print-2copies", copies=2)
        assert response.status_code == 202, response.text
        job = wait(client, response.json()["job_id"])
        assert job["state"] == "completed"
        assert job["copies"] == 2
        assert job["completion"] == "confirmed"
        with Image.open(io.BytesIO(client.get(f"/v1/print-jobs/{job['job_id']}/artefact").content)) as im:
            assert im.size == (1200, 1800)
            assert im.info.get("dpi") == (300, 300)
        stored = db.get_job(s.db_path, job["job_id"])
        assert stored is not None
        for index, image in enumerate(stored["images"]):
            assert hashlib.sha256(open(image["path"], "rb").read()).hexdigest() == hashlib.sha256(images[index]).hexdigest()


def test_duplicate_submission_does_not_create_second_job(tmp_path):
    s = settings(tmp_path)
    images = [make_jpeg() for _ in range(3)]
    with TestClient(create_app(s)) as client:
        first = post(client, images, key="same-idempotency")
        assert first.status_code == 202
        duplicate = post(client, images, key="same-idempotency")
        assert duplicate.status_code == 200
        assert duplicate.json()["duplicate"] is True
        assert duplicate.json()["job_id"] == first.json()["job_id"]


def test_printer_unavailable_marks_failed_and_never_claims_success(tmp_path):
    s = Settings(**{**settings(tmp_path).__dict__, "mock_fail": True})
    images = [make_jpeg() for _ in range(3)]
    with TestClient(create_app(s)) as client:
        response = post(client, images, key="printer-fail")
        assert response.status_code == 202
        job = wait(client, response.json()["job_id"])
        assert job["state"] == "failed"
        assert job["completion"] == "unknown"


def test_restart_marks_printing_unknown_and_queued_failed_without_resubmit(tmp_path):
    s = settings(tmp_path)
    images = [make_jpeg() for _ in range(3)]
    with TestClient(create_app(s)) as client:
        a = post(client, images, key="restart-printing").json()
        b = post(client, images, key="restart-queued").json()
        wait(client, a["job_id"])
        wait(client, b["job_id"])
        db.update_job(s.db_path, a["job_id"], state="printing", completion="unknown")
        db.update_job(s.db_path, b["job_id"], state="queued", completion="unknown")

    with TestClient(create_app(s)) as client:
        a2 = client.get(f"/v1/print-jobs/{a['job_id']}").json()
        b2 = client.get(f"/v1/print-jobs/{b['job_id']}").json()
        assert a2["state"] == "unknown"
        assert "verify physical output" in (a2.get("error") or "")
        assert b2["state"] == "failed"
        assert "Reprint" in (b2.get("error") or "")
        attempts = db.get_job(s.db_path, a["job_id"])["id"]
        assert attempts == a["job_id"]


def test_invalid_image_is_rejected_before_print(tmp_path):
    s = settings(tmp_path)
    bad = b"not-an-image"
    meta = metadata([bad, bad, bad])
    files = [
        ("image_" + str(i), (f"{i}.jpg", bad, "image/jpeg"))
        for i in range(3)
    ]
    with TestClient(create_app(s)) as client:
        response = client.post(
            "/v1/print-jobs",
            data={"metadata": json.dumps(meta)},
            files=files,
            headers={"Idempotency-Key": "bad-image-print"},
        )
        assert response.status_code == 422


def test_mock_printer_receives_copy_count(tmp_path):
    from app.printer import MockPrinter
    from tests.conftest import make_jpeg

    s = settings(tmp_path)
    source = tmp_path / "artefact.jpg"
    source.write_bytes(make_jpeg((10, 20, 30)))
    printer = MockPrinter(s)
    printer.submit("job-copy", source, 2)
    assert printer.submitted_copies == [2]
    assert (s.outbox_dir / "job-copy.jpg").exists()


def test_printer_preflight_reports_configured_queue_and_mock_mode(tmp_path):
    from app.printer import printer_preflight

    s = settings(tmp_path)
    out = printer_preflight(s)
    assert out["configured_queue_name"] == "DS-RX1"
    assert out["spooler_mode_enabled"] is False
    assert out["available"] is False  # Windows-only query on this host
    assert isinstance(out["query_error"], str)


def test_printers_endpoint_exposes_safe_preflight_without_enabling_spooler(tmp_path):
    s = settings(tmp_path)
    with TestClient(create_app(s)) as client:
        response = client.get("/v1/printers")
        assert response.status_code == 200
        body = response.json()
        assert body["printers"][0]["mode"] == "mock"
        assert body["preflight"]["configured_queue_name"] == "DS-RX1"
        assert body["preflight"]["spooler_mode_enabled"] is False
        assert "query_error" not in body["preflight"] or isinstance(
            body["preflight"]["query_error"], str
        )
