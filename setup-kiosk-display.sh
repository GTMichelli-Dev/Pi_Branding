#!/usr/bin/env bash
#
# setup-kiosk-display.sh   --   GTMichelli-Dev/Pi_Branding
# Brands a Raspberry Pi (OS Trixie / Bookworm, Pi 4/5) as a Michelli product.
#
# ONE-SHOT PROVISIONING. Run once with sudo; reboot once; done.
#
#   - Plymouth boot logo (Michelli) on a light-grey background, own cloned theme
#   - quiet boot: no rainbow, no kernel text, no corner logos, no cursor
#   - light-grey desktop with the Michelli logo centred, no icons
#   - Michelli "M" as the taskbar menu button; launcher buttons removed
#   - optional display rotation (desktop + boot splash)
#
# INTERACTIVE (prompts for display + rotation when you don't pass them):
#   curl -fsSL https://raw.githubusercontent.com/GTMichelli-Dev/Pi_Branding/main/setup-kiosk-display.sh | sudo bash
#
# NON-INTERACTIVE / fleet (pass everything, no prompts):
#   sudo bash setup-kiosk-display.sh [logo] [theme] [rotate] [output] [panel_orientation] [boot_mode] [menu_icon] [icon_theme]
#   e.g.  ... | sudo bash -s -- "" michelli 270 DSI-2 right_side_up
#
#   rotate            : desktop kanshi transform: normal|90|180|270   (Right == 270)
#   output            : Wayland output, e.g. DSI-1 DSI-2 HDMI-A-1
#   panel_orientation : boot/splash rotation: normal|left_side_up|right_side_up|upside_down
#
# Idempotent. Originals backed up with a timestamp. Reboot to apply.

set -euo pipefail

# -------- tunables ------------------------------------------------------------
REPO_RAW="https://raw.githubusercontent.com/GTMichelli-Dev/Pi_Branding/main"
LOGO_SRC="${1:-$REPO_RAW/Michelli-Logo.png}"   # local path, URL, or "" to skip
THEME_NAME="${2:-michelli}"                    # cloned plymouth theme name
ROTATE="${3:-}"                                # desktop kanshi: ""|normal|90|180|270
OUTPUT="${4:-}"                                 # Wayland output; prompts if empty
PANEL_ORIENT="${5:-}"                           # boot: ""|normal|left_side_up|right_side_up|upside_down
BOOT_MODE="${6:-720x1280M@60D}"                 # connector mode for the cmdline rotation line
MENU_SRC="${7:-$REPO_RAW/Michelli-Menu.png}"   # square taskbar menu icon, or "" to skip
ICON_THEME="${8:-PiXtrix}"                      # icon theme holding the 'start-here' menu icon
GREY_HEX="#aaaaaa"                              # desktop fill (light grey)
GREY_R="0.67"; GREY_G="0.67"; GREY_B="0.67"     # plymouth bg (light grey), 0-1
WALL_PATH="/usr/share/pixmaps/michelli-logo.png" # where the centred desktop logo is installed
THEMES="/usr/share/plymouth/themes"
SRC_THEME="$THEMES/pix"
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

# -------- interactive helpers -------------------------------------------------
detect_outputs() {
  local uid rt wd
  command -v wlr-randr >/dev/null 2>&1 || return 0
  uid="$(id -u "$TARGET_USER" 2>/dev/null)" || return 0
  rt="/run/user/$uid"
  for wd in "$rt"/wayland-*; do
    [ -S "$wd" ] || continue
    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="$rt" WAYLAND_DISPLAY="$(basename "$wd")" \
      wlr-randr 2>/dev/null | awk '/^[A-Za-z0-9]/{print $1}'
    return 0
  done
  return 0
}

prompt_output() {
  local detected list opt i n
  detected="$(detect_outputs 2>/dev/null || true)"
  if [ -n "$detected" ]; then
    list="$detected"
  else
    list="$(printf 'DSI-1\nDSI-2\nHDMI-A-1\nHDMI-A-2\n')"
  fi
  {
    echo ""
    echo "Available displays:"
    i=1
    while IFS= read -r opt; do
      [ -n "$opt" ] && { echo "  $i) $opt"; i=$((i+1)); }
    done <<EOT
$list
EOT
    printf "Select display [1]: "
  } > /dev/tty
  read -r n < /dev/tty || n=""
  n="${n:-1}"
  OUTPUT="$(printf '%s\n' "$list" | sed -n "${n}p")"
  [ -n "$OUTPUT" ] || OUTPUT="$(printf '%s\n' "$list" | sed -n '1p')"
  echo "  -> $OUTPUT" > /dev/tty
}

