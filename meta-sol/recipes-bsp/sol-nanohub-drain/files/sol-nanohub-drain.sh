#!/bin/sh
# /usr/bin/sol-nanohub-drain.sh
#
# Keeps the nanohub buffer pool from being exhausted by channels nothing reads.
#
# THE BUG (full analysis: .investigation-logs/20260816_sol_nanohub_pool_exhaustion.md):
# google-modules/nanohub gives all 30 channels ONE shared pool of exactly 20
# buffers (READ_QUEUE_DEPTH). A buffer returns to that pool only when userspace
# read()s it. nanohub_process_buffer() drops packets for unopened channels ONLY
# when id == ID_NANOHUB_CLIENT:
#
#     if (id == ID_NANOHUB_CLIENT && atomic_read(&io->busy) != 1) {
#             pr_info("nanohub: dropping packet for /dev/nanohub/%d\n", id);
#     } else if (!io->is_kernel) {
#             nanohub_io_put_buf(io, *buf);      /* queued unconditionally */
#
# and nanohub_release()'s "discard packets on release" sweep is likewise
# CLIENT-only. So every special-purpose userspace channel accumulates buffers
# forever on a watch that does not open it.
#
# CONFIRMED ON HARDWARE (aurora, 2026-08-16): the pool was found FULLY
# EXHAUSTED -- 20 of 20 buffers stranded on /dev/nanohub_metrics after 8h17m of
# uptime (1 removed by the first probe, 19 more by the drain loop, then the
# channel blocked). That watch's sensors were already dead; every systemd unit
# still reported healthy, sensorfwd included, which is what makes this hide.
# Container HALs DO hold some channels open (displayoffload takes display/
# render/brightness, mcu_mgmtd takes debug_log), so this is not "nothing reads
# any of them" -- it is specifically the orphans, and metrics is the one with
# real traffic.
#
# Once 20 buffers are stranded, the reader kthread's non-blocking
# nanohub_io_get_buf(&data->free_pool, false) returns NULL, the whole read body
# is skipped, and THE DRIVER STOPS READING THE MCU ALTOGETHER. Every sensor dies,
# which is the head of kido's chain: multihal starves -> hybris blocks ->
# sensorfwd stops answering DBus -> mce blocks in an untimed DBus call while
# holding a wakelock -> no suspend, drain, dead tap-to-wake and compass.
#
# THIS IS THE UGLY-BUT-LOCAL FIX. The correct fix is in the driver (extend the
# busy guard and the release sweep to every non-kernel channel), but nanohub is
# shared with aurora and the rest of the Google-watch fleet, so that belongs in
# front of the maintainers, not in a sol bring-up branch.
#
# IT IS ALSO THE EXPERIMENT. The byte counters it logs are the hardware evidence
# the source analysis is still missing: if a channel reports steadily growing
# bytes, traffic really does arrive there and really would have leaked.
set -u

INTERVAL=60          # how often to report counters
GRACE=90             # see below -- do NOT remove
STATE=/run/sol-nanohub-drain

# WAIT BEFORE DECIDING WHO OWNS WHAT.
#
# The holder scan is only meaningful once the Android container's HALs have
# actually opened their nodes. displayoffload/mcu_mgmtd/chre come up some time
# after sol-lxc-android.service starts, so a scan run immediately at boot would
# see an empty field, conclude "nobody reads brightness/display/render", and
# start draining channels that displayoffload is about to claim -- stealing its
# packets. That would turn this fix into a considerably worse bug than the one
# it addresses. The grace delay plus the per-read re-check below are what keep
# that from happening.

# EVERY non-kernel channel is listed. The runtime holder check below -- not this
# list -- is what keeps us off channels somebody else reads, and that matters
# because the reader set DIFFERS BETWEEN WATCHES. Measured on aurora 2026-08-16:
#
#   /vendor/bin/mcu_mgmtd                    -> nanohub, nanohub_debug_log
#   ...displayoffload@2.0-service.1p         -> nanohub_display, _render, _brightness
#   /vendor/bin/chre                         -> nanohub
#   NOBODY                                   -> nanohub_metrics, _console, _rpc0, _rpc1
#
# and of those four orphans only METRICS carried traffic: it held the ENTIRE
# 20-buffer pool after 8h17m of uptime. If sol's container
# does not run displayoffload, then brightness/display/render are orphans HERE
# too and this list must already cover them -- hence listing everything and
# letting the holder check decide per boot, per watch.
# 2026-08-21: _brightness, _display and _render are DELIBERATELY NOT LISTED any
# more. displayoffload is started again (it draws the always-on watchface) and,
# exactly as on aurora, it holds and reads all three from one pid -- so they are
# no longer "channels nothing reads" and need no draining. The holder check below
# would skip them anyway once displayoffload has them, but only if it wins the
# race at boot; leaving them out removes the race instead of relying on ordering.
# If displayoffload is ever stubbed again, put them back or the pool leaks.
NODES="/dev/nanohub_metrics
/dev/nanohub_console
/dev/nanohub_rpc0
/dev/nanohub_rpc1
/dev/nanohub_debug_log
/dev/nanohub_pele
/dev/nanohub_bt"

