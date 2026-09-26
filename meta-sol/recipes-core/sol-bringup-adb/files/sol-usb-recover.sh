#!/bin/sh
# BRING-UP ONLY, ships alongside sol-bringup-adb.sh.
#
# THE PROBLEM THIS EXISTS FOR: on sol a VBUS loss is currently a ONE-WAY DOOR.
# sol-bringup-adb.sh is a one-shot -- it waits for FunctionFS, links ffs.adb,
# binds the UDC once, and explicitly returns early if the UDC is already bound.
# Nothing in the image ever re-binds it, and usb-moded (which would normally own
# cable state) is masked on sol because its udev monitor dies with
# "udev io watch disabled". So when the watch loses VBUS and gets it back, the
# gadget never re-enumerates: the host sees POWER ON but no device on the port,
# and the ONLY recovery is the fastboot button combo, i.e. human hands.
#
# Measured on 2026-08-16: a 75 s VBUS cut via the docking bay left sol running
# happily on battery, but it never came back on USB. Three further cycles (5 s,
# 30 s) and 90 s of waiting produced nothing -- /sys/bus/usb/devices/1-3.4.3
# stayed absent while aurora on the neighbouring port was fine.
#
# WHY IT MATTERS BEYOND CONVENIENCE: every off-charger investigation on this
# watch needs a VBUS cut (kido's mce/sensorfwd lockup chain reproduces "after a
# few screen on/off while unplugged"). If each cut costs a human button combo,
# that whole class of work is untestable overnight or remotely.
#
# THE RECOVERY: /sys/class/udc/<udc>/state reports the link state. When VBUS is
# present but the UDC has sat at "not attached" for several consecutive checks,
# the gadget is bound in configfs yet not enumerating -- unbind and rebind it,
# which re-runs composite_bind and re-asserts the D+ pull-up.
#
# DELIBERATELY CONSERVATIVE, because rebinding a healthy gadget would drop a live
# adb session mid-command:
#   - requires VBUS actually present (never touches anything off-charger),
#   - requires N consecutive bad samples, not one (enumeration legitimately
#     takes a moment after a cable event),
#   - does nothing at all while the state is attached/addressed/configured.
set -u

G=/config/usb_gadget/g1
POLL=15
NEED=3          # consecutive bad samples before acting (~45 s)
bad=0
attempts=0    # rebind attempts made; drives the backoff below

# Log to BOTH the journal and a file on the rootfs.
#
# The journal alone is not good enough here: after the v1 failure the previous
# boot's journal showed up under `journalctl -b -1` and then VANISHED minutes
# later when journald rotated, taking the only record of what the watchdog
# actually did with it. The whole point of this unit is to diagnose a state in
# which adb is gone, so its evidence has to outlive both the boot and journald's
# housekeeping. /var/log is on the rootfs and does persist (verified: the soak
# log survived a reboot).
LOGF=/var/log/sol-usb-recover.log
log() {
    echo "sol-usb-recover: $1"
    echo "$(cut -d. -f1 /proc/uptime)s $1" >> "$LOGF" 2>/dev/null || true
}

# THE VBUS GATE, AND WHY IT IS BACK (v4, 2026-08-18).
#
# v3 removed this as a gate on the theory that /sys/class/power_supply/usb/online
# might stay 0 after VBUS returns, leaving the watchdog blind. That theory was
# never measured, and it is wrong. Measured on sol directly:
#
#     plugged:   usb/online=1  qcom_usb/online=1  usb/present=1  status=Charging
#     unplugged: usb/online=0  qcom_usb/online=0                 status=Discharging
#
# Both readings come from live captures on this watch, the unplugged one from
# the watchdog's own log line the moment before it killed the device.
#
# Ungated, it killed the watch. Off charger the UDC sits at "not attached", which
# is correct and healthy -- no host, nothing to enumerate to -- but the state
# machine below reads it as broken, counts to 3 and escalates. Recovery level 2
# unbinds the dwc3 platform driver, and doing that with no cable attached resets
# the SoC instantly, traceless. Captured over WiFi while USB was down:
#
#     sol-usb-recover: attempt #2: usb/online=0 ... status=Discharging
#     sol-usb-recover: recovery level 2
#     sol-usb-recover:   dwc3: unbinding 4e00000.dwc3
#     msm-dwc3 4e00000.hsusb: DWC3 exited from low power mode
#     dwc3 4e00000.dwc3: request 0000000000000000 was not queued to ep0out
#     <stream ends, watch reboots>
#
# The same unbind WITH a cable attached completes cleanly and leaves the gadget
# "configured" (verified on the very next boot). So the hazard is the unbind
# off charger, not the unbind.
#
# This mattered far beyond adb: that reset was being read as "sol cannot survive
# a USB disconnect", which is what stood between this watch and suspending at
# all. It was this script all along.
#
# Off charger there is no host to enumerate to, so there is nothing to recover
# and the gate costs nothing.
vbus_report() {
    out=""
    for p in /sys/class/power_supply/usb/online \
             /sys/class/power_supply/qcom_usb/online \
             /sys/class/power_supply/sw5100_bms/status; do
        [ -r "$p" ] && out="$out $(basename "$(dirname "$p")")/$(basename "$p")=$(cat "$p" 2>/dev/null)"
    done
    echo "$out"
}