prompt_rotation() {
  local n
  {
    echo ""
    echo "Screen rotation:"
    echo "  1) Normal"
    echo "  2) Right    (90 clockwise)"
    echo "  3) Inverted (180)"
    echo "  4) Left     (90 counter-clockwise)"
    printf "Select rotation [1]: "
  } > /dev/tty
  read -r n < /dev/tty || n=""
  case "${n:-1}" in
    2) ROTATE=270;    PANEL_ORIENT=right_side_up ;;
    3) ROTATE=180;    PANEL_ORIENT=upside_down ;;
    4) ROTATE=90;     PANEL_ORIENT=left_side_up ;;
    *) ROTATE=normal; PANEL_ORIENT=normal ;;
  esac
  echo "  -> rotation selected" > /dev/tty
}

# Prompt for anything not supplied on the command line (needs a terminal).
if [ -z "$OUTPUT" ]; then
  if [ -e /dev/tty ]; then prompt_output; else OUTPUT="HDMI-A-1"; fi
fi
if [ -z "$ROTATE" ] && [ -z "$PANEL_ORIENT" ] && [ -e /dev/tty ]; then
  prompt_rotation
fi

case "$ROTATE" in
  ""|normal|90|180|270) ;;
  *) echo "ERROR: rotate must be one of: normal 90 180 270 (got '$ROTATE')." >&2; exit 1 ;;
esac
case "$PANEL_ORIENT" in
  ""|normal|left_side_up|right_side_up|upside_down) ;;
  *) echo "ERROR: panel_orientation invalid: '$PANEL_ORIENT'." >&2; exit 1 ;;
esac

echo "==> Boot dir:       $BOOT"
echo "==> Target user:    $TARGET_USER  (home: $USER_HOME)"
echo "==> Plymouth theme: $THEME_NAME"
echo "==> Output:         $OUTPUT"
[ -n "$ROTATE" ]       && echo "==> Desktop rotation: transform $ROTATE"
[ -n "$PANEL_ORIENT" ] && echo "==> Boot rotation:    panel_orientation=$PANEL_ORIENT"

# -----------------------------------------------------------------------------
# 0) Resolve the logo (download if URL); install a copy for the desktop wallpaper
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

if [ -n "$LOGO_PATH" ]; then
  install -D -m 0644 "$LOGO_PATH" "$WALL_PATH"
  WALL_MODE="center"; WALL_LINE="wallpaper=$WALL_PATH"
else
  WALL_MODE="color";  WALL_LINE=""
fi

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
sed -i "s#themes/pix#themes/$THEME_NAME#g; s/pix\.script/$THEME_NAME.script/g; s/^Name=.*/Name=$THEME_NAME/" \
       "$DST_THEME/$THEME_NAME.plymouth"
[ -n "$LOGO_PATH" ] && { echo "==> Installing logo into theme"; cp "$LOGO_PATH" "$DST_THEME/splash.png"; }

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
# 2) Quiet boot + optional boot/splash rotation (cmdline)
# -----------------------------------------------------------------------------
echo "==> Disabling rainbow splash in $CONFIG"
cp "$CONFIG" "$CONFIG.bak-$TS"
grep -q "^disable_splash=1" "$CONFIG" || echo "disable_splash=1" >> "$CONFIG"

echo "==> Updating kernel cmdline in $CMDLINE (kept single-line)"
cp "$CMDLINE" "$CMDLINE.bak-$TS"
read -r CMD < "$CMDLINE" || true   # cmdline.txt has no trailing newline; read returns 1 at EOF
for opt in quiet splash plymouth.ignore-serial-consoles logo.nologo vt.global_cursor_default=0 consoleblank=0; do
  case " $CMD " in *" $opt "*) ;; *) CMD="$CMD $opt" ;; esac
done
if [ -n "$PANEL_ORIENT" ]; then
  NEW=""
  for tok in $CMD; do
    case "$tok" in video=*panel_orientation=*) ;; *) NEW="${NEW:+$NEW }$tok" ;; esac
  done
  CMD="$NEW video=$OUTPUT:$BOOT_MODE,panel_orientation=$PANEL_ORIENT"
  echo "    NOTE: if the panel is black after reboot, remove the 'video=$OUTPUT:...'"
  echo "          token from $CMDLINE (via SSH or the SD card) to recover."
