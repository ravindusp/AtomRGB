# AtomRGB

Experimental macOS RGB controller for the Fantech ATOM PRO63 MK912.

## Hardware identity

- Product: `Fantech Atom Pro Keyboard`
- Manufacturer: `ZXWMicroChip`
- VID: `0x5566`
- PID: `0x0008`
- Initial scope: wired USB mode
- RGB interface: USB Interface 2 / `ZXWCustom`
- RGB reports: 64-byte input/output, no HID Report ID

The global RGB protocol is now documented from the Windows Fantech utility capture analysis. The repository currently contains the supplied protocol report and packet fixtures, but not the original `.pcapng` files. Hardware writes remain explicitly gated behind `atomctl --write`.

The RGB MVP uses only Interface 2. The earlier logical `0xFF00` privilege result is documented as an upstream HIDAPI/macOS access issue and is not required. Per-key RGB, key remapping, macros, firmware updates, profiles, and wireless mode remain out of scope.

See [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for the execution plan and [Fantech_MK912_macOS_RGB_Reverse_Engineering_Plan.md](Fantech_MK912_macOS_RGB_Reverse_Engineering_Plan.md) for the original research.