udc_name() { ls /sys/class/udc 2>/dev/null | head -n 1; }

# Bind the gadget. This is the part that provably works: it recovers a manually
# unbound UDC in ~60 s (measured 2026-08-16). Delegates to sol-bringup-adb.sh so
# there is ONE implementation of the wait-for-ep1 + symlink + bind sequence.
bind_gadget() {
    u=$(udc_name)
    [ -n "$u" ] || { log "no UDC present"; return 1; }
    echo "" > "$G/UDC" 2>/dev/null
    systemctl restart android-tools-adbd 2>/dev/null || true
    if [ -x /usr/bin/sol-bringup-adb.sh ]; then
        /usr/bin/sol-bringup-adb.sh 2>&1 | while read -r l; do log "  bringup: $l"; done
    else
        i=0
        while [ ! -e /dev/usb-ffs/adb/ep1 ] && [ "$i" -lt 100 ]; do i=$((i + 1)); sleep 0.1; done
        echo "$u" > "$G/UDC" 2>/dev/null || log "bare bind failed"
    fi
}

# Force the D+ pull-up off and on again. Accepts either the string or the
# numeric form depending on kernel vintage.
soft_reconnect() {
    u=$(udc_name); f="/sys/class/udc/$u/soft_connect"
    [ -e "$f" ] || { log "  no soft_connect node"; return 1; }
    { echo disconnect > "$f" 2>/dev/null || echo 0 > "$f" 2>/dev/null; } && log "  soft_connect: disconnected"
    sleep 2
    { echo connect > "$f" 2>/dev/null || echo 1 > "$f" 2>/dev/null; } && log "  soft_connect: connected"
}

# Full controller re-init: unbind and re-bind the dwc3 platform driver itself.
# The heaviest hammer available short of a reboot, and the one thing that
# actually re-runs the controller's own probe/PHY init.
dwc3_reinit() {
    u=$(udc_name)
    d=/sys/bus/platform/drivers/dwc3
    [ -d "$d" ] || { log "  no dwc3 driver dir"; return 1; }
    log "  dwc3: unbinding $u"
    echo "$u" > "$d/unbind" 2>/dev/null || { log "  dwc3 unbind FAILED"; return 1; }
    sleep 3
    log "  dwc3: rebinding $u"
    echo "$u" > "$d/bind" 2>/dev/null || { log "  dwc3 bind FAILED"; return 1; }
    sleep 3
}

