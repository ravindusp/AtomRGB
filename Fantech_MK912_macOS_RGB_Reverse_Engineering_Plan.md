# Fantech ATOM PRO63 MK912 — macOS RGB Control Project

**Project goal:** Build a native macOS utility that can control the RGB lighting of the **Fantech ATOM PRO63 MK912** without needing Fantech's Windows-only configuration software.

**Current status:** Hardware identity confirmed on macOS. We have a strong lead pointing to a shared **ZXWMicroChip / 0x5566:0x0008** OEM platform used by other rebranded keyboards, especially the **ZiFriend ZA63 Pro**. The actual RGB protocol has **not yet been proven**, so the next milestone is to identify the correct HID interface and reproduce one known-safe lighting command.

**Recommended end product:** A small native **SwiftUI macOS app** backed by a clean keyboard-protocol module. Do **not** start with the GUI. First prove the protocol with a tiny CLI/test harness.

---

## 1. What We Know So Far

### 1.1 Target keyboard

- **Brand:** Fantech
- **Model:** ATOM PRO63 MK912
- **Layout:** 63-key compact mechanical keyboard
- **Connection modes:** Wired USB + wireless modes
- **RGB:** Per-key RGB / built-in effects according to Fantech product/software documentation
- **Primary scope for this project:** **Wired USB mode first**

The Windows software exists on Fantech's official downloads page, but there is no official macOS configuration utility for this model.

Official Fantech download page:

- https://fantechworld.com/pages/download-keyboard
- https://fantechworld.com/pages/download-all-filter

The page currently lists **Atom Pro63 MK912** with **Software** and **User Manual** downloads.

---

## 2. Hardware Identity Confirmed on the User's Mac

The keyboard was plugged into the Mac in wired mode and inspected in **System Information → Hardware → USB**.

Observed values:

```text
USB Service Name:    Fantech Atom Pro Keyboard
Manufacturer:        ZXWMicroChip
USB Vendor ID:       0x5566
USB Product ID:      0x0008
USB Product Version: 0x0100
Link Speed:          12 Mb/s
Power Allocated:     2.5 W (500 mA)
```

This is the most important discovery so far.

### Important identification rule

Do **not** identify the device only by `VID=0x5566` and `PID=0x0008` in production code.

There is evidence that this VID/PID combination is reused by multiple keyboards from the same OEM/controller family. Production matching should eventually consider several properties where available:

- Vendor ID
- Product ID
- USB product string
- Manufacturer string
- HID usage page / usage
- HID report descriptor fingerprint
- Possibly interface number/path

A safe detector might eventually look conceptually like:

```text
VID == 0x5566
PID == 0x0008
manufacturer contains "ZXWMicroChip"
product contains "Fantech Atom Pro"
AND HID collection matches the known configuration interface
```

The report descriptor/interface fingerprint will be much more reliable than VID/PID alone.

---

## 3. Strong OEM/Controller Lead: ZiFriend ZA63 Pro

A public GitHub project documenting ZiFriend keyboards reports that the **ZiFriend ZA63 Pro** uses:

```text
VID: 0x5566
PID: 0x0008
```

Source:

- https://github.com/ken-kuro/Zifriend-Keyboard-Linux

The repository also states that ZiFriend/SAMA/GameStop/Cyberlinx-style rebrands can share this hardware identity, and specifically notes `5566:0008` for the ZA63 Pro and other variants.

This is interesting because the ZA63 Pro appears broadly similar in category to the MK912:

- compact layout
- multi-mode connection
- RGB lighting
- per-key lighting capability
- similar OEM-style configuration software

ZiFriend also publishes drivers/manuals publicly:

- https://www.zifriend.net/pages/drivers-manuals
- https://www.zifriend.net/pages/drivers-manuals-1
- https://www.zifriend.net/pages/user-manuals

### What this does **not** prove

The VID/PID match is a **strong lead**, not proof that the RGB protocol is identical.

Possible cases:

1. **Best case:** MK912 and ZA63 Pro use the same controller and almost the same protocol.
2. They use the same USB identity but different report descriptors or command formats.
3. They share a controller family but differ in keyboard matrix, LED count, effect IDs, or packet offsets.
4. The vendor software has model-specific tables while using a common low-level transport.

Therefore the agent must verify descriptors and packet behavior before reusing any ZA63 assumptions.

---

## 4. Open-Source Projects Relevant to the Work

### 4.1 HIDAPI — recommended low-level reference/tooling

Repository:

- https://github.com/libusb/hidapi

HIDAPI is a small cross-platform library for HID communication. Its macOS backend uses **IOHIDManager**.

It supports the operations we are likely to need:

- enumerate HID collections
- open a specific HID path
- send output reports
- send feature reports
- read input reports
- get feature reports

Homebrew currently provides HIDAPI:

```bash
brew install hidapi
```

For the final macOS app we may either:

- use HIDAPI directly, or
- implement the final transport in native Swift/IOKit once the protocol is known.

The protocol layer should be written so either transport can be swapped in.

---

### 4.2 hidapitester — recommended discovery/replay tool

Repository:

- https://github.com/todbot/hidapitester

This is probably the most useful tool for the first stage because it exposes HIDAPI functionality through a CLI.

