# Fantech MK912 Windows USB capture guide

This guide explains how to capture the official Fantech Windows utility's normal RGB traffic so the MK912 protocol can be understood safely on macOS.

The capture work must happen on Windows because the Fantech configuration utility is Windows-only. A physical Windows computer is preferred. A USB-passthrough virtual machine is a fallback, but USB capture and vendor software compatibility are less predictable there.

## Safety rules

Follow these rules for every capture:

- Use wired USB mode only.
- Do not open or run a firmware updater.
- Do not capture or replay firmware-update traffic.
- Change one setting per capture.
- Do not click Apply/Save unless that action is the specific thing being captured.
- Do not send any captured bytes from Windows or macOS during the capture stage.
- Keep the original `.pcapng` files unchanged.
- Do not commit proprietary installers or captures unless redistribution is permitted.

The first goal is observation, not replay. The first macOS replay will happen only after one normal RGB command is understood and confirmed to target USB Interface 2.

## 1. Required equipment

You need:

- Fantech ATOM PRO63 MK912
- USB cable capable of data transfer
- Windows 10 or Windows 11 computer
- Official Fantech MK912 configuration utility
- Wireshark
- USBPcap
- Administrator access to install the capture driver
- A way to transfer captures back to the AtomRGB repository

Optional but useful:

- Python 3 for local payload-diffing on Windows
- Git for Windows if you want to clone the repository directly on Windows
- 7-Zip for inspecting vendor packages without installing them

## 2. Download the required software

Use official sources wherever possible.

### Fantech utility and manual

Open the official keyboard download page:

- <https://fantechworld.com/pages/download-keyboard>
- Alternate official all-downloads page: <https://fantechworld.com/pages/download-all-filter>

Find **Atom Pro63 MK912** and download its **Software** package and **User Manual**. Do not download firmware for this research.

Save the installer in a local research folder such as:

```text
research/vendor-software/fantech/
```

Before installing, record its filename and SHA-256 in PowerShell:

```powershell
Get-FileHash "$env:USERPROFILE\Downloads\<fantech-installer>.exe" -Algorithm SHA256
```

Record the installer version, download date, and whether it recognizes the connected MK912 in:

```text
docs/research/vendor-software.md
```

### Wireshark

Download the Windows installer from:

- <https://www.wireshark.org/download.html>

Install the normal 64-bit package for an x64 Windows system. Choose the USB capture components offered by the installer if available. Wireshark's Windows package includes Npcap for network capture; USBPcap is the USB-specific component used in this workflow.

After installation, verify in PowerShell:

```powershell
Get-Command wireshark.exe
Get-Command tshark.exe
```

Typical locations are:

```text
C:\Program Files\Wireshark\Wireshark.exe
C:\Program Files\Wireshark\tshark.exe
```

### USBPcap

Download the end-user USBPcap installer or release package from:

- <https://github.com/desowin/usbpcap/releases>
- Project documentation: <https://github.com/desowin/usbpcap>

Install it as Administrator and reboot Windows if the installer requests it. Confirm that `USBPcapCMD.exe` exists. Common locations include:

```text
C:\Program Files\USBPcap\USBPcapCMD.exe
C:\Program Files\Wireshark\extcap\USBPcapCMD.exe
```

If the executable is not on `PATH`, call it with its full path. Verify it with:

```powershell
& "C:\Program Files\USBPcap\USBPcapCMD.exe" --help
```

The exact installation path can differ between USBPcap versions.

### Optional Python and Git

Download Python from:

- <https://www.python.org/downloads/windows/>

Download Git for Windows from:

- <https://git-scm.com/download/win>

Python is optional because the captures can be analyzed on the Mac. Git is optional because the `.pcapng` files can be copied back manually.

## 3. Prepare the Windows machine

1. Close other keyboard configuration programs, OpenRGB, RGB utilities, and macro tools.
2. Connect the MK912 directly to the Windows computer in wired USB mode.
3. Do not use the 2.4 GHz receiver or Bluetooth for the first capture set.
4. Open Device Manager and confirm that the keyboard remains present when keys are pressed.
5. Install and launch the official Fantech utility.
6. Confirm that it recognizes the MK912 before starting protocol captures.
7. If the utility does not recognize the keyboard, stop and record that result. Do not install firmware or try random model utilities as a workaround.

Create this capture layout either by cloning the repository or by creating it manually:

```text
captures/windows/
├── raw/
├── exports/
└── notes/
```

The repository already contains instructions in:

```text
captures/windows/README.md
```

## 4. Identify the USBPcap capture source

USBPcap exposes one capture source per USB root hub. The source is not necessarily named after the keyboard.

### GUI method

