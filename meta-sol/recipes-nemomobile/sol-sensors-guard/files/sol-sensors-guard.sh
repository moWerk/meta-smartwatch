#!/bin/sh
# /usr/bin/sol-sensors-guard.sh
#
# Notice when sensorfw's D-Bus interface has gone deaf, and put it back. Does
# nothing at all on a healthy watch.
#
# DEBUGGING THIS SUBSYSTEM? `systemctl stop sol-sensors-guard.timer` FIRST.
# Anyone who stops sensorfwd or pokes the Android container by hand will look
# exactly like the wedge below, and this guard will restart the container out
# from under the experiment (the sol-usb-recover lesson: a watchdog fighting a
# human mid-experiment costs a lockout).
#
# THE FAILURE THIS EXISTS FOR (root-caused 2026-08-26). sol's A14 vendor ships
# only an AIDL sensors HAL; AsteroidOS's sensorfw is a HIDL client. The
# sol-sensors-hidl bridge normally binds a HIDL @2.1 multihal over the AIDL path
# and adds the VINTF fragment, in order, from sol-lxc-android-start.sh before
# lxc-start. But after an ABNORMAL container restart (a crash + systemd Restart=,
# or a suspend/resume dereg) the HIDL sensors HAL can end up NOT registered on
# hwbinder (hwservicemanager: "sensors@2.1::ISensors/default is not registered
# ... ctl.interface_start ... error 0x20"). With no HIDL ISensors to find,
# sensorfw's HybrisManager::finishConnect() sits in a blocking sleep() loop ON
# ITS MAIN THREAD, which starves its own Qt/D-Bus event loop: com.nokia.
# SensorService then answers NOTHING, not even Introspect.
#
# WHY THAT WRECKS THE WATCH, not just sensors. mce is a sensorfw client. It
# retries loadPlugin (als/orientation/proximity/wristgesture) every 10 s; with
# no replies the calls pile up past D-Bus's 128 pending-reply cap and mce's whole
# connection jams with LimitsExceeded. A jammed mce cannot reliably run
# powerkey->unblank, so the screen goes black and the button will not wake it --
# exactly the "not daily-driveable" failure a wear test hit.
#
# HOW TO RECOGNISE IT. A healthy sensorfw answers a D-Bus Introspect on
# /SensorManager instantly; a wedged one (main thread stuck in the finishConnect
# sleep loop) never answers. Three misses over ~20 s is conclusive: a merely-busy
# or restarting sensorfw answers at least one, a structurally-wedged one answers
# none, ever.
#
# THE KICK, cheapest first, and why the cheap one usually is not enough:
#   1. restart sensorfwd -- fixes a transient sensorfw, but NOT an unregistered
#      HAL (a fresh sensorfw just re-enters the same sleep loop as soon as mce's
#      next loadPlugin lands). Cheap and invisible, so we try it and rule out the
#      easy case -- but we confirm recovery over ~25 s, because a fresh sensorfwd
#      LOOKS healthy for a few seconds until mce's next retry re-wedges it.
#   2. restart sol-lxc-android -- re-runs sol-lxc-android-start.sh, which
#      re-applies the HIDL bridge IN ORDER and lets the HAL register on a clean
#      hwservicemanager. This is what actually fixes it (verified by hand
#      2026-08-26). It is VISIBLE (the container/UI blink), so it is deferred
#      while the wearer is looking at the screen, and rate-limited so a
#      persistent failure cannot restart the container every 5 min.
#
# POLLING COST. The timer is frozen along with everything else while the watch is
# genuinely asleep, so on a healthy watch this wakes nothing extra.
set -u

DEST=com.nokia.SensorService
OBJ=/SensorManager
STAMP=/run/sol-sensors-guard.last          # uptime-seconds of the last container kick
BACKOFF=1800                               # >= 30 min between container restarts

log() { echo "sol-sensors-guard: $*"; }

# sensorfw D-Bus alive?  0 = healthy (replied), non-zero = wedged/absent.
probe() {
    timeout 8 dbus-send --system --print-reply --reply-timeout=6000 \
        --dest="$DEST" "$OBJ" \
        org.freedesktop.DBus.Introspectable.Introspect >/dev/null 2>&1
}

# Recovery is real only if sensorfw ANSWERS AND KEEPS ANSWERING across an mce
# retry period (~10 s). A single post-restart probe can win the race against
# mce's next loadPlugin and read "healthy" on a watch that re-wedges seconds
# later. Require two passes ~13 s apart.
confirm_healthy() {
    probe || return 1
    sleep 13
    probe || return 1
    return 0
}

display_state() {
    timeout 10 mcetool 2>/dev/null | sed -n 's/^Display state:[[:space:]]*//p'
}

# Only meaningful while the container is up. During a (re)start, sensorfw being
# briefly unable to answer is expected and self-corrects -- do not act on it.
[ "$(systemctl is-active sol-lxc-android 2>/dev/null)" = active ] || exit 0

# ─── Is anything wrong? Confirm a PERSISTENT wedge, 3 misses over ~20 s ───────
i=1
while [ "$i" -le 3 ]; do
    if probe; then exit 0; fi              # any reply => healthy, done
    [ "$i" -lt 3 ] && sleep 8
    i=$((i + 1))
done
log "sensorfw D-Bus unresponsive on 3/3 Introspect probes -- wedged (likely an unregistered HIDL sensors HAL)"

# ─── Kick 1: cheap + invisible -- restart sensorfwd, rule out a transient ─────
systemctl restart sensorfwd >/dev/null 2>&1
if confirm_healthy; then log "recovered after restarting sensorfwd"; exit 0; fi

# ─── Kick 2: the real fix, but VISIBLE -- defer while the wearer is looking ───
case "$(display_state)" in
    off|lpm_on|lpm_off) ;;                  # screen not in use -- safe to blink the container
    *)
        log "still wedged, but the display is on (wearer looking) -- deferring the container restart to a later cycle"
        exit 0 ;;
esac

# Rate-limit: never restart the container more than once per BACKOFF.
now=$(cut -d. -f1 /proc/uptime 2>/dev/null || echo 0)   # monotonic; sol's wall clock is unreliable
last=0; [ -r "$STAMP" ] && last=$(cat "$STAMP" 2>/dev/null || echo 0)
if [ "$last" != 0 ] && [ $((now - last)) -lt "$BACKOFF" ]; then
    log "still wedged, but the container was restarted $((now - last))s ago (< ${BACKOFF}s) -- backing off"
    exit 0
fi
echo "$now" > "$STAMP"

log "restarting the Android container to re-register the HIDL sensors HAL"
systemctl restart sol-lxc-android >/dev/null 2>&1

# wait (up to 2 min) for the sensors HAL process to reappear
i=0
while [ "$i" -lt 24 ]; do
    sleep 5; i=$((i + 1))
    pgrep -f sensors-service.multihal >/dev/null 2>&1 && break
done
sleep 5
systemctl restart sensorfwd >/dev/null 2>&1     # clean connect to the now-registered HAL
sleep 8
systemctl restart mce >/dev/null 2>&1           # drain any pending-reply saturation mce built up

if confirm_healthy; then
    log "recovered after re-running the container bring-up (+ sensorfwd + mce)"
else
    log "STILL wedged after a container restart -- needs a look (HIDL sensors HAL not registering?)"
fi
