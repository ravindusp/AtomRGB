# Research tools

## HID enumeration

Build the local research copy if `hidapitester` is not already installed:

```bash
tools/build_hidapitester.sh
```

The build applies `tools/patches/hidapi-macos-nonseize.patch`. This is required because upstream HIDAPI initializes its macOS compatibility mode with device seizure. The local build forces every `IOHIDDeviceOpen` call to use `kIOHIDOptionsTypeNone`.

Run:

```bash
tools/enumerate_mk912.sh
```

Inspect the active Interface 2 candidate without hardcoding its runtime registry path:

```bash
tools/inspect_interface2.sh
```

The helper derives the runtime path from the `interface: 2` enumeration record. It does not use hidapitester's usage-`0x0000` filter because that value is treated as unset by the tool.

The wrapper is read-only. It checks that `hidapitester` exists, lists every `0x5566:0x0008` collection, and prints the commands needed to inspect a specific path.

The current macOS limitation check is also read-only:

```bash
sudo tools/diagnose_vendor_collection.sh
```

This is a single descriptor-read attempt against the `0xFF00` collection. It must never be changed to send reports.

## Packet diff

Use the packet diff helper with two or more exported hex/JSON payloads:

```bash
python3 tools/packet_diff.py \
  captures/windows/exports/10-static-red.hex \
  captures/windows/exports/11-static-green.hex \
  captures/windows/exports/12-static-blue.hex
```

It classifies every offset as constant or varying across the supplied payloads.
