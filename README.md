# Pi_Branding

Brands a Raspberry Pi as a Michelli appliance: Michelli boot splash, quiet boot, a light-grey desktop with the logo centred and no icons, the Michelli "M" as the taskbar menu button, no launcher buttons, and optional screen rotation. Targets **Raspberry Pi OS Trixie** (and Bookworm) on Pi 4 / Pi 5.

### Quick start

On the Pi — interactive (prompts for display and rotation):

```bash
curl -fsSL https://raw.githubusercontent.com/GTMichelli-Dev/Pi_Branding/main/setup-kiosk-display.sh | sudo bash
sudo reboot
```

That's it. Run once, answer the two prompts, reboot once — the branding is permanent. The script does **not** run on every boot.

### What it does

- **Boot splash** — clones the stock `pix` Plymouth theme into its own `michelli` theme (so OS updates don't overwrite it), shows the Michelli logo on light grey.
- **Quiet boot** — removes the rainbow square, kernel text, corner Raspberry logos, blinking cursor, and screen blanking.
- **Desktop** — light-grey wallpaper with the Michelli logo centred, and Home / Wastebasket / drive icons hidden.
- **Taskbar** — the menu button becomes the Michelli "M"; the browser / file-manager / terminal launcher buttons are removed (clock, wifi, tray stay).
- **Rotation (optional)** — rotates the desktop (kanshi) and the boot splash (cmdline) together.

All edited boot files are backed up next to the original as `*.bak-<timestamp>`; replaced theme icons are backed up as `*.orig`.

### The prompts

When you don't pass arguments, it asks two things:

- **Display** — a numbered list of outputs (auto-detected, or `DSI-1 / DSI-2 / HDMI-A-1 / HDMI-A-2`). For the Touch Display 2 this is usually `DSI-2`.
- **Rotation** — `1) Normal  2) Right (90 clockwise)  3) Inverted (180)  4) Left`. Picking a direction sets both the desktop and the boot-splash rotation correctly.

### Non-interactive / fleet

Pass everything to skip the prompts (good for scripted rollout):

```bash
sudo bash setup-kiosk-display.sh [logo] [theme] [rotate] [output] [panel_orientation] [boot_mode] [menu_icon] [icon_theme]
```

Touch Display 2, rotated right, no prompts:

```bash
curl -fsSL https://raw.githubusercontent.com/GTMichelli-Dev/Pi_Branding/main/setup-kiosk-display.sh | sudo bash -s -- "" michelli 270 DSI-2 right_side_up
```

| # | Argument            | Default                          | Notes                                                            |
|---|---------------------|----------------------------------|------------------------------------------------------------------|
| 1 | `logo`              | `Michelli-Logo.png` (repo)       | Local path, URL, or `""` to keep current splash                  |
| 2 | `theme`             | `michelli`                       | Cloned Plymouth theme name                                       |
| 3 | `rotate`            | *(prompt)*                       | Desktop transform: `normal` `90` `180` `270` — **Right = 270**   |
| 4 | `output`            | *(prompt)*                       | Wayland output, e.g. `DSI-2`                                     |
| 5 | `panel_orientation` | *(prompt)*                       | Boot/splash: `normal` `left_side_up` `right_side_up` `upside_down` |
| 6 | `boot_mode`         | `720x1280M@60D`                  | Connector mode for the rotation line (Touch Display 2 7")        |
| 7 | `menu_icon`         | `Michelli-Menu.png` (repo)       | Square taskbar menu icon, or `""` to skip                        |
| 8 | `icon_theme`        | `PiXtrix`                        | Icon theme that holds the `start-here` menu icon                 |
| 9 | `desktop_logo`      | `Michelli-Desktop.png` (repo)    | Larger logo centred on the desktop; `""` falls back to the splash logo |

> "Right" is 90° clockwise; the desktop expresses it as kanshi transform **270** and the boot splash as `right_side_up`.

### Reverting

```bash
# boot files
sudo cp /boot/firmware/config.txt.bak-*  /boot/firmware/config.txt
sudo cp /boot/firmware/cmdline.txt.bak-* /boot/firmware/cmdline.txt

# boot splash back to stock
sudo plymouth-set-default-theme --rebuild-initrd pix
sudo rm -rf /usr/share/plymouth/themes/michelli

# desktop + rotation
rm -f ~/.config/pcmanfm/default/desktop-items-*.conf ~/.config/pcmanfm/LXDE-pi/desktop-items-*.conf
rm -f ~/.config/kanshi/config
rm -f ~/.config/wf-panel-pi.ini

# taskbar menu icon back to stock
for f in /usr/share/icons/PiXtrix/*/places/start-here.png.orig; do sudo mv "$f" "${f%.orig}"; done
sudo mv /usr/share/icons/PiXtrix/scalable/places/start-here.svg.orig \
        /usr/share/icons/PiXtrix/scalable/places/start-here.svg 2>/dev/null
sudo gtk-update-icon-cache -f /usr/share/icons/PiXtrix

sudo reboot
```

With several timestamped backups, pick the specific one instead of the `*` glob.

### Notes

- The display connector (`DSI-1` vs `DSI-2`) depends on which port the panel uses; run `wlr-randr` to confirm, or standardise the port across the fleet.
- The Michelli menu icon and the desktop logo replace files inside the `PiXtrix` icon theme and `/usr/share/pixmaps`; a theme package update could overwrite them — re-running the script restores everything (originals are kept as `*.orig`).
- On Pi 5 with a DSI panel, the bootloader can't drive the display, so the first thing the panel shows is the Michelli Plymouth splash — there's no earlier logo to change.

### Requirements

- Raspberry Pi OS Trixie or Bookworm (Pi 4 / Pi 5)
- `plymouth` and `plymouth-themes`
- `curl` or `wget` on the device

### Files

- `setup-kiosk-display.sh` — the provisioning script
- `Michelli-Logo.png` — boot splash logo
- `Michelli-Desktop.png` — larger logo centred on the desktop
- `Michelli-Menu.png` — taskbar menu-button icon
