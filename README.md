# Pi_Branding

Brands a Raspberry Pi as a Michelli product: replaces the boot splash with the
Michelli logo on a grey background, silences the boot sequence, and presents a
clean grey desktop with no icons. Display rotation is optional and off by
default. Targets **Raspberry Pi OS Trixie** (and Bookworm) on Pi 4 / Pi 5.

### Quick install (no rotation)

On the Pi:

```bash
curl -fsSL https://raw.githubusercontent.com/GTMichelli-Dev/Pi_Branding/main/setup-kiosk-display.sh | sudo bash
sudo reboot
```

No arguments needed — the script pulls `Michelli-Logo.png` from this repo
automatically and leaves the screen orientation untouched. It is a **one-shot
provisioning script**: run once, reboot once, branding is permanent. It does
not run on every boot.

Safer for a fleet — download, inspect, then run:

```bash
curl -fsSL https://raw.githubusercontent.com/GTMichelli-Dev/Pi_Branding/main/setup-kiosk-display.sh -o brand.sh
less brand.sh
sudo bash brand.sh
```

### What it changes

- **Boot logo** — clones the stock `pix` Plymouth theme into its own theme (`michelli`) and drops in the logo, so OS/package updates never overwrite it.
- **Boot background** — solid grey behind the logo.
- **Quiet boot** — removes the rainbow square (`disable_splash=1`), kernel text (`quiet`), corner Raspberry logos (`logo.nologo`), blinking cursor (`vt.global_cursor_default=0`), and screen blanking (`consoleblank=0`).
- **Desktop** — solid grey wallpaper with Home / Wastebasket / mounted-drive icons hidden (pcmanfm, under both labwc/Wayland and X11).
- **Rotation (optional, off by default)** — see below.

All edited boot files are backed up next to the original with a `.bak-<timestamp>` suffix.

### Arguments

```bash
sudo bash setup-kiosk-display.sh [logo] [theme] [rotate] [output] [panel_orientation] [boot_mode]
```

| # | Argument            | Default                            | Notes                                                                 |
|---|---------------------|------------------------------------|-----------------------------------------------------------------------|
| 1 | `logo`              | `Michelli-Logo.png` from this repo | Local path, any URL, or `""` to keep the current splash               |
| 2 | `theme`             | `michelli`                         | Name of the cloned Plymouth theme                                     |
| 3 | `rotate`            | *(none)*                           | DESKTOP rotation (kanshi): `normal` / `90` / `180` / `270`            |
| 4 | `output`            | `HDMI-A-1`                         | Wayland output name; use `DSI-1` for Touch Display 2                  |
| 5 | `panel_orientation` | *(none)*                           | BOOT/LOGO rotation (cmdline): `normal` / `left_side_up` / `right_side_up` / `upside_down` |
| 6 | `boot_mode`         | `720x1280M@60D`                    | Connector mode for the cmdline line (Touch Display 2 7"); only used with arg 5 |

`90` = 90° clockwise (i.e. rotated "right"). Leave args 3 and 5 empty to skip
rotation entirely.

### Rotation

Two independent layers:

- **Desktop** (arg 3, `rotate`) is rotated by kanshi — safe and reversible.
- **Boot / logo / console** (arg 5, `panel_orientation`) is rotated in `cmdline.txt`. On the Touch Display 2 this one usually rotates the *whole* stack (logo, console, desktop, touch). A bad `boot_mode` can black-screen the panel, so **test on one unit first**.

**Touch Display 2 ("rotate right") — test the boot layer alone first:**

```bash
curl -fsSL https://raw.githubusercontent.com/GTMichelli-Dev/Pi_Branding/main/setup-kiosk-display.sh | sudo bash -s -- "" michelli "" DSI-1 right_side_up
sudo reboot
```

After reboot, check logo, desktop, and touch:

- All three correct → that's your fleet command.
- Logo rotated but desktop still landscape → add the desktop knob: `... | sudo bash -s -- "" michelli 90 DSI-1 right_side_up`
- Rotated the wrong way → swap `right_side_up` for `left_side_up` (and `90` for `270`).
- Black screen → SSH in or edit the SD card, delete the `video=DSI-1:...` token from `/boot/firmware/cmdline.txt`. For a 5-inch panel or odd EDID, pass a different `boot_mode` as arg 6 (confirm with `wlr-randr` or `kmsprint -m`).

> Don't blindly set both arg 3 and arg 5: if `panel_orientation` already turns
> the desktop, adding a kanshi transform on top lands you 180° off.

### Examples

```bash
# No rotation (just branding):
curl -fsSL <raw-url>/setup-kiosk-display.sh | sudo bash

# Different theme name, default logo, no rotation:
curl -fsSL <raw-url>/setup-kiosk-display.sh | sudo bash -s -- "" jollyroger

# One-off local logo:
sudo bash setup-kiosk-display.sh /home/pi/other-logo.png
```

Grey shade is set near the top of the script: `GREY_HEX` for the desktop and
`GREY_R/G/B` (0–1) for the Plymouth background.

### Reverting

The stock `pix` theme is left untouched, so reverting is quick.

```bash
# 1) Restore the boot files from the timestamped backups
sudo cp /boot/firmware/config.txt.bak-*  /boot/firmware/config.txt
sudo cp /boot/firmware/cmdline.txt.bak-* /boot/firmware/cmdline.txt

# 2) Switch back to the stock splash and rebuild the initramfs
sudo plymouth-set-default-theme --rebuild-initrd pix
sudo rm -rf /usr/share/plymouth/themes/michelli   # optional: remove the clone

# 3) Restore the default desktop (icons + stock wallpaper)
rm -f ~/.config/pcmanfm/LXDE-pi/desktop-items-*.conf

# 4) If rotation was applied, remove it
rm -f ~/.config/kanshi/config        # desktop rotation

sudo reboot
```

With several backups, pick the specific timestamp instead of the `*` glob.

### Requirements

- Raspberry Pi OS Trixie or Bookworm (Pi 4 / Pi 5)
- `plymouth` and `plymouth-themes` (default on the desktop image)
- `curl` or `wget` on the device (to pull the logo)

### Files

- `setup-kiosk-display.sh` — the provisioning script
- `Michelli-Logo.png` — the boot logo