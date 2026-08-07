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

echo "Read-only Interface 2 descriptor inspection"
echo "Selection: VID/PID 5566:0008, USB interface 2"

# hidapitester treats usage 0x0000 as an unset filter. Select the exact
# interface record from --list-detail instead of risking a keyboard match.
interface2_path="$($hidapitester_bin --vidpid 5566:0008 --list-detail | awk '
  /usagePage:/ { usage_page = $2 }
  /usage:/ { usage = $2 }
  /interface:/ { interface_number = $2 }
  /path:/ {
    if (usage_page == "0x0001" && usage == "0x0000" && interface_number == "2") {
      print $2
      exit
    }
  }
')"

if [ -z "$interface2_path" ]; then
  echo "Could not identify USB interface 2 from HID enumeration." >&2
  exit 1
fi

echo "Path: $interface2_path"
"$hidapitester_bin" --open-path "$interface2_path" --get-report-descriptor
