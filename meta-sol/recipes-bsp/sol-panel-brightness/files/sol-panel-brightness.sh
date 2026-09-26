#!/bin/sh
# Tell userspace the truth about this panel's brightness range.
#
# THE PROBLEM. sol's panel packs TWO values into one backlight number. From the
# display driver's setter:
#
#     /* We put NBM brightness at lower 16 bits and AOD brightness at higher 16 bits */
#     bl_lvl      = brightness & 0xFFFF;
#     doze_bl_lvl = (brightness >> 16) & 0xFFFF;
#
# so qcom,mdss-brightness-max-level = 0xFF01FF means "normal brightness up to
# 0x1FF, AOD up to 0xFF" -- NOT "brightness goes up to 16712191". The driver
# advertises that number verbatim as max_brightness, and anything that scales a
# percentage against it puts most of the value in the AOD half. Measured:
#
#     writing 511      -> nbm: 511,   aod: 0     (plain values are fine)
#     writing 1671219  -> nbm: 32819, aod: 25    (mce's "10%")
#
# which is why brightness jumped around instead of following the setting, and why
# raising it past half made the screen DIMMER.
#
# THE FIX. Bind-mount a file containing just the normal-brightness maximum over
# the sysfs attribute, before anything reads it. mce then scales percentages onto
# the real range and never touches the AOD field:
#
#     10% -> nbm 51    30% -> nbm 153    50% -> nbm 255
#     70% -> nbm 357  100% -> nbm 511          aod 0 throughout
#
# WHY NOT FIX THE DRIVER. Because this port cannot: sol loads the stock
# msm_drm.ko from the Android vendor_dlkm image, not the copy linux-sol-modules
# builds. A two-line patch there was written, built, flashed and had no effect --
# the module it changes is never loaded. See
# .investigation-logs/20260819_sol_brightness_and_display_module.md
#
# WHY NOT FIX MCE. It would work -- mce reads max_brightness from sysfs with no
# override -- but mce is shared by every watch in the fleet, and this is a
# property of one panel. A device-local mount is the smaller, safer change.
set -u

BL=/sys/class/backlight/panel0-backlight/max_brightness
OUT=/run/sol-panel-max-brightness

[ -e "$BL" ] || { echo "sol-panel-brightness: $BL absent, nothing to correct"; exit 0; }

raw=$(cat "$BL" 2>/dev/null)
case "$raw" in
    ''|*[!0-9]*) echo "sol-panel-brightness: '$raw' is not a number, leaving it alone"; exit 0 ;;
esac

# The normal-brightness maximum is the low 16 bits; anything above that is the
# AOD field. If the panel already advertises a plain value there is nothing to do.
nbm=$((raw & 0xFFFF))
if [ "$nbm" -eq "$raw" ]; then
    echo "sol-panel-brightness: max_brightness=$raw is already a plain value"
    exit 0
fi

echo "$nbm" > "$OUT"
chmod 0444 "$OUT"
if mount --bind "$OUT" "$BL" 2>/dev/null; then
    echo "sol-panel-brightness: max_brightness $raw -> $(cat "$BL") (normal-brightness range only)"
else
    echo "sol-panel-brightness: could not bind $OUT over $BL"
fi
