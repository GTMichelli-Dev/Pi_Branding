# \# Pi\_Branding

# 

# Brands a Raspberry Pi as a Michelli product: replaces the boot splash with the

# Michelli logo on a grey background, silences the boot sequence, and presents a

# clean grey desktop with no icons.

# 

# Targets \*\*Raspberry Pi OS Trixie\*\* (and Bookworm) on Pi 4 / Pi 5.

# 

# \## Quick install

# 

# On the Pi:

# 

# ```bash

# curl -fsSL https://raw.githubusercontent.com/GTMichelli-Dev/Pi\_Branding/main/setup-kiosk-display.sh | sudo bash

# sudo reboot

# ```

# 

# No arguments are needed — the script pulls `Michelli-Logo.png` from this repo

# automatically. It is a \*\*one-shot provisioning script\*\*: run once, reboot once,

# and the branding is permanent. It does not run on every boot.

# 

# > Safer for a fleet: download, inspect, then run.

# > ```bash

# > curl -fsSL https://raw.githubusercontent.com/GTMichelli-Dev/Pi\_Branding/main/setup-kiosk-display.sh -o brand.sh

# > less brand.sh

# > sudo bash brand.sh

# > ```

# 

# \## What it changes

# 

# \- \*\*Boot logo\*\* — clones the stock `pix` Plymouth theme into its own theme

# &#x20; (`michelli`) and drops in the logo, so package/OS updates never overwrite it.

# \- \*\*Boot background\*\* — solid grey behind the logo.

# \- \*\*Quiet boot\*\* — removes the rainbow test square (`disable\_splash=1`), kernel

# &#x20; console text (`quiet`), the corner Raspberry logos (`logo.nologo`), the

# &#x20; blinking cursor (`vt.global\_cursor\_default=0`), and screen blanking

# &#x20; (`consoleblank=0`).

# \- \*\*Desktop\*\* — solid grey wallpaper, with Home / Wastebasket / mounted-drive

# &#x20; icons hidden (pcmanfm, under both the labwc/Wayland session and X11).

# 

# All edited boot files are backed up next to the original with a `.bak-<timestamp>`

# suffix.

# 

# \## Options

# 

# ```bash

# sudo bash setup-kiosk-display.sh \[logo\_path\_or\_URL] \[theme\_name]

# ```

# 

# | Argument     | Default                          | Notes                                   |

# |--------------|----------------------------------|-----------------------------------------|

# | `logo`       | `Michelli-Logo.png` from this repo | Local path, any URL, or `""` to keep the current splash |

# | `theme\_name` | `michelli`                       | Name of the cloned Plymouth theme       |

# 

# Examples:

# 

# ```bash

# \# Different theme name, default logo:

# curl -fsSL <raw-url>/setup-kiosk-display.sh | sudo bash -s -- "" jollyroger

# 

# \# One-off local logo:

# sudo bash setup-kiosk-display.sh /home/pi/other-logo.png

# ```

# 

# Grey shade is set near the top of the script: `GREY\_HEX` for the desktop and

# `GREY\_R/G/B` (0–1) for the Plymouth background.

# 

# \## Reverting

# 

# The script leaves the stock `pix` theme untouched, so reverting is quick.

# 

# ```bash

# \# 1) Restore the boot files from the timestamped backups

# sudo cp /boot/firmware/config.txt.bak-\*  /boot/firmware/config.txt

# sudo cp /boot/firmware/cmdline.txt.bak-\* /boot/firmware/cmdline.txt

# 

# \# 2) Switch back to the stock splash and rebuild the initramfs

# sudo plymouth-set-default-theme --rebuild-initrd pix

# sudo rm -rf /usr/share/plymouth/themes/michelli   # optional: remove the clone

# 

# \# 3) Restore the default desktop (icons + stock wallpaper)

# rm -f \~/.config/pcmanfm/LXDE-pi/desktop-items-\*.conf

# 

# sudo reboot

# ```

# 

# If you have several backups, pick the specific timestamp you want instead of the

# `\*` glob.

# 

# \## Requirements

# 

# \- Raspberry Pi OS Trixie or Bookworm (Pi 4 / Pi 5)

# \- `plymouth` and `plymouth-themes` installed (default on the desktop image)

# \- `curl` or `wget` on the device (for pulling the logo)

# 

# \## Files

# 

# \- `setup-kiosk-display.sh` — the provisioning script

# \- `Michelli-Logo.png` — the boot logo

