#!/bin/sh
# /usr/bin/sol-sleep-guard.sh
#
# Notice when the watch has silently stopped being able to sleep, and nudge it
# back. Does nothing at all on a healthy watch.
#
# THE FAILURE THIS EXISTS FOR. mce can end up holding its `mce_display_on`
# wakelock while the display is actually off. One held wakelock stops the kernel
# ARMING autosleep at all, so the watch never even attempts a suspend and simply
# burns battery until someone notices. Measured 2026-08-22: sol spent a whole
# night this way at ~72 mA, and three separate drain measurements were silently
# invalidated by the same state before it was spotted.
#
# HOW TO RECOGNISE IT, and why each half of the test is needed:
#
#   /sys/power/autosleep      == "off"   while the display is off
#   /sys/power/wake_lock      contains mce_display_on
#   suspend_stats/success and .../fail  BOTH frozen
#
# The frozen-fail half matters: a wakeup-source storm (e.g. Bluetooth holding
# the UART) also leaves success frozen, but drives fail into the thousands. That
# is a DIFFERENT problem with a different fix, and kicking mce would not help it,
# so this script must not fire on it.
#
# THE KICK. Verified on hardware, cheapest first:
#   1. re-issue a blank -- sometimes enough to re-run the display transition
#   2. toggle low-power mode off/on -- cleared it instantly on sol, where a
#      restart did NOT
#   3. restart mce -- clears it every time on aurora
# AoD is deliberately left ON: the discriminator showed low-power mode does not
# cause this, so there is nothing to gain by taking the watchface away.
#
# POLLING COST. The timer is frozen along with everything else while the watch
# is genuinely asleep, so on a healthy watch this wakes nothing extra; it only
# runs often when the watch is already awake -- which is exactly the broken case.
set -u

AUTOSLEEP=/sys/power/autosleep
WAKELOCK=/sys/power/wake_lock
OK=/sys/power/suspend_stats/success
FAIL=/sys/power/suspend_stats/fail
STAMP=/run/sol-sleep-guard.last

log() { echo "sol-sleep-guard: $*"; }

[ -r "$AUTOSLEEP" ] || exit 0

display_state() {
    timeout 10 mcetool 2>/dev/null | sed -n 's/^Display state:[[:space:]]*//p'
}

# ─── Is anything wrong? ──────────────────────────────────────────────────────
[ "$(cat "$AUTOSLEEP" 2>/dev/null)" = "off" ] || exit 0

case "$(display_state)" in
    off|lpm_on|lpm_off) ;;                 # screen not in use -- should be sleeping
    *) exit 0 ;;                           # user is looking at it; awake is correct
esac

grep -q mce_display_on "$WAKELOCK" 2>/dev/null || exit 0

# Distinguish "never arms" from "arms and aborts". Only the former is ours.
now_ok=$(cat "$OK" 2>/dev/null || echo 0)
now_fail=$(cat "$FAIL" 2>/dev/null || echo 0)
if [ -r "$STAMP" ]; then
    read -r prev_ok prev_fail < "$STAMP" 2>/dev/null || { prev_ok=""; prev_fail=""; }
    if [ "${prev_fail:-}" != "" ] && [ "$now_fail" -gt "${prev_fail:-0}" ]; then
        log "suspend is being ATTEMPTED and aborted (fail $prev_fail -> $now_fail) -- a wakeup source is to blame, not mce; leaving alone"
        echo "$now_ok $now_fail" > "$STAMP"
        exit 0
    fi
    if [ "${prev_ok:-}" != "" ] && [ "$now_ok" -gt "${prev_ok:-0}" ]; then
        echo "$now_ok $now_fail" > "$STAMP"          # it did sleep since last look
        exit 0
    fi
fi
echo "$now_ok $now_fail" > "$STAMP"

log "stuck: autosleep=off, display off, mce_display_on held, suspend never attempted (ok=$now_ok fail=$now_fail)"

armed() { [ "$(cat "$AUTOSLEEP" 2>/dev/null)" = "mem" ]; }

# ─── Kick, cheapest first ────────────────────────────────────────────────────
timeout 10 mcetool --blank-screen >/dev/null 2>&1
sleep 3
if armed; then log "recovered after re-blanking"; exit 0; fi

timeout 10 mcetool --set-low-power-mode=disabled >/dev/null 2>&1
sleep 2
timeout 10 mcetool --set-low-power-mode=enabled  >/dev/null 2>&1
sleep 3
if armed; then log "recovered after a low-power-mode toggle (AoD left on)"; exit 0; fi

log "still stuck -- restarting mce"
systemctl restart mce >/dev/null 2>&1
sleep 8
timeout 10 mcetool --blank-screen >/dev/null 2>&1
sleep 3
if armed; then log "recovered after restarting mce"; else log "STILL STUCK after all three kicks -- needs a look"; fi
