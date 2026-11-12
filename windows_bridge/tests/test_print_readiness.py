import hashlib
from pathlib import Path
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
    # The query is unavailable on macOS but available on Windows; this test
    # must not assume the host platform.
    assert isinstance(out["available"], bool)
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


def test_safe_defaults_are_mock_and_actual_queue(tmp_path):
    from app.config import Settings
    from app.printer import MockPrinter, build_printer

    s = Settings(data_dir=tmp_path / "data", db_path=tmp_path / "data" / "t.db")
    assert s.printer_mode == "mock"
    assert s.printer_name == "DS-RX1"
    assert isinstance(build_printer(s), MockPrinter)


def test_spooler_submit_fails_closed_when_preflight_not_ready(tmp_path, monkeypatch):
    from app import printer as printer_module
    from app.printer import WindowsSpoolerPrinter

    s = Settings(
        data_dir=tmp_path / "data", db_path=tmp_path / "data" / "t.db",
        printer_mode="spooler", printer_name="DS-RX1",
    )
    artefact = tmp_path / "artefact.jpg"
    artefact.write_bytes(b"x")
    monkeypatch.setattr(
        printer_module, "printer_preflight",
        lambda _s: {"available": True, "ready": False,
                    "blockers": ["user_media_not_PR_4x6"]},
    )
    called = {"subprocess": False}
    monkeypatch.setattr(
        printer_module.subprocess, "run",
        lambda *a, **k: called.__setitem__("subprocess", True),
    )
    try:
        WindowsSpoolerPrinter(s).submit("job_1", artefact, 1)
        assert False, "expected RuntimeError"
    except RuntimeError as exc:
        assert "DNP print blocked" in str(exc)
        assert "user_media_not_PR_4x6" in str(exc)
    assert called["subprocess"] is False


def test_spooler_submit_fails_closed_when_preflight_unavailable(tmp_path, monkeypatch):
    from app import printer as printer_module
    from app.printer import WindowsSpoolerPrinter

    s = Settings(
        data_dir=tmp_path / "data", db_path=tmp_path / "data" / "t.db",
        printer_mode="spooler", printer_name="DS-RX1",
    )
    artefact = tmp_path / "artefact.jpg"
    artefact.write_bytes(b"x")
    monkeypatch.setattr(
        printer_module, "printer_preflight",
        lambda _s: {"available": False, "ready": False,
                    "query_error": "PowerShell missing"},
    )
    try:
        WindowsSpoolerPrinter(s).submit("job_1", artefact, 1)
        assert False, "expected RuntimeError"
    except RuntimeError as exc:
        assert "preflight unavailable" in str(exc)


def test_run_windows_launcher_defaults_to_mock():
    from pathlib import Path

    script = Path(__file__).resolve().parent.parent / "scripts" / "run_windows.ps1"
    text = script.read_text()
    assert 'if (-not $env:TERABOOTH_PRINTER) { $env:TERABOOTH_PRINTER = "mock" }' in text
    assert 'if (-not $env:TERABOOTH_PRINTER) { $env:TERABOOTH_PRINTER = "spooler" }' not in text


