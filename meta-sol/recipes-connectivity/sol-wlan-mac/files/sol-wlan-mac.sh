#!/bin/sh
# Give wlan0 this watch's real MAC, every boot.
#
# THE PROBLEM. sol's wlan0 does not come up with a stable address. Observed in
# one session: 00:90:4c:d1:a6:ad, 00:90:4c:f0:ad:40, 00:90:4c:5e:e5:05 --
# different every time, all on Broadcom's TEST OUI -- against the factory address
# 20:f0:94:4c:1b:2f, which the bootloader publishes in the device tree as
# chosen/config/wlan_mac1 (right beside the bt_addr patchram already uses, and
# sharing its Google OUI).
#
# WHY IT IS WORSE THAN COSMETIC. connman's saved-network identity embeds the
# interface MAC: wifi_<mac>_<ssid-hex>_managed_psk. A different MAC means the
# saved network no longer matches, so WiFi silently never auto-connects and the
# watch has no network after a reboot until someone reconnects it by hand. For a
# daily driver that is a bug; during development it also removes the one channel
# that survives USB going away.
#
# WHAT DOES NOT WORK, both tested on hardware:
#   - Editing macaddr= in bcmdhd.cal. The driver does not take its address from
#     there: with all three calibration files rewritten to the factory MAC, a
#     module reload still produced a fresh random test-OUI address.
#   - Setting it while the interface is DOWN. bcmdhd unregisters the netdev on
#     down, so the request lands on a device that no longer exists
#     ("RTNETLINK answers: No such device").
#
# WHAT WORKS: bring the interface UP first, then set the address. Verified.
set -u

DT=/sys/firmware/devicetree/base/chosen/config/wlan_mac1
IF=wlan0

[ -r "$DT" ] || { echo "sol-wlan-mac: $DT absent -- nothing to apply"; exit 0; }

MAC=$(tr -d '\0' < "$DT" | tr 'A-F' 'a-f')
case "$MAC" in
    [0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]) : ;;
    *) echo "sol-wlan-mac: '$MAC' is not a MAC -- refusing"; exit 0 ;;
esac

# The driver is loaded by systemd-modules-load; the netdev appears a moment
# later. Wait rather than race it.
i=0
while [ "$i" -lt 60 ]; do
    [ -e "/sys/class/net/$IF" ] && break
    sleep 1
    i=$((i + 1))
done
[ -e "/sys/class/net/$IF" ] || { echo "sol-wlan-mac: $IF never appeared"; exit 0; }

cur=$(cat "/sys/class/net/$IF/address" 2>/dev/null)
if [ "$cur" = "$MAC" ]; then
    echo "sol-wlan-mac: $IF already has $MAC"
    exit 0
fi

# The interface has to be UP for the address to be settable, and at this point in
# boot it is usually RF-killed -- `ip link set up` then fails outright with
# "Operation not possible due to RF-kill" and the address set that follows fails
# with ENODEV. So lift the soft block just long enough, and put it back exactly
# as found: connman applies the user's own WiFi preference afterwards, and this
# must not be what turns the radio on for someone who turned it off.
blocked=$(rfkill list wifi 2>/dev/null | grep -c "Soft blocked: yes")
[ "$blocked" -gt 0 ] && rfkill unblock wifi 2>/dev/null

ip link set "$IF" up 2>/dev/null
i=0
while [ "$i" -lt 8 ]; do
    [ "$(cat /sys/class/net/$IF/operstate 2>/dev/null)" != "down" ] && break
    sleep 1
    i=$((i + 1))
done

if ip link set "$IF" address "$MAC" 2>/dev/null; then
    echo "sol-wlan-mac: $IF $cur -> $(cat /sys/class/net/$IF/address)"
else
    echo "sol-wlan-mac: failed to set $MAC on $IF (still $(cat /sys/class/net/$IF/address 2>/dev/null))"
fi

[ "$blocked" -gt 0 ] && rfkill block wifi 2>/dev/null
exit 0
