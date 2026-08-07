# AtomRGB Implementation Plan

## Objective

Build a native macOS utility that controls the RGB lighting of the Fantech ATOM PRO63 MK912 in wired USB mode, without relying on the Windows-only Fantech configuration software.

The research baseline is documented in [Fantech_MK912_macOS_RGB_Reverse_Engineering_Plan.md](Fantech_MK912_macOS_RGB_Reverse_Engineering_Plan.md).

## Current evidence

Confirmed:

- Product: Fantech ATOM PRO63 MK912
- Product string: `Fantech Atom Pro Keyboard`
- Manufacturer: `ZXWMicroChip`
- VID: `0x5566`
- PID: `0x0008`
- Wired USB mode is the initial scope

Confirmed by the supplied Windows USBPcap analysis:

- RGB traffic uses USB Interface 2 / `ZXWCustom`.
- OUT endpoint `0x05`, IN endpoint `0x85`.
- HID input/output reports are exactly 64 bytes with no Report ID.
- Host marker is `0x55`; device marker is `0xAA`.
- Checksum is the sum of bytes `4...63` modulo 256, stored at byte `3`.
- Lighting edits use `0x01 -> 0x05 -> 0x06 -> 0x02`.
- Effect, brightness, speed, direction, Colorful, and RGB offsets are documented in `docs/protocol/protocol-notes.md`.

Still intentionally unknown:

- Semantic names for commands `0x01` and `0x02`.
- Meanings of bytes `20...26`.
- Startup command families `0x07` and `0x08`.
- Key remapping, macro, visualizer, firmware, and per-key RGB protocols.

## Safety rules

- Perform read-only HID enumeration before any writes.
- Never send invented report payloads.
- Replay only an exact packet captured from the official configuration software.
- Do not inspect or replay firmware-updater traffic during RGB research.
- Start with one transaction and observe the result before repeating it.
- Use wired mode until the wired protocol is stable.
- Do not identify a production device using VID/PID alone.
- Treat the upstream HIDAPI `0xFF00` `kIOReturnNotPrivileged` result as a documented non-seizing/access limitation, not a blocker.
- Every `IOHIDDeviceOpen` call must use `kIOHIDOptionsTypeNone`; never use `kIOHIDOptionsTypeSeizeDevice`.
- Do not send output or feature reports until a Windows command is understood.

## Execution phases

### Phase 0 — Workspace and lab setup

Status: complete for global RGB research; original raw Windows PCAP files are not stored in the repository

Deliverables:

- Repository documentation and evidence directories
- Capture and protocol-note templates
- A safe HID enumeration wrapper
- Packet-diff tooling
- A dependency checklist

Exit criteria:

- `hidapitester` is available on macOS, or a documented build path exists.
- The keyboard is available in wired USB mode.
- A Windows capture environment with Fantech software and USBPcap was used; the original raw captures are not yet archived here.

Progress: the local `hidapitester` build completed successfully on Apple Silicon, and the connected keyboard has been enumerated without sending any reports.

### Phase 1 — Read-only MK912 HID fingerprint

Status: complete — Interface 2 descriptor and macOS collection identity are documented

Actions:

1. Run `tools/enumerate_mk912.sh`.
2. Save the complete collection listing to `docs/hardware/mk912-hid-enumeration.txt`.
3. Dump the complete Interface 2 report descriptor into `docs/hardware/descriptors/`.
4. Record usage page/usage, report IDs, maximum input/output/feature sizes, registry path, and USB interface number.
5. Hash the Interface 2 descriptor and document the fingerprint.
6. Perform one read-only root diagnostic against the `0xFF00` collection and record whether it becomes openable.
7. Treat the unpatched `0xFF00` access result as documented background; do not make it a protocol-research blocker.

Exit criteria:

- Interface 2 is fully documented as the confirmed global-RGB configuration channel.
- The `0xFF00` access result and one root diagnostic result are recorded.
- Interface 2 can be reopened after reconnecting the keyboard.

Current findings:

- Nine HID collections are exposed by the connected keyboard.
- Interface 2 (`0x0001:0x0000`) opens successfully and exposes 64-byte input/output reports.
- Interface 0 includes a `0xFF00:0x0000` vendor-defined collection. The unpatched HIDAPI open returned `0xE00002C1`; the patched non-seizing build opens the shared descriptor read-only.
- Interface 2 is the confirmed endpoint used by the Windows global-RGB traffic.

### Phase 2 — Controlled Windows traffic capture

Status: complete for global RGB MVP; report supplied, raw `.pcapng` files pending archival

Capture one variable at a time, in this order:

