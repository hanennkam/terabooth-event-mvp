import io
import json
import time

from fastapi.testclient import TestClient
from PIL import Image

from app.config import Settings
from app.main import create_app
from app.templates import COLLAGE, DEFAULT, MINIMAL


def make_settings(tmp_path):
    data = tmp_path / "data"
    data.mkdir()
    return Settings(
        data_dir=data,
        db_path=data / "test.db",
        printer_mode="mock",
        delivery_secret="template-secret",
        job_timeout_seconds=5,
        mock_delay_seconds=0,
    )


def run_job(client, images, *, template=DEFAULT, version=1, crops=None, key="t-1"):
    from tests.test_api import metadata

    payload = metadata(images)
    payload["template"] = template.id
    payload["template_version"] = version
    if crops is not None:
        payload["crops"] = crops
    files = [("image_" + str(i), (f"{i}.jpg", data, "image/jpeg")) for i, data in enumerate(images)]
    return client.post(
        "/v1/print-jobs",
        data={"metadata": json.dumps(payload)},
        files=files,
        headers={"Idempotency-Key": key},
    )


def crop(slot_id, image_id, mode="fit", x=0.0, y=0.0, w=1.0, h=1.0):
    return {
        "image_id": image_id,
        "slot_id": slot_id,
        "mode": mode,
        "rect": {"x": x, "y": y, "w": w, "h": h},
        "zoom": 1,
        "offset_x": 0,
        "offset_y": 0,
    }


def wait_terminal(client, job_id):
    for _ in range(50):
        job = client.get(f"/v1/print-jobs/{job_id}").json()
        if job["state"] in {"completed", "failed", "unknown"}:
            return job
        time.sleep(0.05)
    return job


def test_default_template_geometry_is_preserved():
    assert DEFAULT.id == "strip_2x6_3up_v1"
    assert DEFAULT.version == 1
    assert (DEFAULT.canvas_width, DEFAULT.canvas_height) == (1200, 1800)
    assert DEFAULT.repeat_x == 2 and DEFAULT.panel_width == 600
    assert [(s.x, s.y, s.width, s.height) for s in DEFAULT.slots] == [
        (24, 100, 552, 531),
        (24, 649, 552, 531),
        (24, 1198, 552, 531),
    ]


def test_all_builtin_templates_validate_dimensions():
    for template in (DEFAULT, COLLAGE, MINIMAL):
        assert (template.output_width, template.output_height) == (1200, 1800)
        assert template.dpi == 300
        assert len(template.slots) == 3
        assert template.repeat_x in (1, 2)


def test_default_job_with_crops_uses_template_renderer(tmp_path, three_images):
    s = make_settings(tmp_path)
    with TestClient(create_app(s)) as client:
        crops = [
            crop("photo_1", "img0", "smart", 0.1, 0.1, 0.7, 0.7),
            crop("photo_2", "img1", "fit"),
            crop("photo_3", "img2", "manual", 0.0, 0.0, 0.5, 0.5),
        ]
        r = run_job(client, three_images, crops=crops, key="crop-default")
        assert r.status_code == 202, r.text
        job = wait_terminal(client, r.json()["job_id"])
        assert job["state"] == "completed"
        art = client.get(f"/v1/print-jobs/{job['job_id']}/artefact")
        with Image.open(io.BytesIO(art.content)) as im:
            assert im.format == "JPEG"
            assert im.size == (1200, 1800)
            assert im.info.get("dpi") == (300, 300)


def test_visually_different_template_renders(tmp_path, three_images):
    s = make_settings(tmp_path)
    with TestClient(create_app(s)) as client:
        crops = [
            crop("hero", "img0"),
            crop("left", "img1"),
            crop("right", "img2"),
        ]
        r = run_job(client, three_images, template=COLLAGE, crops=crops, key="collage")
        assert r.status_code == 202, r.text
        job = wait_terminal(client, r.json()["job_id"])
        assert job["state"] == "completed"
        art = client.get(f"/v1/print-jobs/{job['job_id']}/artefact")
        with Image.open(io.BytesIO(art.content)) as im:
            assert im.size == (1200, 1800)


def test_minimal_template_renders(tmp_path, three_images):
    s = make_settings(tmp_path)
    with TestClient(create_app(s)) as client:
        crops = [
            crop("photo_1", "img0"),
            crop("photo_2", "img1"),
            crop("photo_3", "img2"),
        ]
        r = run_job(client, three_images, template=MINIMAL, crops=crops, key="minimal")
        assert r.status_code == 202, r.text
        job = wait_terminal(client, r.json()["job_id"])
        assert job["state"] == "completed"


def test_unsupported_version_is_rejected(tmp_path, three_images):
    s = make_settings(tmp_path)
    with TestClient(create_app(s)) as client:
        r = run_job(client, three_images, version=99, key="bad-version")
        assert r.status_code == 422
        assert "version" in r.text


def test_non_default_template_requires_version(tmp_path, three_images):
    s = make_settings(tmp_path)
    with TestClient(create_app(s)) as client:
        r = run_job(client, three_images, template=COLLAGE, version=None, key="no-version")
        assert r.status_code == 422


def test_unknown_template_is_rejected(tmp_path, three_images):
    s = make_settings(tmp_path)
    with TestClient(create_app(s)) as client:
        from tests.test_api import metadata

        payload = metadata(three_images)
        payload["template"] = "not_a_template"
        files = [("image_" + str(i), (f"{i}.jpg", data, "image/jpeg")) for i, data in enumerate(three_images)]
        r = client.post("/v1/print-jobs", data={"metadata": json.dumps(payload)}, files=files,
                        headers={"Idempotency-Key": "bad-template"})
        assert r.status_code == 422


def test_invalid_crop_is_rejected(tmp_path, three_images):
    s = make_settings(tmp_path)
    with TestClient(create_app(s)) as client:
        bad = crop("photo_1", "img0", "manual", 0.8, 0.8, 0.5, 0.5)
        r = run_job(client, three_images, crops=[bad], key="bad-crop")
        assert r.status_code == 422
        wrong_slot = crop("missing_slot", "img0")
        r = run_job(client, three_images, crops=[wrong_slot], key="bad-slot")
        assert r.status_code == 422


def test_crop_image_must_match_slot(tmp_path, three_images):
    s = make_settings(tmp_path)
    with TestClient(create_app(s)) as client:
        mismatched = crop("photo_1", "img1")
        r = run_job(client, three_images, crops=[mismatched], key="mismatch")
        assert r.status_code == 422
