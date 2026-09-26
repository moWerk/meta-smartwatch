#!/bin/sh
# /usr/bin/sol-zygote-wakelock.sh
#
# Release the Android container's `zygote_kwl` kernel wakelock, which otherwise
# prevents this watch from EVER suspending.
#
# THE MECHANISM, from the init.rc inside the Halium system image sol runs
# (/mnt/storage/sol-halium-a14-v2/sol-halium-a14-labeled.img):
#
#     service zygote /system/bin/app_process -Xzygote /system/bin --zygote --start-system-server
#         ...
#         onrestart write /sys/power/state on
#         # NOTE: If the wakelock name here is changed, then also
#         # update it in SystemSuspend.cpp
#         onrestart write /sys/power/wake_lock zygote_kwl
#         onrestart restart audioserver
#
# Android's contract is that init TAKES this wakelock whenever zygote restarts,
# to hold the device awake while the Java framework comes back, and that
# SystemSuspend (android.system.suspend, which hardcodes the same name -- hence
# that comment) RELEASES it once things settle.
#
# On AsteroidOS the second half never happens. The container runs HALs only;
# there is no system_server, so nothing ever reaches the state where
# SystemSuspend would drop it. The wakelock is therefore held forever.
#
# MEASURED ON SOL: /sys/power/wake_lock contained `zygote_kwl` in essentially
# every sample across ~100 samples of two long runs, on charger and off, screen
# on and blanked -- and /sys/power/suspend_stats/success stayed at 0 for the
# entire life of the boot. This watch has never suspended once.
#
# WHY NOT JUST DISABLE ZYGOTE: that is the cleaner fix and is worth doing later
# (AsteroidOS needs no Java framework at all, and a restarting zygote also burns
# CPU). It is a bigger, riskier change to the container's init, so this ships
# first: it is small, reversible, and its log doubles as a measurement of how
# often zygote actually restarts -- which we do not currently know.
#
# !! BEHAVIOUR CHANGE, TEST DELIBERATELY !!
# Releasing this may let sol suspend for the FIRST TIME EVER. Suspend/resume on
# this device is completely untested: wakeup sources, the MCU, BT and WiFi
# resume paths have never been exercised. Expect the possibility that the watch
# sleeps and does not come back, and test it with adb attached and a way to
# recover (see sol-usb-recover and the dead-man reboot pattern). Do not enable
# this in an image that is meant to be stable until suspend/resume is proven.
set -u

POLL=30
LOCK=zygote_kwl
LOGF=/var/log/sol-zygote-wakelock.log

log() {
    echo "sol-zygote-wakelock: $1"
    echo "$(cut -d. -f1 /proc/uptime)s $1" >> "$LOGF" 2>/dev/null || true
}

held() {
    # /sys/power/wake_lock lists the currently held userspace wakelocks,
    # space separated. Match on a word boundary so a future "zygote_kwl2"
    # cannot be mistaken for this one.
    case " $(cat /sys/power/wake_lock 2>/dev/null) " in
        *" $LOCK "*) return 0 ;;
        *) return 1 ;;
    esac
}

[ -w /sys/power/wake_unlock ] || { log "FATAL: /sys/power/wake_unlock not writable"; exit 1; }

log "watchdog started (poll=${POLL}s, target=$LOCK)"

releases=0
while :; do
    if held; then
        if echo "$LOCK" > /sys/power/wake_unlock 2>/dev/null; then
            releases=$((releases + 1))
            # Each release after the first means zygote restarted and init
            # re-took the lock. The count is therefore a direct measure of
            # zygote restart activity, which is worth knowing on its own.
            log "released $LOCK (release #$releases) suspend_success=$(cat /sys/power/suspend_stats/success 2>/dev/null)"
        else
            log "WARNING: write to wake_unlock failed while $LOCK was held"
        fi
    fi
    sleep "$POLL"
done
