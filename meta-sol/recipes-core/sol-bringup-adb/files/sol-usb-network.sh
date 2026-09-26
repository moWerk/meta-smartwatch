#!/bin/sh
# /usr/bin/sol-usb-network.sh
#
# Give sol a working USB network link (and therefore ssh-over-USB) using the NCM
# gadget function.
#
# SOL IS THE CLEAN CASE. usb-moded is MASKED here by sol-bringup-adb (its udev
# watch dies on this device, exactly as on aurora), so there is no second writer
# of configfs to race -- unlike aurora, where init_gfs's header warns about
# exactly that. Writing the gadget directly is simply correct on sol.
#
# HARDWARE-VERIFIED on sol 2026-08-16:
#     created ncm.0 function / linked / rebound / udc state: configured
#     usb0: inet 192.168.43.2/24        sshd.socket=active
# and a matching USB ethernet interface came up on the host, with adb still
# connected on the same composite gadget throughout.
#
# ADDRESS: 192.168.43.2 deliberately, NOT aurora's 192.168.42.2 -- both watches
# sit on the same host and would otherwise collide when docked together.
#
# WHY THIS EXISTS. ssh-over-USB does not come up at all on the newer ports
# (beluga, rubyfish, aurora, sol) while ssh over wifi is fine everywhere, so they
# all fall back to adb. Two separate reasons, both visible in aurora's own log:
#
#   1. usb-moded's developer_mode asks for RNDIS:
#          sysfs_value      = rndis
#          network_interface = rndis0
#      and this kernel has no rndis configfs function, so it fails outright:
#          usb_moded: /config/usb_gadget/g1/functions/rndis.rndis: mkdir failed:
#                     No such file or directory
#      (sol's own recipe already records CONFIG_USB_CONFIGFS_RNDIS unset on
#      beluga/hoki/koi -- same family of devices.)
#
#   2. usb-moded never selects ANY mode on these devices anyway; its udev
#      monitor dies at startup --
#          usb_moded: CONFIGFS detected
#          usb_moded: udev io watch disabled      (twice)
#      -- and it then sits there for the rest of the boot (17 log lines total).
#      That is a SHARED usb-moded bug, not something to fix per-device.
#
# So a mode .ini alone would not help: the component that would apply it is dead.
# This script configures the gadget directly.
#
# NCM IS AVAILABLE AND WORKS. aurora's gadget already exposes ncm.0 among its
# functions (accessory.gs2, audio_source.gs3, ffs.adb, ffs.diag*, mass_storage*,
# midi.gs5, ncm.0, qdss*, uac2.0, uvc.0). Verified on hardware 2026-08-16:
# linking ncm.0 into configs/b.1 and rebinding the UDC brought up usb0
# (BROADCAST,MULTICAST,UP,LOWER_UP) on the watch and a matching USB ethernet
# interface on the host, with adb still working alongside it on the same
# composite gadget.
#
# ssh itself needs nothing further: sshd.socket is already socket-activated and
# listening on [::]:22 (Accept=yes). It was never an ssh problem -- there was
# simply no network interface for it to be reached on.
set -u

G=/config/usb_gadget/g1
ADDR="${SOL_USB_ADDR:-192.168.43.2/24}"
LOGF=/var/log/sol-usb-network.log

log() {
    echo "sol-usb-network: $1"
    echo "$(cut -d. -f1 /proc/uptime)s $1" >> "$LOGF" 2>/dev/null || true
}

# --- stable, per-device MAC so the IPv6 link-local never changes ------------
#
# WHY: a-d-b reaches these watches over IPv6 link-local
# (ssh -6 ceres@fe80::...%iface), which needs no addressing and no root -- but
# the link-local is EUI-64 derived from usb0's MAC, and the kernel generates that
# MAC RANDOMLY every time the ncm function is created, i.e. every boot. That made
# the address undiscoverable-by-cache: a-d-b had to re-run neighbour discovery
# each boot. Pinning dev_addr from the device's own serial makes both the MAC and
# the link-local deterministic and unique per watch, so it can be cached.
#
# The DSN is the same source init_gfs now uses for the USB serial (aurora's
# cmdline has no androidboot.serialno= at all). Falls back to the machine name so
# two different watches can never silently collide on one MAC.
#
# First octet is forced to 0x02: locally-administered (bit 1) and unicast
# (bit 0 clear). Anything else risks colliding with a real OUI.
#
# MUST be written while the function is UNBOUND -- configfs rejects changes to a
# bound gadget, which is why this sits between the unbind and the bind below.
stable_mac() {
    dsn=""
    [ -r /sys/firmware/devicetree/base/chosen/config/dsn ] && \
        dsn="$(tr -d '\0' < /sys/firmware/devicetree/base/chosen/config/dsn)"
    [ -n "$dsn" ] || dsn="$(cat /etc/hostname 2>/dev/null)"
    [ -n "$dsn" ] || dsn="asteroid"
    h=$(printf '%s' "$dsn" | md5sum | cut -c1-10)
    printf '02:%s:%s:%s:%s:%s\n' \
        "$(printf '%s' "$h" | cut -c1-2)" "$(printf '%s' "$h" | cut -c3-4)" \
        "$(printf '%s' "$h" | cut -c5-6)" "$(printf '%s' "$h" | cut -c7-8)" \
        "$(printf '%s' "$h" | cut -c9-10)"
}

