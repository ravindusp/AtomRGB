#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hidapitester_bin="${HIDAPITESTER_BIN:-$repo_root/tools/.cache/hidapitester/hidapitester}"

if command -v hidapitester >/dev/null 2>&1; then
  hidapitester_bin="$(command -v hidapitester)"
fi

if [ ! -x "$hidapitester_bin" ]; then
  echo "hidapitester is not installed or is not on PATH." >&2
  exit 127
fi

echo "Read-only root diagnostic for the MK912 0xFF00 collection"
echo "No output or feature report commands are included."
"$hidapitester_bin" --vidpid 5566:0008 --usagePage FF00 --open --get-report-descriptor
