#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cache_root="$repo_root/tools/.cache"
hidapi_dir="$cache_root/hidapi"
tester_dir="$cache_root/hidapitester"
nonseize_patch="$repo_root/tools/patches/hidapi-macos-nonseize.patch"

mkdir -p "$cache_root"

if [ ! -d "$hidapi_dir/.git" ]; then
  git clone --depth 1 https://github.com/libusb/hidapi.git "$hidapi_dir"
fi

if [ ! -d "$tester_dir/.git" ]; then
  git clone --depth 1 https://github.com/todbot/hidapitester.git "$tester_dir"
fi

if ! rg -q 'AtomRGB: never seize HID devices' "$hidapi_dir/mac/hid.c"; then
  patch -N -p1 -d "$hidapi_dir" < "$nonseize_patch"
fi

make -C "$tester_dir" HIDAPI_DIR="$hidapi_dir"
echo "Built: $tester_dir/hidapitester"
