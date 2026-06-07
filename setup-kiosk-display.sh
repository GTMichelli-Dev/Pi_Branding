#!/usr/bin/env bash
#
# setup-kiosk-display.sh   --   GTMichelli-Dev/Pi_Branding
# Brands a Raspberry Pi (OS Trixie / Bookworm, Pi 4/5) as a Michelli product.
#
# ONE-SHOT PROVISIONING. Run once with sudo; reboot once; done.
#
#   - custom Plymouth boot logo on a grey background (own cloned theme,
#     so apt/package updates never overwrite it)
#   - quiet boot: no rainbow square, no kernel text, no corner logos, no cursor
#   - grey solid desktop background, no icons (pcmanfm; labwc/Wayland + X11)
#   - OPTIONAL display rotation (off by default), two independent knobs:
#       * desktop   -> kanshi transform   (safe, reversible)
#       * boot/logo -> cmdline panel_orientation (rotates the whole stack;
#                      TEST ON ONE UNIT FIRST -- a bad mode black-screens it)
#
# Run from the repo (logo pulled automatically):
#   curl -fsSL https://raw.githubusercontent.com/GTMichelli-Dev/Pi_Branding/main/setup-kiosk-display.sh | sudo bash
#
# Full arg list:
#   sudo bash setup-kiosk-display.sh [logo] [theme] [rotate] [output] [panel_orientation] [boot_mode]
#     rotate            : kanshi transform for the DESKTOP: ""(skip)|normal|90|180|270
#     output            : Wayland output name. HDMI-A-1 (default) or DSI-1 for Touch Display 2
#     panel_orientation : rotate BOOT/LOGO layer via cmdline: ""(skip)|normal|left_side_up|right_side_up|upside_down
#     boot_mode         : connector mode for the cmdline line (default 720x1280M@60D = Touch Display 2 7")
#
#   Touch Display 2, "rotate right" -- test the boot layer alone first:
#     curl -fsSL <raw-url>/setup-kiosk-display.sh | sudo bash -s -- "" michelli "" DSI-1 right_side_up
#   If the DESKTOP didn't follow, re-run adding the desktop transform:
#     ... | sudo bash -s -- "" michelli 90 DSI-1 right_side_up
#
# Idempotent. Originals backed up with a timestamp. Reboot to apply.

set -euo pipefail

# -------- tunables ------------------------------------------------------------
REPO_RAW="https://raw.githubusercontent.com/GTMichelli-Dev/Pi_Branding/main"
LOGO_SRC="${1:-$REPO_RAW/Michelli-Logo.png}"   # local path, URL, or "" to skip
THEME_NAME="${2:-michelli}"                    # cloned plymouth theme name
ROTATE="${3:-}"                                # desktop kanshi: ""|normal|90|180|270
OUTPUT="${4:-HDMI-A-1}"                         # Wayland output (DSI-1 for Touch Display 2)
PANEL_ORIENT="${5:-}"                           # boot layer: ""|normal|left_side_up|right_side_up|upside_down
BOOT_MODE="${6:-720x1280M@60D}"                 # connector mode used only when PANEL_ORIENT is set
GREY_HEX="#808080"                             # desktop solid fill (hex)
GREY_R="0.50"; GREY_G="0.50"; GREY_B="0.50"    # plymouth bg, normalized 0-1
THEMES="/usr/share/plymouth/themes"
SRC_THEME="$THEMES/pix"
# ------------------------------------------------------------------------------

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: run with sudo (needs root for boot files, themes, initramfs)." >&2
  exit 1
fi

case "$ROTATE" in
  ""|normal|90|180|270) ;;
  *) echo "ERROR: rotate must be one of: normal 90 180 270 (got '$ROTATE')." >&2; exit 1 ;;
esac
case "$PANEL_ORIENT" in
  ""|normal|left_side_up|right_side_up|upside_down) ;;
  *) echo "ERROR: panel_orientation must be one of: normal left_side_up right_side_up upside_down." >&2; exit 1 ;;
