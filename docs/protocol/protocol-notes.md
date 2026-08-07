# MK912 protocol notes

The current global-RGB conclusions come from `ATOM_PRO_RGB_PROTOCOL_IMPLEMENTATION_GUIDE.md`, supplied after Windows USBPcap analysis of the official Fantech MK912 utility. The original `.pcapng` files are not currently present in this repository; packet fixtures and the report are the available evidence.

Only replay packets supported by the report and fixtures. Do not include firmware-updater, key-remapping, macro, or per-key traffic in the RGB MVP.

## Packet record template

```text
Action:
Source application/version:
Capture file:
Interface/path:
Report type: output | feature | input
Report ID:
Report length:
Raw bytes:
Response:
Observed keyboard behavior:
Hypothesis:
Confidence: confirmed | probable | unknown
Safety classification: RGB configuration | unknown | firmware-related (do not replay)
```

## Confirmed device and report

| Field | Value | Evidence |
|---|---|---|
| VID/PID | `0x5566:0x0008` | Windows report and macOS enumeration |
| Product/manufacturer | `Fantech Atom Pro Keyboard` / `ZXWMicroChip` | Windows report |
| Configuration interface | USB Interface `2`, `ZXWCustom` | Windows report |
| OUT/IN endpoints | `0x05` / `0x85` | Windows report |
| Report type/size | HID output/input, 64 bytes | Interface-2 descriptor and capture analysis |
| HID Report ID | none; implicit API ID `0` | Interface-2 descriptor has no `0x85` item |
| Host/device markers | `0x55` / `0xAA` | 781/781 validated frames |
| Checksum | byte `3` = sum of bytes `4...63` modulo 256 | 781/781 validated frames |

## Transaction and state layout

Every captured lighting edit used:

```text
0x01 -> 0x05 -> 0x06 -> 0x02
```

| Offset | Meaning |
|---:|---|
| 10 | Effect ID `0x01...0x16` |
| 11 | Brightness `0...100` |
| 12 | Speed `0...4`, where lower is faster |
| 13 | Direction/reverse flag `0` or `1` |
| 14 | Colorful flag `0` or `1` |
| 16 | Red |
| 17 | Green |
| 18 | Blue |

SET frames must be built from the current GET response. Preserve all unknown bytes, change only the known state fields, change the marker/command to `55 06`, and recalculate byte `3`.

## Reference fixture

Static red is a 64-byte SET frame with checksum `0x6B`. Wave Bar fixtures have checksums `0x87` at speed `0x00` and `0x88` at speed `0x01`.

## Confidence and unknowns

Confirmed: Interface 2, endpoints, report size, no report ID, framing, checksum, transaction order, global lighting offsets, RGB channel order, brightness, speed, direction flag, Colorful flag, and 22 global effects.

Unknown: semantic names for commands `0x01`/`0x02`, bytes `20...26`, startup commands `0x07`/`0x08`, key remapping, macros, music visualizer, and per-key RGB.
