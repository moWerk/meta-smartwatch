#!/bin/sh
# BRING-UP ONLY. Ships via meta-sol/recipes-core/sol-bringup-adb; remove once
# usb-moded works on sol (see the recipe header for the open bug).
#
# Replaces the one thing usb-moded's adb_mode does that we still need, minus the
# cable-state dependency that is failing on sol:
#   usb_moded: udev io watch disabled   (log_crit, G_IO_ERR/HUP on the monitor)
# after which usb-moded never sets a mode, never calls set_udc, and adb never
# comes up after switch_root.
#
# adbd-prepare.service has already created functions/ffs.adb and mounted
# FunctionFS at /dev/usb-ffs/adb; adbd then writes its descriptors. ep1 only
# exists once FunctionFS is FFS_ACTIVE, which is the precondition the kernel's
# composite_bind needs for ffs_func_bind() to succeed. Binding the UDC before
# that returns ENODEV. Same reasoning as the FFS_ACTIVE patch in usb-moded.
G=/config/usb_gadget/g1
log() { echo "sol-bringup-adb: $1"; }

[ -d "$G" ] || { log "FATAL: $G missing (init_gfs did not run?)"; exit 1; }

i=0
while [ ! -e /dev/usb-ffs/adb/ep1 ]; do
    i=$((i+1))
    [ "$i" -gt 100 ] && { log "FATAL: timed out waiting for /dev/usb-ffs/adb/ep1"; exit 1; }
    sleep 0.1
done
log "FunctionFS ready (ep1 present after $((i))00ms)"

if [ ! -e "$G/configs/b.1/ffs.adb" ]; then
    ln -s "$G/functions/ffs.adb" "$G/configs/b.1/ffs.adb" || { log "FATAL: symlink failed"; exit 1; }
    log "linked ffs.adb into configs/b.1"
fi

udc=$(ls /sys/class/udc 2>/dev/null | head -n 1)
[ -n "$udc" ] || { log "FATAL: no UDC in /sys/class/udc"; exit 1; }

cur=$(cat "$G/UDC" 2>/dev/null)
if [ -n "$cur" ]; then
    log "UDC already bound to '$cur', leaving alone"
    exit 0
fi

if echo "$udc" > "$G/UDC" 2>/dev/null; then
    log "bound UDC=$udc -- adb gadget should be live"
else
    log "FATAL: writing UDC=$udc failed"
    exit 1
fi
