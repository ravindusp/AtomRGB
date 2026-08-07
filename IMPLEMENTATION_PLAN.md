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

Strong lead:

- A ZiFriend ZA63 Pro is publicly documented with the same `0x5566:0x0008` identity.

Unknown and requiring experiments:

- The configuration HID collection and descriptor fingerprint
- Output versus feature report usage
- Report IDs and packet lengths
- RGB field order and offsets
- Effect, brightness, speed, direction, and per-key encoding
- Volatile versus onboard persistence behavior

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

Status: in progress — local setup complete; Windows capture environment pending

Deliverables:

- Repository documentation and evidence directories
- Capture and protocol-note templates
- A safe HID enumeration wrapper
- Packet-diff tooling
- A dependency checklist

Exit criteria:

- `hidapitester` is available on macOS, or a documented build path exists.
- The keyboard is available in wired USB mode.
- A Windows capture environment with Fantech software and USBPcap is available.

Progress: the local `hidapitester` build completed successfully on Apple Silicon, and the connected keyboard has been enumerated without sending any reports.

### Phase 1 — Read-only MK912 HID fingerprint

Status: in progress — Interface 2 is the active investigation target

Actions:

1. Run `tools/enumerate_mk912.sh`.
2. Save the complete collection listing to `docs/hardware/mk912-hid-enumeration.txt`.
3. Dump the complete Interface 2 report descriptor into `docs/hardware/descriptors/`.
4. Record usage page/usage, report IDs, maximum input/output/feature sizes, registry path, and USB interface number.
5. Hash the Interface 2 descriptor and document the fingerprint.
6. Perform one read-only root diagnostic against the `0xFF00` collection and record whether it becomes openable.
7. Treat the unpatched `0xFF00` access result as documented background; do not make it a protocol-research blocker.

Exit criteria:

- Interface 2 is fully documented as the current configuration-channel hypothesis.
- The `0xFF00` access result and one root diagnostic result are recorded.
- Interface 2 can be reopened after reconnecting the keyboard.

Current findings:

- Nine HID collections are exposed by the connected keyboard.
- Interface 2 (`0x0001:0x0000`) opens successfully and exposes 64-byte input/output reports.
- Interface 0 includes a `0xFF00:0x0000` vendor-defined collection. The unpatched HIDAPI open returned `0xE00002C1`; the patched non-seizing build opens the shared descriptor read-only.
- Interface 2 is therefore the provisional configuration-interface candidate, not a confirmed protocol endpoint.

### Phase 2 — Controlled Windows traffic capture

Status: pending Windows capture environment

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

Exit criteria:

- At least one static-color capture is repeatable.
- Each transfer has a known interface, report type, report ID, and length.
- Dynamic bytes are distinguished from command fields.

### Phase 3 — First safe macOS replay

Status: not started

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

Status: not started

Keep these boundaries separate:

```text
AtomProtocol  ->  HIDTransport  ->  atomctl
```

Initial commands:

```text
atomctl list
atomctl info
atomctl static FF0000
atomctl brightness 3
atomctl off
```

Add golden packet fixtures and pure encoder tests before adding UI code.

Exit criteria:

- Arbitrary static RGB colors work.
- Brightness and off are verified.
- The exact MK912 device matcher rejects unverified `0x5566:0x0008` devices.

### Phase 5 — Effects and per-key RGB

Implement only after static RGB is stable:

1. Effect IDs
2. Speed
3. Direction
4. Per-key packet chunking
5. Empirical mapping of all 63 LEDs
6. Volatile profile application
7. Onboard save only after persistence behavior is understood

Exit criteria:

- Supported effects are documented in `docs/protocol/effects.md`.
- The complete physical-key-to-LED-index map is documented.
- Hardware integration tests can apply a known profile reliably.

### Phase 6 — SwiftUI application

Build the app on top of the proven CLI/protocol layer:

1. Device detection and connection state
2. Static color, brightness, and off
3. Effects, speed, and direction
4. Hotplug handling
5. Per-key editor
6. Local profiles and debounced live preview
7. Diagnostics export

Do not add macros, key remapping, firmware updates, wireless support, or integrations to the first release.

### Phase 7 — Release hardening

- Separate unit tests from hardware tests.
- Handle disconnects, timeouts, short writes, and rejected reports.
- Document supported descriptor fingerprints.
- Sign and notarize the macOS application.
- Package a development release before considering broader distribution.

## Milestones

| Milestone | Definition of done |
|---|---|
| M0 | HID collections and configuration descriptor fingerprint documented |
| M1 | One captured RGB packet successfully replayed from macOS |
| M2 | Arbitrary static colors, brightness, and off work |
| M3 | Effects, speed, and direction are mapped |
| M4 | All 63 per-key LEDs are mapped and controllable |
| M5 | SwiftUI app controls the proven protocol and handles hotplug |
| M6 | Diagnostics, documentation, signing, and packaging are complete |

## Immediate next actions

1. Install or build `hidapitester`.
2. Connect the MK912 in wired mode.
3. Run `tools/enumerate_mk912.sh`.
4. Save its complete output to `docs/hardware/mk912-hid-enumeration.txt`.
5. Dump and fingerprint each promising report descriptor.
6. Keep `0xFF00` documented as a non-blocking HIDAPI/macOS access issue.
7. Continue with Interface 2 and prepare the Windows capture environment before attempting any protocol write.

## Stop conditions

Pause and reassess if:

- No configuration interface can be identified.
- The official software cannot be made to communicate with the keyboard.
- Captures are not repeatable.
- A replay changes behavior unexpectedly or interrupts normal keyboard input.

The fallback order is: physical Windows capture, reliable USB-passthrough VM, then static analysis of the vendor software. Do not guess packet formats.
