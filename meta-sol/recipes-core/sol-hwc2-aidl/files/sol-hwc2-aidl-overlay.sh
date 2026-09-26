#!/bin/sh
# /usr/libexec/sol-hwc2-aidl-overlay.sh
#
# Put sol's AIDL-capable libhwc2_compat_layer.so, and the two AIDL stubs it
# needs, into the Halium system's library directory.
#
# WHY AN OVERLAY AND NOT A FILE INSTALL: these libraries have to be visible to
# the bionic linker at /android/hybris/system/lib, which is hybris-system.img --
# a read-only loop mount, on a loop device that is itself write-protected, so
# `mount -o remount,rw` fails outright. Two of the three files do not exist in
# that image at all (it ships composer@2.1 and composer3-V1-ndk; the compat
# layer wants @2.4 and V4), so a per-file bind mount has nothing to bind over.
# An overlay is the only mechanism that can ADD names to that directory without
# rewriting an image we do not own.
#
# WHY WE DO NOT JUST FIX THE IMAGE: hybris-system.img is meta-aurora's hosted
# Halium-13 bundle, kido's artifact, borrowed by sol because the two share the
# monaco SoC. Rewriting it to suit sol would fork a shared asset for one device.
# When sol gets its own Halium system built against its A14 vendor, these three
# files belong inside it and this unit should be deleted.
#
# WHAT IT FIXES: without this, asteroid-launcher aborts with "failed to get
# hwcomposer service" -- the image's own libhwc2_compat_layer.so is the older
# HIDL-only build, while sol's composer is AIDL composer3 and registers
# android.hardware.graphics.composer3.IComposer/default on vndbinder. Hardware
# 2026-08-15: with these three in place the launcher goes from a SIGABRT restart
# loop to stable, and DSI-1 goes from enabled=disabled to enabled with dpms=On.
set -eu

LIBDIR=/android/hybris/system/lib
SRCDIR=/usr/share/sol-hwc2-aidl
UPPER=/run/sol-hwc2-upper
WORK=/run/sol-hwc2-work

[ -d "$LIBDIR" ] || { echo "sol-hwc2-aidl: $LIBDIR absent, hybris system not mounted"; exit 0; }

if mountpoint -q "$LIBDIR" && [ -e "$LIBDIR/android.hardware.graphics.composer3-V4-ndk.so" ]; then
    echo "sol-hwc2-aidl: overlay already active"
    exit 0
fi

mkdir -p "$UPPER" "$WORK"
mount -t overlay sol-hwc2 -o "lowerdir=$LIBDIR,upperdir=$UPPER,workdir=$WORK" "$LIBDIR"

for f in libhwc2_compat_layer.so \
         android.hardware.graphics.composer@2.4.so \
         android.hardware.graphics.composer3-V4-ndk.so; do
    cp "$SRCDIR/$f" "$LIBDIR/$f"
    chmod 0644 "$LIBDIR/$f"
done
sync

echo "sol-hwc2-aidl: overlay active, libhwc2_compat_layer.so is $(stat -c %s "$LIBDIR/libhwc2_compat_layer.so") bytes"
