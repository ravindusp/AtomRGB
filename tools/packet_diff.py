#!/usr/bin/env python3
"""Compare normalized HID payloads and classify constant/varying byte offsets.

Accepted input formats:
  - a text file containing one whitespace-separated hex payload
  - a JSON list of byte values
  - a JSON object containing a `bytes`, `payload`, or `data` list/string

This tool intentionally compares captured payloads only. It does not open HID
devices or send reports.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


HEX_BYTE = re.compile(r"^(?:0x)?([0-9a-fA-F]{2})$")


def parse_value(value: Any, source: Path) -> bytes:
    if isinstance(value, list):
        parsed = []
        for item in value:
            try:
                if isinstance(item, str):
                    match = HEX_BYTE.match(item)
                    if match:
                        item = int(match.group(1), 16)
                    else:
                        item = int(item, 0)
                item = int(item)
            except (TypeError, ValueError) as exc:
                raise ValueError(f"{source}: JSON byte list contains an invalid value") from exc
            if not 0 <= item <= 255:
                raise ValueError(f"{source}: JSON byte list contains a value outside 0..255")
            parsed.append(item)
        if not parsed:
            raise ValueError(f"{source}: payload is empty")
        return bytes(parsed)

    if isinstance(value, str):
        tokens = value.replace(",", " ").split()
        parsed = []
        for token in tokens:
            match = HEX_BYTE.match(token)
            if not match:
                raise ValueError(f"{source}: invalid hex byte {token!r}")
            parsed.append(int(match.group(1), 16))
        if not parsed:
            raise ValueError(f"{source}: payload is empty")
        return bytes(parsed)

    raise ValueError(f"{source}: expected a byte list or hex string")


def load_payload(path: Path) -> bytes:
    text = path.read_text(encoding="utf-8").strip()
    if not text:
        raise ValueError(f"{path}: file is empty")

    try:
        document = json.loads(text)
    except json.JSONDecodeError:
        # Text format: take the longest line made entirely of byte tokens.
        candidates = []
        for line in text.splitlines():
            tokens = line.split("#", 1)[0].strip().replace(",", " ").split()
            if tokens and all(HEX_BYTE.match(token) for token in tokens):
                candidates.append(tokens)
        if not candidates:
            raise ValueError(f"{path}: expected a hex payload line or JSON byte payload")
        return parse_value(" ".join(max(candidates, key=len)), path)

    if isinstance(document, dict):
        for key in ("bytes", "payload", "data"):
            if key in document:
                document = document[key]
                break
        else:
            raise ValueError(f"{path}: JSON object must contain bytes, payload, or data")

    return parse_value(document, path)


def format_byte(value: int | None) -> str:
    return "--" if value is None else f"{value:02X}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "payloads",
        type=Path,
        nargs="+",
        help="two or more baseline/comparison payload files",
    )
    parser.add_argument(
        "--show",
        choices=("all", "constant", "varying"),
        default="all",
        help="which offsets to print (default: all)",
    )
    args = parser.parse_args()

    if len(args.payloads) < 2:
        parser.error("at least two payload files are required")

    try:
        payloads = [load_payload(path) for path in args.payloads]
    except (OSError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    width = max(len(payload) for payload in payloads)
    classifications = []
    for offset in range(width):
        values = tuple(payload[offset] if offset < len(payload) else None for payload in payloads)
        present_values = {value for value in values if value is not None}
        is_constant = len(present_values) == 1 and all(value is not None for value in values)
        classifications.append((offset, is_constant, values))

    constant_count = sum(1 for _, is_constant, _ in classifications if is_constant)
    varying_count = len(classifications) - constant_count
    print(f"payloads:     {len(payloads)}")
    print("lengths:      " + ", ".join(str(len(payload)) for payload in payloads))
    print(f"constant:     {constant_count} offsets")
    print(f"varying:      {varying_count} offsets")

    print("\nOffset  Class     Values")
    print("------  --------  " + "  ".join(path.name for path in args.payloads))
    for offset, is_constant, values in classifications:
        classification = "constant" if is_constant else "varying"
        if args.show != "all" and args.show != classification:
            continue
        formatted_values = "  ".join(format_byte(value) for value in values)
        print(f"0x{offset:04X}  {classification:<8}  {formatted_values}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
