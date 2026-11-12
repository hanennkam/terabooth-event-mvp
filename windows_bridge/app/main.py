from __future__ import annotations

import asyncio
import hashlib
import html
import io
import json
import os
import secrets
import socket
import tempfile
import time
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import qrcode
from fastapi import BackgroundTasks, Depends, FastAPI, File, Form, Header, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, Response
from starlette.background import BackgroundTask
from PIL import Image
from pydantic import BaseModel, ConfigDict, Field
from starlette.datastructures import UploadFile as StarletteUploadFile

from . import db
from .compose import compose_strip
from .gif_render import GifGenerationError, cleanup_gif_temp_files, generate_gif, inspect_gif
from .log_redaction import install_log_redaction
from .template_render import compose_template
from .templates import DEFAULT_TEMPLATE_ID, TemplateSpec, get_template
from .config import ConfigurationError, Settings, load_settings, validate_settings
from .diagnostics import snapshot as diagnostics_snapshot
from .printer import Printer, build_printer
from .security import make_access_token, make_token, token_hash, verify_token

TEMPLATE = "strip_2x6_3up_v1"
TERMINAL = {"completed", "failed", "unknown"}


class EventText(BaseModel):
    title: str
    date: str


class ImageMeta(BaseModel):
    id: str
    filename: str
    sha256: str
    width: int | None = None
    height: int | None = None


class CropRect(BaseModel):
    x: float
    y: float
    w: float
    h: float


class CropMeta(BaseModel):
    image_id: str
    slot_id: str
    mode: str
    rect: CropRect | None = None
    zoom: float = 1
    offset_x: float = 0
    offset_y: float = 0
    face_count: int = 0
    fallback_reason: str | None = None


class BrandingMeta(BaseModel):
    enabled: bool = False
    title: str = ""
    tagline: str = ""
    color_hex: str = "#C8A464"
    placement: str = "bottom"


class PrintMetadata(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="ignore")
    schema_name: str = Field(alias="schema")
    event_id: str
    session_id: str
    template: str = TEMPLATE
    template_version: int | None = None
    crops: list[CropMeta] = Field(default_factory=list)
    branding: BrandingMeta | None = None
    copies: int = 1
    paper: str = "4x6"
    cut: str = "2x6"
    event_text: EventText
    images: list[ImageMeta]
    delivery: dict[str, Any] = Field(default_factory=dict)


def validate_crops(meta: PrintMetadata, template: TemplateSpec) -> dict[str, dict[str, Any]]:
    image_indexes = {image.id: index for index, image in enumerate(meta.images)}
    slots = template.slots_by_id
    result: dict[str, dict[str, Any]] = {}
    for crop in meta.crops:
        if crop.slot_id not in slots:
            raise HTTPException(422, f"unsupported slot {crop.slot_id}")
        if crop.slot_id in result:
            raise HTTPException(422, f"duplicate crop for slot {crop.slot_id}")
        if crop.image_id not in image_indexes:
            raise HTTPException(422, f"unknown crop image {crop.image_id}")
        if image_indexes[crop.image_id] != slots[crop.slot_id].image_index:
            raise HTTPException(422, f"crop image does not match slot {crop.slot_id}")
        if crop.mode not in {"smart", "fit", "manual"}:
            raise HTTPException(422, "crop mode must be smart, fit or manual")
        if crop.mode != "fit":
            if crop.rect is None:
                raise HTTPException(422, f"crop rect required for slot {crop.slot_id}")
            rect = crop.rect
            values = (rect.x, rect.y, rect.w, rect.h)
            if any(not (0 <= value <= 1) for value in values):
                raise HTTPException(422, "crop values must be normalized 0..1")
            if rect.w <= 0 or rect.h <= 0 or rect.x + rect.w > 1.0001 or rect.y + rect.h > 1.0001:
                raise HTTPException(422, "crop rectangle is out of bounds")
            if crop.zoom < 1 or crop.zoom > 3:
                raise HTTPException(422, "crop zoom must be between 1 and 3")
        result[crop.slot_id] = crop.model_dump()
    return result


def _loopback(host: str) -> bool:
    value = (host or "").strip("[]").lower()
    return value in {"localhost", "127.0.0.1", "::1"} or value.startswith("127.")


def _lan_ip() -> str | None:
    candidates: set[str] = set()
    for name in {socket.gethostname(), socket.getfqdn()}:
        try:
            for info in socket.getaddrinfo(name, None, socket.AF_INET):
                candidates.add(info[4][0])
        except OSError:
            continue
    # A route lookup gives the interface address without sending packets.
    try:
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            probe.connect(("192.0.2.1", 80))
            candidates.add(probe.getsockname()[0])
        finally:
            probe.close()
    except OSError:
        pass
    for candidate in sorted(candidates):
        if not _loopback(candidate) and not candidate.startswith("169.254."):
            return candidate
    return None


def base_url(request: Request, settings: Settings) -> str | None:
    if settings.public_base_url:
        value = settings.public_base_url.rstrip("/")
        if _loopback(value.split("://", 1)[-1].split("/", 1)[0].split(":", 1)[0]):
            return None
        return value
    host = request.url.hostname or ""
    if not _loopback(host):
        return str(request.base_url).rstrip("/")
    ip = _lan_ip()
    if not ip:
        return None
    port = request.url.port or 8787
    return f"http://{ip}:{port}"


