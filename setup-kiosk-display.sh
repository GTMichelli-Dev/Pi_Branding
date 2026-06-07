#!/usr/bin/env bash
#
# setup-kiosk-display.sh   --   GTMichelli-Dev/Pi_Branding
# Brands a Raspberry Pi (OS Trixie / Bookworm, Pi 4/5) as a Michelli product.
#
# ONE-SHOT PROVISIONING. Run once with sudo; reboot once; done.
# It writes config, rebuilds the initramfs, and the NEXT reboot shows the
# result permanently. It does not run at every boot.
#
#   - custom Plymouth boot logo on a grey background (own cloned theme,
#     so apt/package updates never overwrite it)
#   - quiet boot: no rainbow square, no kernel text, no corner logos, no cursor
#   - grey solid desktop background, no icons (pcmanfm; labwc/Wayland + X11)
#
# Call it straight from the repo (logo pulled from the repo automatically):
#   curl -fsSL https://raw.githubusercontent.com/GTMichelli-Dev/Pi_Branding/main/setup-kiosk-display.sh | sudo bash
#
# Or with overrides:
#   sudo bash setup-kiosk-display.sh [logo_path_or_URL] [theme_name]
#
# Idempotent. Originals backed up with a timestamp. Reboot to apply.

set -euo pipefail

# -------- tunables ------------------------------------------------------------
REPO_RAW="https://raw.githubusercontent.com/GTMichelli-Dev/Pi_Branding/main"
LOGO_SRC="${1:-$REPO_RAW/Michelli-Logo.png}"   # local path, URL, or "" to skip
THEME_NAME="${2:-michelli}"                    # cloned plymouth theme name
GREY_HEX="#808080"                             # desktop solid fill (hex)
GREY_R="0.50"; GREY_G="0.50"; GREY_B="0.50"    # plymouth bg, normalized 0-1
THEMES="/usr/share/plymouth/themes"
SRC_THEME="$THEMES/pix"                         # stock Raspberry theme to clone
# ------------------------------------------------------------------------------

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: run with sudo (needs root for boot files, themes, initramfs)." >&2
  exit 1
fi

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

# -----------------------------------------------------------------------------
# 0) Resolve the logo (download if it's a URL)
# -----------------------------------------------------------------------------
LOGO_PATH=""
CLEANUP_LOGO=""
trap '[ -n "$CLEANUP_LOGO" ] && rm -f "$CLEANUP_LOGO"' EXIT

case "$LOGO_SRC" in
  "")
    echo "==> No logo specified; keeping current splash image"
    ;;
  http://*|https://*)
    LOGO_PATH="$(mktemp /tmp/pi-logo.XXXXXX.png)"
    CLEANUP_LOGO="$LOGO_PATH"
    echo "==> Downloading logo: $LOGO_SRC"
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL "$LOGO_SRC" -o "$LOGO_PATH"
    elif command -v wget >/dev/null 2>&1; then
      wget -qO "$LOGO_PATH" "$LOGO_SRC"
    else
      echo "ERROR: need curl or wget to fetch the logo URL." >&2; exit 1
    fi
    [ -s "$LOGO_PATH" ] || { echo "ERROR: downloaded logo is empty." >&2; exit 1; }
    ;;
  *)
    [ -f "$LOGO_SRC" ] || { echo "ERROR: logo '$LOGO_SRC' not found." >&2; exit 1; }
    LOGO_PATH="$LOGO_SRC"
    ;;
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
rm -rf "$DST_THEME"
cp -a "$SRC_THEME" "$DST_THEME"
mv "$DST_THEME/pix.plymouth" "$DST_THEME/$THEME_NAME.plymouth"
mv "$DST_THEME/pix.script"   "$DST_THEME/$THEME_NAME.script"
sed -i "s#/themes/pix/#/themes/$THEME_NAME/#g; s/pix\.script/$THEME_NAME.script/g; s/^Name=.*/Name=$THEME_NAME/" \
       "$DST_THEME/$THEME_NAME.plymouth"

if [ -n "$LOGO_PATH" ]; then
  echo "==> Installing logo into theme"
  cp "$LOGO_PATH" "$DST_THEME/splash.png"
fi

echo "==> Setting Plymouth background to grey ($GREY_R, $GREY_G, $GREY_B)"
if grep -q "SetBackgroundTopColor" "$DST_THEME/$THEME_NAME.script"; then
  sed -i "s/Window\.SetBackgroundTopColor([^)]*)/Window.SetBackgroundTopColor($GREY_R, $GREY_G, $GREY_B)/" \
         "$DST_THEME/$THEME_NAME.script"
  sed -i "s/Window\.SetBackgroundBottomColor([^)]*)/Window.SetBackgroundBottomColor($GREY_R, $GREY_G, $GREY_B)/" \
         "$DST_THEME/$THEME_NAME.script"
else
  sed -i "1a Window.SetBackgroundTopColor($GREY_R, $GREY_G, $GREY_B);\nWindow.SetBackgroundBottomColor($GREY_R, $GREY_G, $GREY_B);" \
         "$DST_THEME/$THEME_NAME.script"
fi

echo "==> Selecting theme and rebuilding initramfs"
plymouth-set-default-theme --rebuild-initrd "$THEME_NAME"

# -----------------------------------------------------------------------------
# 2) Quiet boot: kill rainbow, kernel text, corner logos, blinking cursor
# -----------------------------------------------------------------------------
echo "==> Disabling rainbow splash in $CONFIG"
cp "$CONFIG" "$CONFIG.bak-$TS"
grep -q "^disable_splash=1" "$CONFIG" || echo "disable_splash=1" >> "$CONFIG"

echo "==> Updating kernel cmdline in $CMDLINE (kept single-line)"
cp "$CMDLINE" "$CMDLINE.bak-$TS"
read -r CMD < "$CMDLINE"
for opt in quiet splash plymouth.ignore-serial-consoles logo.nologo vt.global_cursor_default=0 consoleblank=0; do
  case " $CMD " in *" $opt "*) ;; *) CMD="$CMD $opt" ;; esac
done
printf '%s\n' "$CMD" > "$CMDLINE"

# -----------------------------------------------------------------------------
# 3) Grey desktop, no icons (pcmanfm; applies under labwc/Wayland + X11)
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
for f in desktop-items-0.conf desktop-items-HDMI-A-1.conf desktop-items-HDMI-A-2.conf; do
  write_desktop_conf "$DCONF_DIR/$f"
done
chown -R "$TARGET_USER":"$TARGET_USER" "$USER_HOME/.config/pcmanfm"

echo
echo "Done. Config backups tagged .bak-$TS"
echo "Reboot once to apply:  sudo reboot"