# ESCALATING RECOVERY. Each level is strictly more invasive than the last.
#
# WHY IT ESCALATES, from hardware evidence (2026-08-16):
# A gadget rebind alone recovers a MANUALLY unbound UDC in ~60 s, but does NOT
# recover a real VBUS cut. After a VBUS cut the log shows the bind succeeding
# every time --
#     bringup: FunctionFS ready (ep1 present after 100ms)
#     bringup: bound UDC=4e00000.dwc3 -- adb gadget should be live
#     post-rebind UDC state='default'
# -- three attempts running, each binding cleanly, and the state never leaving
# "default". Bound but never enumerated, and the host saw no device on the port
# at all. So the gadget layer is fine and something below it (pull-up, PHY,
# controller) did not survive losing VBUS. Rebinding the GADGET cannot fix the
# CONTROLLER, hence levels 2 and 3.
rebind() {
    lvl=$1
    log "recovery level $lvl"
    # TWO levels, not three, and the split is set by measurement rather than
    # taste. The full ladder was run on hardware against a real VBUS cut:
    #   L1 gadget rebind                      -> bound clean, state stayed "default"  FAILED
    #   L2 gadget rebind + soft_connect       -> bound clean, state stayed "default"  FAILED
    #   L3 dwc3 driver unbind/bind + the above-> state "not attached" -> "configured"  WORKED
    # (uptime was continuous across that recovery, so it was a genuine repair and
    # not the dead-man reboot.) soft_connect never fixed anything on its own, so
    # it is folded into the cheap level instead of costing a whole extra round.
    #
    # LEVEL 2 IS HEAVILY GATED, because unbinding dwc3 in the wrong state resets
    # the SoC instantly and tracelessly. Two conditions, both measured:
    #
    #   spoof_connected must be 1. Every unbind that completed cleanly happened
    #   with the shipped spoof of 1 (2026-08-16 recovery, and again with a cable
    #   attached); both unbinds that killed the watch happened with spoof=0.
    #   Reading the extcon shim instead is NOT equivalent and was the first
    #   wrong answer here: with spoof=0 and a cable attached the shim follows the
    #   PMIC and reads 1, so a shim-based gate would have permitted the very
    #   unbind that killed the watch the second time.
    #
    #   A HOST must be attached, not merely a charger. usb/type reads USB_CDP on
    #   the docking bay; a power bank or wall charger enumerates as DCP and there
    #   is no host on the other end, so there is nothing to recover and the whole
    #   escalation is pointless there. This matters beyond tidiness: on a power
    #   bank usb/online is 1 while the UDC can never reach "configured", so
    #   without this the watchdog escalates to an unbind every couple of minutes
    #   for as long as the watch is on the bank -- which is exactly the cadence
    #   and setting of the still-unexplained resets during GPS sky tests.
    #
    # Skipping level 2 costs adb recovery. Running it in the wrong state costs
    # the watch. The asymmetry decides every uncertain case.
    spoof=$(cat /sys/bus/platform/devices/soc:google,extcon-usb-shim/spoof_connected 2>/dev/null)
    utype=$(cat /sys/class/power_supply/usb/type 2>/dev/null)
    case "$lvl" in
        1)  bind_gadget; soft_reconnect ;;
        *)  if [ "$spoof" != "1" ]; then
                log "  SKIPPING dwc3 re-init: spoof_connected='$spoof', unbind is only proven safe at 1"
            elif [ "${utype#*CDP}" = "$utype" ] && [ "${utype#*SDP}" = "$utype" ]; then
                log "  SKIPPING dwc3 re-init: usb/type='$utype' is not a host port"
            else
                dwc3_reinit
            fi
            bind_gadget; soft_reconnect ;;
    esac
    u=$(udc_name)
    sleep 5
    log "post-recovery UDC state='$(cat "/sys/class/udc/$u/state" 2>/dev/null)' UDC='$(cat "$G/UDC" 2>/dev/null)'"
}

[ -d "$G" ] || { log "FATAL: $G missing"; exit 1; }
log "watchdog started (poll=${POLL}s, threshold=${NEED} samples)"