def job_json(job: dict[str, Any], request: Request, settings: Settings) -> dict[str, Any]:
    token = job.get("delivery_token")
    root = base_url(request, settings)
    url = f"{root}/d/{token}" if token and root else None
    return {
        "job_id": job["id"],
        "state": job["state"],
        "completion": job["completion"],
        "attempts": job["attempts"],
        "session_id": job["session_id"],
        "event_id": job["event_id"],
        "template": job["template"],
        "copies": job["copies"],
        "event_title": job.get("event_title", "TERABOOTH"),
        "event_date": job.get("event_date", ""),
        "created_at": job["created_at"],
        "updated_at": job["updated_at"],
        "completed_at": job["completed_at"],
        "error": job["error"],
        "reprint_of": job["reprint_of"],
        "gif_state": job.get("gif_state", "pending"),
        "printer_mode": settings.printer_mode,
        "gif_bytes": job.get("gif_bytes"),
        "delivery_url": url,
        "delivery_available": url is not None,
        "images": [
            {"id": i["id"], "filename": i["filename"], "sha256": i["sha256"],
             "width": i["width"], "height": i["height"]}
            for i in job.get("images", [])
        ],
    }


def _mime_for(path: Path) -> str:
    try:
        with Image.open(path) as im:
            return {
                "JPEG": "image/jpeg",
                "PNG": "image/png",
                "GIF": "image/gif",
            }.get((im.format or "").upper(), "application/octet-stream")
    except Exception:
        return "application/octet-stream"


def _asset_entry(path: Path, token: str, endpoint: str, filename: str) -> dict[str, Any] | None:
    if not path.exists() or not path.is_file():
        return None
    return {
        "filename": filename,
        "mime": _mime_for(path),
        "bytes": path.stat().st_size,
        "download_url": f"/d/{token}/{endpoint}",
    }


def guest_manifest(job: dict[str, Any], token: str, settings: Settings) -> dict[str, Any]:
    images = []
    for index, image in enumerate(job.get("images", []), start=1):
        path = Path(image["path"])
        entry = _asset_entry(
            path,
            token,
            f"original/{image['id']}",
            f"photo-{index}{path.suffix.lower()}",
        )
        if entry:
            entry["id"] = image["id"]
            entry["order"] = index
            images.append(entry)
    strip = _asset_entry(
        settings.jobs_dir / job["id"] / "artefact.jpg",
        token,
        "strip",
        "terabooth-strip.jpg",
    )
    gif_state = job.get("gif_state", "pending")
    gif_path_value = job.get("gif_path")
    gif_path = (
        Path(gif_path_value)
        if gif_path_value
        else settings.jobs_dir / job["id"] / "guest.gif"
    )
    gif = (
        _asset_entry(gif_path, token, "gif", "terabooth.gif")
        if gif_state == "ready"
        else None
    )
    brand = None
    logo_available = False
    if job.get("branding_json"):
        try:
            raw_brand = json.loads(job["branding_json"])
        except Exception:
            raw_brand = {}
        logo_path = raw_brand.get("logo_path")
        logo_available = bool(logo_path and Path(str(logo_path)).is_file())
        brand = {
            "enabled": bool(raw_brand.get("enabled")),
            "title": raw_brand.get("title", ""),
            "tagline": raw_brand.get("tagline", ""),
            "color_hex": raw_brand.get("color_hex", "#C8A464"),
            "placement": raw_brand.get("placement", "bottom"),
            "logo_available": logo_available,
        }
    return {
        "schema": "terabooth.guest/1",
        "session_id": job.get("session_id"),
        "event_id": job.get("event_id"),
        "job_id": job["id"],
        "approved": True,
        "event": {
            "title": job.get("event_title") or "Terabooth",
            "date": job.get("event_date") or "",
            "branding": brand or {},
        },
        "originals": images,
        "strip": strip,
        "gif": {
            "state": gif_state,
            "asset": gif,
            "error": job.get("gif_error"),
        },
        "created_at": job.get("created_at"),
        "updated_at": job.get("updated_at"),
    }


def persist_guest_manifest(job: dict[str, Any], settings: Settings) -> None:
    """Persist a path-free manifest atomically next to the derived assets."""
    data = guest_manifest(job, "", settings)
    for item in data.get("originals", []):
        item.pop("download_url", None)
    for key in ("strip",):
        if data.get(key):
            data[key].pop("download_url", None)
    if data.get("gif", {}).get("asset"):
        data["gif"]["asset"].pop("download_url", None)
    target = settings.jobs_dir / job["id"] / "manifest.json"
    temp = settings.jobs_dir / job["id"] / ".manifest.json.part"
    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        temp.write_text(
            json.dumps(data, separators=(",", ":"), ensure_ascii=False),
            encoding="utf-8",
        )
        from .atomic import replace_with_retry

        replace_with_retry(temp, target)
    except OSError:
        try:
            temp.unlink(missing_ok=True)
        except OSError:
            pass


def _remove_quietly(path: Path) -> None:
    try:
        path.unlink(missing_ok=True)
    except OSError:
        pass


