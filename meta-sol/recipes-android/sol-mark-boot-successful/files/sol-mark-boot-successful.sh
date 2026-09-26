#!/bin/sh
# /usr/bin/sol-mark-boot-successful.sh
#
# Tell the bootloader this boot worked. Without this the watch eventually
# refuses to boot at all.
#
# sol is an A/B device. The bootloader decrements the current slot's
# tries-remaining on every boot and expects userspace to mark the slot
# successful once the system is up; when nothing ever does, the counter walks
# down to zero and the bootloader declares the slot UNBOOTABLE and drops to
# fastboot. Recovering then needs a host and `fastboot flash boot`. Observed on
# 2026-08-23 after a day of reboots:
#
#     slot-successful:a  no      slot-retry-count:a  0      slot-unbootable:a  yes
#
# AOSP does this from update_verifier, which its own init.rc starts on
# `sys.boot_completed=1`. Nothing sets that property here -- AsteroidOS does not
# run the Android framework -- so the binary ships in the container image and
# simply never runs. Running it directly is enough; verified on hardware, the
# same three variables afterwards:
#
#     slot-successful:a  yes     slot-retry-count:a  5      slot-unbootable:a  no
#
# Deliberately NOT fatal if anything is missing: a watch that cannot mark its
# slot should still boot and be usable, and this must never become the reason a
# boot fails.
set -u

PID=$(lxc-info -n android -p -H 2>/dev/null) || exit 0
[ -n "${PID:-}" ] || { echo "sol-mark-boot-successful: container not running -- skipping"; exit 0; }

if ! nsenter -t "$PID" -m -p -- /system/bin/ls /system/bin/update_verifier >/dev/null 2>&1; then
    echo "sol-mark-boot-successful: no update_verifier in the container image -- skipping"
    exit 0
fi

nsenter -t "$PID" -m -p -- /system/bin/update_verifier >/dev/null 2>&1
echo "sol-mark-boot-successful: ran update_verifier; slot should now be marked successful"
exit 0
