#!/bin/sh
# /usr/libexec/sol-adsp-boot.sh
#
# Boot sol's ADSP, which is where the Qualcomm sensor sub-HAL actually runs.
#
# WHY THIS IS NEEDED: sol's sensor stack has two legs. The Google MCU leg
# (nanohub -> mcu_mgmtd -> CHRE) comes up once spi-msm-geni is loaded, see
# sol-post-rootfs.conf. The Qualcomm leg is the USF sub-HAL: the AIDL multihal's
# config, /vendor/etc/sensors/hals.conf, names exactly one sub-HAL,
# /vendor/lib/hw/sensors.usf.so, and USF runs on the ADSP as a protection
# domain ("sensorspd"). With the ADSP down, sscrpcd loops forever trying to
# spawn that PD and no sensor can ever be enumerated.
#
# WHY IT WAS DOWN: the kernel's firmware loader only searches /lib/firmware
# (firmware_class path is empty by default), and the host rootfs ships only GPU
# firmware there -- a702_*/a740_* and no adsp.*. The ADSP firmware lives in the
# Android vendor image at /android/vendor/firmware/adsp.mdt + adsp.b00..bNN,
# which the loader never looks at. So remoteproc0 sat at state=offline from
# boot, with no error that pointed anywhere useful.
#
# Stock reaches the same end state a different way, from second-stage init --
# the same structural reason the side button and the touch digitizer were never
# brought up on our boots. Compare stock's dmesg, which after this runs we match
# line for line:
#     adsprpc: fastrpc_setup_service_locator: pdr_add_lookup enabled for
#              tms/servreg (sensors_pdr_adsprpc, msm/adsp/sensor_pd)
#     adsprpc: fastrpc_rpmsg_probe: opened rpmsg channel for lpass
#
# Verified on hardware 2026-08-15: no reset, boot_id unchanged, remoteproc0 goes
# offline -> running, and mcu_mgmtd/chre/contexthub-wac/sensors-hal-multihal all
# come up behind it.
set -u

RPROC=/sys/class/remoteproc/remoteproc0
FWDIR=/android/vendor/firmware
FWPATH=/sys/module/firmware_class/parameters/path

[ -d "$RPROC" ] || { echo "sol-adsp-boot: $RPROC absent, nothing to do"; exit 0; }

name=$(cat "$RPROC/name" 2>/dev/null)
case "$name" in
    *remoteproc-adsp) : ;;
    *) echo "sol-adsp-boot: remoteproc0 is '$name', not the adsp -- refusing to start it"; exit 0 ;;
esac

state=$(cat "$RPROC/state" 2>/dev/null)
[ "$state" = "running" ] && { echo "sol-adsp-boot: already running"; exit 0; }

if [ ! -f "$FWDIR/adsp.mdt" ]; then
    echo "sol-adsp-boot: $FWDIR/adsp.mdt missing -- is sol-vendor-mount up?"
    exit 0
fi

# Additional search path for the firmware loader; the kernel tries this before
# falling back to /lib/firmware, so the GPU firmware there keeps working.
echo "$FWDIR" > "$FWPATH" 2>/dev/null || echo "sol-adsp-boot: could not set $FWPATH"

echo start > "$RPROC/state" 2>/dev/null
sleep 3
echo "sol-adsp-boot: remoteproc0 state=$(cat "$RPROC/state" 2>/dev/null)"