fi
printf '%s\n' "$CMD" > "$CMDLINE"

# -----------------------------------------------------------------------------
# 3) Desktop: light grey + centred logo, no icons (both pcmanfm profiles)
# -----------------------------------------------------------------------------
echo "==> Writing desktop config (profiles: default, LXDE-pi)"
write_desktop_conf() {
  cat > "$1" <<EOF
[*]
wallpaper_mode=$WALL_MODE
$WALL_LINE
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
for prof in default LXDE-pi; do
  DCONF_DIR="$USER_HOME/.config/pcmanfm/$prof"
  mkdir -p "$DCONF_DIR"
  for f in desktop-items-0.conf desktop-items-HDMI-A-1.conf desktop-items-HDMI-A-2.conf desktop-items-DSI-1.conf desktop-items-DSI-2.conf "desktop-items-$OUTPUT.conf"; do
    write_desktop_conf "$DCONF_DIR/$f"
  done
done
chown -R "$TARGET_USER":"$TARGET_USER" "$USER_HOME/.config/pcmanfm"

# -----------------------------------------------------------------------------
# 4) Desktop rotation (kanshi)
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

# -----------------------------------------------------------------------------
# 5) Taskbar: rebrand menu button + remove launcher buttons
# -----------------------------------------------------------------------------
MENU_PATH=""
case "$MENU_SRC" in
  "") echo "==> No menu icon specified; leaving menu button as-is" ;;
  http://*|https://*)
    MENU_PATH="$(mktemp /tmp/pi-menu.XXXXXX.png)"
    echo "==> Downloading menu icon: $MENU_SRC"
    if command -v curl >/dev/null 2>&1; then curl -fsSL "$MENU_SRC" -o "$MENU_PATH" || true
    elif command -v wget >/dev/null 2>&1; then wget -qO "$MENU_PATH" "$MENU_SRC" || true; fi
    if [ ! -s "$MENU_PATH" ]; then
      echo "    (menu icon not found at $MENU_SRC -- skipping icon, still removing launchers)"
      rm -f "$MENU_PATH"; MENU_PATH=""
    fi
    ;;
  *) if [ -f "$MENU_SRC" ]; then MENU_PATH="$MENU_SRC"; else echo "    (menu icon '$MENU_SRC' not found; skipping)"; fi ;;
esac

ICON_BASE="/usr/share/icons/$ICON_THEME"
if [ -n "$MENU_PATH" ] && [ -d "$ICON_BASE" ]; then
  echo "==> Rebranding menu icon (start-here) in $ICON_THEME"
  while IFS= read -r f; do
    [ -f "$f.orig" ] || cp "$f" "$f.orig"
    cp "$MENU_PATH" "$f"
  done < <(find "$ICON_BASE" -path '*places/start-here.png')
  SVG="$ICON_BASE/scalable/places/start-here.svg"
  if [ -f "$SVG" ] && [ ! -f "$SVG.orig" ]; then mv "$SVG" "$SVG.orig"; fi
  command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -f "$ICON_BASE" 2>/dev/null || true
elif [ -n "$MENU_PATH" ]; then
  echo "    (icon theme dir $ICON_BASE not found -- check ICON_THEME; skipping icon)"
fi
case "$MENU_SRC" in http://*|https://*) [ -n "$MENU_PATH" ] && rm -f "$MENU_PATH" ;; esac

DEF_PANEL="/etc/xdg/wf-panel-pi/wf-panel-pi.ini"
UPANEL="$USER_HOME/.config/wf-panel-pi.ini"
echo "==> Writing panel config (launchers removed) to $UPANEL"
mkdir -p "$USER_HOME/.config"
if [ -f "$DEF_PANEL" ]; then cp "$DEF_PANEL" "$UPANEL"
else printf '[panel]\nwidgets_left=smenu spacing4 window-list\nwidgets_center=\nposition=top\nicon_size=32\nwindow-list_max_width=200\n' > "$UPANEL"; fi
sed -i 's/^launchers=.*/launchers=/' "$UPANEL"
sed -i '/^widgets_left=/ s/ launchers / /' "$UPANEL"
chown "$TARGET_USER":"$TARGET_USER" "$UPANEL"

echo
echo "Done. Config backups tagged .bak-$TS"
echo "Reboot once to apply:  sudo reboot"