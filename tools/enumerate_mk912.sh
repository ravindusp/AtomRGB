#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hidapitester_bin="${HIDAPITESTER_BIN:-$repo_root/tools/.cache/hidapitester/hidapitester}"

if command -v hidapitester >/dev/null 2>&1; then
  hidapitester_bin="$(command -v hidapitester)"
fi

if [ ! -x "$hidapitester_bin" ]; then
  echo "hidapitester is not installed or is not on PATH." >&2
  echo "Run tools/build_hidapitester.sh, or install/build it from https://github.com/todbot/hidapitester." >&2
  exit 127
fi

echo "MK912 read-only HID enumeration"
echo "VID=0x5566 PID=0x0008"
echo
"$hidapitester_bin" --vidpid 5566:0008 --list-detail

echo
echo "For each candidate configuration path, inspect its descriptor with:"
echo "hidapitester --open-path '<PATH>' --get-report-descriptor"
echo
echo "No output or feature reports were sent by this script."
