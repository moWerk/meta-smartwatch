#!/bin/sh
# Pin the Bluetooth UART awake only while Bluetooth is actually on.
#
# WHY THE PIN EXISTS AT ALL. patchram.service sets power/control=on for
# 4a94000.qcom,qup_uart once hci0 appears, because the port cannot be woken by
# the controller: the driver takes its wake source from a SECOND interrupt
# (wakeup_irq = platform_get_irq(pdev, 1)) and sol's device tree declares only
# one, so it logs "No wakeup IRQ configured". A runtime-suspended port therefore
# never sees an incoming byte. Measured directly: with the port on auto, TX
# leaves (TX bytes climb) and absolutely nothing comes back (RX bytes frozen),
# every command ends in "tx timeout", and an LE scan finds zero devices where a
# pinned port finds five.
#
# WHY THE PIN IS EXPENSIVE. The driver holds its wakeup source for exactly as
# long as the port is runtime-active, and one held wakeup source stops the kernel
# even ATTEMPTING suspend. Pinned, suspend_stats never moves; with the port on
# auto the same watch suspends immediately. So the pin is the difference between
# a watch that sleeps and one that cannot.
#
# WHAT THIS DOES. Neither state is right all the time, so follow Bluetooth:
# pinned while the adapter is up, released while it is down. A user who turns
# Bluetooth off gets a watch that sleeps; a user who leaves it on keeps working
# Bluetooth. Nothing is silently traded away in either direction.
#
# THIS DEPENDS ON THE resume-on-TX KERNEL PATCH. Bringing the adapter back up
# writes HCI commands to a port that is still suspended. Before that patch the
# write was voted for but never sent, so `hciconfig hci0 up` failed with
# "Connection timed out (110)" and Bluetooth could not be recovered without a
# reboot -- which would have made this service a trap. With it, the transition
# was measured clean: 7 devices discovered and RX bytes flowing again after an
# unpin/suspend/repin cycle.
set -u

U=/sys/devices/platform/soc/4ac0000.qcom,qupv3_0_geni_se/4a94000.qcom,qup_uart/power/control
POLL=5

[ -w "$U" ] || { echo "sol-bt-uart-pm: $U not writable -- nothing to do"; exit 0; }

# ─── The pin is no longer needed: the watch sleeps with Bluetooth ON ─────────
# Three things had to be true, and all three now are:
#
#   1. the port can wake for RX -- the patched dtbo restores this node's second
#      interrupts-extended entry (<&tlmm 29 2>);
#   2. resuming the port does not veto suspend --
#      geni-serial-wakelock-only-on-rx gates __pm_stay_awake(geni_wake) on
#      check_wakeup_byte, so the port's wakeup source now reads 0 activations
#      where it used to show 2065 and 404 s of blocking;
#   3. the port no longer REFUSES the suspend --
#      geni-serial-force-suspend-like-spi force-suspends a voteless port instead
#      of returning -EBUSY, which is what the sibling GENI SPI driver already
#      does on this SoC.
#
# Measured with all three in place, Bluetooth ON and the port on auto:
# 216 suspends in 487 s (it was exactly 0 before, always), fail 19, and the
# blocking device is no longer this port. Bluetooth is unharmed by those cycles:
# hci0 UP RUNNING, a scan finds seven devices, RX flowing, errors 0.
#
# So do not pin. Pinning holds a runtime-PM usage count, which blocks suspend
# regardless of the kernel fixes -- it would silently undo all of the above.
#
# Detect rather than assume: the dtbo is flashed separately from the rootfs and
# the kernel separately again. Without the wakeup IRQ the port cannot receive
# while suspended, and pinning is still the lesser evil (~29 mA and no sleep,
# versus ~75 mA and no sleep unpinned on an unfixed kernel).
IE=/sys/firmware/devicetree/base/soc/qcom,qupv3_0_geni_se@4ac0000/qcom,qup_uart@4a94000/interrupts-extended
WAKEUP_IRQ=no
if [ -r "$IE" ]; then
    sz=$(wc -c < "$IE" 2>/dev/null || echo 0)
    [ "$sz" -ge 28 ] && WAKEUP_IRQ=yes
