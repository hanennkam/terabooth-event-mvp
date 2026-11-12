from __future__ import annotations

import errno
import os
import socket
import sys
from pathlib import Path


class InstanceLockError(RuntimeError):
    pass


class PortInUseError(RuntimeError):
    pass


class InstanceLock:
    """Portable single-instance guard using an OS file lock.

    The lock is released automatically if the process exits unexpectedly. The
    lock file may remain on disk; that is harmless.
    """

    def __init__(self, path: Path):
        self.path = path
        self._fd: int | None = None

    def acquire(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(str(self.path), os.O_CREAT | os.O_RDWR, 0o600)
        try:
            if sys.platform.startswith("win"):
                import msvcrt

                os.lseek(fd, 0, os.SEEK_SET)
                if os.fstat(fd).st_size == 0:
                    os.write(fd, b"\0")
                os.lseek(fd, 0, os.SEEK_SET)
                msvcrt.locking(fd, msvcrt.LK_NBLCK, 1)
            else:
                import fcntl

                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            os.ftruncate(fd, 0)
            os.write(fd, f"{os.getpid()}\n".encode("ascii"))
            os.fsync(fd)
            self._fd = fd
        except OSError as exc:
            os.close(fd)
            if exc.errno in {errno.EACCES, errno.EAGAIN, errno.EDEADLK}:
                raise InstanceLockError(
                    f"another Terabooth Bridge instance is already running ({self.path})"
                ) from exc
            raise InstanceLockError(f"could not acquire instance lock: {exc}") from exc

    def release(self) -> None:
        if self._fd is None:
            return
        fd = self._fd
        self._fd = None
        try:
            if sys.platform.startswith("win"):
                import msvcrt

                os.lseek(fd, 0, os.SEEK_SET)
                try:
                    msvcrt.locking(fd, msvcrt.LK_UNLCK, 1)
                except OSError:
                    pass
            else:
                import fcntl

                try:
                    fcntl.flock(fd, fcntl.LOCK_UN)
                except OSError:
                    pass
        finally:
            os.close(fd)


def ensure_port_available(host: str, port: int) -> None:
    """Fail early with a clear message if the configured port cannot bind."""
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        probe.bind((host, port))
    except OSError as exc:
        raise PortInUseError(f"cannot bind {host}:{port}: {exc}") from exc
    finally:
        probe.close()
