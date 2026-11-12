import os
import socket
from pathlib import Path

import pytest

from app.config import ConfigurationError, Settings, validate_settings
from app.main import _build_zip_file, create_app, persist_guest_manifest
from app.runtime import (
    InstanceLock,
    InstanceLockError,
    PortInUseError,
    ensure_port_available,
)


def base_settings(tmp_path):
    data = tmp_path / "data"
    data.mkdir()
    return Settings(
        data_dir=data,
        db_path=data / "bridge.db",
        printer_mode="mock",
        delivery_secret="portable-test-secret",
    )


def test_settings_validate_and_warn_without_mutating_data(tmp_path):
    s = base_settings(tmp_path)
    warnings = validate_settings(s)
    assert isinstance(warnings, list)
    assert s.jobs_dir.exists()
    with pytest.raises(ConfigurationError):
        validate_settings(
            Settings(
                data_dir=s.data_dir,
                db_path=s.db_path,
                printer_mode="unknown",
                delivery_secret="x",
            )
        )
    with pytest.raises(ConfigurationError):
        validate_settings(
            Settings(
                data_dir=s.data_dir,
                db_path=s.db_path,
                printer_mode="mock",
                delivery_secret="x",
                port=70000,
            )
        )
    with pytest.raises(ConfigurationError):
        validate_settings(
            Settings(
                data_dir=s.data_dir,
                db_path=s.db_path,
                printer_mode="mock",
                delivery_secret="x",
                public_base_url="http://localhost:8787",
            )
        )


def test_instance_lock_blocks_second_holder_and_releases(tmp_path):
    path = tmp_path / "bridge.lock"
    first = InstanceLock(path)
    first.acquire()
    try:
        second = InstanceLock(path)
        with pytest.raises(InstanceLockError):
            second.acquire()
    finally:
        first.release()
    third = InstanceLock(path)
    third.acquire()
    third.release()


def test_port_conflict_is_reported():
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
    try:
        with pytest.raises(PortInUseError):
            ensure_port_available("127.0.0.1", port)
    finally:
        probe.close()


def test_unicode_paths_zip_and_manifest_do_not_leak_paths(tmp_path):
    s = base_settings(tmp_path)
    job_dir = s.jobs_dir / "job_unicode"
    job_dir.mkdir(parents=True)
    original = job_dir / "café 照片.jpg"
    original.write_bytes(b"not-decoded-for-zip-test")
    job = {
        "id": "job_unicode",
        "session_id": "ses_unicode",
        "event_id": "evt_unicode",
        "event_title": "Café 婚禮",
        "event_date": "14 Nov 2026",
        "created_at": "2026-11-14T18:00:00Z",
        "updated_at": "2026-11-14T18:01:00Z",
        "images": [
            {
                "id": "img_unicode",
                "filename": "café 照片.jpg",
                "path": str(original),
                "sha256": "0" * 64,
                "width": 900,
                "height": 1200,
                "created_at": "2026-11-14T18:00:00Z",
            }
        ],
        "gif_state": "pending",
    }
    zip_path = _build_zip_file(job, s)
    try:
        import zipfile

        with zipfile.ZipFile(zip_path) as archive:
            assert archive.namelist() == ["photo-1.jpg"]
    finally:
        zip_path.unlink(missing_ok=True)

    persist_guest_manifest(job, s)
    text = (job_dir / "manifest.json").read_text()
    assert "Café" in text
    assert str(tmp_path) not in text
    assert "path" not in text
    assert not list(job_dir.glob(".manifest.json.*.part"))


def test_atomic_manifest_replaces_existing_file(tmp_path):
    s = base_settings(tmp_path)
    job_dir = s.jobs_dir / "job_atomic"
    job_dir.mkdir(parents=True)
    target = job_dir / "manifest.json"
    target.write_text("old")
    job = {
        "id": "job_atomic",
        "session_id": "s",
        "event_id": "e",
        "images": [],
        "gif_state": "failed",
        "created_at": "x",
        "updated_at": "y",
    }
    persist_guest_manifest(job, s)
    assert target.read_text() != "old"
    assert '"schema":"terabooth.guest/1"' in target.read_text()


def test_lightweight_diagnostics_endpoint(tmp_path):
    from fastapi.testclient import TestClient

    s = base_settings(tmp_path)
    with TestClient(create_app(s)) as client:
        response = client.get("/v1/diagnostics")
        assert response.status_code == 200
        data = response.json()
        assert data["process"]["pid"] > 0
        assert data["jobs"]["active_print"] == 0
        assert data["jobs"]["active_gif"] == 0
        assert data["jobs"]["active_zip"] == 0
        assert "asset_bytes" in data["storage"]
