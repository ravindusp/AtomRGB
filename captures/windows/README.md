# Windows USBPcap + Wireshark capture workflow

## Status

The global RGB capture analysis is complete and recorded in `docs/protocol/protocol-notes.md`. The Windows utility addresses USB Interface 2 using 64-byte HID input/output reports, OUT endpoint `0x05`, IN endpoint `0x85`, and no HID Report ID. The original `.pcapng` files are not currently stored in this repository.

For the complete installation and capture procedure, read [the detailed Windows capture guide](../../docs/research/windows-capture-guide.md).

This workflow captures only normal RGB configuration traffic from the official Fantech MK912 Windows utility. Do not capture or replay firmware-update traffic.

## Environment

Preferred:

- Physical Windows machine
- MK912 connected in wired USB mode
- Official Fantech ATOM PRO63 MK912 utility
- Wireshark with USBPcap installed

A USB-passthrough VM is a fallback only if the physical Windows machine is unavailable or unsuitable.

## Before capturing

1. Close other keyboard configuration utilities.
2. Connect only the target MK912 if possible.
3. Record the Windows version, Fantech utility version, keyboard serial, and USBPcap capture interface.
4. Start from a known baseline setting.
5. Change exactly one setting per capture.
6. Save the original `.pcapng` file under `captures/windows/raw/` and keep it private unless redistribution is permitted.

In Wireshark, begin by filtering for the device VID/PID if those USB fields are available:

```text
usb.idVendor == 0x5566 && usb.idProduct == 0x0008
```

Then inspect control transfers and interrupt transfers. Record the USB interface, endpoint, direction, report ID, payload length, and payload bytes for every candidate transfer. Pay special attention to transfers addressed to USB Interface 2.

## Capture procedure

For each action:

1. Start a new USBPcap capture on the bus containing the MK912.
2. Launch the Fantech utility only when the action is an initialization capture.
3. Perform one isolated UI change.
4. Wait for the utility to finish applying the change.
5. Stop the capture immediately.
6. Save the capture with the canonical name below.
7. Add a note in `captures/windows/notes/` describing the baseline, exact UI action, selected values, timestamp, and whether the utility displayed an Apply/Save action.
8. Export candidate HID payloads into `captures/windows/exports/` as one hex line or JSON byte payload per file.
9. Record the SHA-256 of the original capture and exported payload.

## Required isolated captures

| Capture | Exact action |
|---|---|
| `01-app-launch.pcapng` | Launch utility and allow device detection; change nothing |
| `10-static-red.pcapng` | Set static color to `FF0000` |
| `11-static-green.pcapng` | Set static color to `00FF00` |
| `12-static-blue.pcapng` | Set static color to `0000FF` |
| `20-brightness-low.pcapng` | Change brightness to the lowest available level |
| `21-brightness-high.pcapng` | Change brightness to the highest available level |
| `30-speed-slow.pcapng` | Change speed to the slowest available level in one effect |
| `31-speed-fast.pcapng` | Change speed to the fastest available level in the same effect |
| `40-effect-breathing.pcapng` | Select breathing only |
| `41-effect-wave.pcapng` | Select wave or the closest directional effect available |
| `42-effect-rainbow.pcapng` | Select rainbow or the closest color-cycling effect available |

If the utility requires Apply, capture Apply separately from the setting change. Do not combine color, brightness, speed, and effect changes in one capture.

## Interface identification

For each candidate transfer, record:

- USB interface number
- Endpoint number and direction
- HID report type: input, output, or feature/control transfer
- Report ID, including implicit ID `0` if no ID is present
- Report length and raw payload
- Whether the transfer occurs before or after the UI change

The first protocol conclusion must state which interface the Fantech utility addresses. This has been confirmed as Interface 2; future captures should only extend coverage or preserve raw evidence.

## Capture index

| File | Baseline | Action | Interface | Endpoint | Payload export | Notes |
|---|---|---|---:|---|---|---|
| Report-only analysis | global RGB actions | 2 | `0x05` OUT / `0x85` IN | not archived | `docs/protocol/protocol-notes.md` |
