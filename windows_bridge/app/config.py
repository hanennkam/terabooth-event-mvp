from __future__ import annotations

import os
import secrets
from dataclasses import dataclass
from pathlib import Path


class ConfigurationError(ValueError):
    pass


def _path(value: str | None, default: Path) -> Path:
    return Path(value).expanduser().resolve() if value else default.resolve()


def _ensure_dir(path: Path, label: str) -> None:
    try:
        path.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        raise ConfigurationError(f"{label} is not writable: {path}: {exc}") from exc


@dataclass(frozen=True)
class Settings:
    data_dir: Path
    db_path: Path
    printer_mode: str = "mock"          # mock | spooler | hotfolder
    printer_name: str = "DS-RX1"
    hot_folder: Path | None = None
    hot_folder_archive: Path | None = None
    api_token: str | None = None
    public_base_url: str | None = None
    delivery_secret: str = ""
    token_ttl_hours: int = 24
    job_timeout_seconds: float = 60.0
    max_image_bytes: int = 20 * 1024 * 1024
    max_total_bytes: int = 60 * 1024 * 1024
    max_images: int = 4
    font_path: str | None = None
    mock_delay_seconds: float = 0.0
    mock_fail: bool = False
    mock_unknown: bool = False
    retain_days: int = 7
    assets_dir: Path | None = None
    host: str = "0.0.0.0"
    port: int = 8787

    @property
    def jobs_dir(self) -> Path:
        return self.assets_dir or (self.data_dir / "jobs")

    @property
    def outbox_dir(self) -> Path:
        return self.data_dir / "outbox"


def _load_or_create_secret(data_dir: Path) -> str:
    value = os.getenv("TERABOOTH_DELIVERY_SECRET", "").strip()
    if value:
        return value
    path = data_dir / ".delivery_secret"
    try:
        if path.exists():
            existing = path.read_text(encoding="utf-8").strip()
            if existing:
                return existing
        generated = secrets.token_urlsafe(32)
        path.write_text(generated + "\n", encoding="utf-8")
        try:
            os.chmod(path, 0o600)
        except OSError:
            pass
        return generated
    except OSError as exc:
        raise ConfigurationError(f"delivery secret file is not writable: {path}: {exc}") from exc


def validate_settings(settings: Settings) -> list[str]:
    """Validate portable startup settings. Returns non-fatal warnings."""
    warnings: list[str] = []
    if settings.printer_mode not in {"mock", "spooler", "hotfolder"}:
        raise ConfigurationError(f"unknown printer mode {settings.printer_mode!r}")
    if not 1 <= settings.port <= 65535:
        raise ConfigurationError("TERABOOTH_PORT must be between 1 and 65535")
    if not settings.host.strip():
        raise ConfigurationError("TERABOOTH_HOST must not be empty")
    if settings.token_ttl_hours < 0:
        raise ConfigurationError("TERABOOTH_TOKEN_TTL_HOURS must be positive")
    if settings.max_images < 1 or settings.max_images > 4:
        raise ConfigurationError("TERABOOTH_MAX_IMAGES must be between 1 and 4")
    if settings.max_image_bytes <= 0 or settings.max_total_bytes <= 0:
        raise ConfigurationError("image size limits must be positive")
    if not settings.delivery_secret:
        raise ConfigurationError("delivery secret is empty")
    if not settings.data_dir.exists():
        _ensure_dir(settings.data_dir, "data directory")
    _ensure_dir(settings.jobs_dir, "asset directory")
    _ensure_dir(settings.outbox_dir, "outbox directory")
    _ensure_dir(settings.db_path.parent, "database directory")
    if settings.public_base_url:
        host = settings.public_base_url.split("://", 1)[-1].split("/", 1)[0].split(":", 1)[0]
        if host.lower() in {"localhost", "127.0.0.1", "::1"}:
            raise ConfigurationError("TERABOOTH_PUBLIC_BASE_URL must be a LAN address")
    if settings.printer_mode in {"spooler", "hotfolder"}:
        warnings.append("printer mode is configured but physical DNP output is unverified")
    if settings.api_token is None:
        warnings.append("TERABOOTH_API_TOKEN is empty; operator API is unauthenticated")
    return warnings


def load_settings() -> Settings:
    data_dir = _path(os.getenv("TERABOOTH_DATA_DIR"), Path("data"))
    _ensure_dir(data_dir, "data directory")
    assets_raw = os.getenv("TERABOOTH_ASSETS_DIR")
    assets_dir = _path(assets_raw, data_dir / "jobs") if assets_raw else None
    _ensure_dir(assets_dir or (data_dir / "jobs"), "asset directory")
    _ensure_dir(data_dir / "outbox", "outbox directory")
    hot = os.getenv("TERABOOTH_HOT_FOLDER")
    archive = os.getenv("TERABOOTH_HOT_FOLDER_ARCHIVE")
    settings = Settings(
        data_dir=data_dir,
        db_path=_path(os.getenv("TERABOOTH_DB_PATH"), data_dir / "terabooth.db"),
        printer_mode=os.getenv("TERABOOTH_PRINTER", "mock").lower(),
        printer_name=os.getenv("TERABOOTH_PRINTER_NAME", "DS-RX1"),
        hot_folder=_path(hot, Path(hot)) if hot else None,
        hot_folder_archive=_path(archive, Path(archive)) if archive else None,
        api_token=os.getenv("TERABOOTH_API_TOKEN") or None,
        public_base_url=os.getenv("TERABOOTH_PUBLIC_BASE_URL") or None,
        delivery_secret=_load_or_create_secret(data_dir),
        token_ttl_hours=int(os.getenv("TERABOOTH_TOKEN_TTL_HOURS", "24")),
        job_timeout_seconds=float(os.getenv("TERABOOTH_JOB_TIMEOUT_SECONDS", "60")),
        max_image_bytes=int(os.getenv("TERABOOTH_MAX_IMAGE_BYTES", str(20 * 1024 * 1024))),
        max_total_bytes=int(os.getenv("TERABOOTH_MAX_TOTAL_BYTES", str(60 * 1024 * 1024))),
        max_images=int(os.getenv("TERABOOTH_MAX_IMAGES", "4")),
        font_path=os.getenv("TERABOOTH_FONT") or None,
        mock_delay_seconds=float(os.getenv("TERABOOTH_MOCK_DELAY", "0")),
        mock_fail=os.getenv("TERABOOTH_MOCK_FAIL", "0") == "1",
        mock_unknown=os.getenv("TERABOOTH_MOCK_UNKNOWN", "0") == "1",
        retain_days=int(os.getenv("TERABOOTH_RETAIN_DAYS", "7")),
        assets_dir=assets_dir,
        host=os.getenv("TERABOOTH_HOST", "0.0.0.0"),
        port=int(os.getenv("TERABOOTH_PORT", "8787")),
    )
    validate_settings(settings)
    return settings