Important commands include:

```text
--list
--list-usages
--list-detail
--open
--open-path
--get-report-descriptor
--send-output
--send-feature
--read-input
--read-feature
```

#### macOS installation

Do **not** assume `brew install hidapitester` exists as a standard Homebrew formula.

The upstream project provides prebuilt macOS binaries on its Releases page, or it can be built from source.

Build route:

```bash
xcode-select --install

cd ~/Developer

git clone https://github.com/libusb/hidapi.git
git clone https://github.com/todbot/hidapitester.git

cd hidapitester
make
```

Then test:

```bash
./hidapitester --version
```

The project also supports CMake.

---

### 4.3 OpenRGB — protocol reverse-engineering reference, not our main codebase

Main project:

- https://gitlab.com/CalcProgrammer1/OpenRGB

OpenRGB is useful because its device-support process provides good examples of reverse-engineering RGB HID devices.

#### Relevant Fantech issue

There is an OpenRGB device-support ticket for the **Fantech MK871**:

- https://gitlab.com/CalcProgrammer1/OpenRGB/-/issues/2211

The MK871 is **not the same controller identity** as our MK912. It reports:

```text
VID: 0x258A
PID: 0x1006
```

So its raw packets should **not** be sent to the MK912.

However, the issue is extremely useful as a model for how to reverse engineer a keyboard. It contains captures for:

- report descriptor
- static red
- static green
- static blue
- brightness changes
- speed changes
- breathing mode
- rainbow-style modes
- snake mode
- other effects
- custom/per-key lighting

This shows the exact methodology we should use for the MK912: capture one setting change at a time and diff the packets.

### Licensing note

OpenRGB is GPL-licensed. Treat it primarily as a **reference for architecture and protocol-research methodology** unless we deliberately choose a GPL-compatible license for this project.

Do not copy large chunks of OpenRGB implementation into a permissively licensed project without reviewing licensing consequences.

---

### 4.4 Rangoli — interesting project, but probably not the right protocol base

Rangoli was initially considered because it supports several inexpensive/rebranded mechanical keyboards and HID-based RGB configuration.

However, the important discovery is that our MK912 is:

```text
5566:0008
ZXWMicroChip
```

while the earlier Sino Wealth lead involved `0x258A` devices.

Therefore:

> **Do not base the MK912 implementation on the assumption that it uses the Rangoli/Sino Wealth protocol.**

Rangoli may still be useful for UI/architecture ideas, but it should not be considered protocol evidence for this keyboard.

---

## 5. Recommended Project Strategy

The project should be split into two major stages:

```text
STAGE A — PROVE THE PROTOCOL

MK912
  ↓
Enumerate HID collections
  ↓
Identify vendor/config collection
  ↓
Capture official Windows software traffic
  ↓
Decode packets
  ↓
Replay one known command from macOS
  ↓
Build small CLI protocol test tool


STAGE B — BUILD THE APP

Proven MK912 protocol
  ↓
Protocol library
  ↓
macOS HID transport
  ↓
SwiftUI state/model layer
  ↓
RGB/effects UI
  ↓
Profiles + persistence
  ↓
Signing / packaging
```

**Do not start Stage B until a known-safe Stage A command works.**

The first meaningful milestone is not “app window opens.”

It is:

> **A command run from macOS changes the MK912 to a known RGB color or effect.**

For example:

```bash
atomctl static --color FF0000
```

and the keyboard becomes red.

Once that works, most of the uncertainty is gone.

---

# PHASE 1 — HID Enumeration on macOS

## 6. Enumerate every HID collection for `5566:0008`

Run:

```bash
hidapitester --vidpid 5566:0008 --list-detail
```

Save the complete output to:

```text
docs/hardware/mk912-hid-enumeration.txt
```

Do not keep only one entry. Composite keyboards usually expose multiple HID collections.

Possible examples:

```text
Usage Page 0x01 / Usage 0x06
    Standard keyboard

Usage Page 0x0C
    Consumer/media controls

Usage Page 0xFF00, 0xFF01, etc.
    Vendor-defined HID interface
```

The exact values must be discovered from the real device.

### What we are looking for

The most likely configuration endpoint is a **vendor-defined usage page**, usually in the `0xFFxx` range.

However, do not assume this before inspecting the descriptors.

Record for every entry:

| Field | Record |
|---|---|
| VID | yes |
| PID | yes |
| path | yes |
| serial | yes |
| manufacturer | yes |
| product | yes |
| usagePage | yes |
| usage | yes |
| interface number | if exposed |
| release number | if exposed |

---

## 7. Extract HID report descriptors

For each promising collection, use `--open-path` rather than opening only by VID/PID.

Why?

`5566:0008` may expose multiple collections. Opening only by VID/PID can select the wrong one.

Conceptual flow:

```bash
hidapitester --open-path '<PATH FROM LIST-DETAIL>' --get-report-descriptor
```

Save each descriptor separately:

```text
docs/hardware/descriptors/
  interface-01.txt
  interface-02.txt
  vendor-interface.txt
```

Also create a human-readable summary:

```text
docs/hardware/report-descriptor-notes.md
```

Record:

