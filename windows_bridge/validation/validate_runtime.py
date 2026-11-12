"""Runtime-only import and filesystem smoke checks. No bridge/startup."""
from __future__ import annotations
import os
import sqlite3
import tempfile
from pathlib import Path

with tempfile.TemporaryDirectory(prefix="terabooth-runtime-") as raw:
    root = Path(raw) / "unicode path café 照片"
    root.mkdir()
    import fastapi, uvicorn, PIL
    from PIL import Image
    import qrcode
    assert fastapi.__version__ and uvicorn.__version__
    image = Image.new("RGB", (64, 64), "white")
    try:
        image_path = root / "café 照片.jpg"
        image.save(image_path, "JPEG")
    finally:
        image.close()
    with Image.open(image_path) as opened:
        assert opened.size == (64, 64)
    qr = qrcode.make("http://192.168.8.50:8787/d/test")
    try:
        qr_path = root / "qr.png"
        qr.save(qr_path)
        assert qr_path.stat().st_size > 0
    finally:
        qr.close()
    db_path = root / "bridge.db"
    connection = sqlite3.connect(db_path)
    cursor = connection.cursor()
    try:
        cursor.execute("PRAGMA journal_mode=WAL")
        cursor.execute("CREATE TABLE IF NOT EXISTS smoke (id INTEGER)")
        cursor.execute("INSERT INTO smoke VALUES (1)")
        connection.commit()
        assert (root / "bridge.db-wal").exists() or (root / "bridge.db-shm").exists()
    finally:
        # sqlite3.connect(...) as a context manager commits/rolls back but does
        # NOT close the underlying handle. Explicit close is required so
        # TemporaryDirectory can remove the SQLite files on Windows.
        cursor.close()
        connection.close()
    source = root / "a.part"
    target = root / "a.txt"
    source.write_text("atomic", encoding="utf-8")
    os.replace(source, target)
    assert target.read_text(encoding="utf-8") == "atomic"
    print("RUNTIME_PASS")
    print(f"python={os.sys.version.split()[0]}")
    print(f"pillow={PIL.__version__}")
    print(f"sqlite={sqlite3.sqlite_version}")
    print(f"unicode_atomic=ok")
