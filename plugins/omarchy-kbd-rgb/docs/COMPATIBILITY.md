# Compatibility

`omarchy-kbd-rgb` only controls keyboards that the installed [VRGB](https://github.com/vrgb-dev/vrgb) version recognizes. It does **not** identify support from the laptop name alone: the keyboard must expose one of VRGB's verified ITE5570 HID LampArray mappings.

## Confirmed laptops

| Laptop / known configuration | HID ID | VRGB reports | Plugin result |
| --- | --- | --- | --- |
| ASUS Vivobook S 14 OLED **S5406SA** (including the reported S5406SA-WH79 configuration and Q423SA) | `0018:00000B05:000019B6` | firmware `0x0B`, color `0x05` | Supported. Load `asus-nb-wmi`; static color, brightness, off, theme sync, and the plugin's software rainbow work. |
| ASUS Vivobook S 16 **M5606K** | `0018:00000B05:00005570` | firmware `0x46`, color `0x45` | Supported. |
| ASUS Vivobook S 16 **M5606WA** | `0018:00000B05:00005570` | firmware `0x46`, color `0x45` | Supported. |
| ASUS Vivobook S 14 **M5406WA** | `0018:00000B05:00005570` | firmware `0x46`, color `0x45` | Supported. |

“Supported” means VRGB static color and brightness control have been verified upstream. The plugin layers its UI, persistence, theme color, and timer-driven rainbow over that same `vrgb set` command.

> **SKU warning:** ASUS's S5406 and M5606/M5406 product-family specification pages include configurations with a one-zone RGB keyboard and configurations without it. Check the actual keyboard HID ID, not only the family/model printed by a retailer.

## Not supported or not yet verified

| Laptop | Status | Why |
| --- | --- | --- |
| ASUS TUF Gaming A16 **FA608UP** | **Not supported by this plugin** | It shares HID ID `0018:00000B05:000019B6`, but a VRGB compatibility report found that VRGB's Vivobook feature-report payloads did not change the physical keyboard. A separate model-specific arming workaround is required, which this plugin does not implement. |
| ASUS Vivobook S 16 **S5606CA** | **Unverified** | A community report discusses OEM rainbow after disabling Secure Boot, but does not establish that VRGB static control—the command this plugin uses—works. It is not in VRGB's current verified mapping. |
| Any ROG, other TUF, Zenbook, Vivobook, or non-ASUS laptop | **Unsupported unless VRGB adds and verifies its exact mapping** | A backlit or RGB keyboard, and even an ITE5570 controller, are insufficient evidence; report IDs and initialization can differ. |

The plugin's **Rainbow** mode is software-driven: it continuously sends static colors through `vrgb set`. It is different from VRGB's optional `vrgb rainbow` OEM/WMI mode, so an unavailable OEM rainbow mode does not by itself prevent the plugin's Rainbow mode from working.

## Check a machine before installing

1. Install VRGB and load the required module on the S5406SA mapping:

   ```bash
   sudo modprobe asus-nb-wmi
   vrgb --debug status
   ```

2. Only continue if the output selects one of the two HID IDs above and `vrgb set FF0000 100` visibly changes the keyboard:

   ```bash
   vrgb set FF0000 100
   ```

3. If either check fails, do not install this plugin as a workaround. Submit the full `vrgb --debug status` output to [VRGB's compatibility issue](https://github.com/vrgb-dev/vrgb/issues/1) instead.

## Research sources

- VRGB v0.3.5 [device map](https://github.com/vrgb-dev/vrgb/blob/main/vrgb.py) and [release notes](https://github.com/vrgb-dev/vrgb/releases/tag/v0.3.5): the two supported HID IDs, report IDs, and confirmed models.
- VRGB [compatibility reports](https://github.com/vrgb-dev/vrgb/issues/1): working reports for M5606WA and M5406WA, the S5406SA working report, the S5606CA note, and the FA608UP failure/workaround.
- VRGB issues [#2](https://github.com/vrgb-dev/vrgb/issues/2) and [#3](https://github.com/vrgb-dev/vrgb/issues/3): M5606K validation and the `asus-nb-wmi` requirement on the Q423SA/S5406SA mapping.
- ASUS product-family technical specifications for [S5406](https://www.asus.com/laptops/for-home/vivobook/asus-vivobook-s-14-oled-s5406/techspec/), [M5606](https://www.asus.com/laptops/for-home/vivobook/asus-vivobook-s-16-oled-m5606/techspec/), and [M5406](https://www.asus.com/laptops/for-home/vivobook/asus-vivobook-s-14-oled-m5406/techspec/): one-zone RGB keyboard availability varies by configuration.