- Report IDs
- Input report sizes
- Output report sizes
- Feature report sizes
- Usage page
- Usage
- Collection type

This immediately tells us whether the software probably communicates using:

- HID Output Reports
- HID Feature Reports
- or both

---

## 8. Establish a descriptor fingerprint

Because `5566:0008` appears to be reused, calculate a hash of the relevant report descriptor once captured.

Example:

```bash
shasum -a 256 vendor-interface-descriptor.bin
```

Store the fingerprint in documentation.

Later, the app can use descriptor structure as an additional compatibility check before enabling write operations.

---

# PHASE 2 — Obtain and Preserve Vendor Software

## 9. Download both useful vendor packages

Collect these from official sources where possible:

### Fantech

- ATOM PRO63 MK912 Windows software
- MK912 manual

Source:

- https://fantechworld.com/pages/download-keyboard

### ZiFriend

- ZA63/ZA63 Pro software if available
- ZA63 Pro manual

Sources:

- https://www.zifriend.net/pages/drivers-manuals
- https://www.zifriend.net/pages/user-manuals

Store installers under a local research folder, not necessarily in Git if redistribution rights are unclear:

```text
research/vendor-software/
  fantech/
  zifriend/
```

Record hashes:

```bash
shasum -a 256 <installer.exe>
```

Create:

```text
docs/research/vendor-software.md
```

with:

- original filename
- download URL
- date downloaded
- SHA-256
- version shown by installer/app
- whether it recognizes the MK912

Do not commit proprietary installer binaries unless redistribution is clearly permitted.

---

# PHASE 3 — Capture the Official Windows Protocol

## 10. Preferred capture environment

Use a **physical Windows machine** if available. This is the least complicated setup.

Alternative:

- Windows VM with reliable USB passthrough

For Apple Silicon Macs, Windows ARM + USB passthrough may work, but vendor software compatibility can introduce unnecessary variables. Use a physical Windows machine if the vendor app fails under virtualization.

Recommended tools:

- Wireshark
- USBPcap

Goal:

> Observe exactly what Fantech software sends to the keyboard when one UI setting changes.

---

## 11. Capture rules

Every capture should change **one variable only**.

Bad capture:

```text
Open software
change mode
change color
change brightness
change speed
click Apply
```

This makes packet interpretation difficult.

Good captures:

```text
Capture A: baseline → static red
Capture B: static red → static green
Capture C: brightness 20% → 40%
Capture D: speed level 1 → level 2
```

Each capture should be short and named precisely.

---

## 12. Capture matrix

Create captures in roughly this order.

### 12.1 Application initialization

Capture:

```text
01-app-launch.pcapng
```

Procedure:

1. Start capture.
2. Launch Fantech software.
3. Wait until the keyboard is detected.
4. Do not change any setting.
5. Stop capture.

Purpose:

- identify device interrogation packets
- identify current-state reads
- identify initialization/unlock/session commands

---

### 12.2 Static color

Use full-intensity primary colors because byte differences are easy to identify.

Capture:

```text
10-static-red.pcapng     # FF0000
11-static-green.pcapng   # 00FF00
12-static-blue.pcapng    # 0000FF
13-static-white.pcapng   # FFFFFF
14-static-black.pcapng   # 000000 if UI allows
```

Also test a deliberately unusual color:

```text
15-static-test-color.pcapng
```

Example:

```text
R = 0x12
G = 0x34
B = 0x56
```

This helps identify byte order.

If the packet contains:

```text
12 34 56
```

we likely have RGB.

If it contains:

```text
56 34 12
```

we likely have BGR.

---

### 12.3 Brightness

Capture every discrete level the official app exposes.

Example filenames:

```text
20-brightness-0.pcapng
21-brightness-20.pcapng
22-brightness-40.pcapng
23-brightness-60.pcapng
24-brightness-80.pcapng
25-brightness-100.pcapng
```

Do not assume brightness is represented as 0–100. Firmware may use:

```text
0x00–0x04
0x01–0x05
0x00–0xFF
```

or another mapping.

---

### 12.4 Effects/modes

Capture every effect individually.

Create a canonical mode table in:

```text
docs/protocol/effects.md
```

Example:

| UI Name | Capture | Suspected Mode ID | Color-capable | Speed | Direction |
|---|---|---:|---|---|---|
| Static | `30-mode-static.pcapng` | ? | yes | no | no |
| Breathing | `31-mode-breathing.pcapng` | ? | yes | yes | maybe |
| Rainbow | `32-mode-rainbow.pcapng` | ? | maybe | yes | yes |

Use the exact effect names from Fantech's application.

---

### 12.5 Speed

For one mode that supports speed, capture each speed level.

```text
40-speed-1.pcapng
41-speed-2.pcapng
42-speed-3.pcapng
43-speed-4.pcapng
44-speed-5.pcapng
```

---

### 12.6 Direction

If effects support direction:

```text
50-direction-left.pcapng
51-direction-right.pcapng
52-direction-up.pcapng
53-direction-down.pcapng
```

Only capture directions actually exposed by the UI.

---

### 12.7 Per-key RGB

This is one of the most important tests.

Start with every LED black/off if possible, then set **one key only**.

Suggested sequence:

