# MK912 report descriptor notes

This document records descriptors discovered from the actual keyboard. Do not infer values from the VID/PID or from related devices.

## Candidate interfaces

| Interface/path | Usage page | Usage | Collection | Input size | Output size | Feature size | Descriptor SHA-256 | Assessment |
|---|---:|---:|---|---:|---:|---:|---|---|
| Interface 2 / `DevSrvsID:4294995700` | `0x0001` | `0x0000` | Generic data | 64 | 64 | 0 | `73867a68eef832176527175d6277108de35cb5ecfa6e8638966d2fb1306bd0b5` | Active configuration-channel hypothesis; opened successfully |
| Interface 0 / `DevSrvsID:4294995706` | `0xFF00` | `0x0000` | Vendor-defined, shared composite interface | descriptor contains multiple collections | descriptor contains multiple collections | none observed | `4dcb3bc4e1909cc34b009dbb0177f27d2443993cc2a693b2571788b528115e67` | Openable with patched non-seizing HIDAPI; not the active target |
| Interface 1 / `DevSrvsID:4294995702` | `0x0001` | `0x0006` | Keyboard | unknown | unknown | unknown | pending | Normal keyboard input; do not write |

## Interface 2 descriptor

Source command:

```bash
hidapitester --open-path 'DevSrvsID:4294995700' --get-report-descriptor
```

Initial result with upstream HIDAPI:

```text
05 01 09 00 A1 01 15 00 26 FF 00 19 00 29 08 95 40 75 08 81 02 19 01 29 08 95 40 75 08 91 02 C0
```

Parsed observations:

- One application collection.
- USB interface number: `2`.
- Registry path: `DevSrvsID:4294995700`.
- Usage page: `0x0001` (Generic Desktop).
- Usage: `0x0000`.
- Input report ID: none; implicit report ID `0`.
- Output report ID: none; implicit report ID `0`.
- Feature reports: none described; maximum feature report size `0` bytes.
- Maximum input report size: `64` bytes.
- Maximum output report size: `64` bytes.
- Logical range: `0x00` through `0xFF`.
- The descriptor uses Generic Desktop usage page `0x0001`, usage `0x0000`.
- Descriptor SHA-256: `73867a68eef832176527175d6277108de35cb5ecfa6e8638966d2fb1306bd0b5`.

## Interface 0 opening attempt

Source command:

```bash
hidapitester --vidpid 5566:0008 --usagePage FF00 --open --get-report-descriptor
```

Result:

```text
Error: hid_open_path: failed to open IOHIDDevice from mach entry: (0xE00002C1) (iokit/common) privilege violation
```

The initial `0xE00002C1` result was produced by upstream HIDAPI's default macOS seize behavior. After applying `tools/patches/hidapi-macos-nonseize.patch`, the same read-only descriptor request opened successfully and returned the complete shared descriptor in `descriptors/interface-0-shared-report-descriptor.txt`.

This remains documented as a macOS/HIDAPI access limitation for the unpatched toolchain, but it is not the current project blocker and is not evidence that the vendor-defined collection is required for RGB control. Interface 2 remains the active investigation target.

## Native diagnostic comparison

The first native `atomctl info` run found three collections and included the interface-2 candidate, but did not return the vendor-defined `0xFF00` collection. The complete output is preserved in `native-atomctl-info.txt`. Until Windows traffic identifies the endpoint, keep hidapitester as the discovery authority and treat the native enumeration as a diagnostic transport foundation.

## Permission recheck

After macOS keystroke/Input Monitoring access was granted, the enumeration was repeated on 2026-08-07. The unpatched open attempt produced `0xE00002C1`. With the local non-seizing build, a non-root read-only control run opened the collection and retrieved the descriptor. A single non-interactive root diagnostic was also attempted, but `sudo` could not execute because a password was required. The I/O Registry confirms one USB device with the expected Fantech/ZXWMicroChip identity.

## Open-mode confirmation

- Upstream HIDAPI declares `device_open_options = 0`, but its `hid_init()` compatibility path changes it to `kIOHIDOptionsTypeSeizeDevice`.
- The SDK defines `kIOHIDOptionsTypeNone = 0x00` and `kIOHIDOptionsTypeSeizeDevice = 0x01`.
- The local research build applies `tools/patches/hidapi-macos-nonseize.patch`.
- The patched backend initializes non-exclusive mode and calls `IOHIDDeviceOpen(dev->device_handle, kIOHIDOptionsTypeNone)` directly.
- No project source currently calls `IOHIDDeviceOpen` directly.
- The project will use `kIOHIDOptionsTypeNone` explicitly in any future native transport implementation and will never seize the keyboard.

## Evidence

- Enumeration source:
- Descriptor files: `descriptors/interface-2-report-descriptor.txt`, `descriptors/interface-0-shared-report-descriptor.txt`
- Reconnect behavior: pending
- Selected configuration interface: provisional — interface 2
- Reason for selection: it exposes 64-byte input/output reports and was successfully opened by hidapitester; this is not yet protocol proof.
