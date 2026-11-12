from __future__ import annotations

import json
import sqlite3
import threading
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator

_LOCK = threading.RLock()


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def new_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex}"


def _connect(path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(str(path), timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def init_db(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with _LOCK, _connect(path) as conn:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS sessions (
              id TEXT PRIMARY KEY,
              event_id TEXT NOT NULL,
              created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS jobs (
              id TEXT PRIMARY KEY,
              session_id TEXT NOT NULL,
              event_id TEXT NOT NULL,
              idempotency_key TEXT NOT NULL UNIQUE,
              state TEXT NOT NULL,
              completion TEXT NOT NULL DEFAULT 'unknown',
              attempts INTEGER NOT NULL DEFAULT 0,
              printer TEXT,
              template TEXT,
              copies INTEGER NOT NULL DEFAULT 1,
              event_title TEXT NOT NULL DEFAULT 'TERABOOTH',
              event_date TEXT NOT NULL DEFAULT '',
              error TEXT,
              delivery_token TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              completed_at TEXT,
              reprint_of TEXT,
              template_version INTEGER NOT NULL DEFAULT 1,
              crops_json TEXT,
              branding_json TEXT,
              gif_state TEXT NOT NULL DEFAULT 'pending',
              gif_path TEXT,
              gif_error TEXT,
              gif_bytes INTEGER,
              gif_updated_at TEXT,
              gif_attempts INTEGER NOT NULL DEFAULT 0,
              FOREIGN KEY(session_id) REFERENCES sessions(id)
            );
            CREATE TABLE IF NOT EXISTS images (
              id TEXT PRIMARY KEY,
              session_id TEXT NOT NULL,
              job_id TEXT NOT NULL,
              filename TEXT NOT NULL,
              sha256 TEXT NOT NULL,
              width INTEGER NOT NULL,
              height INTEGER NOT NULL,
              path TEXT NOT NULL,
              created_at TEXT NOT NULL,
              FOREIGN KEY(job_id) REFERENCES jobs(id)
            );
            CREATE TABLE IF NOT EXISTS attempts (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              job_id TEXT NOT NULL,
              state TEXT NOT NULL,
              detail TEXT,
              created_at TEXT NOT NULL,
              FOREIGN KEY(job_id) REFERENCES jobs(id)
            );
            CREATE TABLE IF NOT EXISTS delivery_tokens (
              token_hash TEXT PRIMARY KEY,
              job_id TEXT NOT NULL,
              expires_at INTEGER NOT NULL,
              created_at TEXT NOT NULL,
              FOREIGN KEY(job_id) REFERENCES jobs(id)
            );
            CREATE INDEX IF NOT EXISTS idx_jobs_state ON jobs(state);
            CREATE INDEX IF NOT EXISTS idx_images_job ON images(job_id);
            """
        )
        cols = {r[1] for r in conn.execute("PRAGMA table_info(jobs)").fetchall()}
        if "event_title" not in cols:
            conn.execute("ALTER TABLE jobs ADD COLUMN event_title TEXT NOT NULL DEFAULT 'TERABOOTH'")
        if "event_date" not in cols:
            conn.execute("ALTER TABLE jobs ADD COLUMN event_date TEXT NOT NULL DEFAULT ''")
        if "template_version" not in cols:
            conn.execute("ALTER TABLE jobs ADD COLUMN template_version INTEGER NOT NULL DEFAULT 1")
        if "crops_json" not in cols:
            conn.execute("ALTER TABLE jobs ADD COLUMN crops_json TEXT")
        if "branding_json" not in cols:
            conn.execute("ALTER TABLE jobs ADD COLUMN branding_json TEXT")
        if "gif_state" not in cols:
            conn.execute("ALTER TABLE jobs ADD COLUMN gif_state TEXT NOT NULL DEFAULT 'pending'")
        if "gif_path" not in cols:
            conn.execute("ALTER TABLE jobs ADD COLUMN gif_path TEXT")
        if "gif_error" not in cols:
            conn.execute("ALTER TABLE jobs ADD COLUMN gif_error TEXT")
        if "gif_bytes" not in cols:
            conn.execute("ALTER TABLE jobs ADD COLUMN gif_bytes INTEGER")
        if "gif_updated_at" not in cols:
            conn.execute("ALTER TABLE jobs ADD COLUMN gif_updated_at TEXT")
        if "gif_attempts" not in cols:
            conn.execute("ALTER TABLE jobs ADD COLUMN gif_attempts INTEGER NOT NULL DEFAULT 0")
        if "print_now" not in cols:
            conn.execute("ALTER TABLE jobs ADD COLUMN print_now INTEGER NOT NULL DEFAULT 1")


@contextmanager
def db(path: Path) -> Iterator[sqlite3.Connection]:
    with _LOCK:
        conn = _connect(path)
        try:
            yield conn
            conn.commit()
        finally:
            conn.close()


def row(r: sqlite3.Row | None) -> dict[str, Any] | None:
    return dict(r) if r is not None else None


def create_session(path: Path, event_id: str) -> dict[str, Any]:
    sid = new_id("ses")
    with db(path) as conn:
        conn.execute(
            "INSERT INTO sessions(id,event_id,created_at) VALUES(?,?,?)",
            (sid, event_id, now_iso()),
        )
    return {"id": sid, "event_id": event_id}


def create_job(path: Path, *, session_id: str, event_id: str, idempotency_key: str,
               template: str, copies: int, delivery_token: str, reprint_of: str | None,
               print_now: bool = True,
               job_id: str | None = None, event_title: str = "TERABOOTH",
               event_date: str = "", template_version: int = 1,
               crops_json: str | None = None, branding_json: str | None = None) -> dict[str, Any]:
    jid = job_id or new_id("job")
    ts = now_iso()
    with db(path) as conn:
        conn.execute(
            """INSERT INTO jobs(id,session_id,event_id,idempotency_key,state,completion,
               attempts,printer,template,copies,event_title,event_date,error,delivery_token,created_at,updated_at,reprint_of,template_version,crops_json,branding_json,print_now)
               VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (jid, session_id, event_id, idempotency_key, "received", "unknown",
             0, None, template, copies, event_title, event_date, None, delivery_token, ts, ts, reprint_of,
             template_version, crops_json, branding_json, 1 if print_now else 0),
        )
    return get_job(path, jid)  # type: ignore[return-value]


def get_job(path: Path, job_id: str) -> dict[str, Any] | None:
    with db(path) as conn:
        j = conn.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone()
        if j is None:
            return None
        out = dict(j)
        out["images"] = [dict(r) for r in conn.execute(
            "SELECT * FROM images WHERE job_id=? ORDER BY created_at", (job_id,))]
    return out


def get_job_by_key(path: Path, key: str) -> dict[str, Any] | None:
    with db(path) as conn:
        j = conn.execute("SELECT id FROM jobs WHERE idempotency_key=?", (key,)).fetchone()
    return get_job(path, j["id"]) if j else None


def update_job(path: Path, job_id: str, **fields: Any) -> dict[str, Any] | None:
    allowed = {"state", "completion", "attempts", "printer", "error", "completed_at", "delivery_token"}
    sets = {k: v for k, v in fields.items() if k in allowed}
    if not sets:
        return get_job(path, job_id)
    sets["updated_at"] = now_iso()
    cols = ", ".join(f"{k}=?" for k in sets)
    with db(path) as conn:
        conn.execute(f"UPDATE jobs SET {cols} WHERE id=?", (*sets.values(), job_id))
    return get_job(path, job_id)


def claim_gif(path: Path, job_id: str) -> bool:
    """Atomically claim a pending GIF. Only one generator can proceed."""
    with db(path) as conn:
        cur = conn.execute(
            "UPDATE jobs SET gif_state='processing', gif_updated_at=?, "
            "gif_attempts=gif_attempts+1 "
            "WHERE id=? AND gif_state='pending' AND gif_attempts < 3",
            (now_iso(), job_id),
        )
        return cur.rowcount == 1


def reset_gif_claim(path: Path, job_id: str) -> bool:
    """Release a stale processing claim after a bridge restart."""
    with db(path) as conn:
        cur = conn.execute(
            "UPDATE jobs SET gif_state='pending', gif_error=NULL, gif_updated_at=? "
            "WHERE id=? AND gif_state='processing'",
            (now_iso(), job_id),
        )
        return cur.rowcount == 1


def gif_jobs(path: Path) -> list[dict[str, Any]]:
    with db(path) as conn:
        jobs = [dict(r) for r in conn.execute(
            "SELECT * FROM jobs WHERE gif_state IN ('pending','processing','ready') "
            "ORDER BY created_at"
        )]
        for job in jobs:
            job["images"] = [dict(r) for r in conn.execute(
                "SELECT * FROM images WHERE job_id=? ORDER BY created_at", (job["id"],))]
    return jobs


def add_gif_attempt(path: Path, job_id: str, detail: str) -> None:
    add_attempt(path, job_id, "gif_recovery", detail)


def update_gif(path: Path, job_id: str, *, state: str, gif_path: str | None = None,
               error: str | None = None, gif_bytes: int | None = None) -> None:
    with db(path) as conn:
        conn.execute(
            "UPDATE jobs SET gif_state=?, gif_path=?, gif_error=?, gif_bytes=?, gif_updated_at=? WHERE id=?",
            (state, gif_path, error, gif_bytes, now_iso(), job_id),
        )


def add_attempt(path: Path, job_id: str, state: str, detail: str | None = None) -> None:
    with db(path) as conn:
        conn.execute(
            "INSERT INTO attempts(job_id,state,detail,created_at) VALUES(?,?,?,?)",
            (job_id, state, detail, now_iso()),
        )


def add_image(path: Path, *, job_id: str, session_id: str, image_id: str, filename: str,
              sha256: str, width: int, height: int, file_path: str) -> None:
    with db(path) as conn:
        conn.execute(
            """INSERT INTO images(id,session_id,job_id,filename,sha256,width,height,path,created_at)
               VALUES(?,?,?,?,?,?,?,?,?)""",
            (image_id, session_id, job_id, filename, sha256, width, height, file_path, now_iso()),
        )


def get_image(path: Path, image_id: str) -> dict[str, Any] | None:
    with db(path) as conn:
        r = conn.execute("SELECT * FROM images WHERE id=?", (image_id,)).fetchone()
    return dict(r) if r else None


def add_delivery(path: Path, token: str, job_id: str, expires_at: int) -> None:
    from .security import token_hash
    with db(path) as conn:
        conn.execute(
            "INSERT OR REPLACE INTO delivery_tokens(token_hash,job_id,expires_at,created_at) VALUES(?,?,?,?)",
            (token_hash(token), job_id, expires_at, now_iso()),
        )


def delete_delivery(path: Path, token: str) -> None:
    from .security import token_hash
    with db(path) as conn:
        conn.execute("DELETE FROM delivery_tokens WHERE token_hash=?", (token_hash(token),))


def delete_delivery_for_job(path: Path, job_id: str) -> None:
    with db(path) as conn:
        conn.execute("DELETE FROM delivery_tokens WHERE job_id=?", (job_id,))


def get_delivery(path: Path, token: str) -> dict[str, Any] | None:
    from .security import token_hash
    with db(path) as conn:
        r = conn.execute(
            "SELECT d.*, j.event_id, j.session_id FROM delivery_tokens d JOIN jobs j ON j.id=d.job_id WHERE d.token_hash=?",
            (token_hash(token),),
        ).fetchone()
    return dict(r) if r else None


def jobs_in_states(path: Path, states: set[str], limit: int = 500) -> list[dict[str, Any]]:
    placeholders = ",".join("?" for _ in states)
    with db(path) as conn:
        rows = conn.execute(
            f"SELECT * FROM jobs WHERE state IN ({placeholders}) ORDER BY created_at LIMIT ?",
            (*sorted(states), limit),
        ).fetchall()
        out = []
        for row in rows:
            job = dict(row)
            job["images"] = [dict(r) for r in conn.execute(
                "SELECT * FROM images WHERE job_id=? ORDER BY created_at", (job["id"],)
            )]
            out.append(job)
    return out


def list_jobs(path: Path, limit: int = 50) -> list[dict[str, Any]]:
    with db(path) as conn:
        rows = conn.execute("SELECT * FROM jobs ORDER BY created_at DESC LIMIT ?", (limit,)).fetchall()
    return [dict(r) for r in rows]
