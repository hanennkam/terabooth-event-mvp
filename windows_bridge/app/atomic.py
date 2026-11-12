from __future__ import annotations

import os
import time
from pathlib import Path


def replace_with_retry(
    source: Path,
    target: Path,
    *,
    attempts: int = 6,
    delay_seconds: float = 0.05,
) -> None:
    """Replace a file atomically with a short retry window.

    Windows can transiently reject os.replace while an antivirus/indexer has the
    destination open. Retrying is safe because the target is only replaced once.
    """
    last: OSError | None = None
    for attempt in range(max(1, attempts)):
        try:
            os.replace(source, target)
            return
        except OSError as exc:
            last = exc
            if attempt + 1 >= attempts:
                break
            time.sleep(delay_seconds)
    if last is not None:
        raise last