```text
60-per-key-esc-red.pcapng
61-per-key-1-red.pcapng
62-per-key-q-red.pcapng
63-per-key-a-red.pcapng
64-per-key-z-red.pcapng
65-per-key-space-red.pcapng
66-per-key-enter-red.pcapng
```

Then use different colors:

```text
ESC   = FF0000
Q     = 00FF00
A     = 0000FF
SPACE = 123456
```

Purpose:

- discover LED index order
- discover RGB byte order
- discover packet chunking
- discover whether the app sends all keys or only changed keys

Eventually map all 63 physical keys.

---

### 12.8 Apply vs save/profile

Very important: determine whether the software distinguishes between:

- temporary/live update
- apply
- save to onboard memory

Capture them separately.

Repeated flash writes should be avoided during development if the keyboard stores settings in nonvolatile memory.

Suggested tests:

```text
70-live-preview.pcapng
71-apply.pcapng
72-save-profile.pcapng
```

Then unplug/replug the keyboard to see which settings persist.

---

## 13. Do NOT capture/replay firmware updater traffic initially

If Fantech publishes a firmware updater, keep it separate from normal RGB research.

Never blindly replay firmware-update packets.

Firmware traffic can involve:

- bootloader mode
- flash erase
- firmware blocks
- reset commands

These can brick the keyboard if misused.

RGB research should focus only on packets emitted by the normal configuration software.

---

# PHASE 4 — Decode the Protocol

## 14. Build a protocol notebook

Create:

```text
docs/protocol/protocol-notes.md
```

For every packet, record:

```text
Report type:
Report ID:
Report length:
Endpoint/interface:
Raw bytes:
Action that caused it:
Response, if any:
Hypothesis:
Confidence:
```

Example:

```text
Action: Static red
Report type: Feature
Report ID: 0x05
Length: 64

05 12 01 FF 00 00 04 03 ...

Hypothesis:
byte[1] = command family
byte[2] = mode
byte[3] = red
byte[4] = green
byte[5] = blue
byte[6] = brightness
byte[7] = speed

Confidence: LOW — needs green/blue comparison
```

Never promote a byte interpretation to “known” based on one packet.

---

## 15. Diff captures programmatically

Write a helper script such as:

```text
tools/packet-diff/
```

It should be able to compare normalized report payloads and show changed offsets.

Example output:

```text
static-red vs static-green

Offset   Red capture   Green capture
0x04     FF            00
0x05     00            FF
0x06     00            00
```

This is far faster and less error-prone than visually comparing hex dumps.

Potential tools:

- Python
- tshark export
- Scapy, if useful
- custom CSV/JSON normalized representation

A simple Python script is enough.

---

## 16. Look for common packet patterns

Typical HID RGB protocols often contain some subset of:

```text
[reportId]
[command]
[subcommand]
[mode]
[brightness]
[speed]
[direction]
[R]
[G]
[B]
[data length]
[LED payload]
[checksum]
[padding]
```

But do **not** impose this format on the evidence.

Infer fields only from controlled experiments.

---

## 17. Determine packet length and chunking

Per-key RGB may require more bytes than a single report.

For 63 keys:

```text
63 keys × 3 bytes = 189 RGB bytes
```

If reports are 64 bytes, the keyboard may use several packets such as:

```text
packet 0 → header + LEDs 0–N
packet 1 → continuation
packet 2 → continuation
packet 3 → commit/apply
```

Or it may use a compressed/indexed representation.

Capture per-key updates carefully to discover this.

---

## 18. Check for checksum/sequence bytes

If one or two bytes change even when settings do not, investigate:

- packet counter
- transaction ID
- checksum
- CRC
- timestamp/random byte

To identify a checksum:

1. Create several packets with known controlled differences.
2. Test basic candidates:
   - byte sum
   - XOR
   - two's complement sum
   - CRC-8 variants
   - CRC-16 variants
3. Do not brute-force blindly until simpler explanations are ruled out.

---

# PHASE 5 — First Safe Replay on macOS

## 19. Replay only captured, known-safe packets

Once we know:

- correct HID path/interface
- report type
- report ID
- packet length
- one complete known-safe RGB command

replay the exact command on macOS.

Use `hidapitester` first.

Conceptual example only:

```bash
hidapitester \
  --open-path '<KNOWN VENDOR HID PATH>' \
  --length 64 \
  --send-feature '<CAPTURED BYTES>' \
  --close
```

or:

```bash
hidapitester \
  --open-path '<KNOWN VENDOR HID PATH>' \
  --length 64 \
  --send-output '<CAPTURED BYTES>' \
  --close
```

**Do not use these example commands with invented packet bytes.**

Only use payloads derived from the official software captures.

---

## 20. Safety rules for replay

The agent must follow these rules:

1. Open the **configuration/vendor HID collection**, not the ordinary keyboard input collection, unless captures prove otherwise.
2. Never send random feature reports.
3. Never send firmware-updater traffic.
4. Start by replaying an exact known-good packet.
5. Send one transaction, observe, then stop.
6. Keep the keyboard's hardware reset procedure/manual available.
7. Do not rapidly loop write operations during early testing.
8. Prefer volatile RGB updates before testing onboard profile writes.

---

# PHASE 6 — Build `atomctl` Before the GUI