def test_preflight_parses_machine_user_job_sources_and_blockers(tmp_path, monkeypatch):
    from types import SimpleNamespace
    from app import printer as printer_module

    s = Settings(
        data_dir=tmp_path / "data", db_path=tmp_path / "data" / "t.db",
        printer_mode="mock", printer_name="DS-RX1",
    )
    payload = {
        "available": True, "ready": False, "queue_exists": True,
        "queue_name": "DS-RX1", "driver_name": "DS-RX1",
        "driver_manufacturer": "Dai Nippon Printing",
        "driver_version": "v", "port_name": "USB001",
        "printer_status": "Normal", "work_offline": False, "shared": False,
        "paper_size": "", "media": "ns0000:PR_4x6",
        "orientation": "psk:Portrait", "resolution": "ns0000:Option1",
        "cut": "ns0000:CUT_2INCH", "queued_jobs": 0,
        "machine_default": {"media": "ns0000:PC"},
        "user_default": {"media": "ns0000:PR_4x6"},
        "capabilities": {"media": ["ns0000:PR_4x6", "ns0000:PC"]},
        "job_request": {"media": "PR_4x6"},
        "job_level": {"available": False},
        "blockers": ["user_cut_not_standard", "machine_media_not_PR_4x6"],
        "query_error": "",
    }
    monkeypatch.setattr(printer_module.sys, "platform", "win32")
    monkeypatch.setattr(
        printer_module.subprocess, "run",
        lambda *a, **k: SimpleNamespace(
            returncode=0, stdout=json.dumps(payload), stderr=""
        ),
    )
    out = printer_module.printer_preflight(s)
    assert out["ready"] is False
    assert out["machine_default"]["media"] == "ns0000:PC"
    assert out["user_default"]["media"] == "ns0000:PR_4x6"
    assert out["job_level"]["available"] is False
    assert "user_cut_not_standard" in out["blockers"]
    assert out["configured_queue_name"] == "DS-RX1"
    assert out["spooler_mode_enabled"] is False


def test_spooler_submit_uses_no_subprocess_when_ready_gate_fails(tmp_path, monkeypatch):
    from app import printer as printer_module
    from app.printer import WindowsSpoolerPrinter

    s = Settings(
        data_dir=tmp_path / "data", db_path=tmp_path / "data" / "t.db",
        printer_mode="spooler", printer_name="DS-RX1",
    )
    artefact = tmp_path / "artefact.jpg"
    artefact.write_bytes(b"x")
    monkeypatch.setattr(
        printer_module, "printer_preflight",
        lambda _s: {"available": True, "ready": False, "blockers": ["machine_media_not_PR_4x6"]},
    )
    called = {"run": False}
    def fake_run(*a, **k):
        called["run"] = True
        raise AssertionError("print subprocess must not run")
    monkeypatch.setattr(printer_module.subprocess, "run", fake_run)
    try:
        WindowsSpoolerPrinter(s).submit("job", artefact, 1)
        assert False
    except RuntimeError as exc:
        assert "DNP print blocked" in str(exc)
    assert called["run"] is False


def test_xps_backend_uses_explicit_job_ticket_and_4x6_page():
    from pathlib import Path

    script = Path(__file__).resolve().parent.parent / "scripts" / "print_xps.ps1"
    text = script.read_text(encoding="utf-8")
    assert "XpsDocumentWriter" in text
    assert "FixedPage" in text
    assert "$page.Width = 384" in text
    assert "$page.Height = 576" in text
    assert "PR_4x6" in text
    assert "CUT_STANDARD" in text
    assert "Write($page, $ticket)" in text
    assert "MergeAndValidatePrintTicket" in text
    assert "DryRun" in text
    assert "driver_conflict" in text
    assert "CUT_2INCH" not in text
    legacy = (Path(__file__).resolve().parent.parent / "scripts" / "print_image.ps1").read_text(encoding="utf-8")
    assert "print_xps.ps1" in legacy


