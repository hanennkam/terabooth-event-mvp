#!/usr/bin/env python3
"""Print LAN addresses and probe the bridge health endpoint from this machine."""
from __future__ import annotations

import json
import socket
import sys
import urllib.request


def ips() -> list[str]:
    out = []
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if not ip.startswith("127.") and ip not in out:
                out.append(ip)
    except Exception:
        pass
    return out


def main() -> int:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8787
    found = ips()
    print("LAN IPs:", ", ".join(found) or "(none detected)")
    for ip in found:
        url = f"http://{ip}:{port}/v1/health"
        try:
            with urllib.request.urlopen(url, timeout=3) as r:
                data = json.loads(r.read())
            print(f"OK   {url} -> {data.get('service')} / {data.get('printer', {}).get('state')}")
        except Exception as exc:
            print(f"FAIL {url} -> {exc}")
    print("Use the Windows LAN IP in the guest QR, never localhost.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
