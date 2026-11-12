import io
import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.config import Settings
from app.gif_render import GifGenerationError, generate_gif, inspect_gif
from app.main import create_app


def settings(tmp_path, *, mock_fail=False):
    data = tmp_path / "data"
    data.mkdir()
    return Settings(
        data_dir=data,
        db_path=data / "test.db",
        printer_mode="mock",
        delivery_secret="gif-secret",
        job_timeout_seconds=5,
        mock_delay_seconds=0,
        mock_fail=mock_fail,
    )


def wait_gif(client, job_id, expected=("ready", "failed")):
    for _ in range(100):
        job = client.get(f"/v1/print-jobs/{job_id}").json()
        if job.get("gif_state") in expected:
            return job
        time.sleep(0.05)
    return job


def post_job(client, three_images, key):
    from tests.test_api import post_job as helper

    return helper(client, three_images, key=key)


def test_gif_frames_are_exactly_specified(tmp_path, three_images):
    s = settings(tmp_path)
    with TestClient(create_app(s)) as client:
        r = post_job(client, three_images, "gif-spec")
        assert r.status_code == 202, r.text
        job_id = r.json()["job_id"]
        job = wait_gif(client, job_id)
        assert job["gif_state"] == "ready", job
        assert job["gif_bytes"] > 0

        response = client.get(f"/v1/print-jobs/{job_id}/gif")
        assert response.status_code == 200
        assert response.headers["content-type"].startswith("image/gif")
        assert response.content[:6] == b"GIF89a"

        path = Path(s.jobs_dir) / job_id / "guest.gif"
        meta = inspect_gif(path)
        assert meta["frames"] == 3
        assert meta["width"] == 360 and meta["height"] == 540
        assert meta["durations_ms"] == [1800, 1800, 1800]
        assert meta["loop"] == 0

        with Image.open(io.BytesIO(response.content)) as gif:
            assert gif.n_frames == 3
            assert gif.info["loop"] == 0
            assert gif.size == (360, 540)
            colors = []
            for index in range(3):
                gif.seek(index)
                assert gif.info["duration"] == 1800
                colors.append(gif.convert("RGB").getpixel((180, 270)))
            # Source order is red, green, blue; GIF palette conversion should
            # preserve the dominant channel order.
            assert colors[0][0] > colors[0][1]
            assert colors[1][1] > colors[1][0]
            assert colors[2][2] > colors[2][0]
            assert 0 < response.content.__len__() < 2_000_000


def test_gif_guest_token_and_page_link(tmp_path, three_images):
    s = settings(tmp_path)
    with TestClient(create_app(s)) as client:
        r = post_job(client, three_images, "gif-guest")
        job_id = r.json()["job_id"]
        job = wait_gif(client, job_id)
        assert job["gif_state"] == "ready"
        token = job["delivery_url"].rsplit("/", 1)[-1]

        page = client.get(f"/d/{token}")
        assert page.status_code == 200
        assert "Download animated GIF" in page.text
        gif = client.get(f"/d/{token}/gif")
        assert gif.status_code == 200
        assert gif.content[:6] == b"GIF89a"
        assert client.get("/d/not-a-token/gif").status_code == 404


def test_gif_is_independent_of_print_failure(tmp_path, three_images):
    s = settings(tmp_path, mock_fail=True)
    with TestClient(create_app(s)) as client:
        r = post_job(client, three_images, "gif-print-fail")
        job_id = r.json()["job_id"]
        for _ in range(100):
            job = client.get(f"/v1/print-jobs/{job_id}").json()
            if job["state"] in {"failed", "completed", "unknown"} and job.get("gif_state") in {"ready", "failed"}:
                break
            time.sleep(0.05)
        assert job["state"] == "failed"
        assert job["gif_state"] == "ready"
        assert client.get(f"/v1/print-jobs/{job_id}/gif").status_code == 200


def test_gif_persists_across_bridge_restart(tmp_path, three_images):
    s = settings(tmp_path)
    with TestClient(create_app(s)) as client:
        r = post_job(client, three_images, "gif-restart")
        job_id = r.json()["job_id"]
        assert wait_gif(client, job_id)["gif_state"] == "ready"
    with TestClient(create_app(s)) as client:
        response = client.get(f"/v1/print-jobs/{job_id}/gif")
        assert response.status_code == 200
        assert response.content[:6] == b"GIF89a"


