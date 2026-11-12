import hashlib
import io
import json
import time

from fastapi.testclient import TestClient
from PIL import Image

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
        delivery_secret="brand-secret",
        job_timeout_seconds=5,
        mock_delay_seconds=0,
    )


def payload(images, *, template, version=1, branding=None):
    return {
        "schema": "terabooth.print/1",
        "event_id": "evt-brand",
        "session_id": "ses-brand",
        "template": template,
        "template_version": version,
        "copies": 1,
        "paper": "4x6",
        "cut": "2x6",
        "event_text": {"title": "Acme Gala", "date": "14 Nov 2026"},
        "images": [
            {
                "id": f"img{i}",
                "filename": f"{i}.jpg",
                "sha256": hashlib.sha256(data).hexdigest(),
                "width": 900,
                "height": 1200,
            }
            for i, data in enumerate(images)
        ],
        "branding": branding,
        "delivery": {"required": True, "ttl_hours": 24},
    }


def post(client, images, *, template, key, branding=None, logo=None):
    files = [
        ("image_" + str(i), (f"{i}.jpg", data, "image/jpeg"))
        for i, data in enumerate(images)
    ]
    if logo is not None:
        files.append(("branding_logo", ("logo.png", logo, "image/png")))
    return client.post(
        "/v1/print-jobs",
        data={"metadata": json.dumps(payload(images, template=template, branding=branding))},
        files=files,
        headers={"Idempotency-Key": key},
    )


def wait(client, job_id):
    for _ in range(80):
        job = client.get(f"/v1/print-jobs/{job_id}").json()
        if job["state"] in {"completed", "failed", "unknown"}:
            return job
        time.sleep(0.05)
    return job


def test_count_templates_render_1_2_and_4_photos(tmp_path):
    with TestClient(create_app(settings(tmp_path))) as client:
        for count, template, version in [
            (1, "solo_4x6_v1", 1),
            (2, "duo_4x6_v1", 1),
            (4, "grid_4x6_v1", 1),
        ]:
            images = [make_jpeg((20 * i + 20, 80, 120)) for i in range(count)]
            response = post(client, images, template=template, key=f"count-{count}")
            assert response.status_code == 202, response.text
            job = wait(client, response.json()["job_id"])
            assert job["state"] == "completed", job
            art = client.get(f"/v1/print-jobs/{job['job_id']}/artefact")
            with Image.open(io.BytesIO(art.content)) as im:
                assert im.format == "JPEG"
                assert im.size == (1200, 1800)


def test_branding_and_logo_are_applied_to_composition(tmp_path):
    buffer = io.BytesIO()
    Image.new("RGB", (200, 100), (200, 30, 40)).save(buffer, "PNG")
    logo = buffer.getvalue()
    branding = {
        "enabled": True,
        "title": "Acme Events",
        "tagline": "Make it memorable",
        "color_hex": "#123ABC",
        "placement": "top",
    }
    with TestClient(create_app(settings(tmp_path))) as client:
        images = [make_jpeg((80, 100, 220)) for _ in range(3)]
        response = post(
            client,
            images,
            template="strip_2x6_3up_v1",
            key="brand-1",
            branding=branding,
            logo=logo,
        )
        assert response.status_code == 202, response.text
        job = wait(client, response.json()["job_id"])
        assert job["state"] == "completed", job
        art = client.get(f"/v1/print-jobs/{job['job_id']}/artefact")
        with Image.open(io.BytesIO(art.content)) as im:
            assert im.size == (1200, 1800)


def test_invalid_logo_is_rejected(tmp_path):
    with TestClient(create_app(settings(tmp_path))) as client:
        images = [make_jpeg() for _ in range(3)]
        response = post(
            client,
            images,
            template="strip_2x6_3up_v1",
            key="brand-bad",
            branding={
                "enabled": True,
                "title": "Bad",
                "tagline": "",
                "color_hex": "#000000",
                "placement": "top",
            },
            logo=b"not an image",
        )
        assert response.status_code == 422
