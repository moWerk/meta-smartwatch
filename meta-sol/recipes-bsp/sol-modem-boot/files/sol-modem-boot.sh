#!/bin/sh
# Bring up the modem subsystem, which is where sol's GNSS engine lives.
#
# Nothing starts 6080000.remoteproc-mss at boot: the qcom_q6v5_pas driver is not
# even bound to it, so geoclue's provider initialises fine and then waits forever
# for an engine that is not running. This binds and starts it.
#
# THE FIRMWARE PATH IS THE TRAP. Starting the remoteproc fails with a bare
# "write error: No such file or directory" (ENOENT, -2) unless the firmware
# loader can see modem.mdt. The modem's firmware is NOT where the ADSP's is:
#
#     ADSP   /android/vendor/firmware/adsp.mdt
#     modem  /android/vendor/firmware_mnt/image/modem.mdt
#
# and /sys/module/firmware_class/parameters/path holds exactly ONE value, which
# sol-adsp-boot has already set to the ADSP's directory. So point it at the modem
# image directory, start the modem, and put it back -- the loader only reads that
# parameter while a firmware is being loaded, so a later ADSP reload still finds
# its own files. Restoring it is not optional: leaving it pointed at the modem
# directory silently breaks the next thing that loads firmware.
#
# WHY THIS SHIPS DISABLED. A live positioning session against this modem used to
# reset the SoC within 40-100 s, three times out of three, with no trace anywhere.
# That no longer reproduces -- 114 polled GetPosition calls over ~19 minutes, the
# exact condition that caused it, with no reset and no subsystem restart -- but
# what changed in between was never isolated (container work, parked services,
# the qrtr transport fix all landed together). Enabling this by default would bet
# every user's watch on that. It is here so the decision can be made deliberately.
set -u

RPROC=/sys/class/remoteproc/remoteproc1
DRV=/sys/bus/platform/drivers/qcom_q6v5_pas
FWPATH=/sys/module/firmware_class/parameters/path
MODEM_FW=/android/vendor/firmware_mnt/image
ADSP_FW=/android/vendor/firmware

[ -f "$MODEM_FW/modem.mdt" ] || {
    echo "sol-modem-boot: $MODEM_FW/modem.mdt missing -- is sol-vendor-mount up?"
    exit 0
}

if [ ! -d "$RPROC" ]; then
    echo "sol-modem-boot: binding 6080000.remoteproc-mss"
    echo 6080000.remoteproc-mss > "$DRV/bind" 2>/dev/null || {
        echo "sol-modem-boot: bind failed"; exit 0; }
    sleep 3
fi

[ -d "$RPROC" ] || { echo "sol-modem-boot: $RPROC absent after bind"; exit 0; }

name=$(cat "$RPROC/name" 2>/dev/null)
case "$name" in
    *remoteproc-mss) : ;;
    *) echo "sol-modem-boot: remoteproc1 is '$name', not the modem -- refusing"; exit 0 ;;
esac

state=$(cat "$RPROC/state" 2>/dev/null)
[ "$state" = "running" ] && { echo "sol-modem-boot: already running"; exit 0; }

echo "$MODEM_FW" > "$FWPATH" 2>/dev/null || echo "sol-modem-boot: could not set $FWPATH"
echo start > "$RPROC/state" 2>/dev/null || echo "sol-modem-boot: start failed (firmware not found?)"
sleep 5
echo "$ADSP_FW" > "$FWPATH" 2>/dev/null || echo "sol-modem-boot: could not restore $FWPATH"

# Report the value written, not a read-back: this parameter is mode 0200
# (write-only), so reading it always fails and an inherited "$(cat ...)" here
# printed an empty string that looked exactly like a failed restore.
echo "sol-modem-boot: remoteproc1 state=$(cat "$RPROC/state" 2>/dev/null), fw path restored to $ADSP_FW"

# RESTART THE GNSS HAL, because it started before the modem existed.
#
# The container brings android.hardware.gnss-aidl-service-qti up with everything
# else at boot, long before anything starts the modem. A GNSS HAL that
# initialises with no modem behind it never gets a QMI client, and it does not
# retry: it sits in recvfrom forever, sends nothing, and the entire QTI location
# stack logs NOTHING -- not one LocSvc line even with IZAT_DEBUG_LEVEL=2 -- which
# reads exactly like broken hardware and is really just an ordering bug.
#
# Restarted after the modem is running, the same HAL immediately talks to it:
#     LocSvc_IzatApiV02: Success at the 1st try, index 0..4
#     LocSvc_ApiV02: req QMI_LOC_SET_CONSTRAINED_TUNC_MODE_REQ_V02, eLOC_CLIENT_SUCCESS
#     LocSvc_ApiV02: req QMI_LOC_ENABLE_POSITION_ASSISTED_CLOCK_EST_REQ_V02, eLOC_CLIENT_SUCCESS
#
# ctl.restart is init's own mechanism and is preferred; the kill is a fallback
# for when the property service cannot be reached from here, since init respawns
# the service either way.
[ "$(cat "$RPROC/state" 2>/dev/null)" = "running" ] || exit 0

restart_gnss_hal() {
    # Wait for the HAL to exist before restarting it. Ordered after the container
    # we are close, but init still needs a moment to bring class hal up, and a
    # restart request that lands before the service exists is silently useless --
    # which is exactly what happened on the first clean-boot test.
    i=0
    while [ "$i" -lt 60 ]; do
        ps -eo args 2>/dev/null | grep -q "[g]nss-aidl-service-qti" && break
        sleep 1
        i=$((i + 1))
    done
    echo "sol-modem-boot: gnss HAL present after ${i}s"

    # ctl.restart is init's own mechanism and is STRONGLY preferred over killing:
    # a killed HAL never closes its QMI session, so the modem keeps the old owner
    # and the next client is refused with QMI_ERR_SESSION_OWNERSHIP_V01. Restarted
    # gracefully, the same stack initialises clean ("Success at the 1st try").
    if [ -x /system/bin/setprop ] && /system/bin/setprop ctl.restart gnss_service 2>/dev/null; then
        echo "sol-modem-boot: requested ctl.restart gnss_service"
    else
        pid=$(ps -eo pid,args 2>/dev/null | grep "[g]nss-aidl-service-qti" | head -n 1 | awk '{print $1}')
        if [ -n "$pid" ]; then
            kill -9 "$pid" 2>/dev/null && echo "sol-modem-boot: killed gnss HAL pid $pid, init will respawn it"
        else
            echo "sol-modem-boot: gnss HAL not running, nothing to restart"
            return
        fi
    fi
    # Give init time to bring it back before anything asks it for a position.
    i=0
    while [ "$i" -lt 30 ]; do
        sleep 1
        ps -eo args 2>/dev/null | grep -q "[g]nss-aidl-service-qti" && break
        i=$((i + 1))
    done
    echo "sol-modem-boot: gnss HAL back after ${i}s"
}

restart_gnss_hal