def test_invalid_and_expired_gif_tokens(tmp_path, three_images):
    import sqlite3

    s = settings(tmp_path)
    with TestClient(create_app(s)) as client:
        r = post_job(client, three_images, "gif-expire")
        job_id = r.json()["job_id"]
        wait_gif(client, job_id)
        token = client.get(f"/v1/print-jobs/{job_id}").json()["delivery_url"].rsplit("/", 1)[-1]
        assert client.get(f"/d/{token}/gif").status_code == 200
        assert client.get("/d/not-a-token/gif").status_code == 404
        conn = sqlite3.connect(s.db_path)
        conn.execute("UPDATE delivery_tokens SET expires_at=0 WHERE job_id=?", (job_id,))
        conn.commit(); conn.close()
        assert client.get(f"/d/{token}/gif").status_code == 404


def test_gif_missing_and_corrupt_sources_fail_safely(tmp_path):
    missing = tmp_path / "missing.jpg"
    with pytest.raises(GifGenerationError):
        generate_gif([missing, missing, missing], tmp_path / "out.gif")
    corrupt = tmp_path / "bad.jpg"
    corrupt.write_bytes(b"not an image")
    with pytest.raises(GifGenerationError):
        generate_gif([corrupt, corrupt, corrupt], tmp_path / "out.gif")
    assert not (tmp_path / "out.gif").exists()


def test_gif_exif_source_and_atomic_output(tmp_path):
    fixtures = Path(__file__).resolve().parents[2] / "ipad_app" / "test" / "fixtures"
    names = ("exif_o2.jpg", "exif_o3.jpg", "exif_o6.jpg")
    paths = []
    for index, name in enumerate(names):
        source = fixtures / name
        assert source.exists()
        path = tmp_path / f"oriented_{index}.jpg"
        path.write_bytes(source.read_bytes())
        paths.append(path)
    out = tmp_path / "oriented.gif"
    meta = generate_gif(paths, out)
    assert meta["frames"] == 3
    assert meta["width"] == 360 and meta["height"] == 540
    assert out.exists()
    assert not list(tmp_path.glob(".*.part"))
    with Image.open(out) as gif:
        for index in range(3):
            gif.seek(index)
            assert gif.size == (360, 540)


def test_gif_generation_can_only_be_claimed_once(tmp_path, three_images):
    from app import db

    s = settings(tmp_path)
    with TestClient(create_app(s)) as client:
        r = post_job(client, three_images, "gif-claim")
        job_id = r.json()["job_id"]
        wait_gif(client, job_id)
        assert db.claim_gif(s.db_path, job_id) is False


def test_recovery_preserves_valid_processing_gif_without_overwrite(tmp_path, three_images):
    import hashlib
    from app import db

    s = settings(tmp_path)
    with TestClient(create_app(s)) as client:
        r = post_job(client, three_images, "gif-recovery-ready")
        job_id = r.json()["job_id"]
        wait_gif(client, job_id)
        job = client.get(f"/v1/print-jobs/{job_id}").json()
        path = Path(s.jobs_dir) / job_id / "guest.gif"
        before = hashlib.sha256(path.read_bytes()).hexdigest()

    db.update_gif(s.db_path, job_id, state="processing", gif_path=str(path), gif_bytes=path.stat().st_size)
    with TestClient(create_app(s)) as client:
        job = wait_gif(client, job_id)
        assert job["gif_state"] == "ready"
        response = client.get(f"/v1/print-jobs/{job_id}/gif")
        assert response.status_code == 200
    after = hashlib.sha256(path.read_bytes()).hexdigest()
    assert after == before
    assert db.claim_gif(s.db_path, job_id) is False