esac

TARGET_USER="${SUDO_USER:-pi}"
USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TS="$(date +%Y%m%d-%H%M%S)"
DST_THEME="$THEMES/$THEME_NAME"

if [ -f /boot/firmware/config.txt ]; then BOOT="/boot/firmware"; else BOOT="/boot"; fi
CONFIG="$BOOT/config.txt"
CMDLINE="$BOOT/cmdline.txt"

echo "==> Boot dir:       $BOOT"
echo "==> Target user:    $TARGET_USER  (home: $USER_HOME)"
echo "==> Plymouth theme: $THEME_NAME"
[ -n "$ROTATE" ]       && echo "==> Desktop rotation: $OUTPUT transform $ROTATE"
[ -n "$PANEL_ORIENT" ] && echo "==> Boot rotation:    video=$OUTPUT:$BOOT_MODE,panel_orientation=$PANEL_ORIENT"

# -----------------------------------------------------------------------------
# 0) Resolve the logo (download if it's a URL)
# -----------------------------------------------------------------------------
LOGO_PATH=""; CLEANUP_LOGO=""
trap '[ -n "$CLEANUP_LOGO" ] && rm -f "$CLEANUP_LOGO"' EXIT
case "$LOGO_SRC" in
  "") echo "==> No logo specified; keeping current splash image" ;;
  http://*|https://*)
    LOGO_PATH="$(mktemp /tmp/pi-logo.XXXXXX.png)"; CLEANUP_LOGO="$LOGO_PATH"
    echo "==> Downloading logo: $LOGO_SRC"
    if command -v curl >/dev/null 2>&1; then curl -fsSL "$LOGO_SRC" -o "$LOGO_PATH"
    elif command -v wget >/dev/null 2>&1; then wget -qO "$LOGO_PATH" "$LOGO_SRC"
    else echo "ERROR: need curl or wget to fetch the logo URL." >&2; exit 1; fi
    [ -s "$LOGO_PATH" ] || { echo "ERROR: downloaded logo is empty." >&2; exit 1; }
    ;;
  *) [ -f "$LOGO_SRC" ] || { echo "ERROR: logo '$LOGO_SRC' not found." >&2; exit 1; }; LOGO_PATH="$LOGO_SRC" ;;
esac

# -----------------------------------------------------------------------------
# 1) Clone the stock theme -> our own (survives package updates)
# -----------------------------------------------------------------------------
if [ ! -d "$SRC_THEME" ]; then
  echo "ERROR: stock 'pix' theme not found at $SRC_THEME." >&2
  echo "       Install with: sudo apt install plymouth plymouth-themes" >&2
  exit 1
fi
echo "==> Cloning $SRC_THEME -> $DST_THEME"
rm -rf "$DST_THEME"; cp -a "$SRC_THEME" "$DST_THEME"
mv "$DST_THEME/pix.plymouth" "$DST_THEME/$THEME_NAME.plymouth"
mv "$DST_THEME/pix.script"   "$DST_THEME/$THEME_NAME.script"
sed -i "s#/themes/pix/#/themes/$THEME_NAME/#g; s/pix\.script/$THEME_NAME.script/g; s/^Name=.*/Name=$THEME_NAME/" \
       "$DST_THEME/$THEME_NAME.plymouth"
if [ -n "$LOGO_PATH" ]; then echo "==> Installing logo into theme"; cp "$LOGO_PATH" "$DST_THEME/splash.png"; fi

echo "==> Setting Plymouth background to grey ($GREY_R, $GREY_G, $GREY_B)"
if grep -q "SetBackgroundTopColor" "$DST_THEME/$THEME_NAME.script"; then
  sed -i "s/Window\.SetBackgroundTopColor([^)]*)/Window.SetBackgroundTopColor($GREY_R, $GREY_G, $GREY_B)/" "$DST_THEME/$THEME_NAME.script"
  sed -i "s/Window\.SetBackgroundBottomColor([^)]*)/Window.SetBackgroundBottomColor($GREY_R, $GREY_G, $GREY_B)/" "$DST_THEME/$THEME_NAME.script"