## 21. CLI goals

Once the first replay works, build a tiny CLI called `atomctl`.

Initial commands:

```bash
atomctl list
atomctl info
atomctl static FF0000
atomctl brightness 3
atomctl effect breathing
atomctl speed 2
atomctl off
```

Later:

```bash
atomctl key esc FF0000
atomctl key q 00FF00
atomctl profile apply profile.json
```

The CLI proves that the protocol module is independent from SwiftUI.

---

## 22. Suggested repository layout

```text
AtomRGB/
├── README.md
├── LICENSE
├── docs/
│   ├── hardware/
│   │   ├── mk912-hid-enumeration.txt
│   │   ├── report-descriptor-notes.md
│   │   └── descriptors/
│   ├── protocol/
│   │   ├── protocol-notes.md
│   │   ├── effects.md
│   │   ├── key-index-map.md
│   │   └── captures-index.md
│   └── research/
│       ├── vendor-software.md
│       └── related-devices.md
│
├── captures/
│   ├── README.md
│   └── <pcap files if redistribution is appropriate>
│
├── tools/
│   ├── packet-diff/
│   └── descriptor-dump/
│
├── Sources/
│   ├── AtomProtocol/
│   │   ├── DeviceIdentity.swift
│   │   ├── MK912Protocol.swift
│   │   ├── LightingMode.swift
│   │   ├── RGBColor.swift
│   │   ├── KeyMap.swift
│   │   └── PacketEncoder.swift
│   │
│   ├── HIDTransport/
│   │   ├── HIDTransport.swift
│   │   ├── HIDDeviceInfo.swift
│   │   └── MacHIDTransport.swift
│   │
│   └── atomctl/
│       └── main.swift
│
├── Tests/
│   ├── AtomProtocolTests/
│   └── Fixtures/
│       └── known-packets.json
│
└── App/
    └── AtomRGB/
        ├── AtomRGBApp.swift
        ├── Models/
        ├── Views/
        └── Resources/
```

Exact structure can vary, but the key boundary is:

```text
UI ≠ Protocol ≠ HID Transport
```

Keep those concerns separate.

---

# PHASE 7 — Software Architecture

## 23. Transport abstraction

Define a small interface conceptually like:

```swift
protocol HIDTransport {
    func enumerate() throws -> [HIDDeviceInfo]
    func open(_ device: HIDDeviceInfo) throws
    func close()

    func sendOutputReport(reportID: UInt8, data: Data) throws
    func sendFeatureReport(reportID: UInt8, data: Data) throws
    func getFeatureReport(reportID: UInt8, length: Int) throws -> Data
}
```

The MK912 protocol code should not know about SwiftUI or IOHIDManager.

Then:

```text
MK912Protocol
    ↓
HIDTransport protocol
    ↓
MacHIDTransport (IOHIDManager)
```

If HIDAPI is used during discovery, an optional `HIDAPITransport` can implement the same abstraction.

---

## 24. Recommended final macOS transport

For a Mac-only polished application, native **IOKit / IOHIDManager** is attractive because:

- no external runtime dependency
- direct integration with macOS
- easy device-connect/disconnect callbacks
- easier native packaging once implemented correctly

However, do not rewrite the transport too early.

During discovery, HIDAPI/hidapitester is faster.

Recommended sequence:

```text
hidapitester proof
      ↓
atomctl using simplest reliable transport
      ↓
protocol stabilized
      ↓
native IOHIDManager transport
      ↓
SwiftUI app
```

---

## 25. Device matching

Create a model-specific matcher rather than hardcoding only VID/PID.

Conceptual:

```swift
struct MK912Identity {
    static let vendorID: UInt16 = 0x5566
    static let productID: UInt16 = 0x0008

    static func matches(_ device: HIDDeviceInfo) -> Bool {
        // VID/PID
        // product string
        // manufacturer
        // usage page/usage
        // descriptor/interface fingerprint if possible
    }
}
```

If another `5566:0008` board is connected, the application should refuse model-specific writes unless compatibility is confirmed.

---

# PHASE 8 — Model the RGB Protocol

## 26. Do not expose raw packets to the UI

The protocol layer should provide semantic operations:

```swift
setStaticColor(_ color: RGBColor)
setBrightness(_ level: BrightnessLevel)
setEffect(_ effect: LightingEffect)
setSpeed(_ speed: EffectSpeed)
setDirection(_ direction: EffectDirection)
setPerKeyColors(_ colors: [KeyID: RGBColor])
apply()
saveProfile(slot: Int)
```

Internally these functions encode packets.

SwiftUI should never contain packet offsets such as:

```swift
packet[7] = 0x03
```

That belongs only in `PacketEncoder`/protocol code.

---

## 27. Preserve raw/semantic separation

Recommended types:

```text
RGBColor
LightingEffect
BrightnessLevel
EffectSpeed
EffectDirection
KeyID
KeyboardProfile
MK912Packet
```

This makes it possible to change the underlying packet format without changing the UI.

---

# PHASE 9 — Per-Key RGB Mapping

## 28. Derive physical LED order empirically

The firmware's LED order may not match USB key codes or visual left-to-right order.

Create:

```text
docs/protocol/key-index-map.md
```