1. Launch Wireshark as Administrator.
2. Open **Capture → Options**.
3. Look for interfaces named `USBPcap1`, `USBPcap2`, and so on.
4. Start with the source whose device tree contains the MK912's USB port.
5. If unsure, capture from the likely source while unplugging and reconnecting the keyboard. The enumeration events will reveal which source contains the device.

### USBPcapCMD method

Open an Administrator PowerShell window and run:

```powershell
$usbpcap = "C:\Program Files\USBPcap\USBPcapCMD.exe"
& $usbpcap --help
& $usbpcap
```

The no-argument form lists available USBPcap filter instances and their root-hub device trees. Select the instance containing the keyboard.

To write a capture directly to a file, the USBPcap command-line form is generally:

```powershell
& $usbpcap -d "\\.\USBPcap1" -o "$PWD\captures\windows\raw\01-app-launch.pcapng"
```

Replace `USBPcap1` with the instance shown on that computer. If the capture is empty, try the Wireshark GUI or add USBPcap's capture-all-devices option shown by that installed version's `--help` output. Capture-all is useful for discovery but produces more unrelated traffic.

Stop a command-line capture with `Ctrl+C`. Do not terminate it by unplugging the keyboard during the first capture.

## 5. Find the MK912 packets in Wireshark

Start with this display filter:

```text
usb.idVendor == 0x5566 && usb.idProduct == 0x0008
```

If that field is not recognized by the installed Wireshark version, filter on `usb` and locate the device by:

- Vendor ID `0x5566`
- Product ID `0x0008`
- Product string `Fantech Atom Pro Keyboard`
- Manufacturer `ZXWMicroChip`
- Serial `2021-09-09`

For each candidate transfer, inspect and record:

- USB interface number
- Endpoint number and direction
- Control versus interrupt transfer
- HID report type: input, output, or feature/control transfer
- Report ID, including implicit ID `0` if no ID byte is present
- Transfer length
- Raw payload bytes
- Whether the packet happened during initialization or after the isolated UI action

The exact field names can vary with the USBPcap/Wireshark version. The packet details pane is authoritative for the capture being analyzed.

Pay special attention to **USB Interface 2**. Do not assume it is the configuration interface just because the macOS descriptor is compatible; verify that the Windows utility actually addresses it.

## 6. Capture the initialization traffic

Use a fresh capture for this step.

1. Unplug the keyboard.
2. Start a USBPcap capture.
3. Plug in the keyboard.
4. Wait for Windows to finish device enumeration.
5. Launch the Fantech utility.
6. Wait until the utility shows the keyboard as connected.
7. Change nothing.
8. Stop the capture.

Save it as:

```text
captures/windows/raw/01-app-launch.pcapng
```

This capture may contain enumeration, state reads, initialization, or unlock traffic. Do not replay any of it yet.

## 7. Capture isolated RGB actions

For every capture below, start from a known baseline, change only the listed setting, wait for the utility to finish, and stop the capture. If the utility has an **Apply** button, record whether it was clicked. If Apply is the subject of the capture, do not change another setting at the same time.

### Static colors

Use the same static-lighting mode for all colors.

```text
10-static-red.pcapng       # R=FF G=00 B=00
11-static-green.pcapng     # R=00 G=FF B=00
12-static-blue.pcapng      # R=00 G=00 B=FF
13-static-test-123456.pcapng
```

The test color `123456` helps distinguish RGB, BGR, GRB, and other byte orders.

### Brightness

Keep the mode and color unchanged. Capture the lowest and highest available levels:

```text
20-brightness-low.pcapng
21-brightness-high.pcapng
```

If the UI exposes discrete levels, capture every level later. The first pass only needs the endpoints.

### Speed

Select one effect that clearly exposes speed. Keep effect, color, brightness, and direction unchanged:

```text
30-speed-slow.pcapng
31-speed-fast.pcapng
```

### Effects

Capture two or three effects individually. Prefer effects with clearly different behavior:

```text
40-effect-breathing.pcapng
41-effect-wave.pcapng
42-effect-rainbow.pcapng
```

Use the exact names shown by the Fantech utility. If an effect is unavailable, replace it with another and record the substitution in its note.

Do not start per-key mapping until static colors and at least one effect are decoded.

## 8. Create a note for each capture

For every `.pcapng`, create a Markdown note with the same base name in `captures/windows/notes/`.

Example: `captures/windows/notes/10-static-red.md`

```markdown
# Static red capture

- Date/time:
- Windows version:
- Fantech utility version:
- Keyboard serial:
- USBPcap source:
- Baseline before action:
- Exact UI action:
- Selected color/effect/brightness/speed:
- Apply clicked: yes/no
- Capture file:
- SHA-256:

## Candidate transfers

| Packet/frame | USB interface | Endpoint | Direction | Report type | Report ID | Length | Payload export | Notes |
|---:|---:|---|---|---|---:|---:|---|---|
| | | | | | | | | |
```