def test_recovery_regenerates_missing_processing_artefact(tmp_path, three_images):
    from app import db

    s = settings(tmp_path)
    with TestClient(create_app(s)) as client:
        r = post_job(client, three_images, "gif-recovery-missing")
        job_id = r.json()["job_id"]
        wait_gif(client, job_id)
        path = Path(s.jobs_dir) / job_id / "guest.gif"
        path.unlink()
        db.update_gif(s.db_path, job_id, state="processing", gif_path=str(path))
    with TestClient(create_app(s)) as client:
        job = wait_gif(client, job_id)
        assert job["gif_state"] == "ready"
        assert client.get(f"/v1/print-jobs/{job_id}/gif").status_code == 200


def test_recovery_fails_safely_on_wrong_image_count(tmp_path, three_images):
    import sqlite3
    from app import db

    s = settings(tmp_path)
    with TestClient(create_app(s)) as client:
        r = post_job(client, three_images, "gif-recovery-badcount")
        job_id = r.json()["job_id"]
        wait_gif(client, job_id)
        Path(s.jobs_dir, job_id, "guest.gif").unlink()
    conn = sqlite3.connect(s.db_path)
    conn.execute("DELETE FROM images WHERE job_id=?", (job_id,))
    conn.commit(); conn.close()
    db.update_gif(s.db_path, job_id, state="processing", gif_path=None)
    with TestClient(create_app(s)) as client:
        job = wait_gif(client, job_id, expected=("failed", "ready"))
        assert job["gif_state"] == "failed"
        with db.db(s.db_path) as conn:
            stored = conn.execute("SELECT gif_error FROM jobs WHERE id=?", (job_id,)).fetchone()
        assert "one to four" in (stored["gif_error"] or "")


def test_recovery_attempts_exhausted_and_temp_cleanup(tmp_path, three_images):
    from app import db

    s = settings(tmp_path)
    with TestClient(create_app(s)) as client:
        r = post_job(client, three_images, "gif-recovery-attempts")
        job_id = r.json()["job_id"]
        wait_gif(client, job_id)
        path = Path(s.jobs_dir) / job_id / "guest.gif"
        path.unlink()
    temp = Path(s.jobs_dir) / job_id / ".guest.gif.123.part"
    temp.write_bytes(b"abandoned")
    db.update_gif(s.db_path, job_id, state="processing", gif_path=None)
    with db.db(s.db_path) as conn:
        conn.execute("UPDATE jobs SET gif_attempts=3 WHERE id=?", (job_id,))
    with TestClient(create_app(s)) as client:
        job = wait_gif(client, job_id, expected=("failed",))
        assert job["gif_state"] == "failed"
        with db.db(s.db_path) as conn:
            stored = conn.execute("SELECT gif_error FROM jobs WHERE id=?", (job_id,)).fetchone()
        assert "exhausted" in (stored["gif_error"] or "")
    assert not temp.exists()


def test_identical_frames_are_not_published_as_a_fake_animation(tmp_path, three_images):
    same = []
    for index in range(3):
        path = tmp_path / f"same_{index}.jpg"
        path.write_bytes(three_images[0])
        same.append(path)
    with pytest.raises(GifGenerationError):
        generate_gif(same, tmp_path / "identical.gif")
    assert not (tmp_path / "identical.gif").exists()


def test_guest_page_pending_and_failed_gif_states(tmp_path, three_images):
    from app import db

    s = settings(tmp_path)
    with TestClient(create_app(s)) as client:
        r = post_job(client, three_images, "gif-states")
        job_id = r.json()["job_id"]
        job = wait_gif(client, job_id)
        token = job["delivery_url"].rsplit("/", 1)[-1]

        db.update_gif(s.db_path, job_id, state="pending", gif_path=None, error=None)
        page = client.get(f"/d/{token}")
        assert page.status_code == 200
        assert "still being prepared" in page.text
        assert client.get(f"/v1/print-jobs/{job_id}/gif").status_code == 409
        assert client.get(f"/d/{token}/gif").status_code == 409
        assert "Photo 1" in page.text and "Download your photostrip" in page.text

        db.update_gif(s.db_path, job_id, state="failed", gif_path=None, error="test failure")
        page = client.get(f"/d/{token}")
        assert page.status_code == 200
        assert "could not be prepared" in page.text
        assert client.get(f"/v1/print-jobs/{job_id}/gif").status_code == 404
        assert client.get(f"/d/{token}/gif").status_code == 404
        assert "Photo 1" in page.text and "Download your photostrip" in page.text
