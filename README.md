# AtomRGB

Experimental macOS RGB controller for the Fantech ATOM PRO63 MK912.

## Hardware identity

- Product: `Fantech Atom Pro Keyboard`
- Manufacturer: `ZXWMicroChip`
- VID: `0x5566`
- PID: `0x0008`
- Initial scope: wired USB mode

The RGB protocol is not yet proven. The current work is read-only investigation of USB Interface 2, which exposes 64-byte input/output reports. The earlier logical `0xFF00` privilege result is documented as an upstream HIDAPI/macOS access issue and is not currently required. Do not send packets to the keyboard unless they have been captured from the official configuration software and documented in the protocol notes.

See [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for the execution plan and [Fantech_MK912_macOS_RGB_Reverse_Engineering_Plan.md](Fantech_MK912_macOS_RGB_Reverse_Engineering_Plan.md) for the original research.