def test_adapter_invokes_xps_backend_with_job_config_path(tmp_path, monkeypatch):
    from types import SimpleNamespace
    from app import printer as printer_module
    from app.printer import WindowsSpoolerPrinter

    s = Settings(
        data_dir=tmp_path / "data", db_path=tmp_path / "data" / "t.db",
        printer_mode="spooler", printer_name="DS-RX1",
    )
    s.jobs_dir.mkdir(parents=True, exist_ok=True)
    artefact = tmp_path / "artefact.jpg"
    artefact.write_bytes(b"x")
    monkeypatch.setattr(
        printer_module, "printer_preflight",
        lambda _s: {
            "available": True, "ready": True, "blockers": [],
            "job_level": {"available": True},
        },
    )
    seen = {}
    def fake_run(cmd, **kwargs):
        seen["cmd"] = cmd
        idx = cmd.index("-ConfigOut")
        Path(cmd[idx + 1]).write_text(json.dumps({
            "mode": "spooler_job",
            "mechanism": "XpsDocumentWriter+explicit_PrintTicket",
            "page_inches": "4x6",
            "page_px_96dpi": "384x576",
            "media": "PR_4x6", "orientation": "Portrait",
            "resolution": "300x300", "cut": "CUT_STANDARD",
            "ticket_media": "PR_4x6", "ticket_orientation": "Portrait",
            "ticket_resolution": "300x300", "ticket_cut": "CUT_STANDARD",
            "driver_accepted_media": "PR_4x6",
            "driver_accepted_orientation": "Portrait",
            "driver_accepted_resolution": "300x300",
            "driver_accepted_cut": "CUT_STANDARD",
            "driver_conflict": "NoConflict", "driver_validated": True,
            "physical_completion": "unverified",
        }), encoding="utf-8")
        return SimpleNamespace(returncode=0, stdout='{"mechanism":"xps"}', stderr="")
    monkeypatch.setattr(printer_module.subprocess, "run", fake_run)
    handle = WindowsSpoolerPrinter(s).submit("job_xps", artefact, 1)
    assert handle.transport == "spooler"
    assert any("print_xps.ps1" in str(part) for part in seen["cmd"])
    assert "-Sta" in seen["cmd"]
    assert "-ConfigOut" in seen["cmd"]
    assert any("print_job_config.json" in str(part) for part in seen["cmd"])


def test_preflight_requires_xps_job_level(tmp_path, monkeypatch):
    from app import printer as printer_module
    from app.printer import WindowsSpoolerPrinter

    s = Settings(
        data_dir=tmp_path / "data", db_path=tmp_path / "data" / "t.db",
        printer_mode="spooler", printer_name="DS-RX1",
    )
    artefact = tmp_path / "artefact.jpg"
    artefact.write_bytes(b"x")
    monkeypatch.setattr(
        printer_module, "printer_preflight",
        lambda _s: {
            "available": True, "ready": True, "blockers": [],
            "job_level": {"available": False},
        },
    )
    try:
        WindowsSpoolerPrinter(s).submit("job", artefact, 1)
        assert False
    except RuntimeError as exc:
        assert "job-level PrintTicket backend unavailable" in str(exc)


def test_job_config_rejects_unsupported_or_conflicting_settings():
    from app.printer import validate_job_config

    good = {
        "mode": "spooler_job",
        "mechanism": "XpsDocumentWriter+explicit_PrintTicket",
        "page_inches": "4x6", "page_px_96dpi": "384x576",
        "media": "PR_4x6", "orientation": "Portrait",
        "resolution": "300x300", "cut": "CUT_STANDARD",
        "ticket_media": "PR_4x6", "ticket_orientation": "Portrait",
        "ticket_resolution": "300x300", "ticket_cut": "CUT_STANDARD",
        "driver_accepted_media": "PR_4x6",
        "driver_accepted_orientation": "Portrait",
        "driver_accepted_resolution": "300x300",
        "driver_accepted_cut": "CUT_STANDARD",
        "driver_conflict": "NoConflict", "driver_validated": True,
        "physical_completion": "unverified",
    }
    assert validate_job_config(good) == []
    cases = [
        {"cut": "CUT_2INCH", "ticket_cut": "CUT_2INCH", "driver_accepted_cut": "CUT_2INCH"},
        {"media": "PC", "ticket_media": "PC", "driver_accepted_media": "PC"},
        {"orientation": "Landscape", "ticket_orientation": "Landscape", "driver_accepted_orientation": "Landscape"},
        {"page_inches": "2x6", "page_px_96dpi": "192x576"},
        {"driver_conflict": "Conflict", "driver_validated": False},
        {"physical_completion": "completed"},
    ]
    for change in cases:
        bad = dict(good)
        bad.update(change)
        assert validate_job_config(bad), change