# Healthy on this hardware is "configured" -- measured directly on sol while
# plugged in with adb working. The other three are the intermediate enumeration
# states and are treated as fine so a rebind is never attempted mid-enumeration.
last_report=0
while true; do
    sleep "$POLL"
    u=$(udc_name)
    [ -n "$u" ] || continue
    st=$(cat "/sys/class/udc/$u/state" 2>/dev/null)

    # THE GATE. Off charger, do nothing at all -- see vbus_report above for the
    # capture of what happens without it. bad is reset so a cable that returns
    # starts from a clean count rather than escalating immediately.
    if [ "$(cat /sys/class/power_supply/usb/online 2>/dev/null)" != "1" ]; then
        bad=0
        continue
    fi

    # Heartbeat every ~5 min so the persistent log shows the healthy baseline
    # too, not only the failures. Without it a quiet log is ambiguous: it could
    # mean "nothing went wrong" or "the watchdog died three hours ago".
    now=$(cut -d. -f1 /proc/uptime)
    if [ $((now - last_report)) -ge 300 ]; then
        log "heartbeat: udc=$u state='${st:-unknown}'$(vbus_report)"
        last_report=$now
    fi

    # ONLY "configured" IS HEALTHY. This is the bug that made v1, v2 and v3 all
    # fail against a real VBUS cut, and it took a differential experiment to see.
    #
    # Measured on sol 2026-08-16:
    #   healthy, plugged, adb working      -> state = "configured"
    #   manual `echo "" > .../g1/UDC`      -> state = "not attached"
    #   AFTER A REAL VBUS CUT AND RESTORE  -> state = "default"   <-- the killer
    #
    # "default" means attached and powered but never enumerated, and the earlier
    # versions listed it as healthy (it was written from the generic kernel
    # usb_device_state names, guessing that the intermediate enumeration states
    # were fine to ignore). So after a VBUS cut the watchdog inspected a
    # completely dead gadget every 15 s and concluded nothing was wrong. That is
    # exactly why the manual-unbind test recovered in 60 s while the VBUS test
    # never recovered at all: the two produce DIFFERENT states, and only one of
    # them was in the bad list.
    #
    # Treating the transient enumeration states as bad is safe because of the
    # 3-consecutive-sample threshold: real enumeration walks
    # default -> addressed -> configured in milliseconds, nowhere near 45 s.
    case "$st" in
        configured)
            bad=0
            # A CONFIGURED GADGET IS NOT THE SAME AS A WORKING ADB, and this
            # blind spot locked the watch out on 2026-08-19. The host enumerated
            # sol perfectly -- 18d1:d002 with the adb interface (class ff) and
            # both NCM interfaces present -- while adbd answered nothing, so
            # `adb devices` listed it not at all. The UDC read "configured"
            # throughout, which this loop treats as healthy, so no recovery ever
            # ran. Cycling the port did not help either: the gadget re-enumerates
            # to "configured" too quickly to be counted as bad, and off charger
            # the VBUS gate above (correctly) does nothing.
            #
            # The cheap check is the process itself. Restarting adbd is far below
            # level 1 in cost -- no gadget teardown, no dwc3 anything -- so it is
            # safe to do the moment it is seen dead, without a sample threshold.
            #
            # LIMIT, stated because the lockout that motivated this was never
            # fully diagnosed: this only catches adbd being NOT ACTIVE. An adbd
            # that systemd still considers running while wedged on its FunctionFS
            # endpoint looks healthy here and is not covered. On 2026-08-19 there
            # was no channel left to tell those two apart, so which one occurred
            # is unknown -- do not read this check as a confirmed fix for it.
            if ! systemctl is-active --quiet android-tools-adbd; then
                log "gadget configured but adbd is $(systemctl is-active android-tools-adbd) -- restarting it"
                systemctl restart android-tools-adbd 2>/dev/null || log "  adbd restart failed"
            fi
            ;;
        *)
            # "not attached", empty, or anything unexpected.
            bad=$((bad + 1))
            # Log the RAW state string. The "good" list below was written from
            # the kernel's usb_device_state names without ever seeing what this
            # controller actually reports -- if recovery misbehaves, this line
            # is what tells you whether the state names are even right.
            log "VBUS present but UDC state='${st:-unknown}' (${bad}/${NEED})"
            if [ "$bad" -ge "$NEED" ]; then
                attempts=$((attempts + 1))
                log "attempt #${attempts}:$(vbus_report)"
                rebind "$attempts"
                bad=0
                # Back off after each attempt. Without this, a watch sitting
                # genuinely off charger would restart adbd every 45 s forever.
                if [ "$attempts" -ge 3 ]; then
                    log "3 attempts made; backing off to 5 min between tries"
                    sleep 300
                else
                    # Short gap: the escalation must reach the dwc3 re-init
                    # quickly, since that is the only level that fixes a VBUS
                    # cut. With NEED=3 this puts L1 at ~45 s and L2 at ~65 s
                    # after the cable returns, versus 255 s in the first
                    # working version.
                    sleep 15
                fi
            fi
            ;;
    esac
done
