"""Runtime-only import and filesystem smoke checks. No bridge/startup."""
from __future__ import annotations
import os, sqlite3, tempfile, time
from pathlib import Path

with tempfile.TemporaryDirectory(prefix="terabooth-runtime-") as raw:
    root = Path(raw) / "unicode path café 照片"
    root.mkdir()
    import fastapi, uvicorn, PIL
    from PIL import Image
    import qrcode
    assert fastapi.__version__ and uvicorn.__version__
    image = Image.new("RGB", (64, 64), "white")
    image_path = root / "café 照片.jpg"
    image.save(image_path, "JPEG")
    with Image.open(image_path) as opened:
        assert opened.size == (64, 64)
    qr = qrcode.make("http://192.168.8.50:8787/d/test")
    qr_path = root / "qr.png"
    qr.save(qr_path)
    assert qr_path.stat().st_size > 0
    db_path = root / "bridge.db"
    with sqlite3.connect(db_path) as conn:
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("CREATE TABLE IF NOT EXISTS smoke (id INTEGER)")
        conn.execute("INSERT INTO smoke VALUES (1)")
        conn.commit()
    assert (root / "bridge.db-wal").exists() or (root / "bridge.db-shm").exists()
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
