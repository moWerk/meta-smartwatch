#!/bin/sh
# Restore the container's flattened /apex AFTER Android init switches mount
# namespace. Runs on the HOST, entering init's CURRENT namespace.
#
# WHY THIS CANNOT BE DONE INSIDE init.rc.
# init switches mount namespace partway through boot -- measured on sol:
#     t=4s   ns=mnt:[4026532809]  apex=32   (bootstrap namespace)
#     t=10s  ns=mnt:[4026532814]  apex=0    (default namespace)
# Every `on <stage>` rebind runs in the bootstrap namespace and is discarded by
# the switch, which is why six different anchor points all failed identically.
# A service does not help either: it is FORKED before the switch, so it inherits
# the bootstrap namespace and its mount lands there whenever it runs. That is
# exactly what halium-apexfix did -- exited 0, changed nothing -- while the same
# command via nsenter works every time.
#
# Detection needs no namespace bookkeeping: /apex is populated before the switch
# and empty after it, so "empty on two consecutive checks" means we are past it.
#
# nsenter can execute something even with /apex empty because
# /system/bin/bootstrap/linker plus /system/lib/bootstrap bionic exist -- the
# same path servicemanager, logd and lmkd already use to run in this state.
# /system/bin/linker points into the empty /apex, so the bootstrap linker must
# be invoked explicitly with the binary as its argument.
set +e

STASH=${STASH:-/postinstall}
LINKER=/system/bin/bootstrap/linker
TOYBOX=/system/bin/toybox
empty=0

for _ in $(seq 1 180); do
    sleep 1
    pid=$(lxc-info -n android -pH 2>/dev/null)
    [ -n "$pid" ] || continue
    [ -d "/proc/$pid/root/apex" ] || continue

    if [ "$(ls "/proc/$pid/root/apex" 2>/dev/null | wc -l)" = "0" ]; then
        empty=$((empty + 1))
    else
        empty=0
        continue
    fi
    [ "$empty" -ge 2 ] || continue

    nsenter -t "$pid" -m -p -- "$LINKER" "$TOYBOX" mount -o bind "$STASH" /apex 2>/dev/null
    n=$(ls "/proc/$pid/root/apex" 2>/dev/null | wc -l)
    if [ "$n" != "0" ]; then
        echo "sol-apex-restore: /apex restored post-switch ($n entries)"
        nsenter -t "$pid" -m -p -- /apex/com.android.runtime/bin/linkerconfig \
                --target /linkerconfig 2>/dev/null
        echo "sol-apex-restore: linkerconfig regenerated ($(wc -c < "/proc/$pid/root/linkerconfig/ld.config.txt" 2>/dev/null) bytes)"
        exit 0
    fi
    empty=0
done

echo "sol-apex-restore: WARNING never fired; /apex left empty" >&2
exit 1