Example format:

| Physical Key | LED Index | Packet | Offset | Notes |
|---|---:|---:|---:|---|
| Esc | ? | ? | ? | |
| 1 | ? | ? | ? | |
| 2 | ? | ? | ? | |
| Q | ? | ? | ? | |
| Space | ? | ? | ? | |

Use one-key captures to derive the mapping.

Do not assume ANSI physical order.

---

## 29. Keyboard visual editor

Once mapping is known, the GUI can present a 63-key layout.

Clicking a key should set its color in a local profile model first.

Only send to the keyboard when:

- live preview is enabled, or
- user clicks Apply

For live preview, debounce writes to avoid flooding the device.

---

# PHASE 10 — macOS SwiftUI Application

## 30. MVP UI

The first useful UI can be one window:

```text
┌──────────────────────────────────────────┐
│ ATOM PRO63 MK912             ● Connected │
│                                          │
│ Lighting Mode   [ Static             ▾ ] │
│                                          │
│ Color           [ color picker ]         │
│ Brightness      ━━━━━━━━━●━━━━           │
│ Speed           ━━━━━●━━━━━━━━           │
│ Direction       [ Left               ▾ ] │
│                                          │
│ [ Keyboard / Per-Key Editor ]            │
│                                          │
│               [ Apply ]   [ Save ]       │
└──────────────────────────────────────────┘
```

Do not overbuild the design until the protocol is complete.

---

## 31. Connection states

Support clear states:

```text
Disconnected
Connected — supported MK912
Connected — compatible ZXW device, unverified
Connected — unsupported
Communication error
```

Never silently send MK912 packets to an unverified `5566:0008` device.

---

## 32. Hotplug support

Use HID manager callbacks so the app responds when the keyboard is:

- connected
- disconnected
- reconnected

The UI should not require relaunching.

---

## 33. MVP feature priority

Build in this order:

1. Detect MK912
2. Static color
3. Brightness
4. RGB off
5. Built-in effects
6. Effect speed
7. Direction
8. Per-key RGB
9. Local profiles
10. Onboard profile save, **only after persistence behavior is understood**
11. Menu bar control
12. Launch at login

Do not make macros/key remapping part of MVP unless specifically needed later.

RGB is the initial goal.

---

# PHASE 11 — Testing

## 34. Golden packet tests

Every decoded vendor packet should have a fixture.

Example:

```json
{
  "operation": "staticColor",
  "input": { "r": 255, "g": 0, "b": 0 },
  "expectedReports": [
    "...hex payload..."
  ]
}
```

Unit tests should verify the encoder produces byte-for-byte expected output.

This prevents UI work from accidentally breaking the protocol.

---

## 35. Hardware integration tests

Keep hardware tests separate from unit tests.

Examples:

```bash
atomctl test static-colors
atomctl test brightness
atomctl test effects
```

These require the real keyboard and should not run automatically in CI.

---

## 36. Compatibility database

Because the OEM IDs appear reused, design for future support:

```text
Devices/
  FantechMK912.swift
  ZiFriendZA63Pro.swift
  ...
```

Potentially multiple branded devices can share the same `ZXWProtocolFamily` while defining different:

- key count
- LED order
- supported effects
- product strings
- packet quirks

Do not prematurely declare them identical.

---

# PHASE 12 — Research the ZiFriend Software

## 37. Why the ZiFriend app is worth testing

The ZA63 Pro has the same documented VID/PID as the MK912.

Therefore, on a Windows test machine:

1. Install/run the official ZiFriend ZA63 software.
2. Plug in the MK912.
3. Observe whether the ZiFriend app detects it.

Possible outcomes:

### Outcome A — ZiFriend app fully detects MK912

Excellent evidence of shared protocol/model family.

Capture ZiFriend traffic and compare it with Fantech traffic.

### Outcome B — detects device but wrong layout/features

Still useful. Likely shared transport/controller with model-specific definitions.

### Outcome C — does not detect it

Still not a dead end. The app may check product strings, firmware versions, or other model identifiers before enabling a shared protocol.

### Outcome D — recognizes VID/PID but errors

Inspect the initialization exchange. It may reveal a model-query command.

---

# PHASE 13 — Optional Static Analysis of Vendor Software

## 38. Only after packet capture

Do not start by spending days decompiling the Windows app.

USB capture is usually faster.

Static analysis becomes useful when packets contain unexplained fields.

Potential tools:

- `strings`
- 7-Zip / archive inspection
- Detect It Easy
- Ghidra
- Cutter/radare2
- dnSpy/ILSpy if it is .NET
- JavaScript extraction if the app is Electron

Search for:

```text
5566
0008
ZXW
HID
Report
Feature
Effect names
model names
ZA63
MK912
```

If the software contains static tables for effect IDs or packet templates, this can dramatically accelerate decoding.

Do not redistribute proprietary binaries or decompiled source.

---

# PHASE 14 — macOS Permissions / Distribution

## 39. Initial development

Develop outside the Mac App Store sandbox first.

HID access through IOHIDManager is normally user-space, but macOS security behavior can vary depending on the HID collection and how the application is packaged.

Do not automatically request:

- Accessibility
- Input Monitoring
- Full Disk Access