log() { echo "sol-nanohub-drain: $1"; }

# Refuse to touch a node another process already has open.
#
# Scans /proc/*/fd rather than trusting fuser (not present on this image). A zero
# result here is a claim that NOTHING holds the node -- so it must be a method
# that can actually see an opener. Validate it once at startup against a node
# known to be open (the multihal holds a CLIENT id), and say so in the log, so a
# silently-broken scan cannot masquerade as "nothing is listening".
holder_of() {
    want_dev=$(stat -c '%t:%T' "$1" 2>/dev/null)
    want_base=$(basename "$1")
    for l in /proc/[0-9]*/fd/*; do
        t=$(readlink "$l" 2>/dev/null) || continue
        # Cheap filter first; only the handful of nanohub fds get stat'd.
        case "$t" in *nanohub*) ;; *) continue ;; esac
        # Match on the DEVICE NUMBER, not just the path string. A holder inside
        # the Android container can render a different path for the same node,
        # and a pure string compare would silently miss it -- which would make
        # this function answer "nobody is reading" about a node that is actively
        # read, and the drainer would then steal that reader's packets.
        got_dev=$(stat -Lc '%t:%T' "$l" 2>/dev/null)
        if [ "$got_dev" = "$want_dev" ] || [ "$(basename "$t")" = "$want_base" ]; then
            p=${l#/proc/}; p=${p%%/*}
            echo "$p"
            return 0
        fi
    done
    return 1
}

mkdir -p "$STATE"

log "waiting ${GRACE}s for container HALs to claim their nodes before deciding"
sleep "$GRACE"

# --- startup sanity: can this scan see ANY nanohub opener at all? -------------
seen=""
for n in /dev/nanohub /dev/nanohub_comms; do
    [ -e "$n" ] || continue
    h=$(holder_of "$n") && seen="$seen $n(pid $h)"
done
if [ -n "$seen" ]; then
    log "fd scan validated, sees existing openers:$seen"
else
    log "WARNING: fd scan found no opener on any nanohub node. Either nothing has one (possible) or the scan cannot see them (method broken). Treat the skip decisions below with suspicion."
fi

started=""
for n in $NODES; do
    if [ ! -e "$n" ]; then
        log "skip $n (absent)"
        continue
    fi
    if h=$(holder_of "$n"); then
        log "SKIP $n -- already held by pid $h; draining it would steal that reader's packets"
        continue
    fi

    # One drainer per node. Each iteration is a fresh open/read/close: the read
    # blocks in nanohub_io_get_buf(io, true) until a packet arrives, and the
    # close is harmless because the release-time sweep is CLIENT-only anyway.
    (
        name=$(basename "$n")
        total=0; pkts=0; iters=0
        # EFFICIENCY FIX 2026-09-02: holder_of() walks /proc/*/fd (forking
        # readlink/stat per fd) and running it before EVERY read made this the
        # top awake-CPU consumer (76% of awake ticks; ~4.5mA measured). Traffic
        # channels block in dd (cheap); orphan channels return EOF instantly, so
        # the old per-read holder_of + sleep 1 spun the /proc scan ~1Hz/channel.
        # Now: block in dd for traffic, back off hard on EOF, and re-check the
        # holder only every 20 iterations (out of the hot path). The drained
        # nodes are true orphans (held nodes are skipped at startup), so a slow
        # re-check cannot steal a HAL's packets.
        while :; do
            got=$(dd if="$n" bs=255 count=1 2>/dev/null | wc -c)
            if [ "${got:-0}" -gt 0 ]; then
                total=$((total + got))
                pkts=$((pkts + 1))
                echo "$pkts $total" > "$STATE/$name"
            else
                sleep 60
            fi
            iters=$((iters + 1))
            if [ $((iters % 20)) -eq 0 ] && hn=$(holder_of "$n"); then
                log "STOPPING drain of $n -- pid $hn has claimed it (drained ${pkts}pkt/${total}B)"
                exit 0
            fi
        done
    ) &
    started="$started $(basename "$n")"
    log "draining $n"
done

[ -n "$started" ] || { log "nothing to drain; exiting"; exit 0; }
log "drainers running for:$started"

# Periodic report. This is the evidence trail -- a channel whose counter climbs
# is a channel that WOULD have leaked buffers out of the 20-deep shared pool.
while :; do
    sleep "$INTERVAL"
    line=""
    for f in "$STATE"/*; do
        [ -e "$f" ] || continue
        read -r p t < "$f" 2>/dev/null || continue
        line="$line $(basename "$f")=${p}pkt/${t}B"
    done
    [ -n "$line" ] && log "drained:$line"
done
