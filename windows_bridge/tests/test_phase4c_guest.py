import hashlib
import io
import json
import sqlite3
import time

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.config import Settings
from app.gif_render import GifGenerationError, generate_gif, inspect_gif
from app.main import create_app
from tests.conftest import make_jpeg


def settings(tmp_path):
    data = tmp_path / "data"
    data.mkdir()
    return Settings(
        data_dir=data,
        db_path=data / "test.db",
        printer_mode="mock",
        delivery_secret="guest-secret",
        job_timeout_seconds=5,
        mock_delay_seconds=0,
    )


def metadata(images, key="evt-guest"):
    return {
        "schema": "terabooth.print/1",
        "event_id": "evt-guest",
        "session_id": "ses-guest",
        "template": "strip_2x6_3up_v1",
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
        "delivery": {"required": True, "ttl_hours": 24},
    }


def post(client, images, *, key, template="strip_2x6_3up_v1"):
    payload = metadata(images)
    payload["template"] = template
    payload["template_version"] = 1
    files = [
        ("image_" + str(i), (f"{i}.jpg", data, "image/jpeg"))
        for i, data in enumerate(images)
    ]
    return client.post(
        "/v1/print-jobs",
        data={"metadata": json.dumps(payload)},
        files=files,
        headers={"Idempotency-Key": key},
    )


def wait(client, job_id, states=("completed", "failed", "unknown")):
    job = {}
    for _ in range(100):
        job = client.get(f"/v1/print-jobs/{job_id}").json()
        if job["state"] in states:
            return job
        time.sleep(0.05)
    return job


def token(job):
    return job["delivery_url"].rsplit("/", 1)[-1]


def test_guest_manifest_zip_and_cross_session_scope(tmp_path):
    images_a = [make_jpeg((20, 80, 120)) for _ in range(2)]
    images_b = [make_jpeg((200, 80, 20)) for _ in range(2)]
    s = settings(tmp_path)
    with TestClient(create_app(s)) as client:
        a = post(client, images_a, key="guest-a", template="duo_4x6_v1").json()
        b = post(client, images_b, key="guest-b", template="duo_4x6_v1").json()
        a = wait(client, a["job_id"])
        b = wait(client, b["job_id"])
        ta, tb = token(a), token(b)
        manifest = client.get(f"/d/{ta}/manifest.json")
        assert manifest.status_code == 200
        data = manifest.json()
        assert data["session_id"] == a["session_id"]
        assert len(ta) >= 30
        assert "path" not in json.dumps(data)
        assert "logo_path" not in json.dumps(data)
        persisted = s.jobs_dir / a["job_id"] / "manifest.json"
        # The manifest is written by the composition/GIF pipeline.
        assert persisted.exists()
        assert "path" not in persisted.read_text()
        assert len(data["originals"]) == 2
        assert all("path" not in item for item in data["originals"])
        assert "download_url" in data["originals"][0]
        assert data["approved"] is True

        page = client.get(f"/d/{ta}")
        assert page.status_code == 200
        first_image = a["images"][0]["id"]
        assert client.get(f"/d/{ta}/original/{first_image}?inline=1").status_code == 200
        if data["strip"]:
            assert client.get(f"/d/{ta}/strip?inline=1").status_code == 200
        assert "Download all photos" in page.text
        assert "Cross" not in page.text

        archive = client.get(f"/d/{ta}/download.zip")
        assert archive.status_code == 200
        assert archive.headers["content-type"].startswith("application/zip")
        with __import__("zipfile").ZipFile(io.BytesIO(archive.content)) as zf:
            assert sorted(zf.namelist()) == [
                "photo-1.jpg",
                "photo-2.jpg",
                "terabooth-strip.jpg",
            ]

        # A token cannot read another session's image or manifest.
        image_b = b["images"][0]["id"]
        assert client.get(f"/d/{ta}/original/{image_b}").status_code == 404
        assert client.get(f"/d/{tb}/original/{a['images'][0]['id']}").status_code == 404
        assert client.get("/d/not-a-token/manifest.json").status_code == 404