unless testing proves one is actually required.

A vendor-defined configuration interface may be accessible without these permissions.

---

## 40. Production distribution

After the app works:

- build Release configuration
- sign with Developer ID if distributing publicly
- notarize
- package as `.dmg` or `.zip`
- optionally create a Homebrew Cask later

Target Apple Silicon first for development. Add Intel/universal builds only if public distribution requires them.

---

# PHASE 15 — Logging and Diagnostics

## 41. Build diagnostics from day one

Add optional verbose logging:

```bash
atomctl --verbose static FF0000
```

Log:

```text
Matched device
Path
Usage page
Usage
Report type
Report ID
Report length
Outbound report hex
Inbound response hex
Duration
Result
```

Do not log unnecessary personal/system data.

The GUI should eventually provide an **Export Diagnostics** function containing:

- app version
- macOS version
- detected HID metadata
- descriptor fingerprint
- supported protocol version
- recent transport errors

---

# PHASE 16 — Error Handling

## 42. Expected errors

Handle:

- keyboard disconnected during write
- wrong HID interface
- permission denied
- short write
- feature report rejected
- unsupported mode
- response timeout
- device reconnect/path changed

Never crash simply because the keyboard is unplugged.

---

# PHASE 17 — What the Agent Should Do First

## 43. Immediate task list

The coding agent should begin with **research tooling**, not the GUI.

### Task 1 — Initialize repository

Create:

```text
README.md
docs/hardware/
docs/protocol/
docs/research/
tools/
```

Record the confirmed identity:

```text
Fantech Atom Pro Keyboard
ZXWMicroChip
VID 0x5566
PID 0x0008
```

---

### Task 2 — Set up hidapitester

Use the upstream prebuilt binary or compile it from:

- https://github.com/todbot/hidapitester

Confirm:

```bash
hidapitester --version
```

---

### Task 3 — Enumerate the keyboard

Run:

```bash
hidapitester --vidpid 5566:0008 --list-detail
```

Save full output.

---

### Task 4 — Dump report descriptors

Dump each relevant `5566:0008` collection using exact paths.

Identify any vendor-defined collection.

Document report IDs and sizes.

---

### Task 5 — Build a read-only `atomctl info`

Before any write support, create a small program that prints:

```text
Device name
Manufacturer
VID/PID
Path
Usage page
Usage
Serial
Report descriptor fingerprint
```

No writes yet.

Acceptance criteria:

```bash
atomctl info
```

reliably finds the exact MK912 interface while the keyboard still works normally as a keyboard.

---

### Task 6 — Prepare Windows capture checklist

Create the capture directory and checklist from this document.

No protocol values should be guessed.

---

### Task 7 — Capture Fantech software

Produce at minimum:

```text
app launch
static red
static green
static blue
brightness min
brightness max
one effect
per-key one-key change
```

---

### Task 8 — Normalize/diff captures

Create a script that extracts HID transfer payloads and compares them.

Document first protocol hypothesis.

---

### Task 9 — First safe replay

Replay exactly one captured static-color transaction from macOS.

Acceptance criterion:

> Keyboard color changes correctly with no loss of normal keyboard input.

---

### Task 10 — Only then implement `atomctl static`

Turn the captured packet into a parameterized encoder.

Validate:

```bash
atomctl static FF0000
atomctl static 00FF00
atomctl static 0000FF
atomctl static 123456
```

All four colors should match expected output.

---

# 44. Recommended Milestones

## Milestone M0 — Device fingerprint

**Done when:**

- All `5566:0008` HID collections documented
- Correct configuration interface identified
- Report descriptor saved/fingerprinted

---

## Milestone M1 — First RGB write

**Done when:**

- One exact captured Fantech RGB command is successfully replayed from macOS

This is the most important proof-of-concept milestone.

---

## Milestone M2 — Static RGB protocol

**Done when:**

- arbitrary RGB values work
- brightness works
- lights can be disabled or set to black using the correct protocol

---

## Milestone M3 — Built-in effects

**Done when:**

- supported mode IDs mapped
- speed mapped
- direction mapped where available

---

## Milestone M4 — Per-key RGB

**Done when:**

- all 63 LEDs mapped
- arbitrary 63-key RGB profile can be sent reliably

---

## Milestone M5 — Native macOS app

**Done when:**

- SwiftUI app detects device
- static RGB works
- effects work
- brightness/speed work
- connect/disconnect works

---

## Milestone M6 — Polished release

**Done when:**

- profile storage
- per-key editor
- diagnostics
- signed/notarized distribution
- documentation

---

# 45. Questions the Agent Must Answer Through Evidence

Do not guess these. Resolve them experimentally.

1. How many HID collections does the MK912 expose?
2. Which collection does the Fantech app use?
3. What usage page/usage identifies it?
4. Does configuration use Output Reports, Feature Reports, or both?
5. What are the report IDs?
6. What are the report lengths?
7. Does the keyboard acknowledge writes?
8. Is there an initialization/unlock command?
9. How is RGB ordered: RGB, BGR, GRB, etc.?
10. How is brightness encoded?
11. How are effect IDs encoded?
12. How is speed encoded?
13. How is direction encoded?
14. Does a static color packet contain all current state or only changed state?
15. Does the software send a final commit packet?
16. Are live changes volatile?
17. Which operation writes onboard memory?
18. How is per-key LED data chunked?
19. What is the 63-key LED index order?
20. Is there a checksum or sequence byte?
21. Does the ZiFriend ZA63 application recognize the MK912?
22. Are Fantech and ZiFriend packets identical?
23. Does the USB interface/path change after reconnect?
24. Does the protocol work only in wired mode?
25. Can the protocol operate through the 2.4 GHz receiver later?