def test_spooler_status_remains_unknown_not_completed():
    from app.printer import PrintHandle, WindowsSpoolerPrinter

    s = Settings(data_dir=Path('/tmp'), db_path=Path('/tmp/t.db'), printer_name='DS-RX1')
    status = WindowsSpoolerPrinter(s).status(PrintHandle("spooler", "DS-RX1"))
    assert status.state == "unknown"
    assert status.completion == "unknown"


def test_driver_managed_submit_uses_default_page_and_config(tmp_path, monkeypatch):
    from types import SimpleNamespace
    from app import printer as printer_module
    from app.printer import WindowsDriverPrinter

    s = Settings(
        data_dir=tmp_path / "data", db_path=tmp_path / "data" / "t.db",
        printer_mode="driver", printer_name="DS-RX1",
    )
    s.jobs_dir.mkdir(parents=True, exist_ok=True)
    artefact = tmp_path / "artefact.jpg"; artefact.write_bytes(b"x")
    monkeypatch.setattr(printer_module, "printer_preflight", lambda _s: {
        "available": True,
        "driver_managed": {"ready": True},
        "default_page": {"is_4x6": True, "landscape": False},
    })
    seen = {}
    def fake_run(cmd, **kwargs):
        seen["cmd"] = cmd
        idx = cmd.index("-ConfigOut")
        Path(cmd[idx + 1]).write_text(json.dumps({
            "mechanism": "driver_managed_PrintDocument", "mode": "spooler_job",
            "paper_overridden": False, "orientation_overridden": False,
            "margins_overridden": False, "private_vendor_features_set": False,
            "cut_source": "Windows DNP driver preferences",
            "physical_completion": "unverified",
        }), encoding="utf-8")
        return SimpleNamespace(returncode=0, stdout="{}", stderr="")
    monkeypatch.setattr(printer_module.subprocess, "run", fake_run)
    handle = WindowsDriverPrinter(s).submit("job_driver", artefact, 1)
    assert handle.transport == "driver"
    assert any("print_driver.ps1" in str(x) for x in seen["cmd"])
    assert "-ConfigOut" in seen["cmd"]


def test_driver_managed_blocks_wrong_default_page(tmp_path, monkeypatch):
    from app import printer as printer_module
    from app.printer import WindowsDriverPrinter

    s = Settings(
        data_dir=tmp_path / "data", db_path=tmp_path / "data" / "t.db",
        printer_mode="driver", printer_name="DS-RX1",
    )
    artifact = tmp_path / "a.jpg"; artifact.write_bytes(b"x")
    monkeypatch.setattr(printer_module, "printer_preflight", lambda _s: {
        "available": True,
        "driver_managed": {"ready": False},
        "default_page": {"is_4x6": False, "landscape": False},
    })
    called = {"run": False}
    monkeypatch.setattr(printer_module.subprocess, "run",
                        lambda *a, **k: called.__setitem__("run", True))
    try:
        WindowsDriverPrinter(s).submit("j", artifact, 1)
        assert False
    except RuntimeError as exc:
        assert "driver-managed preflight not ready" in str(exc)
    assert called["run"] is False


def test_driver_config_rejects_overrides_and_false_completion():
    from app.printer import validate_driver_job_config

    good = {
        "mechanism": "driver_managed_PrintDocument", "mode": "spooler_job",
        "paper_overridden": False, "orientation_overridden": False,
        "margins_overridden": False, "private_vendor_features_set": False,
        "cut_source": "Windows DNP driver preferences",
        "physical_completion": "unverified",
    }
    assert validate_driver_job_config(good) == []
    for change in (
        {"paper_overridden": True},
        {"orientation_overridden": True},
        {"private_vendor_features_set": True},
        {"physical_completion": "completed"},
    ):
        bad = dict(good); bad.update(change)
        assert validate_driver_job_config(bad)
