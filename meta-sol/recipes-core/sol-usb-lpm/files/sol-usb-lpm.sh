#!/bin/sh
# Let msm-dwc3 reach low power mode when there is genuinely no cable, so the SoC
# can suspend, without giving up the gadget recovery that needs the opposite.
#
# THE CONFLICT THIS RESOLVES
#
# soc:google,extcon-usb-shim ships with spoof_connected=1: it reports a cable
# permanently attached whatever the PMIC says. Two consequences pull in opposite
# directions.
#
#   Keeping it 1 means every suspend attempt aborts --
#       msm-dwc3 4e00000.hsusb: Abort PM suspend!! (USB is outside LPM)
#       suspend_stats: last_failed_dev=4e00000.hsusb  errno=-16
#   -- because a controller that believes a host is attached never goes idle.
#   With CONFIG_PM_AUTOSLEEP now enabled this is the single remaining thing
#   between sol and actually sleeping.
#
#   Clearing it permanently breaks the way back in. sol has a VBUS one-way door:
#   after a cable loss the gadget never re-enumerates on its own, and the only
#   recovery is sol-usb-recover's dwc3 unbind/rebind -- which is proven safe ONLY
#   with spoof_connected=1, and resets the SoC at 0. Ship a permanent 0 and a
#   watch that loses its cable is unreachable until someone holds the buttons.
#
# So follow reality instead of picking a side: 1 while a charger is actually
# present, 0 while it is not. Plugged, the gadget enumerates and recovery stays
# available; unplugged, USB drops to LPM and suspend can proceed. Verified that
# clearing the spoof with a cable attached is harmless -- the shim then follows
# the PMIC and reports connected anyway, and adb stays up.
#
# POLLED, NOT EVENT-DRIVEN, deliberately. The obvious implementation is a udev
# rule on power_supply, but udev's USB event path is exactly what is broken on
# this device: usb-moded dies at startup with "udev io watch disabled" and never
# sees a cable event at all, which is why sol-bringup-adb exists. Depending on
# that same path here would make USB LPM fail in precisely the cases it matters.
set -u

SHIM=/sys/bus/platform/devices/soc:google,extcon-usb-shim/spoof_connected
ONLINE=/sys/class/power_supply/usb/online
POLL=5

[ -w "$SHIM" ] || { echo "sol-usb-lpm: $SHIM not writable -- nothing to do"; exit 0; }

last=""
while true; do
    # Absent or unreadable reads as "assume a cable", the safe direction: the
    # cost is a watch that does not suspend, versus one that cannot be reached.
    want=$(cat "$ONLINE" 2>/dev/null) || want=1
    case "$want" in 0|1) ;; *) want=1 ;; esac

    if [ "$want" != "$last" ]; then
        if echo "$want" > "$SHIM" 2>/dev/null; then
            if [ "$want" = "1" ]; then
                echo "sol-usb-lpm: charger present -- spoof_connected=1, gadget recovery available"
            else
                echo "sol-usb-lpm: no charger -- spoof_connected=0, USB may enter LPM"
            fi
            last=$want
        else
            echo "sol-usb-lpm: failed to write $want to spoof_connected"
        fi
    fi
    sleep "$POLL"
done