fi

if [ "$WAKEUP_IRQ" = yes ]; then
    echo "sol-bt-uart-pm: wakeup IRQ present -- leaving the port on auto so the watch sleeps with BT on"
    echo auto > "$U" 2>/dev/null || true
    exec sleep infinity
fi
echo "sol-bt-uart-pm: no wakeup IRQ (stock dtbo) -- pinning while BT is on, as before"

want_prev=""
while true; do
    # TRIGGER ON INTENT, NOT ON STATE. The obvious test -- "is hci0 UP RUNNING"
    # -- deadlocks, and did on hardware: the adapter cannot come up while the
    # port is asleep, so a service that waits for it to be up never pins and
    # Bluetooth can never be switched back on. bluez exposes the intent
    # separately, which is what makes this safe. Measured on sol:
    #
    #     BT on      Powered=true   PowerState='on'    hci0 UP RUNNING
    #     BT off     Powered=false  PowerState='off'   hci0 DOWN
    #     wanted on, port asleep    Powered=false  PowerState='on'   <- the trap
    #
    # PowerState is 'on' in that third row while Powered is still false, so
    # pinning on PowerState breaks the deadlock and pinning on Powered would not.
    # 2>&1, NOT 2>/dev/null: gdbus reports "no such adapter" as an
    # UnknownObject error on STDERR and exits 0. Discarding stderr left $state
    # empty, the empty string fell through to the "unreadable, change nothing"
    # branch below, and the port stayed pinned with no adapter -- which is
    # exactly the deadlock the UnknownObject case exists to prevent. Caught by
    # restarting patchram with this service live; a clean boot cannot catch it,
    # because on a first boot hci0 already exists by the time this starts.
    state=$(timeout 10 gdbus call --system --dest org.bluez \
        --object-path /org/bluez/hci0 \
        --method org.freedesktop.DBus.Properties.Get \
        org.bluez.Adapter1 PowerState 2>&1)

    case "$state" in
        # NO ADAPTER AT ALL. This must release the port, and getting it wrong
        # deadlocks Bluetooth permanently -- it did, on 2026-08-19, with patchram
        # stuck in a restart loop at counter 30 and hci0 never appearing.
        # patchram's own comment records why: control=on DURING INIT makes
        # brcm_patchram_plus block and never create hci0, while auto-during-init
        # then pinning is the ordering that works. So while no adapter exists,
        # the only safe state is auto -- exactly what patchram needs to bring one
        # up. Pinning "to be safe" here is what makes sure one never appears.
        *UnknownObject*|*ServiceUnknown*|*NoSuchAdapter*) want=auto ;;

        # 'off' and 'off-blocked' are the states where nobody wants the radio.
        *"'off'"*|*"'off-blocked'"*)                      want=auto ;;

        # A real answer that is not 'off' -- including the transitional
        # 'off-enabling' -- means keep the port awake.
        *"'"*)                                            want=on ;;

        # Anything else is an unreadable answer: a timeout, bluez momentarily
        # busy, a shape we do not recognise. Change nothing rather than guess in
        # either direction, and let the next poll decide on real information.
        *)                                                want=${want_prev:-auto} ;;
    esac

    if [ "$want" != "$want_prev" ]; then
        if echo "$want" > "$U" 2>/dev/null; then
            if [ "$want" = "on" ]; then
                echo "sol-bt-uart-pm: bluetooth wanted on -- uart pinned awake (no suspend while BT is on)"
            else
                echo "sol-bt-uart-pm: bluetooth off -- uart released, the SoC may suspend"
            fi
            want_prev=$want
        else
            echo "sol-bt-uart-pm: failed to write $want"
        fi
    fi
    sleep "$POLL"
done