pin_mac() {
    want=$(stable_mac)
    cur=$(tr -d '\0' < "$G/functions/ncm.0/dev_addr" 2>/dev/null)
    if [ "$cur" = "$want" ]; then
        log "dev_addr already pinned to $want"
        return 0
    fi
    if echo "$want" > "$G/functions/ncm.0/dev_addr" 2>/dev/null; then
        log "pinned dev_addr=$want (was ${cur:-unset}) -> stable link-local"
    else
        log "WARNING: could not pin dev_addr (function bound?); link-local will vary per boot"
    fi
}

[ -d "$G" ] || { log "FATAL: $G missing (init_gfs did not run?)"; exit 1; }

# sol's gadget carries ONLY ffs.adb (sol-bringup-adb creates just that), so
# unlike aurora the ncm function has to be created first. mkdir failing here is
# the real "kernel has no NCM" signal. Verified on sol: ncm.test SUPPORTED,
# rndis.test "No such file or directory", CONFIG_USB_CONFIGFS_NCM=y.
if [ ! -d "$G/functions/ncm.0" ]; then
    if ! mkdir "$G/functions/ncm.0" 2>/dev/null; then
        log "kernel has no NCM configfs function -- cannot provide USB networking"
        exit 0
    fi
    log "created ncm.0 function"
    # PIN IMMEDIATELY. dev_addr can only be written while the function is
    # NEITHER BOUND NOR UP -- measured on sol: writing it while the gadget was
    # bound returned an error outright, and writing it merely-unbound stored the
    # attribute but left usb0's MAC (and therefore the link-local) unchanged.
    # Right after mkdir the netdev is fresh and down, which is the only reliable
    # moment.
    pin_mac
fi

# Pin before any linking. See pin_mac: the write only takes effect while the
# function is unbound and its netdev is down.
if [ -e /sys/class/net/usb0 ]; then ip link set usb0 down 2>/dev/null; fi
pin_mac

if [ -e "$G/configs/b.1/ncm.0" ]; then
    log "ncm.0 already linked; leaving the gadget alone"
else
    U=$(ls /sys/class/udc 2>/dev/null | head -1)
    [ -n "$U" ] || { log "FATAL: no UDC"; exit 1; }

    # Adding a function to a live gadget requires unbinding first. This briefly
    # drops adb, which is why it happens once at boot rather than later. ffs.adb
    # is deliberately left linked so the result is a composite: adb AND network
    # on the same gadget.
    log "unbinding UDC=$U to add ncm.0"
    echo "" > "$G/UDC" 2>/dev/null
    sleep 1
    ln -sf "$G/functions/ncm.0" "$G/configs/b.1/ncm.0" 2>/dev/null \
        && log "linked ncm.0" || { log "FATAL: could not link ncm.0"; echo "$U" > "$G/UDC" 2>/dev/null; exit 1; }
    sleep 1
    echo "$U" > "$G/UDC" 2>/dev/null && log "rebound UDC" || log "FATAL: rebind failed"
    sleep 3
fi

# usb0 appears only once the function is bound.
i=0
while [ ! -e /sys/class/net/usb0 ] && [ "$i" -lt 15 ]; do i=$((i + 1)); sleep 1; done
if [ ! -e /sys/class/net/usb0 ]; then
    log "usb0 never appeared after linking ncm.0"
    exit 1
fi

ip link set usb0 up 2>/dev/null
# Idempotent: adding an address that is already there is not an error worth
# failing the unit over.
ip addr add "$ADDR" dev usb0 2>/dev/null || true

log "usb0 up: $(ip -4 addr show usb0 2>/dev/null | grep -o 'inet [0-9./]*' | head -1)"
log "sshd.socket=$(systemctl is-active sshd.socket 2>/dev/null) -- host side needs: ip addr add 192.168.43.1/24 dev <usb-iface>; ip link set <usb-iface> up"
