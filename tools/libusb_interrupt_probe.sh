#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
probe_bin="${LIBUSB_PROBE_BIN:-$repo_root/tools/.cache/libusb_interrupt_probe}"

if command -v brew >/dev/null 2>&1; then
    libusb_prefix="$(brew --prefix libusb 2>/dev/null || true)"
fi
libusb_prefix="${libusb_prefix:-/opt/homebrew/opt/libusb}"

if [ ! -f "$libusb_prefix/include/libusb-1.0/libusb.h" ]; then
    echo "libusb headers were not found at $libusb_prefix." >&2
    echo "Install libusb with: brew install libusb" >&2
    exit 127
fi

mkdir -p "$(dirname "$probe_bin")"
cc -std=c11 -Wall -Wextra -O2 \
    -I"$libusb_prefix/include" \
    "$repo_root/tools/libusb_interrupt_probe.c" \
    -L"$libusb_prefix/lib" \
    -Wl,-rpath,"$libusb_prefix/lib" \
    -lusb-1.0 \
    -o "$probe_bin"

exec "$probe_bin" "$@"