Hash each original capture in PowerShell:

```powershell
Get-FileHash "captures\windows\raw\10-static-red.pcapng" -Algorithm SHA256
```

## 9. Export candidate payloads

Do not copy an entire packet blindly if it contains USBPcap headers. Export the HID report payload identified in the packet details pane.

For a first pass, use one hex line per exported payload:

```text
05 01 02 FF 00 00 03 00
```

Or use JSON:

```json
{
  "action": "static-red",
  "interface": 2,
  "reportType": "output",
  "reportId": 0,
  "bytes": [5, 1, 2, 255, 0, 0, 3, 0]
}
```

Save exports in:

```text
captures/windows/exports/
```

The payload must be linked to its source frame and capture note. Preserve multiple reports when one UI action produces a sequence; do not keep only the last packet without documenting the discarded packets.

## 10. Compare payloads

The repository's diff tool accepts two or more hex/JSON payload files and classifies every byte offset as constant or varying:

```powershell
python tools\packet_diff.py `
  captures\windows\exports\10-static-red.hex `
  captures\windows\exports\11-static-green.hex `
  captures\windows\exports\12-static-blue.hex
```

On macOS, use:

```bash
python3 tools/packet_diff.py \
  captures/windows/exports/10-static-red.hex \
  captures/windows/exports/11-static-green.hex \
  captures/windows/exports/12-static-blue.hex
```

Use `--show varying` to focus on changing offsets or `--show constant` to see stable headers and padding:

```bash
python3 tools/packet_diff.py --show varying \
  captures/windows/exports/10-static-red.hex \
  captures/windows/exports/11-static-green.hex \
  captures/windows/exports/12-static-blue.hex
```

Interpretation rules:

- Constant bytes may be report IDs, command families, fixed headers, lengths, or padding.
- RGB-dependent bytes should change predictably between red, green, blue, and `123456`.
- Brightness-dependent bytes should change while color and mode remain constant.
- Effect-dependent bytes should change while color and brightness remain constant.
- Bytes that change on every transfer may be counters, checksums, or timestamps; do not assign them a meaning from one capture.

## 11. Determine the addressed USB interface

Create a table from the capture evidence:

| Action | Frame | Interface | Endpoint | Report type | Report ID | Length | Notes |
|---|---:|---:|---|---|---:|---:|---|
| Static red | | | | | | | |
| Static green | | | | | | | |
| Brightness | | | | | | | |
| Effect | | | | | | | |

The first protocol conclusion must answer:

> Does the Fantech utility send RGB configuration traffic through USB Interface 2?

If it addresses Interface 2, compare the Windows report length and descriptor/report IDs with the macOS Interface 2 record in:

```text
docs/hardware/report-descriptor-notes.md
```

If it addresses another interface, document that fact before writing any macOS transport code.

## 12. What to send back to the project

Provide these files:

```text
captures/windows/raw/01-app-launch.pcapng
captures/windows/raw/10-static-red.pcapng
captures/windows/raw/11-static-green.pcapng
captures/windows/raw/12-static-blue.pcapng
captures/windows/raw/20-brightness-low.pcapng
captures/windows/raw/21-brightness-high.pcapng
captures/windows/raw/30-speed-slow.pcapng
captures/windows/raw/31-speed-fast.pcapng
captures/windows/raw/40-effect-breathing.pcapng
captures/windows/raw/41-effect-wave.pcapng
captures/windows/raw/42-effect-rainbow.pcapng
```

Also provide the notes and exported payloads. If vendor redistribution is a concern, keep the raw captures private and send only the normalized payload exports, metadata, and hashes.

## 13. Stop conditions

Stop the capture session and do not attempt replay if:

- The keyboard disconnects or stops typing normally.
- The Fantech utility starts a firmware update.
- The capture contains unexplained bootloader or flash-write traffic.
- Multiple UI values changed in one capture.
- You cannot identify the USB interface or report type.
- The same action produces inconsistent payloads without an explained counter/checksum.

Once one static-color command is understood, bring the evidence back to macOS. The next step will be an exact, single-report replay through Interface 2, followed by verification that normal keyboard input still works.

## Official references

- Fantech keyboard downloads: <https://fantechworld.com/pages/download-keyboard>
- Fantech all downloads: <https://fantechworld.com/pages/download-all-filter>
- Wireshark downloads: <https://www.wireshark.org/download.html>
- USBPcap releases: <https://github.com/desowin/usbpcap/releases>
- USBPcap project/documentation: <https://github.com/desowin/usbpcap>
- Python for Windows: <https://www.python.org/downloads/windows/>
- Git for Windows: <https://git-scm.com/download/win>
