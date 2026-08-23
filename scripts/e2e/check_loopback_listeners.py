#!/usr/bin/env python3
"""Fail unless every requested TCP listener is present and loopback-only."""

from __future__ import annotations

import argparse
import ipaddress
from pathlib import Path


def parse_local_address(value: str) -> tuple[str, int]:
    if value.startswith("["):
        closing = value.rfind("]:")
        if closing < 0:
            raise ValueError(f"unsupported local address: {value}")
        host = value[1:closing]
        port_text = value[closing + 2 :]
    else:
        host, port_text = value.rsplit(":", 1)
    return host.split("%", 1)[0], int(port_text)


def validate_listeners(lines: list[str], required_ports: set[int]) -> list[str]:
    found: set[int] = set()
    errors: list[str] = []
    for line in lines:
        fields = line.split()
        if len(fields) < 4:
            continue
        try:
            host, port = parse_local_address(fields[3])
        except (ValueError, IndexError):
            continue
        if port not in required_ports:
            continue
        found.add(port)
        try:
            address = ipaddress.ip_address(host)
        except ValueError:
            errors.append(f"port {port} has an unparseable listener address: {host}")
            continue
        if not address.is_loopback:
            errors.append(f"port {port} is exposed on non-loopback address: {host}")
    for port in sorted(required_ports - found):
        errors.append(f"required loopback listener is missing: port {port}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--ports", type=int, nargs="+", required=True)
    args = parser.parse_args()
    errors = validate_listeners(
        args.input.read_text(encoding="utf-8").splitlines(), set(args.ports)
    )
    if errors:
        for error in errors:
            print(error)
        return 1
    print("LOOPBACK_LISTENERS=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