def _build_zip_file(job: dict[str, Any], settings: Settings) -> Path:
    fd, raw = tempfile.mkstemp(
        prefix=".download-",
        suffix=".zip",
        dir=str(settings.jobs_dir / job["id"]),
    )
    os.close(fd)
    path = Path(raw)
    try:
        with zipfile.ZipFile(path, "w", zipfile.ZIP_STORED) as archive:
            for index, image in enumerate(job.get("images", []), start=1):
                source = Path(image["path"])
                if source.exists() and source.is_file():
                    archive.write(source, arcname=f"photo-{index}{source.suffix.lower()}")
            strip = settings.jobs_dir / job["id"] / "artefact.jpg"
            if strip.exists():
                archive.write(strip, arcname="terabooth-strip.jpg")
            gif_state = job.get("gif_state", "pending")
            gif_path = (
                Path(job["gif_path"])
                if job.get("gif_path")
                else settings.jobs_dir / job["id"] / "guest.gif"
            )
            if gif_state == "ready" and gif_path.exists():
                archive.write(gif_path, arcname="terabooth.gif")
        return path
    except Exception:
        _remove_quietly(path)
        raise


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or load_settings()
    startup_warnings = validate_settings(settings)
    install_log_redaction(settings)
    if settings.public_base_url and any(
        host in settings.public_base_url for host in ("localhost", "127.0.0.1")
    ):
        raise ValueError("TERABOOTH_PUBLIC_BASE_URL must be the Windows LAN IP, not localhost")
    db.init_db(settings.db_path)
    printer: Printer = build_printer(settings)
    app = FastAPI(title="Terabooth Print Bridge", version="0.1.0")
    tasks: set[asyncio.Task] = set()
    print_semaphore = asyncio.Semaphore(1)
    gif_semaphore = asyncio.Semaphore(1)
    zip_semaphore = asyncio.Semaphore(1)
    started_at = time.time()
    active_print = 0
    active_gif = 0
    active_zip = 0

    @app.middleware("http")
    async def guest_security_headers(request: Request, call_next):
        response = await call_next(request)
        if request.url.path.startswith("/d/"):
            response.headers["Cache-Control"] = "no-store"
            response.headers["X-Content-Type-Options"] = "nosniff"
            response.headers["Referrer-Policy"] = "no-referrer"
            response.headers["Content-Security-Policy"] = (
                "default-src 'self'; img-src 'self' data:; "
                "style-src 'self' 'unsafe-inline'; script-src 'none'"
            )
        return response

    def auth(authorization: str | None = Header(default=None)) -> None:
        if settings.api_token and not secrets.compare_digest(
            authorization or "", f"Bearer {settings.api_token}"
        ):
            raise HTTPException(status_code=401, detail="unauthorized")

    async def process_job_impl(job_id: str) -> None:
        job = db.get_job(settings.db_path, job_id)
        if not job:
            return
        try:
            db.update_job(settings.db_path, job_id, state="composing")
            db.add_attempt(settings.db_path, job_id, "composing")
            image_paths = [Path(i["path"]) for i in job["images"]]
            artefact = settings.jobs_dir / job_id / "artefact.jpg"
            template_spec = get_template(job.get("template") or DEFAULT_TEMPLATE_ID)
            crops_json = job.get("crops_json")
            crops = json.loads(crops_json) if crops_json else {}
            branding_json = job.get("branding_json")
            branding = json.loads(branding_json) if branding_json else None
            if template_spec and (
                crops or branding or template_spec.id != DEFAULT_TEMPLATE_ID
            ):
                image_map = {i["id"]: Path(i["path"]) for i in job["images"]}
                compose_template(
                    image_map, artefact, template_spec,
                    title=job.get("event_title") or "TERABOOTH",
                    date=job.get("event_date") or datetime.now().strftime("%d %b %Y"),
                    crops=crops, font_path=settings.font_path,
                    branding=branding,
                )
            else:
                compose_strip(
                    image_paths, artefact,
                    title=job.get("event_title") or "TERABOOTH",
                    date=job.get("event_date") or datetime.now().strftime("%d %b %Y"),
                    font_path=settings.font_path,
                )
            db.update_job(settings.db_path, job_id, state="queued")
            persist_guest_manifest(db.get_job(settings.db_path, job_id), settings)
            db.add_attempt(settings.db_path, job_id, "queued", str(artefact))
            handle = printer.submit(job_id, artefact, int(job["copies"]))
            db.update_job(settings.db_path, job_id, state="printing",
                          attempts=int(job["attempts"]) + 1, printer=handle.transport)
            db.add_attempt(settings.db_path, job_id, "printing", handle.reference)
            deadline = time.monotonic() + settings.job_timeout_seconds
            while time.monotonic() < deadline:
                status = printer.status(handle)
                if status.state == "completed":
                    db.update_job(settings.db_path, job_id, state="completed",
                                  completion=status.completion,
                                  completed_at=db.now_iso(), error=None)
                    db.add_attempt(settings.db_path, job_id, "completed", status.detail)
                    return
                if status.state == "failed":
                    db.update_job(settings.db_path, job_id, state="failed",
                                  completion=status.completion, error=status.detail)
                    db.add_attempt(settings.db_path, job_id, "failed", status.detail)
                    return
                if status.state == "unknown":
                    db.update_job(settings.db_path, job_id, state="unknown",
                                  completion="unknown", error=status.detail)
                    db.add_attempt(settings.db_path, job_id, "unknown", status.detail)
                    return
                await asyncio.sleep(0.25)
            db.update_job(settings.db_path, job_id, state="unknown",
                          completion="unknown", error="print completion not confirmed")
            db.add_attempt(settings.db_path, job_id, "unknown", "timeout")
        except Exception as exc:  # noqa: BLE001
            db.update_job(settings.db_path, job_id, state="failed",
                          completion="unknown", error=str(exc))
            db.add_attempt(settings.db_path, job_id, "failed", str(exc))

    async def process_job(job_id: str) -> None:
        nonlocal active_print
        async with print_semaphore:
            active_print += 1
            try:
                await process_job_impl(job_id)
            finally:
                active_print -= 1

    async def build_gif_impl(job_id: str) -> None:
        job = db.get_job(settings.db_path, job_id)
        if not job or job.get("gif_state") == "ready":
            return
        if not db.claim_gif(settings.db_path, job_id):
            return
        try:
            if not 1 <= len(job.get("images", [])) <= 4:
                raise GifGenerationError(
                    "approved session must contain one to four images"
                )
            paths = [Path(image["path"]) for image in job["images"]]
            out = settings.jobs_dir / job_id / "guest.gif"
            metadata = await asyncio.to_thread(generate_gif, paths, out)
            db.update_gif(
                settings.db_path, job_id,
                state="ready", gif_path=str(out),
                gif_bytes=int(metadata["bytes"]),
            )
            db.add_attempt(settings.db_path, job_id, "gif_ready", f"{metadata['bytes']} bytes")
            persist_guest_manifest(db.get_job(settings.db_path, job_id), settings)
        except Exception as exc:  # GIF failure must never affect printing
            db.update_gif(settings.db_path, job_id, state="failed", error=str(exc))
            db.add_attempt(settings.db_path, job_id, "gif_failed", str(exc))

    async def build_gif(job_id: str) -> None:
        nonlocal active_gif
        async with gif_semaphore:
            active_gif += 1
            try:
                await build_gif_impl(job_id)
            finally:
                active_gif -= 1

    def schedule(coro) -> None:
        task = asyncio.create_task(coro)
        tasks.add(task)
        task.add_done_callback(tasks.discard)

    async def recover_gif_jobs() -> None:
        """Recover interrupted GIF work without touching print state.

        On process start any `processing` claim is stale by definition for this
        single-process bridge. Ready files are validated but never overwritten.
        """
        removed = await asyncio.to_thread(cleanup_gif_temp_files, settings.jobs_dir)
        if removed:
            print(f"GIF recovery: removed {removed} abandoned temp file(s)")
        for job in db.gif_jobs(settings.db_path):
            job_id = job["id"]
            state = job.get("gif_state", "pending")
            path_value = job.get("gif_path")
            path = Path(path_value) if path_value else settings.jobs_dir / job_id / "guest.gif"
            if state == "ready":
                try:
                    if not path.exists():
                        raise GifGenerationError("ready GIF artefact is missing")
                    inspect_gif(path, expected_frames=len(job.get("images", [])))
                    continue
                except Exception as exc:
                    db.update_gif(settings.db_path, job_id, state="failed", error=f"ready GIF validation failed: {exc}")
                    db.add_gif_attempt(settings.db_path, job_id, f"ready validation failed: {exc}")
                    continue
            if path.exists():
                try:
                    metadata = inspect_gif(path, expected_frames=len(job.get("images", [])))
                    db.update_gif(
                        settings.db_path, job_id, state="ready",
                        gif_path=str(path), gif_bytes=int(metadata["bytes"]),
                    )
                    db.add_gif_attempt(settings.db_path, job_id, "existing GIF validated")
                    continue
                except Exception as exc:
                    db.update_gif(settings.db_path, job_id, state="failed", error=f"existing GIF validation failed: {exc}")
                    db.add_gif_attempt(settings.db_path, job_id, f"existing GIF invalid: {exc}")
                    continue
            if not 1 <= len(job.get("images", [])) <= 4:
                db.update_gif(settings.db_path, job_id, state="failed", error="GIF recovery requires one to four job images")
                db.add_gif_attempt(settings.db_path, job_id, "wrong image count")
                continue
            if int(job.get("gif_attempts") or 0) >= 3:
                db.update_gif(settings.db_path, job_id, state="failed", error="GIF recovery attempts exhausted")
                db.add_gif_attempt(settings.db_path, job_id, "attempts exhausted")
                continue
            if state == "processing":
                if not db.reset_gif_claim(settings.db_path, job_id):
                    continue
                db.add_gif_attempt(settings.db_path, job_id, "stale processing claim released")
            schedule(build_gif(job_id))

    @app.on_event("startup")
    async def _startup_recover_gifs() -> None:
        schedule(recover_gif_jobs())

    @app.on_event("shutdown")
    async def _shutdown_tasks() -> None:
        pending = list(tasks)
        for task in pending:
            task.cancel()
        if pending:
            await asyncio.gather(*pending, return_exceptions=True)

    @app.get("/v1/health")
    async def health(_: None = Depends(auth)) -> dict[str, Any]:
        return {
            "service": "terabooth-print",
            "version": "0.1.0",
            "time": db.now_iso(),
            "printer": printer.health(),
            "queue_depth": len([j for j in db.list_jobs(settings.db_path, 100)
                                if j["state"] in {"received", "validated", "composing", "queued", "printing"}]),
            "configuration_warnings": startup_warnings,
            "delivery": {
                "enabled": True,
                "public_base_url": settings.public_base_url,
                "warning": None if settings.public_base_url else
                "set TERABOOTH_PUBLIC_BASE_URL to the Windows LAN IP for guest QR codes",
            },
            "printer_mode": settings.printer_mode,
        }

    @app.get("/v1/diagnostics")
    async def diagnostics(_: None = Depends(auth)) -> dict[str, Any]:
        queue_depth = len([
            j for j in db.list_jobs(settings.db_path, 100)
            if j["state"] in {"received", "validated", "composing", "queued", "printing"}
        ])
        return diagnostics_snapshot(
            jobs_dir=settings.jobs_dir,
            queue_depth=queue_depth,
            active_tasks=len(tasks),
            active_gif=active_gif,
            active_zip=active_zip,
            active_print=active_print,
            uptime_seconds=time.time() - started_at,
        )

    @app.get("/v1/printers")
    async def printers(_: None = Depends(auth)) -> dict[str, Any]:
        return {"printers": [printer.health()]}

    @app.post("/v1/print-jobs")
    async def create_print_job(
        request: Request,
        background: BackgroundTasks,
        idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
        _: None = Depends(auth),
    ) -> Response:
        form = await request.form()
        raw = form.get("metadata")
        if not isinstance(raw, str):
            raise HTTPException(400, "metadata part is required")
        try:
            meta = PrintMetadata.model_validate_json(raw)
        except Exception as exc:
            raise HTTPException(422, f"invalid metadata: {exc}") from exc
        template_spec = get_template(meta.template)
        if template_spec is None:
            raise HTTPException(422, f"unsupported template {meta.template}")
        version = meta.template_version
        if version is None:
            if template_spec.id != DEFAULT_TEMPLATE_ID:
                raise HTTPException(422, "template_version is required for this template")
            version = 1
        if version != template_spec.version:
            raise HTTPException(422, f"unsupported template version {version}")
        crop_map = validate_crops(meta, template_spec)
        if meta.copies < 1 or meta.copies > 2:
            raise HTTPException(422, "copies must be 1 or 2")
        expected_images = len(template_spec.slots)
        if len(meta.images) != expected_images:
            raise HTTPException(
                422,
                f"template requires exactly {expected_images} images",
            )
        key = idempotency_key or request.headers.get("Idempotency-Key")
        if not key:
            raise HTTPException(400, "Idempotency-Key header is required")
        existing = db.get_job_by_key(settings.db_path, key)
        if existing:
            payload = job_json(existing, request, settings)
            payload["duplicate"] = True
            return JSONResponse(payload, status_code=200)

        files: list[StarletteUploadFile] = []
        for field, value in form.multi_items():
            if field.startswith("image_") and isinstance(value, StarletteUploadFile):
                files.append(value)
        if len(files) != expected_images:
            raise HTTPException(
                422,
                f"expected {expected_images} image parts, got {len(files)}",
            )

        total = 0
        raw_images: list[tuple[bytes, ImageMeta]] = []
        for idx, (upload, declared) in enumerate(zip(files, meta.images), start=1):
            data = await upload.read()
            total += len(data)
            if len(data) > settings.max_image_bytes:
                raise HTTPException(413, f"image_{idx} too large")
            if total > settings.max_total_bytes:
                raise HTTPException(413, "total upload too large")
            digest = hashlib.sha256(data).hexdigest()
            if digest.lower() != declared.sha256.lower():
                raise HTTPException(422, f"image_{idx} hash mismatch")
            try:
                with Image.open(io.BytesIO(data)) as im:
                    im.verify()
                with Image.open(io.BytesIO(data)) as im:
                    width, height = im.size
            except Exception as exc:
                raise HTTPException(422, f"image_{idx} is not a valid image") from exc
            if width < 600 or height < 600:
                raise HTTPException(422, f"image_{idx} too small ({width}x{height})")
            raw_images.append((data, declared))

        branding_payload = None
        if meta.branding and meta.branding.enabled:
            import re
            if not re.fullmatch(r"#[0-9a-fA-F]{6}", meta.branding.color_hex):
                raise HTTPException(422, "branding color must be a hex colour")
            if meta.branding.placement not in {"top", "bottom"}:
                raise HTTPException(422, "branding placement must be top or bottom")
            branding_payload = meta.branding.model_dump()
            logo_upload = form.get("branding_logo")
            if isinstance(logo_upload, StarletteUploadFile):
                logo_bytes = await logo_upload.read()
                if len(logo_bytes) > 2 * 1024 * 1024:
                    raise HTTPException(413, "branding logo too large")
                try:
                    with Image.open(io.BytesIO(logo_bytes)) as im:
                        im.verify()
                        logo_format = im.format
                    if logo_format not in {"PNG", "JPEG"}:
                        raise ValueError("logo must be PNG or JPEG")
                except Exception as exc:
                    raise HTTPException(422, "branding logo is invalid") from exc
                branding_payload["logo_bytes_sha"] = hashlib.sha256(logo_bytes).hexdigest()
                branding_payload["_logo_bytes"] = logo_bytes

        session = db.create_session(settings.db_path, meta.event_id)
        job_id = db.new_id("job")
        job_dir = settings.jobs_dir / job_id / "input"
        job_dir.mkdir(parents=True, exist_ok=True)
        if branding_payload is not None:
            logo_bytes = branding_payload.pop("_logo_bytes", None)
            if logo_bytes:
                logo_path = settings.jobs_dir / job_id / "branding_logo"
                logo_path.write_bytes(logo_bytes)
                branding_payload["logo_path"] = str(logo_path)
            branding_payload = {k: v for k, v in branding_payload.items()}
        token_payload = {
            "v": 1, "event_id": meta.event_id, "session_id": session["id"],
            "job_id": job_id, "exp": int(time.time()) + settings.token_ttl_hours * 3600,
        }
        token = make_access_token()
        job = db.create_job(
            settings.db_path, session_id=session["id"], event_id=meta.event_id,
            idempotency_key=key, template=meta.template, copies=meta.copies,
            delivery_token=token, reprint_of=None, job_id=job_id,
            event_title=meta.event_text.title, event_date=meta.event_text.date,
            template_version=version,
            crops_json=json.dumps(crop_map) if crop_map else None,
            branding_json=json.dumps(branding_payload) if branding_payload else None,
        )
        for data, declared in raw_images:
            image_id = db.new_id("img")
            path = job_dir / f"{image_id}.jpg"
            path.write_bytes(data)
            db.add_image(
                settings.db_path, job_id=job_id, session_id=session["id"],
                image_id=image_id, filename=declared.filename,
                sha256=declared.sha256, width=declared.width or 0,
                height=declared.height or 0, file_path=str(path),
            )
        db.add_delivery(settings.db_path, token, job_id, token_payload["exp"])
        db.update_job(settings.db_path, job_id, state="validated")
        db.add_attempt(settings.db_path, job_id, "validated")
        schedule(process_job(job_id))
        schedule(build_gif(job_id))
        fresh = db.get_job(settings.db_path, job_id)
        payload = job_json(fresh, request, settings)  # type: ignore[arg-type]
        payload["duplicate"] = False
        return JSONResponse(payload, status_code=202)

    @app.get("/v1/print-jobs/{job_id}")
    async def get_job(job_id: str, request: Request, _: None = Depends(auth)) -> dict[str, Any]:
        job = db.get_job(settings.db_path, job_id)
        if not job:
            raise HTTPException(404, "job not found")
        return job_json(job, request, settings)

    @app.get("/v1/print-jobs/{job_id}/artefact")
    async def get_artefact(job_id: str, _: None = Depends(auth)) -> FileResponse:
        job = db.get_job(settings.db_path, job_id)
        if not job:
            raise HTTPException(404, "job not found")
        path = settings.jobs_dir / job_id / "artefact.jpg"
        if not path.exists():
            raise HTTPException(404, "artefact not ready")
        return FileResponse(path, media_type="image/jpeg", filename=f"{job_id}.jpg")

    @app.get("/v1/print-jobs/{job_id}/gif")
    async def get_gif(job_id: str, inline: bool = False, _: None = Depends(auth)) -> FileResponse:
        job = db.get_job(settings.db_path, job_id)
        if not job:
            raise HTTPException(404, "job not found")
        state = job.get("gif_state", "pending")
        if state in {"pending", "processing"}:
            raise HTTPException(409, "animated GIF is still being prepared")
        path_value = job.get("gif_path")
        path = Path(path_value) if path_value else settings.jobs_dir / job_id / "guest.gif"
        if state == "ready" and path.exists():
            return FileResponse(
                path,
                media_type="image/gif",
                filename=None if inline else "terabooth.gif",
                content_disposition_type="inline" if inline else "attachment",
                headers={"Cache-Control": "no-store"},
            )
        raise HTTPException(404, "animated GIF unavailable")

    def _new_delivery_link(job: dict[str, Any], request: Request) -> dict[str, Any] | None:
        token = make_access_token()
        expires = int(time.time()) + settings.token_ttl_hours * 3600
        db.add_delivery(settings.db_path, token, job["id"], expires)
        db.update_job(settings.db_path, job["id"], delivery_token=token)
        return db.get_job(settings.db_path, job["id"])

    @app.post("/v1/print-jobs/{job_id}/delivery/revoke")
    async def revoke_delivery(job_id: str, request: Request, _: None = Depends(auth)) -> dict[str, Any]:
        job = db.get_job(settings.db_path, job_id)
        if not job:
            raise HTTPException(404, "job not found")
        db.delete_delivery_for_job(settings.db_path, job_id)
        db.update_job(settings.db_path, job_id, delivery_token=None)
        fresh = db.get_job(settings.db_path, job_id)
        return job_json(fresh, request, settings)  # type: ignore[arg-type]

    @app.post("/v1/print-jobs/{job_id}/delivery/regenerate")
    async def regenerate_delivery(job_id: str, request: Request, _: None = Depends(auth)) -> dict[str, Any]:
        job = db.get_job(settings.db_path, job_id)
        if not job:
            raise HTTPException(404, "job not found")
        db.delete_delivery_for_job(settings.db_path, job_id)
        fresh = _new_delivery_link(job, request)
        if not fresh:
            raise HTTPException(404, "job not found")
        return job_json(fresh, request, settings)

    @app.post("/v1/print-jobs/{job_id}/reprint")
    async def reprint(job_id: str, request: Request, _: None = Depends(auth),
                      idempotency_key: str | None = Header(default=None, alias="Idempotency-Key")) -> Response:
        original = db.get_job(settings.db_path, job_id)
        if not original:
            raise HTTPException(404, "job not found")
        key = idempotency_key or f"reprint:{job_id}:{db.new_id('r')}"
        existing = db.get_job_by_key(settings.db_path, key)
        if existing:
            payload = job_json(existing, request, settings)
            payload["duplicate"] = True
            return JSONResponse(payload, status_code=200)
        new_job_id = db.new_id("job")
        job_dir = settings.jobs_dir / new_job_id / "input"
        job_dir.mkdir(parents=True, exist_ok=True)
        token_payload = {
            "v": 1, "event_id": original["event_id"], "session_id": original["session_id"],
            "job_id": new_job_id, "exp": int(time.time()) + settings.token_ttl_hours * 3600,
        }
        token = make_access_token()
        job = db.create_job(
            settings.db_path, session_id=original["session_id"], event_id=original["event_id"],
            idempotency_key=key, template=original["template"], copies=original["copies"],
            delivery_token=token, reprint_of=job_id, job_id=new_job_id,
            event_title=original.get("event_title", "TERABOOTH"),
            event_date=original.get("event_date", ""),
            template_version=int(original.get("template_version") or 1),
            crops_json=original.get("crops_json"),
            branding_json=original.get("branding_json"),
        )
        for image in original["images"]:
            src = Path(image["path"])
            dest = job_dir / f"{db.new_id('img')}.jpg"
            dest.write_bytes(src.read_bytes())
            db.add_image(
                settings.db_path, job_id=new_job_id, session_id=original["session_id"],
                image_id=db.new_id("img"), filename=image["filename"],
                sha256=image["sha256"], width=image["width"], height=image["height"],
                file_path=str(dest),
            )
        db.add_delivery(settings.db_path, token, new_job_id, token_payload["exp"])
        db.update_job(settings.db_path, new_job_id, state="validated")
        db.add_attempt(settings.db_path, new_job_id, "validated", f"reprint of {job_id}")
        schedule(process_job(new_job_id))
        schedule(build_gif(new_job_id))
        fresh = db.get_job(settings.db_path, new_job_id)
        return JSONResponse(job_json(fresh, request, settings), status_code=202)  # type: ignore[arg-type]

    @app.delete("/v1/print-jobs/{job_id}")
    async def cancel(job_id: str, _: None = Depends(auth)) -> dict[str, Any]:
        job = db.get_job(settings.db_path, job_id)
        if not job:
            raise HTTPException(404, "job not found")
        if job["state"] in {"printing", "completed"}:
            raise HTTPException(409, "cannot cancel after printing has started")
        db.update_job(settings.db_path, job_id, state="failed", error="cancelled")
        return {"job_id": job_id, "state": "failed"}

    def require_delivery(token: str) -> tuple[dict[str, Any], dict[str, Any]]:
        # New tokens are opaque random secrets; signed legacy tokens remain
        # accepted when a matching delivery record exists.
        record = db.get_delivery(settings.db_path, token)
        payload: dict[str, Any] | None = None
        if record:
            if int(record["expires_at"]) < int(time.time()):
                raise HTTPException(404, "invalid or expired link")
            payload = {
                "job_id": record["job_id"],
                "event_id": record.get("event_id"),
                "session_id": record.get("session_id"),
            }
        else:
            payload = verify_token(settings.delivery_secret, token)
            if not payload:
                raise HTTPException(404, "invalid or expired link")
            record = db.get_delivery(settings.db_path, token)
            if not record or record["job_id"] != payload["job_id"]:
                raise HTTPException(404, "invalid or expired link")
            if int(record["expires_at"]) < int(time.time()):
                raise HTTPException(404, "invalid or expired link")
        job = db.get_job(settings.db_path, payload["job_id"])
        if not job:
            raise HTTPException(404, "invalid or expired link")
        return payload, job

    @app.get("/d/{token}", response_class=HTMLResponse)
    async def delivery_page(token: str, request: Request) -> HTMLResponse:
        payload, job = require_delivery(token)
        manifest = guest_manifest(job, token, settings)
        event = manifest["event"]
        title = html.escape(str(event.get("title") or "Terabooth"))
        date = html.escape(str(event.get("date") or ""))
        brand = event.get("branding") or {}
        color = html.escape(str(brand.get("color_hex") or "#C8A464"))
        if not color.startswith("#") or len(color) not in {4, 7}:
            color = "#C8A464"
        tagline = html.escape(str(brand.get("tagline") or ""))
        logo = ""
        if brand.get("logo_path") and Path(str(brand["logo_path"])).exists():
            logo = f'<img class="logo" src="/d/{token}/branding-logo" alt="">'
        cards = "".join(
            f'<a class="photo" href="/d/{token}/original/{html.escape(item["id"])}" '
            f'aria-label="Download photo {item["order"]}">'
            f'<img src="/d/{token}/original/{html.escape(item["id"])}?inline=1" '
            f'alt="Photo {item["order"]}"><span>Photo {item["order"]} · download</span></a>'
            for item in manifest["originals"]
        )
        strip_html = ""
        if manifest["strip"]:
            strip_html = (
                f'<a class="strip" href="/d/{token}/strip">'
                f'<img src="/d/{token}/strip?inline=1" alt="Branded photo strip">'
                f'<span>Download your photostrip</span></a>'
            )
        gif = manifest["gif"]
        if gif["asset"]:
            gif_html = (
                f'<a class="gif" href="/d/{token}/gif">'
                f'<img src="/d/{token}/gif?inline=1" alt="Animated GIF">'
                f'<span>Download animated GIF</span></a>'
            )
        elif gif["state"] in {"pending", "processing"}:
            gif_html = '<p class="notice">Your GIF is still being prepared. Photos and strip are ready now.</p>'
        elif gif["state"] == "failed":
            gif_html = '<p class="notice">The GIF could not be prepared. Photos and strip are still available.</p>'
        else:
            gif_html = ""
        body = f"""<!doctype html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>{title} · Terabooth</title><style>
:root{{--brand:{color};--bg:#111318;--surface:#1c2028;--muted:#a8a39a}}
*{{box-sizing:border-box}}body{{margin:0;background:linear-gradient(160deg,#0b0d11,#17141a);color:#f5efe3;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}}
main{{max-width:760px;margin:0 auto;padding:22px 16px 44px}}header{{text-align:center;padding:16px 0 20px}}
.logo{{max-width:180px;max-height:76px;object-fit:contain;margin-bottom:10px}}
.eyebrow{{color:var(--brand);font-size:11px;font-weight:800;letter-spacing:2.4px;text-transform:uppercase}}
h1{{font-size:clamp(26px,8vw,42px);line-height:1.05;margin:8px 0 6px}}.date,.tagline,figcaption,.notice{{color:var(--muted);font-size:14px}}
.grid{{display:grid;grid-template-columns:repeat(2,1fr);gap:10px;margin:20px 0}}
.photo{{display:block;text-decoration:none;color:#f5efe3;background:var(--surface);border:1px solid #30343d;border-radius:14px;overflow:hidden}}
.photo img{{display:block;width:100%;aspect-ratio:2/3;object-fit:cover}}.photo span{{display:block;padding:10px;font-size:12px;font-weight:700}}
.strip,.gif{{display:block;text-decoration:none;color:#111;background:var(--brand);border-radius:14px;overflow:hidden;margin:12px 0;font-weight:800;text-align:center}}
.strip img,.gif img{{display:block;width:100%;max-height:52vh;object-fit:contain;background:#fff}}.strip span,.gif span{{display:block;padding:14px}}
.gif{{background:#252a34;color:var(--brand)}} .notice{{text-align:center;line-height:1.45}}
.all{{display:block;text-align:center;background:transparent;border:1px solid var(--brand);color:var(--brand);padding:14px;border-radius:14px;text-decoration:none;font-weight:800;margin:16px 0}}
footer{{color:#777;text-align:center;font-size:11px;margin-top:24px;line-height:1.5}}
@media(min-width:620px){{.grid{{grid-template-columns:repeat(3,1fr)}}}}
</style></head><body><main><header>{logo}<div class="eyebrow">Your photos are ready</div>
<h1>{title}</h1><div class="date">{date}</div>{"<div class='tagline'>"+tagline+"</div>" if tagline else ""}</header>
<section class="grid">{cards}</section>{strip_html}{gif_html}
<a class="all" href="/d/{token}/download.zip">Download all photos</a>
<footer>Downloads work on the booth's local Wi-Fi only. No internet or account required.<br>This page only contains your approved session photos.</footer>
</main></body></html>"""
        return HTMLResponse(body, headers={
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff",
            "Referrer-Policy": "no-referrer",
        })

    @app.get("/d/{token}/original/{image_id}")
    async def delivery_original(token: str, image_id: str, inline: bool = False) -> FileResponse:
        _, job = require_delivery(token)
        image = db.get_image(settings.db_path, image_id)
        if not image or image["job_id"] != job["id"]:
            raise HTTPException(404, "not found")
        path = Path(image["path"])
        # The client normally uploads JPEG, but the simulator/mock camera uses
        # PNG. Do not serve PNG bytes as image/jpeg.
        try:
            with Image.open(path) as im:
                image_format = (im.format or "").upper()
        except Exception:
            image_format = ""
        media_type = {
            "JPEG": "image/jpeg",
            "PNG": "image/png",
        }.get(image_format, "application/octet-stream")
        suffix = {"JPEG": ".jpg", "PNG": ".png"}.get(image_format)
        filename = image["filename"]
        if suffix:
            filename = f"{Path(filename).stem}{suffix}"
        return FileResponse(
            path,
            media_type=media_type,
            filename=filename if not inline else None,
            content_disposition_type="inline" if inline else "attachment",
            headers={"Cache-Control": "no-store"},
        )

    @app.get("/d/{token}/strip")
    async def delivery_strip(token: str, inline: bool = False) -> FileResponse:
        _, job = require_delivery(token)
        path = settings.jobs_dir / job["id"] / "artefact.jpg"
        if not path.exists():
            raise HTTPException(404, "not ready")
        return FileResponse(
            path,
            media_type="image/jpeg",
            filename=None if inline else "terabooth-strip.jpg",
            content_disposition_type="inline" if inline else "attachment",
            headers={"Cache-Control": "no-store"},
        )

    @app.get("/d/{token}/gif")
    async def delivery_gif(token: str, inline: bool = False) -> FileResponse:
        _, job = require_delivery(token)
        state = job.get("gif_state", "pending")
        if state in {"pending", "processing"}:
            raise HTTPException(409, "animated GIF is still being prepared")
        path_value = job.get("gif_path")
        path = Path(path_value) if path_value else settings.jobs_dir / job["id"] / "guest.gif"
        if state == "ready" and path.exists():
            return FileResponse(
                path,
                media_type="image/gif",
                filename=None if inline else "terabooth.gif",
                content_disposition_type="inline" if inline else "attachment",
                headers={"Cache-Control": "no-store"},
            )
        raise HTTPException(404, "animated GIF unavailable")

    @app.get("/d/{token}/manifest.json")
    async def delivery_manifest(token: str) -> JSONResponse:
        _, job = require_delivery(token)
        persist_guest_manifest(job, settings)
        return JSONResponse(
            guest_manifest(job, token, settings),
            headers={
                "Cache-Control": "no-store",
                "X-Content-Type-Options": "nosniff",
            },
        )

    @app.get("/d/{token}/download.zip")
    async def delivery_zip(token: str) -> FileResponse:
        _, job = require_delivery(token)
        nonlocal active_zip
        await zip_semaphore.acquire()
        active_zip += 1
        try:
            path = await asyncio.to_thread(
                _build_zip_file, job, settings
            )
        finally:
            active_zip -= 1
            zip_semaphore.release()
        return FileResponse(
            path,
            media_type="application/zip",
            filename="terabooth-photos.zip",
            background=BackgroundTask(_remove_quietly, path),
            headers={
                "Cache-Control": "no-store",
                "X-Content-Type-Options": "nosniff",
            },
        )

    @app.get("/d/{token}/branding-logo")
    async def delivery_logo(token: str) -> FileResponse:
        _, job = require_delivery(token)
        branding = json.loads(job.get("branding_json") or "{}")
        path = Path(str(branding.get("logo_path") or ""))
        if not path.exists() or not path.is_file():
            raise HTTPException(404, "not found")
        return FileResponse(path, media_type=_mime_for(path), filename="event-logo")

    @app.get("/d/{token}/qr.png")
    async def delivery_qr(token: str, request: Request) -> Response:
        require_delivery(token)
        url = f"{base_url(request, settings)}/d/{token}"
        qr = qrcode.QRCode(box_size=8, border=2)
        qr.add_data(url)
        qr.make(fit=True)
        img = qr.make_image(fill_color="black", back_color="white").convert("RGB")
        buf = io.BytesIO()
        img.save(buf, "PNG")
        return Response(buf.getvalue(), media_type="image/png")

    return app


app = create_app()