1. Application launch and initialization
2. Static red, green, and blue
3. Test color `123456`
4. Minimum and maximum brightness
5. One basic effect
6. One-key color change
7. Apply and save behavior separately

Store original captures privately unless redistribution is permitted. Record the software filename, source URL, date, and SHA-256 in `docs/research/vendor-software.md`.

Use the workflow in [`captures/windows/README.md`](captures/windows/README.md). Determine the addressed USB interface from the Windows transfer metadata, with special attention to Interface 2.

Exit criteria achieved in the supplied report:

- Static-color and effect captures are decoded.
- Transfers target Interface 2 with known report type, endpoints, report size, and implicit report ID 0.
- Dynamic state fields and checksum behavior are distinguished.

### Phase 3 — First safe macOS replay

Status: complete — static red replay succeeded and state was confirmed in a fresh read

Actions:

1. Normalize the known-good static-color capture.
2. Confirm that the transfer targets USB Interface 2 and determine the report mechanism.
3. Replay exactly one captured transaction from macOS.
4. Verify the keyboard changes color and remains usable for normal typing.
5. Record the result and any response in `docs/protocol/protocol-notes.md`.

Exit criteria:

> A captured RGB command changes the MK912 from macOS with no loss of normal keyboard input.

This is Milestone M1 and the primary proof-of-concept gate.

### Phase 4 — Protocol module and `atomctl`

Status: complete for the global RGB MVP

Keep these boundaries separate:

```text
AtomProtocol  ->  HIDTransport  ->  atomctl
```

Initial commands:

```text
atomctl info
atomctl state
atomctl --dry-run static FF0000
atomctl --write static FF0000
atomctl --dry-run brightness 50
atomctl --dry-run effect wave
atomctl --dry-run speed slow
atomctl --dry-run direction reverse
atomctl --dry-run colorful on
```

Add golden packet fixtures and pure encoder tests before adding UI code.

Exit criteria:

- Arbitrary static RGB colors work.
- Brightness and off are verified.
- The exact MK912 device matcher rejects unverified `0x5566:0x0008` devices.

### Phase 5 — Effects and per-key RGB

Status: global-control implementation complete; hardware coverage is the next manual verification pass

Implement and verify global effects only after the first static-color hardware proof:

1. Effect IDs
2. Speed
3. Direction
4. Colorful flag

Per-key packet chunking, the 63-LED map, profiles, and onboard save remain out of scope.

Exit criteria:

- Supported effects are documented in `docs/protocol/effects.md`.
- The complete physical-key-to-LED-index map is documented.
- Hardware integration tests can apply a known profile reliably.

### Phase 6 — SwiftUI application

Status: initial global-lighting surface implemented; polish and hardware verification remain

The initial app is built on top of the proven CLI/protocol layer:

1. Device detection and connection state
2. Static color, brightness, and off
3. Effects, speed, and direction
4. Hotplug polling and reconnect
5. Debounced live preview
6. Diagnostics export via CLI JSON

Per-key editing remains out of scope.

Do not add macros, key remapping, firmware updates, wireless support, or integrations to the first release.

### Phase 7 — Release hardening

- Separate unit tests from hardware tests.
- Handle disconnects, timeouts, short writes, and rejected reports.
- Document supported descriptor fingerprints.
- Sign and notarize the macOS application.
- The 0.1 development app bundle and DMG are now generated by `tools/build_dmg.sh`.

## Milestones

| Milestone | Definition of done |
|---|---|
| M0 | HID collections and configuration descriptor fingerprint documented |
| M1 | One captured RGB packet successfully replayed from macOS |
| M2 | Arbitrary static colors, brightness, and off work |
| M3 | Effects, speed, and direction are mapped in code and ready for hardware coverage |
| M4 | All 63 per-key LEDs are mapped and controllable |
| M5 | SwiftUI app controls the proven protocol and handles hotplug |
| M6 | Diagnostics, documentation, and development packaging are complete; notarization remains |

## Immediate next actions

1. Verify green, blue, brightness, effects, speed, direction, and Colorful on hardware.
2. Launch `swift run AtomRGBApp` and verify reconnect behavior.
3. Install a full Xcode toolchain and run the XCTest targets.
4. Archive the original Windows PCAPs if they become available.
5. Obtain distribution credentials and sign/notarize a public macOS build.

## Stop conditions

Pause and reassess if:

- No configuration interface can be identified.
- The official software cannot be made to communicate with the keyboard.
- Captures are not repeatable.
- A replay changes behavior unexpectedly or interrupts normal keyboard input.

The fallback order is: physical Windows capture, reliable USB-passthrough VM, then static analysis of the vendor software. Do not guess packet formats.