def test_token_can_be_revoked_and_regenerated(tmp_path):
    s = settings(tmp_path)
    with TestClient(create_app(s)) as client:
        images = [make_jpeg() for _ in range(3)]
        job = wait(client, post(client, images, key="guest-revoke").json()["job_id"])
        old = token(job)
        assert client.get(f"/d/{old}").status_code == 200
        rev = client.post(f"/v1/print-jobs/{job['job_id']}/delivery/revoke")
        assert rev.status_code == 200
        assert rev.json()["delivery_url"] is None
        assert client.get(f"/d/{old}").status_code == 404

        regen = client.post(f"/v1/print-jobs/{job['job_id']}/delivery/regenerate")
        assert regen.status_code == 200
        new = regen.json()["delivery_url"].rsplit("/", 1)[-1]
        assert new != old
        assert client.get(f"/d/{old}").status_code == 404
        assert client.get(f"/d/{new}").status_code == 200

        # Expired links are rejected independently of the HMAC/opaque form.
        conn = sqlite3.connect(s.db_path)
        conn.execute("UPDATE delivery_tokens SET expires_at=0 WHERE job_id=?", (job["job_id"],))
        conn.commit(); conn.close()
        assert client.get(f"/d/{new}").status_code == 404


def test_guest_page_does_not_expose_other_session_or_paths(tmp_path):
    with TestClient(create_app(settings(tmp_path))) as client:
        images = [make_jpeg() for _ in range(2)]
        job = wait(client, post(client, images, key="guest-page", template="duo_4x6_v1").json()["job_id"])
        tok = token(job)
        page = client.get(f"/d/{tok}").text
        assert "img0" not in page  # internal image IDs are not displayed
        assert "/tmp/" not in page
        assert "data/" not in page
        assert "original/" in page
        assert "download.zip" in page
        # Directory listing / traversal is not served.
        for path in [
            f"/d/{tok}/original/../../dev/null",
            f"/d/{tok}/original/%2e%2e%2f%2e%2e%2fetc%2fpasswd",
        ]:
            assert client.get(path).status_code in {404, 422}


def test_non_loopback_base_url_is_used_for_qr(tmp_path):
    with TestClient(
        create_app(settings(tmp_path)),
        base_url="http://192.168.8.50:8787",
    ) as client:
        images = [make_jpeg() for _ in range(3)]
        job = wait(client, post(client, images, key="guest-lan").json()["job_id"])
        assert job["delivery_url"].startswith("http://192.168.8.50:8787/d/")
        assert "localhost" not in job["delivery_url"]
        assert "127.0.0.1" not in job["delivery_url"]
        assert client.get(f"/d/{token(job)}/qr.png").status_code == 200


def test_gif_supports_one_to_four_frames_and_rejects_invalid_sources(tmp_path):
    for count in [1, 2, 3, 4]:
        source = tmp_path / f"source-{count}"
        source.mkdir()
        paths = []
        for i in range(count):
            path = source / f"{i}.jpg"
            path.write_bytes(make_jpeg((i * 30 + 10, 80, 120)))
            paths.append(path)
        out = source / "out.gif"
        before = [hashlib.sha256(p.read_bytes()).hexdigest() for p in paths]
        metadata = generate_gif(paths, out)
        assert metadata["frames"] == count
        assert inspect_gif(out, expected_frames=count)["frames"] == count
        assert [hashlib.sha256(p.read_bytes()).hexdigest() for p in paths] == before
        # Regeneration is safe and idempotent.
        assert generate_gif(paths, out)["frames"] == count

    # Frame order follows the caller's approved photo order.
    red = tmp_path / "red.jpg"
    green = tmp_path / "green.jpg"
    red.write_bytes(make_jpeg((255, 0, 0)))
    green.write_bytes(make_jpeg((0, 255, 0)))
    ordered = tmp_path / "ordered.gif"
    generate_gif([red, green], ordered)
    with Image.open(ordered) as gif:
        samples = []
        for index in range(2):
            gif.seek(index)
            samples.append(gif.convert("RGB").getpixel((180, 270)))
    assert samples[0][0] > samples[0][1]
    assert samples[1][1] > samples[1][0]

    with pytest.raises(GifGenerationError):
        generate_gif([tmp_path / "missing.jpg"], tmp_path / "bad.gif")
    bad = tmp_path / "bad.jpg"
    bad.write_bytes(b"not-an-image")
    with pytest.raises(GifGenerationError):
        generate_gif([bad], tmp_path / "bad.gif")
