# MK912 lighting effects

Effect IDs are the values observed in byte 10 of the 64-byte Interface-2 lighting state. Confidence is `confirmed` for the global RGB report described in the supplied Windows analysis.

| UI name | Mode ID | Color / Colorful | Brightness | Speed | Direction |
|---|---:|---|---|---|---|
| Spectrum | `0x01` | Colorful | Yes | Yes | No observed control |
| Gradient | `0x02` | Yes | Yes | Yes | No observed control |
| Static | `0x03` | RGB | Yes | No/irrelevant | No |
| Breathe | `0x04` | Yes | Yes | Yes | No observed control |
| Flower | `0x05` | No color control observed | Yes | Yes | No |
| Wave | `0x06` | Yes | Yes | Yes | Left / Right |
| Wave UPR | `0x07` | Yes | Yes | Yes | Up / Down |
| Bubbler | `0x08` | Yes | Yes | Yes | Up / Down |
| Wave Light | `0x09` | Yes | Yes | Yes | Up / Down |
| Vortex | `0x0A` | Yes | Yes | Yes | Left / Right |
| Tide | `0x0B` | Yes | Yes | Yes | No direction recorded |
| Seawave | `0x0C` | Yes | Yes | Yes | Up / Down |
| Ripple | `0x0D` | Yes | Yes | Yes | No observed control |
| Ripple On | `0x0E` | Yes | Yes | Yes | No direction recorded |
| Single | `0x0F` | Yes | Yes | Yes | No direction recorded |
| Cell | `0x10` | No color control observed | Yes | Yes | No |
| Knock | `0x11` | Yes | Yes | Yes | No direction recorded |
| Glisten | `0x12` | Yes | Yes | Yes | No direction recorded |
| Rain | `0x13` | Yes | Yes | Yes | No direction recorded |
| Star | `0x14` | Yes | Yes | Yes | No direction recorded |
| Firework | `0x15` | Yes | Yes | Yes | No direction recorded |
| Wave Bar | `0x16` | Yes | Yes | Yes | No observed control |

The protocol always carries the same state fields. When the UI does not expose a control for an effect, the implementation preserves that field from the GET response instead of resetting it.