else
  sed -i "1a Window.SetBackgroundTopColor($GREY_R, $GREY_G, $GREY_B);\nWindow.SetBackgroundBottomColor($GREY_R, $GREY_G, $GREY_B);" "$DST_THEME/$THEME_NAME.script"
fi
echo "==> Selecting theme and rebuilding initramfs"
plymouth-set-default-theme --rebuild-initrd "$THEME_NAME"

# -----------------------------------------------------------------------------
# 2) Quiet boot
# -----------------------------------------------------------------------------
echo "==> Disabling rainbow splash in $CONFIG"
cp "$CONFIG" "$CONFIG.bak-$TS"
grep -q "^disable_splash=1" "$CONFIG" || echo "disable_splash=1" >> "$CONFIG"

echo "==> Updating kernel cmdline in $CMDLINE (kept single-line)"
cp "$CMDLINE" "$CMDLINE.bak-$TS"
read -r CMD < "$CMDLINE" || true   # cmdline.txt has no trailing newline; read returns 1 at EOF, which would trip set -e
for opt in quiet splash plymouth.ignore-serial-consoles logo.nologo vt.global_cursor_default=0 consoleblank=0; do
  case " $CMD " in *" $opt "*) ;; *) CMD="$CMD $opt" ;; esac
done

# 2b) Boot/logo rotation (cmdline panel_orientation) -- only if requested
if [ -n "$PANEL_ORIENT" ]; then
  # strip any previous video=<OUTPUT>:... token, then append a fresh one
  NEW=""
  for tok in $CMD; do
    case "$tok" in video=$OUTPUT:*) ;; *) NEW="${NEW:+$NEW }$tok" ;; esac
  done
  CMD="$NEW video=$OUTPUT:$BOOT_MODE,panel_orientation=$PANEL_ORIENT"
  echo "    NOTE: if the panel is black after reboot, remove the 'video=$OUTPUT:...'"
  echo "          token from $CMDLINE (via SSH or the SD card) to recover."
fi
printf '%s\n' "$CMD" > "$CMDLINE"

# -----------------------------------------------------------------------------
# 3) Grey desktop, no icons
# -----------------------------------------------------------------------------
DCONF_DIR="$USER_HOME/.config/pcmanfm/LXDE-pi"
echo "==> Writing desktop config to $DCONF_DIR"
mkdir -p "$DCONF_DIR"
write_desktop_conf() {
  cat > "$1" <<EOF
[*]
wallpaper_mode=color
wallpaper_common=1
desktop_bg=$GREY_HEX
desktop_fg=#ffffff
desktop_shadow=#000000
show_wm_menu=0
show_documents=0
show_trash=0
show_mounts=0
EOF
}
for f in desktop-items-0.conf desktop-items-HDMI-A-1.conf desktop-items-HDMI-A-2.conf desktop-items-DSI-1.conf desktop-items-DSI-2.conf "desktop-items-$OUTPUT.conf"; do
  write_desktop_conf "$DCONF_DIR/$f"
done
chown -R "$TARGET_USER":"$TARGET_USER" "$USER_HOME/.config/pcmanfm"

# -----------------------------------------------------------------------------
# 4) Desktop rotation (kanshi) -- only if requested
# -----------------------------------------------------------------------------
if [ -n "$ROTATE" ]; then
  KDIR="$USER_HOME/.config/kanshi"
  echo "==> Writing desktop rotation to $KDIR/config"
  mkdir -p "$KDIR"
  [ -f "$KDIR/config" ] && cp "$KDIR/config" "$KDIR/config.bak-$TS"
  cat > "$KDIR/config" <<EOF
profile {
    output $OUTPUT enable transform $ROTATE
}
EOF
  chown -R "$TARGET_USER":"$TARGET_USER" "$KDIR"
fi

echo
echo "Done. Config backups tagged .bak-$TS"
echo "Reboot once to apply:  sudo reboot"