---

# 46. Important Non-Goals for the First Version

Avoid scope creep.

Do **not** start with:

- macros
- key remapping
- firmware updates
- Bluetooth configuration
- cloud accounts
- cross-platform Windows UI
- Linux packaging
- OpenRGB integration
- automatic game integrations
- audio-reactive RGB

First objective:

```text
Reliable RGB control of the Fantech MK912 on macOS.
```

Everything else can come later.

---

# 47. Suggested README Summary

The repository README can start with something like:

```markdown
# AtomRGB

Experimental open-source macOS RGB controller for the Fantech ATOM PRO63 MK912.

Confirmed hardware identity:

- Manufacturer: ZXWMicroChip
- VID: `0x5566`
- PID: `0x0008`
- USB product: `Fantech Atom Pro Keyboard`

The protocol is being reverse engineered from the official Fantech Windows application. A ZiFriend ZA63 Pro has been independently documented with the same VID/PID, suggesting a shared ZXW/OEM controller family, but protocol compatibility has not yet been assumed.

Current status: protocol research / HID enumeration.
```

---

# 48. Evidence vs Hypothesis

Keep this distinction explicit throughout the project.

## Confirmed

- The physical Fantech MK912 used for this project identifies on macOS as **ZXWMicroChip**.
- Its USB VID is **0x5566**.
- Its USB PID is **0x0008**.
- Its product string is **Fantech Atom Pro Keyboard**.
- Fantech publishes Windows software for the Atom Pro63 MK912.
- A public ZiFriend ZA63 Pro report documents the same `5566:0008` VID/PID.
- HIDAPI supports macOS through IOHIDManager.
- hidapitester can enumerate HID usages/descriptors and send/read HID reports.

## Strong hypothesis

- The MK912 belongs to the same or a closely related ZXW/OEM controller family as the ZiFriend ZA63 Pro.

## Unknown

- Whether the MK912 and ZA63 Pro use identical RGB command packets.
- Which HID interface carries the configuration protocol.
- The report IDs and packet lengths.
- RGB field offsets/order.
- Effect IDs.
- Per-key LED order.
- Persistence behavior.

The agent should update these lists as evidence is collected.

---

# 49. Research Sources

## Fantech

**Official keyboard download page**

https://fantechworld.com/pages/download-keyboard

**Official all-downloads page**

https://fantechworld.com/pages/download-all-filter

These pages list the Atom Pro63 MK912 software/manual downloads.

---

## ZiFriend / same VID-PID lead

**Zifriend-Keyboard-Linux**

https://github.com/ken-kuro/Zifriend-Keyboard-Linux

Key useful finding from the project: the author's ZA63 Pro reports `VID:PID = 5566:0008`, and the repository discusses this identity being reused across ZiFriend/rebranded models.

**ZiFriend Drivers & Manuals**

https://www.zifriend.net/pages/drivers-manuals

https://www.zifriend.net/pages/drivers-manuals-1

https://www.zifriend.net/pages/user-manuals

---

## HID tooling

**HIDAPI**

https://github.com/libusb/hidapi

**Homebrew HIDAPI formula**

https://formulae.brew.sh/formula/hidapi

**hidapitester**

https://github.com/todbot/hidapitester

---

## Reverse-engineering methodology reference

**OpenRGB — Fantech MK871 support issue #2211**

https://gitlab.com/CalcProgrammer1/OpenRGB/-/issues/2211

Important: MK871 uses a different VID/PID (`258A:1006`), so use this issue as a methodology/capture reference rather than a source of packets for the MK912.

**OpenRGB project**

https://gitlab.com/CalcProgrammer1/OpenRGB

---

# 50. Final Direction

The highest-probability path is:

```text
1. Enumerate MK912 HID collections on macOS
2. Identify and fingerprint its vendor/config interface
3. Capture official Fantech Windows software traffic
4. Compare controlled RGB changes
5. Decode the packet format
6. Replay one exact known-safe packet from macOS
7. Parameterize it into atomctl
8. Map effects/brightness/speed
9. Map all 63 per-key LEDs
10. Build SwiftUI app on top of the proven protocol
```

The project should **not** attempt to invent a new RGB protocol and should **not** begin by cloning the entire Fantech UI.

The main technical uncertainty is the proprietary HID packet format. Everything else — device discovery, SwiftUI, profile management, hotplugging, packaging — is conventional once that packet format is known.

The `5566:0008` + `ZXWMicroChip` discovery substantially narrows the research space and gives us a concrete related-device lead in the ZiFriend ZA63 Pro.

**First next action:** run a complete HID enumeration of the actual MK912 and preserve every `5566:0008` HID collection and report descriptor before sending any write commands.
