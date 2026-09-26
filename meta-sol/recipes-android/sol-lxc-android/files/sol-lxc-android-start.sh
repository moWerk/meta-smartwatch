#!/bin/sh
# Host-side setup for sol's Halium Android container, then launch it.
# Adapted from meta-aurora's aurora-lxc-android-start.sh (kido); the structure
# and most of the reasoning are his. Differences from aurora are marked SOL.

exec >/var/log/sol-lxc-android.log 2>&1
echo "sol-lxc-android: =================== boot start ==================="
date 2>&1 || true
set -e

ROOTFS=/var/lib/lxc/android/rootfs

if ! mountpoint -q $ROOTFS; then
    echo "sol-lxc-android: $ROOTFS not mounted, aborting" >&2
    exit 1
fi

# The container root stays read-only. Do NOT overlay it: an overlayfs in the
# container mount tree makes Android init SIGSEGV in early second stage.

# /dev/__properties__ is bind-mounted from the host and persists across runs;
# init (the property writer) SIGSEGVs if it re-mmaps a stale area.
rm -rf /dev/__properties__/* 2>/dev/null || true
mkdir -p /dev/__properties__ /dev/socket

# Clean ephemeral mounts from a previous run. The rootfs mount survives container
# restarts, so a stale /apex (apexd's bind mounts) makes the FIPS self-test fail
# and the container reboot-loops.
for _m in apex data mnt; do
    umount -R "$ROOTFS/$_m" 2>/dev/null || umount -l "$ROOTFS/$_m" 2>/dev/null || true
done

# binderfs on the host; bound into the container via the lxc config.
mkdir -p /dev/binderfs
if ! mountpoint -q /dev/binderfs; then
    mount -t binder binder /dev/binderfs 2>/dev/null \
        && echo "sol-lxc-android: mounted binderfs" \
        || echo "sol-lxc-android: binderfs mount failed" >&2
fi

# Expose the binder nodes to the HOST too: libhybris in asteroid-launcher opens
# /dev/hwbinder to reach the container's composer and allocator HALs. Without
# these symlinks getService() fails and there are no pixels.
for _b in binder hwbinder vndbinder; do
    [ -e "/dev/binderfs/$_b" ] && ln -sf "/dev/binderfs/$_b" "/dev/$_b" 2>/dev/null || true
done

# Bind sol's own A14 vendor into the A13 container. This is the frankenport
# seam: Halium system + sol vendor. Never bind /android/system over
# $ROOTFS/system -- the container's own /system is the Halium one and is what
# makes libhybris work at all.
# system_ext and product must be bound in as well: Android init compiles the
# sepolicy CIL at boot and system_ext's fragment declares types the vendor
# policy references. Without it secilc fails and init aborts before starting
# anything.
# /android/odm is in this list to break a symlink LOOP, not for its contents.
# The image has /odm/etc -> /vendor/odm/etc while vendor has /vendor/odm -> /odm,
# so resolving the SKU manifest libvintf looks for
# (/odm/etc/vintf/manifest_GGE4J.xml, ro.boot.hardware.sku=GGE4J) cycles forever:
#     hwservicemanager: getDeviceHalManifest: -40 VINTF parse error:
#       Cannot read /odm/etc/vintf/manifest_GGE4J.xml:
#       Too many symbolic links encountered
# ELOOP aborts the WHOLE device-manifest fetch, so servicemanager gets no vendor
# VINTF at all and rejects every vendor HAL with "Could not find <X> in the VINTF
# manifest" -- composer3, keymint, boot, power, nfc, qseecom, qteeconnector.
# Binding the real odm partition makes /odm/etc a real directory, so the lookup
# is a plain ENOENT, which libvintf tolerates.
for src in /android/vendor /android/vendor_dlkm /android/system_ext /android/product /android/odm; do
    name=$(basename "$src")
    dst="$ROOTFS/$name"
    mountpoint -q "$dst" && continue
    [ -d "$dst" ] || continue
    mount --bind "$src" "$dst"
    mount -o remount,ro,bind "$dst"
    echo "sol-lxc-android: bound $src -> $dst"
done

# SOL: slot A, so the dm names end _a (aurora is _b). Created by
# sol-vendor-mount.service.
if [ -b /dev/mapper/system_dlkm_a ] && [ -d $ROOTFS/system_dlkm ]; then
    mountpoint -q $ROOTFS/system_dlkm || \
        mount -o ro /dev/mapper/system_dlkm_a $ROOTFS/system_dlkm 2>/dev/null \
            && echo "sol-lxc-android: mounted /system_dlkm"
fi

# SOL: metadata is mmcblk0p54.
if [ -b /dev/mmcblk0p54 ] && [ -d $ROOTFS/metadata ]; then
    mountpoint -q $ROOTFS/metadata || \
        mount -o noatime,nosuid,nodev,discard /dev/mmcblk0p54 $ROOTFS/metadata 2>/dev/null \
            && echo "sol-lxc-android: mounted /metadata"
fi

# SOL: the modem partition (vfat) is mmcblk0p43, not aurora's p44. It is where
# WLAN and BT firmware live, and sol-vendor-mount already mounts it host-side at
# /vendor/firmware_mnt -- which is inside the vendor bind above, so the container
# inherits it. Nothing to do here; kept as a note so nobody re-adds it.

# Mask the vendor's USB init scripts. AsteroidOS owns the USB gadget end to end
# (usb-moded plus init_gfs), and Qualcomm's vendor init would rewrite g1's
# functions and rebind the UDC, which costs us adb -- the one channel we debug
# through. Bind an empty file over each so Android init parses nothing.
#
# The hw/ glob is load-bearing, not belt-and-braces: init.swp5100.usb.rc lives in
# hw/, and it is what resets the SoC. Bisected to it on 2026-08-15 through the
# import chain init.qcom.rc:33 -> init.target.rc:61 -> init.sw5100.rc:62. It
# writes /config/usb_gadget/g1/UDC more than twenty times and rm's g1's function
# links, on the very gadget our host has already bound to 4e00000.dwc3 -- so this
# is the same hazard the paragraph above describes, escalated from "costs us adb"
# to a traceless SoC-level reset. Dropping only that one import survives, with the
# container at 82 processes and the composer up; leaving it in resets every time.
VENDOR_INIT="$ROOTFS/vendor/etc/init"
if [ -d "$VENDOR_INIT" ]; then
    for rc in "$VENDOR_INIT"/*usb*.rc "$VENDOR_INIT"/*gadget*.rc "$VENDOR_INIT"/*configfs*.rc \
              "$VENDOR_INIT"/hw/*usb*.rc "$VENDOR_INIT"/hw/*gadget*.rc "$VENDOR_INIT"/hw/*configfs*.rc; do
        [ -f "$rc" ] || continue
        mountpoint -q "$rc" && continue
        empty="/run/sol-mask-$(basename "$rc")"
        : > "$empty"
        mount --bind "$empty" "$rc" && echo "sol-lxc-android: masked $(basename "$rc")"
    done
fi

# All three servicemanagers must run with libselinux_stubs.so LD_PRELOADed: our
# kernel has no selinuxfs, so they abort on selinux_status_open, and their
# addService access checks otherwise fail closed -- meaning the composer never
# registers IComposer on hwbinder and the launcher never gets a display.
# The stub ships in the Halium rootfs at /system/lib/.
stub_sm_rc() {
    _tgt="$1"; _tmp="/run/sol-$(basename "$1")"
    [ -f "$_tgt" ] || { echo "sol-lxc-android: $_tgt missing, skip stub"; return 0; }
    mountpoint -q "$_tgt" && return 0
    cat > "$_tmp"
    mount --bind "$_tmp" "$_tgt" && echo "sol-lxc-android: stubbed $(basename "$_tgt")"
}

# vndservicemanager: NO LD_PRELOAD, for the same reason as servicemanager above.
#
# This one was missed when the preload was dropped from servicemanager, and the
# consequence was subtle rather than obvious: vndservicemanager died, so nothing
# ever claimed the context-manager role on /dev/vndbinder, and the display
# composer then sat in an infinite retry loop --
#     W ProcessState: Not able to get context object on /dev/vndbinder.
#     E ServiceManagerCppClient: Waiting 1s on context object on /dev/vndbinder.
# -- never registering android.hardware.graphics.composer3.IComposer/default.
# The composer LOOKS healthy while this happens: stable pid, 2 threads, sleeping
# in nanosleep. `service check` showing the interface absent is what gives it
# away, not the process list.
stub_sm_rc "$ROOTFS/vendor/etc/init/vndservicemanager.rc" <<'RC'
service vndservicemanager /vendor/bin/vndservicemanager /dev/vndbinder
    class core
    user system
    group system readproc
    onrestart class_restart main
    onrestart class_restart hal
    onrestart class_restart early_hal
    shutdown critical
RC

# hwservicemanager: A14 moved it to /system_ext, so the aurora path
# (/system/etc/init/hwservicemanager.rc) does not exist here -- the script used
# to log "missing, skip stub" and carry on.
#
# Stubbed WITHOUT `critical` and `shutdown critical`. As shipped it carries both,
# so when it aborts init counts the restarts and gives up:
#     init: Service 'hwservicemanager' (pid 420) received signal 6
#     init: critical process 'hwservicemanager' exited 4 times before boot completed
#     init: InitFatalReboot: signal 6
# and the container is gone before anything else can be diagnosed.
#
# Losing it may be survivable: hwservicemanager brokers HIDL (hwbinder)
# services, and sol's vendor ships AIDL composer3 and allocator-V2-ndk, which
# register with plain servicemanager. aurora needs it because its A13 vendor is
# HIDL. If something here does need it, make it work at this spot rather than
# merely survive.
# hwservicemanager: NOT `disabled`, because sol's TEE chain is still HIDL.
#
# The comment above reasoned that losing hwservicemanager might be survivable
# since sol's vendor ships AIDL composer3. That is true for the composer and
# FALSE for security: the services that get the TEE up are all HIDL @1.0 and
# they cannot register without it, so they crash in main() on a loop:
#     vendor.qti.hardware.qseecom@1.0-service
#     vendor.qti.hardware.qteeconnector@1.0-service
#     android.hardware.security.keymint-service.strongbox.nxp
# and keymint-service-qti then never registers IKeyMintDevice, so keystore2 dies
# with "Cannot connect to Keymint" and its restart storm stalls the whole
# container at 33 processes.
#
# `disabled` means init only starts it on demand, and nothing in this container
# demands it -- it only ever ran here because it was started by hand. Dropping
# `disabled` (and keeping it out of a class that init never reaches) is what
# makes it come up on its own.
stub_sm_rc "$ROOTFS/system_ext/etc/init/hwservicemanager.rc" <<'RC'
service hwservicemanager /system/system_ext/bin/hwservicemanager
    user system
    group system readproc
    onrestart setprop hwservicemanager.ready false
    class core
RC

# servicemanager: NO LD_PRELOAD, and NOT critical.
#
# The stub library above exists for a premise that no longer holds. It was
# written when this kernel had no selinuxfs at all, so anything calling
# selinux_status_open() aborted. Since the CONFIG_LSM reordering, selinuxfs is
# real and mounted:
#     /sys/fs/selinux/{access,avc,booleans,checkreqprot,class,...}
#     enforce = 0        (permissive, via androidboot.selinux=permissive)
# so real libselinux now works, and preloading stubs over it means
# servicemanager talks to a fake status page while its actual security context
# is genuine (audit shows subj=u:r:servicemanager:s0). That mismatch is the
# leading suspect for the SIGABRT, so the preload is dropped here rather than
# carried forward out of habit.
#
# `critical` is dropped too. That is a blast-radius change, not a functional
# one: it only stops init from tearing down the whole container after four
# restarts, so the next failure is observable instead of terminal. If
# servicemanager still aborts, it aborts visibly and the rest of init proceeds.
stub_sm_rc "$ROOTFS/system/etc/init/servicemanager.rc" <<'RC'
service servicemanager /system/bin/servicemanager
    class core animation
    user system
    group system readproc
    onrestart restart apexd
    onrestart class_restart --only-enabled main
    onrestart class_restart --only-enabled hal
    onrestart class_restart --only-enabled early_hal
    shutdown critical
RC

# surfaceflinger: NEVER start it. It is the reason the launcher could not get a
# composer client for most of the display bring-up.
#
# composer3 permits exactly ONE client. surfaceflinger takes it at startup and
# never lets go, so asteroid-launcher's AidlComposer ctor died on
#     createClient FAILED: Status(-8, EX_SERVICE_SPECIFIC): '6: '
# every single time, including against a composer that had just been restarted
# -- which is what disproved the obvious "stale client from a crashed launcher"
# theory. Measured on hardware 2026-08-13: with surfaceflinger killed the very
# next launcher run got `createClient OK` and went on to composite.
#
# A HAL-only container has no use for surfaceflinger at all: asteroid-launcher
# IS the compositor. Nothing here consumes its pdx sockets either, so the stub
# drops them.
#
# Two things are required, and `disabled` alone is NOT enough:
#   - `disabled` stops class_start from starting it, but `restart surfaceflinger`
#     from another service's onrestart line still would (see the allocator stub
#     below, which is where that came from).
#   - the class must be one init never starts. Stock is `core animation`, and
#     init.rc does class_start core, so leaving the class alone would start it
#     regardless. Same reasoning as the hwservicemanager stub above.
stub_sm_rc "$ROOTFS/system/etc/init/surfaceflinger.rc" <<'RC'
service surfaceflinger /system/bin/surfaceflinger
    class sol_never_started
    user system
    group graphics drmrpc readproc
    capabilities SYS_NICE
    disabled
RC

# The display allocator, with `onrestart restart surfaceflinger` removed.
#
# Everything else is byte-identical to the stock rc. That one line resurrects
# surfaceflinger every time the allocator (re)starts, and a resurrected
# surfaceflinger immediately re-steals the single composer client. This was
# observed repeatedly while testing by hand: kill surfaceflinger, start the
# allocator, and surfaceflinger is alive again before the launcher can run.
# It also produces a genuinely misleading state -- the panel lights up and
# looks correct while it is surfaceflinger drawing, with the launcher dead.
#
# Nothing in this container needs surfaceflinger restarted when the allocator
# restarts, because nothing here uses surfaceflinger.
stub_sm_rc "$ROOTFS/vendor/etc/init/vendor.qti.hardware.display.allocator-service.rc" <<'RC'
service vendor.qti.hardware.display.allocator /vendor/bin/hw/vendor.qti.hardware.display.allocator-service
    class hal animation
    user system
    group graphics drmrpc
    capabilities SYS_NICE
RC



# zygote: NOT started. There is no Android framework in this container.
#
# zygote is the app runtime and it launches the system server. A HAL-only
# container has neither, and it cannot even start: BOOTCLASSPATH and
# DEX2OATBOOTCLASSPATH are empty without a framework, so it aborts
#
#     Abort message: 'Check failed: !location.empty()
#       BOOTCLASSPATH and DEX2OATBOOTCLASSPATH must not be empty'
#
# and init restarts it about every five seconds, forever. Three costs, none of
# them visible from outside the container: a SIGABRT and a debuggerd tombstone
# per cycle, `onrestart write /sys/power/wake_lock zygote_kwl` re-taking a
# wakelock on every cycle, and `onrestart restart audioserver` resurrecting the
# service the stub below exists to keep down.
#
# `class main` is what starts it, so the class has to become one init never
# reaches, and the onrestart lines go with it.
stub_sm_rc "$ROOTFS/system/etc/init/hw/init.zygote32.rc" <<'RC'
service zygote /system/bin/app_process -Xzygote /system/bin --zygote --start-system-server
    class sol_never_started
    priority -20
    user root
    group root readproc reserved_disk
    disabled
RC

# audioserver: NOT started. PulseAudio is the audio server on this device.
#
# The in-process audio.primary that module-droid-card loads and Android's
# audioserver are two owners of one HAL and one AudioReach DSP graph. With
# audioserver running, module-droid-card loads the module and then blocks: PA's
# main thread sits in futex_wait with an idle HwBinder thread and no pending
# transaction, and PA never becomes responsive again. aurora, same monaco
# AudioReach architecture and the same in-process HAL under PA, does not run
# audioserver at all -- which is why audio works there.
#
# `class core` is what starts it, since init.rc does class_start core, so the
# class has to become one init never reaches. The onrestart lines go too: they
# resurrect vendor.audio-hal and friends, the same way the display allocator's
# onrestart resurrected surfaceflinger.
stub_sm_rc "$ROOTFS/system/etc/init/audioserver.rc" <<'RC'
service audioserver /system/bin/audioserver
    class sol_never_started
    user audioserver
    group audio camera drmrpc media mediadrm net_bt net_bt_admin net_bw_acct wakelock
    capabilities BLOCK_SUSPEND
    rlimit rtprio 10 10
    ioprio rt 4
    task_profiles ProcessCapacityHigh HighPerformance
    disabled
RC


# vendor.modem_svc: NEVER start it. This watch has no modem, and starting the
# modem subsystem on a modem-less unit RESETS THE WHOLE SoC.
#
# The kernel says so every boot at ~0.9s: `modem_supported=0x0`. sol ships in
# LTE and BT/WiFi variants and this unit is the latter. Kicking
# 6080000.remoteproc-mss fails the firmware load, and Qualcomm's
# subsystem-restart then escalates to a full SoC reset. That exact mechanism
# already bit this port once from the host side and was fixed by removing the
# kick from sol-vendor-mount (commit a2dfc57e).
#
# /vendor/bin/modem_svc is `class core`, and class_start core runs in `on boot`
# immediately after class_start hal. So it could never fire until now: the
# container had always stalled earlier (late-fs, then post-fs-data). The first
# time init actually reached `on boot` -- 2026-08-13, once the userdata fstab
# entry, the TEE modules and the apexd wait were all cleared -- the composer
# started, class main came up, and the device reset shortly after and had to be
# recovered from fastboot.
#
# CAUTION on timing when re-testing: the reset is USERLAND-RELATIVE, roughly
# 35-40s after the trigger runs, NOT boot-relative. A container restart that
# survives 60s past `on boot` is meaningful; one watched for 20s is not.
#
# Same shape as the surfaceflinger stub: `disabled` alone is not enough because
# another rc could `restart` it, so the class is also one init never starts.
stub_sm_rc "$ROOTFS/vendor/etc/init/vendor.google.modem_svc.rc" <<'RC'
service vendor.modem_svc /vendor/bin/modem_svc -q
    class sol_never_started
    user root
    group system
    capabilities NET_BIND_SERVICE
    disabled
RC

# displayoffload: NOT started. mce owns the display on this watch.
#
# It is Wear's display-offload HAL: it holds /dev/nanohub_brightness and
# /dev/nanohub_display and drives panel brightness from the MCU. Two things come
# out of that here, and both are visible rather than theoretical.
#
# It fights mce for the panel. mce writes its own 1-100 scale to
# /sys/class/backlight/panel0-backlight, and the panel receives something else
# entirely -- measured with mce set to 10/40/80/100%, the driver logged
# `nbm: 43143, 59278, 51217, 28656` and `hbm_on: 1, hbm_brightness: 255`
# throughout. A brightness set by the user visibly snaps back, and with
# autobrightness on the screen drops to black every few seconds.
#
# It also pumps the panel hard: with this service running the driver takes ~10
# writes per second (150 hbm + 152 backlight in 15s), and killed it goes to
# exactly 0.
#
# What that does NOT mean, because the obvious reading is wrong: this is not the
# nanohub pool leak. Measured on aurora, displayoffload is the *reader* of
# nanohub_brightness, nanohub_display and nanohub_render -- which is why those
# three measured empty while nanohub_metrics, which nothing holds, was the
# channel that had swallowed the pool. See
# .investigation-logs/20260816_sol_nanohub_pool_exhaustion.md.
#
# So stopping it removes a drainer, which looks dangerous and measures safe: with
# the service stopped, those three channels carry no traffic at all -- 0 bytes
# read from each over 2s, because displayoffload was both the writer and the
# reader and the MCU only answers what it is asked. Nothing is left to strand.
#
# sol-nanohub-drain covers them as well, but only from a boot where this stub is
# already in place: it picks its node set at startup and skips whatever another
# process holds, so stopping displayoffload mid-run leaves them unheld (measured:
# still unheld 90s later). That is fine given the traffic is zero, but it is the
# reason to keep the stub and the drainer shipped together rather than relying on
# either alone.
#
# The rc file is replaced wholesale rather than edited: the service is `disabled`
# in it, but the same file carries an `on property:vendor.wac.state=booting`
# block that starts it, so dropping the file drops the trigger with it.
# 2026-08-21: displayoffload is now STARTED, and it is what draws the always-on
# watchface. aurora runs it (holding /dev/nanohub_brightness, _display and
# _render from one pid) and shows an AoD face; sol stubbed it and showed a black
# screen in low-power mode, which moWerk correctly called a 5-star blocker.
#
# It had been failing for a reason that looks nothing like "display":
#
#     Failed to open display mux file: 13          <- 13 = EACCES
#     Unable to reset display mux select to 1
#     Could not initialize DisplayOffload HAL. Exiting...
#
# The HAL switches the panel between the AP and the MCU through
# /sys/devices/virtual/display/display_comms/display_select (it also probes
# .../virtual/nanohub/nanohub_comms/display_select, which does not exist here).
# That node is root:root 0660 and the HAL runs as `system`, so it could not open
# it and exited -- every 5 s, forever. chown-ing it (below, before the container
# starts) is the whole fix: the HAL then logs "Set display mux select to 1",
# registers IDisplayOffload/default and takes all three nanohub channels.
#
# NOTE the MCU side was never the problem: even while failing it logged
# "GetHwCapabilities: successfully parsed 132 bytes from MCU".
stub_sm_rc "$ROOTFS/vendor/etc/init/vendor.google_clockwork.displayoffload@2.1-service.1p.rc" <<'RC'
service vendor.displayoffload-hal-2-1 /vendor/bin/hw/vendor.google_clockwork.displayoffload@2.1-service.1p
    class late_start
    user system
    group system
RC

# The vendor `on late-fs` block opens with
#     wait_for_prop hwservicemanager.ready true
# (/vendor/etc/init/hw/init.sw5100.rc). We stub hwservicemanager as `disabled`
# and in a class init never starts -- as shipped it is `critical` and SIGABRTs,
# which reboots the container -- so that property is NEVER set and init parks in
# late-fs forever. Measured 2026-08-13: init logged
#     processing action (late-fs) from (/vendor/etc/init/hw/init.sw5100.rc:146)
# and stopped there; procs plateaued at 18 and the composer never started.
# NOTE this is a VENDOR rc, so the awk injection over /system/etc/init/hw/init.rc
# does not reach it -- it needs its own bind, like the other vendor rc files.
# Three vendor services restart forever, and none of them can work here:
#
#     time_daemon        SIGABRTs on `capabilities SYS_TIME`; CAP_SYS_TIME is
#                        absent from the container's bounding set
#                        (000001fcfdbfffff vs the host's 000001ffffffffff), so
#                        init cannot apply it and kills the forked child
#     vendor.per_mgr     exits 255 immediately (peripheral manager)
#     vendor.per_proxy   exits 1, started off per_mgr's own init.svc property
#
# Measured over 60s: 12 starts each, 36 service starts a minute, indefinitely.
# Today that costs a debuggerd tombstone per time_daemon cycle and nothing else
# visible. It stops being free the moment the kernel honours wakelocks -- see
# CONFIG_PM_AUTOSLEEP in sw5100.fragment -- because a watch that starts a process
# every 1.7s does not stay asleep.
#
# Rewritten rather than replaced: per_mgr and per_proxy live inside
# init.sw5100.rc and time_daemon is defined twice (init.time_daemon.rc and
# init.qcom.rc), so dropping whole files would take unrelated services with them.
# Moving each to a class init never starts is enough; per_proxy then never fires
# either, since its trigger is per_mgr reaching "running".
for _drc in "$ROOTFS"/vendor/etc/init/*.rc "$ROOTFS"/vendor/etc/init/hw/*.rc; do
    [ -f "$_drc" ] || continue
    grep -qE "^service (time_daemon|vendor\.per_mgr|vendor\.per_proxy) " "$_drc" || continue
    mountpoint -q "$_drc" && continue
    _dtmp="/run/sol-dead-$(basename "$_drc")"
    awk '
        BEGIN { split("time_daemon vendor.per_mgr vendor.per_proxy", t, " ")
                for (i in t) dead[t[i]] = 1 }
        /^[[:space:]]*service / { inblk = ($2 in dead) }
        inblk && /^[[:space:]]*class / { sub(/class .*/, "class sol_never_started") }
        { print }
    ' "$_drc" > "$_dtmp"
    mount --bind "$_dtmp" "$_drc" \
        && echo "sol-lxc-android: parked crash-looping services in $(basename "$_drc")"
done

for _vrc in "$ROOTFS"/vendor/etc/init/hw/init.*.rc; do
    [ -f "$_vrc" ] || continue
    grep -q "wait_for_prop hwservicemanager.ready" "$_vrc" || continue
    mountpoint -q "$_vrc" && continue
    _vtmp="/run/sol-$(basename "$_vrc")"
    sed -E 's|^([[:space:]]*wait_for_prop hwservicemanager\.ready.*)$|    # HALIUM-SOL: hwservicemanager is stubbed disabled -- \1|' \
        "$_vrc" > "$_vtmp"
    mount --bind "$_vtmp" "$_vrc" \
        && echo "sol-lxc-android: dropped hwservicemanager wait in $(basename "$_vrc")"
done

# fstab: comment out the userdata entry, or init NEVER REACHES class_start hal.
#
# This is what stalls container boot short of every `hal` class service --
# composer and allocator included -- so nothing here can bring the display up
# until it is neutered.
#
# The entry in /vendor/etc/fstab.swp5100 is:
#   /dev/block/bootdevice/by-name/userdata /data f2fs noatime,... \
#     latemount,wait,check,formattable,quota,...,fileencryption=...,
#     metadata_encryption=...,keydirectory=/metadata/vold/metadata_encryption,...
# `latemount,wait` is the problem. In `on late-fs`, mount_all --late turns that
# entry into a WAITING exec:
#   /system/bin/vdc cryptfs mountFstab /dev/block/bootdevice/by-name/userdata /data
# which blocks in a binder call to vold (observed: state=S,
# wchan=binder_thread_read) and never returns, because
# /dev/block/bootdevice/by-name/userdata DOES NOT EXIST in this container --
# checked directly through /proc/<init>/root. A HAL-only container has no real
# userdata partition; /data is the tmpfs mounted further up this script. init
# waits on that exec forever, so `on post-fs-data`, `on boot` and
# `class_start hal` are never reached. Diagnosed on hardware 2026-08-13.
#
# The give-away in the process list is that every early_hal service is running
# (keymint, qseecom, qteeconnector, boot-service, suspend, powerstate) while not
# one `hal` service exists -- that brackets the stall precisely.
#
# Two secondary symptoms come from this and are NOT separate bugs, so do not
# chase them: servicemanager retries lazy-starting keystore2 and IStats once a
# second forever (those services live past the stall), which overflows init's
# control queue --
#     init: Too many pending control messages, dropped 'interface_start'
# -- and that in turn makes any `setprop ctl.start ...` fail with "Failed to set
# property", and floods the dmesg ring buffer so no earlier init history
# survives.
#
# Comment the line rather than deleting it, so the stock entry stays readable.
# Every fstab.* is scanned because the filename is board-specific.
for _fst in "$ROOTFS"/vendor/etc/fstab.*; do
    [ -f "$_fst" ] || continue
    grep -qE '^[[:space:]]*/dev/block/bootdevice/by-name/userdata[[:space:]]' "$_fst" || continue
    mountpoint -q "$_fst" && continue
    sed -E 's|^([[:space:]]*/dev/block/bootdevice/by-name/userdata[[:space:]].*)$|# HALIUM-SOL: no real userdata in a HAL-only container, /data is tmpfs -- \1|' \
        "$_fst" > "/run/sol-$(basename "$_fst")"
    mount --bind "/run/sol-$(basename "$_fst")" "$_fst" \
        && echo "sol-lxc-android: neutered userdata latemount in $(basename "$_fst")"
done

# The display mux node the displayoffload HAL must write to switch the panel
# between AP and MCU. root:root 0660 as the kernel creates it, and the HAL runs
# as `system` (uid 1000), so without this it fails with EACCES and exits in a
# loop -- which is why sol had no always-on watchface. Harmless if absent.
for _mux in /sys/devices/virtual/display/display_comms/display_select \
            /sys/devices/virtual/nanohub/nanohub_comms/display_select; do
    [ -e "$_mux" ] && chown 1000:1000 "$_mux" 2>/dev/null && chmod 0660 "$_mux" 2>/dev/null
done

# /data: vold and init_user0 need something writable. tmpfs is fine for a
# HAL-only container and avoids needing mkfs or a real partition.
if [ -d "$ROOTFS/data" ] && ! mountpoint -q "$ROOTFS/data"; then
    mount -t tmpfs -o rw,nosuid,nodev,mode=0771,size=256M android_data "$ROOTFS/data" \
        && chown 1000:1000 "$ROOTFS/data" 2>/dev/null \
        && echo "sol-lxc-android: mounted tmpfs /data" \
        || echo "sol-lxc-android: WARNING /data tmpfs failed -> init_user0 will fail" >&2
fi

# /linkerconfig MUST be writable. On Android it is a tmpfs that init populates:
# early-init does `mkdir /linkerconfig/bootstrap`, writes stub ld.config.txt
# files there, and linkerconfig later generates the real one. In our image
# /linkerconfig is an empty directory on a READ-ONLY mount, so all of that
# silently fails and no linker configuration ever exists.
#
# The cost is not the warning everyone sees ("failed to find generated linker
# configuration") -- it is that dynamically linked binaries then cannot resolve
# their libraries and die with status 127 as if they were missing entirely:
#     init: Service 'vendor.qseecomd' exited with status 127
#     init: cannot execv('/system/bin/vold'): No such file or directory
# (vold is present and 697728 bytes; it is the linker that cannot run it.)
# hwservicemanager then SIGABRTs, hits its 4-restart limit, and init reboots.
if ! mountpoint -q "$ROOTFS/linkerconfig"; then
    mount -t tmpfs -o rw,mode=0755,size=8M android_linkerconfig "$ROOTFS/linkerconfig" \
        && echo "sol-lxc-android: mounted tmpfs /linkerconfig"
fi

# ...and GENERATE the configuration, because nothing else here will.
#
# init only writes a stub "#" ld.config.txt and bind-mounts
# /linkerconfig/bootstrap over /linkerconfig. The real per-namespace config is
# produced by the linkerconfig binary, which on a normal boot is driven by
# apexd -- and apexd is masked here, because with flattened apexes it hangs and
# its reboot_on_failure kills the container.
#
# Without a real config the linker cannot resolve /vendor libraries, and every
# vendor HAL fails in a way that reads like a missing binary:
#     init: cannot execv('/vendor/bin/hw/qconfigservice')
#     init: cannot execv('/system/bin/vold'): No such file or directory
# both of which are present on disk. Generating it here decouples the linker
# from apexd entirely.
if [ -x "$ROOTFS/apex/com.android.runtime/bin/linkerconfig" ]; then
    mount -t proc proc "$ROOTFS/proc" 2>/dev/null
    mount --rbind /dev "$ROOTFS/dev" 2>/dev/null; mount --make-rslave "$ROOTFS/dev" 2>/dev/null
    mount --rbind /sys "$ROOTFS/sys" 2>/dev/null; mount --make-rslave "$ROOTFS/sys" 2>/dev/null
    chroot "$ROOTFS" /apex/com.android.runtime/bin/linkerconfig --target /linkerconfig 2>&1 \
        | grep -viE "^linker: |^WARNING: linker" | head -3
    umount -R "$ROOTFS/sys" 2>/dev/null; umount -R "$ROOTFS/dev" 2>/dev/null; umount "$ROOTFS/proc" 2>/dev/null
    echo "sol-lxc-android: linkerconfig -> $(ls "$ROOTFS/linkerconfig" 2>/dev/null | tr '\n' ' ')"
fi

# ...and GENERATE the configuration, because nothing else will.
#
# init only writes a stub "#" ld.config.txt and bind-mounts
# /linkerconfig/bootstrap over /linkerconfig. The real per-namespace config is
# produced by the linkerconfig binary, which on a normal boot is driven by
# apexd -- and apexd is masked here, because with flattened apexes it hangs and
# its reboot_on_failure kills the container.
#
# Without a real config the linker cannot resolve /vendor libraries, and every
# vendor HAL fails to start in a way that reads like a missing file:
#     init: cannot execv('/vendor/bin/hw/qconfigservice')
#     init: cannot execv('/system/bin/vold'): No such file or directory
# even though those binaries are present. Generating it here decouples the
# linker from apexd entirely.
if [ -x "$ROOTFS/apex/com.android.runtime/bin/linkerconfig" ]; then
    mount -t proc proc "$ROOTFS/proc" 2>/dev/null
    mount --rbind /dev "$ROOTFS/dev" 2>/dev/null; mount --make-rslave "$ROOTFS/dev" 2>/dev/null
    mount --rbind /sys "$ROOTFS/sys" 2>/dev/null; mount --make-rslave "$ROOTFS/sys" 2>/dev/null
    chroot "$ROOTFS" /apex/com.android.runtime/bin/linkerconfig --target /linkerconfig 2>&1 \
        | grep -viE "^linker: |^WARNING: linker" | head -3
    umount -R "$ROOTFS/sys" 2>/dev/null; umount -R "$ROOTFS/dev" 2>/dev/null; umount "$ROOTFS/proc" 2>/dev/null
    echo "sol-lxc-android: linkerconfig generated: $(ls "$ROOTFS/linkerconfig" 2>/dev/null | tr '\n' ' ')"
fi

# /mnt tmpfs plus /persist (SOL: mmcblk0p16, already mounted host-side).
if ! mountpoint -q $ROOTFS/mnt; then
    mount -t tmpfs android_mnt $ROOTFS/mnt
    mkdir -p $ROOTFS/mnt/vendor/persist
fi
if mountpoint -q /persist && ! mountpoint -q $ROOTFS/mnt/vendor/persist; then
    mount --bind /persist $ROOTFS/mnt/vendor/persist \
        && echo "sol-lxc-android: bound /persist"
fi

# /apex: two layouts, and overlaying the wrong one is fatal.
#
#   aurora Halium A13 -> /apex is an empty mountpoint, flattened apexes live
#                        under /system/apex, so a tmpfs + binds is required
#   our A14 image     -> apexes are flattened into /apex already and
#                        /system/apex is empty (a real TARGET_FLATTEN_APEX
#                        build ships no archives)
#
# Mounting a tmpfs over an already-populated /apex HIDES the linker, and
# /system/bin/env is a toybox symlink whose interpreter is
# /apex/com.android.runtime/bin/linker -- so the very first exec fails and the
# container dies with "Failed to exec". Observed 2026-08-11: "/apex now: " empty
# and "linker present: NO" immediately before the spawn failed.
if [ -x "$ROOTFS/apex/com.android.runtime/bin/linker" ]; then
    echo "sol-lxc-android: /apex already populated in the image, leaving it alone"
else
    mountpoint -q $ROOTFS/apex || mount -t tmpfs -o mode=755 android_apex $ROOTFS/apex
    for apex in com.android.runtime com.android.art com.android.i18n; do
        dst=$ROOTFS/apex/$apex
        mountpoint -q "$dst" && continue
        for suffix in .release .debug ""; do
            src=$ROOTFS/system/apex/$apex$suffix
            [ -d "$src" ] || continue
            mkdir -p "$dst"
            mount --bind "$src" "$dst"
            mount -o remount,ro,bind "$dst"
            echo "sol-lxc-android: bound $apex"
            break
        done
    done
fi
# Restore /apex from the stash, using init's OWN mount builtin.
#
# mount-binder.sh (lxc.hook.mount, runs in the container's mount namespace
# before init) binds the real, flattened /apex onto /postinstall. That stash
# survives init mounting its tmpfs over /apex, so the content is still reachable
# -- just not at the path the linker looks in.
#
# The rebind has to happen INSIDE the container, after init's tmpfs lands, and
# it cannot be done from the host: `nsenter -t PID -m` resolves its program
# after entering the namespace, and every mount binary in there
# (/system/bin/mount is a toybox symlink) is dynamically linked through
# /apex/com.android.runtime/bin/linker -- the very thing that is missing. Any
# helper we could exec is unrunnable for exactly the reason we are trying to
# fix.
#
# init's `mount` builtin is not a separate process and needs no linker, so init
# can always do it. We inject the bind at three points because init mounts a
# tmpfs on /apex more than once (one entry from init, one from apexd bootstrap
# were both observed), and each one re-hides the stash; stacked binds are fine
# and the later ones simply win.
#
# post-fs-data is in the list because init's own perform_apex_config runs
# THERE and mounts a fresh tmpfs over /apex, wiping the earlier rebinds. That
# only started mattering once the FBE fixes let init reach post-fs-data at all;
# before that it stalled at late-init and the early binds survived untouched.
#
# The base is the image's own init.rc, which already carries the linkerconfig,
# reboot_on_failure and critical edits -- read it from the mounted rootfs rather
# than from a copy, so those are never silently reverted (doing exactly that
# once cost a boot cycle: an unstripped copy was written back over a stripped
# one and boringssl started rebooting the container again).
# SELinux: mount selinuxfs and load a policy, because nothing else will.
#
# We launch `/init second_stage` deliberately (a bare /init runs FirstStageMain,
# which is wrong here and whose re-exec SIGSEGVs). The cost is that we skip the
# two things first-stage init normally does: mounting selinuxfs, and the
# selinux_setup stage that compiles and loads the policy. Without them Android
# init is dead in the water, and the symptoms do NOT look like SELinux:
#
#   no selinuxfs at all -> every libselinux call fails, so init cannot set any
#   property and stalls at 2 processes behind a wall of
#       init: Init cannot set 'ro.boot.serialno' to '...': SELinux permission
#             check failed        (762 of these in one boot)
#
#   selinuxfs mounted but NO POLICY loaded -> checks still fail rather than
#   being permitted, so init reaches wait_for_coldboot_done, cannot set
#   ro.cold_boot_done, and blocks there forever.
#
# The kernel does have SELinux (cmdline lsm=...,selinux and
# /sys/kernel/security/lsm = capability,selinux); it is only userspace setup
# that was missing. enforcing=0 + androidboot.selinux=permissive keep it
# permissive, so a loaded policy logs denials instead of blocking, which is what
# we want during bring-up.
#
# Hardware-verified 2026-08-12: with both in place the container goes from 2
# processes to 91, SELinux errors from 762 to 0, coldboot completes, and the
# display composer starts and stays up.
setup_selinux() {
    if ! mountpoint -q /sys/fs/selinux 2>/dev/null; then
        mkdir -p /sys/fs/selinux 2>/dev/null
        mount -t selinuxfs selinuxfs /sys/fs/selinux 2>/dev/null \
            && echo "sol-lxc-android: mounted selinuxfs" \
            || { echo "sol-lxc-android: WARNING selinuxfs mount failed" >&2; return 0; }
    fi

    # Already loaded (e.g. restarting the container)? Leave it alone: reloading
    # is unnecessary and re-labels the running host for no gain.
    if [ -s /sys/fs/selinux/policy ] 2>/dev/null; then
        echo "sol-lxc-android: SELinux policy already loaded ($(wc -c < /sys/fs/selinux/policy) bytes)"
        return 0
    fi

    # Compile exactly the pieces selinux_setup would. The mapping file must match
    # the vendor's expected platform version, which vendor states itself.
    vers=$(cat "$ROOTFS/vendor/etc/selinux/plat_sepolicy_vers.txt" 2>/dev/null | tr -d '[:space:]')
    [ -n "$vers" ] || { echo "sol-lxc-android: WARNING no plat_sepolicy_vers.txt, skipping policy" >&2; return 0; }

    set -- "$ROOTFS/system/etc/selinux/plat_sepolicy.cil" \
           "$ROOTFS/system/etc/selinux/mapping/$vers.cil" \
           "$ROOTFS/system_ext/etc/selinux/system_ext_sepolicy.cil" \
           "$ROOTFS/system_ext/etc/selinux/mapping/$vers.cil" \
           "$ROOTFS/product/etc/selinux/product_sepolicy.cil" \
           "$ROOTFS/product/etc/selinux/mapping/$vers.cil" \
           "$ROOTFS/vendor/etc/selinux/plat_pub_versioned.cil" \
           "$ROOTFS/vendor/etc/selinux/vendor_sepolicy.cil"
    for f in "$@"; do
        [ -f "$f" ] || { echo "sol-lxc-android: WARNING missing policy piece $f, skipping" >&2; return 0; }
    done

    out=/run/sol-sepolicy.bin
    if ! "$ROOTFS/system/bin/secilc" -m -M true -G -N -c 30 "$@" -o "$out" -f /dev/null 2>/dev/null; then
        echo "sol-lxc-android: WARNING secilc failed, container will stall in init" >&2
        return 0
    fi

    # MUST be a single write(). selinuxfs 'load' takes the whole policy in one
    # go; `cat` chunks at 128K and the load silently fails, which cost a cycle
    # to spot. dd with bs=<size> count=1 is the reliable form.
    sz=$(wc -c < "$out")
    if dd if="$out" of=/sys/fs/selinux/load bs="$sz" count=1 2>/dev/null; then
        echo "sol-lxc-android: SELinux policy loaded ($sz bytes, enforce=$(cat /sys/fs/selinux/enforce 2>/dev/null))"
    else
        echo "sol-lxc-android: WARNING policy load failed" >&2
    fi
    rm -f "$out"
}
setup_selinux

# HIDL sensors HAL, injected HERE and not from its own systemd unit.
#
# sol's vendor ships only the AIDL sensors service; sensorfw is a HIDL client,
# so without this the watch has no working sensors at all. The mechanics live in
# /usr/libexec/sol-sensors-hidl.sh (see sol-sensors-hidl recipe); what matters
# at THIS call site is the ordering:
#
#   - it must run AFTER setup_selinux, because it mounts a tmpfs with
#     `-o context=u:object_r:hal_sensors_default_exec:s0` and that option is
#     rejected outright until a policy is loaded. As its own unit ordered
#     Before=sol-lxc-android it failed on every clean boot with mount's exit 32
#     while working perfectly when run by hand afterwards -- because by then the
#     container had loaded the policy. That signature is worth remembering.
#   - it must run BEFORE lxc-start, because Android init execs the sensors
#     service from the bind-mounted path and hwservicemanager reads the VINTF
#     manifest exactly once at startup.
#
# Deliberately non-fatal: no sensors is bad, but not a reason to refuse to boot
# the container and lose the UI with it.
if [ -x /usr/libexec/sol-sensors-hidl.sh ]; then
    /usr/libexec/sol-sensors-hidl.sh || \
        echo "sol-lxc-android: WARNING sol-sensors-hidl.sh failed, sensors will be absent" >&2
fi

APEX_STASH=/postinstall
if [ -d "$ROOTFS$APEX_STASH" ] && [ -f "$ROOTFS/system/etc/init/hw/init.rc" ]; then
    if ! mountpoint -q "$ROOTFS/system/etc/init/hw/init.rc"; then
        _irc=/run/sol-init.rc
        awk -v stash="$APEX_STASH" '
            # MUST come before the print rule below: awk runs rules in order, so
            # rewriting $0 after printing would change nothing.
            #
            # Do NOT let init mount its own binderfs over the host'"'"'s.
            # mount-binder.sh binds the HOST binderfs into the container so both
            # sides share one binder instance. Binder contexts do not span
            # binderfs instances, so a second mount here gives host and container
            # separate contexts and libhybris can never reach the container'"'"'s
            # composer. Observed directly: host binder/hwbinder/vndbinder were
            # minors 1/2/3, the container'"'"'s 5/6/... The symlink lines just
            # below it in init.rc still do the right thing, because they now
            # resolve inside the shared instance.
            /^[[:space:]]*mount binder binder \/dev\/binderfs/ {
                $0 = "    # HALIUM-SOL: host binderfs bind-mounted instead -- " $0
            }
            # installkey runs `vdc --wait cryptfs enablefilecrypto`, i.e. sets up
            # file-based encryption on /data. Our /data is a tmpfs (a HAL-only
            # container has no real userdata and no use for FBE), and FBE cannot
            # be enabled on tmpfs, so it fails and init reboots the container:
            #     exec 8 (/system/bin/vdc --wait cryptfs enablefilecrypto)
            #       exited with status 25
            #     init: Exec service failed, status 25: Rebooting into recovery,
            #           reason: enablefilecrypto_failed
            #     init: Got shutdown_command 'reboot,recovery'
            # This only became reachable once the VINTF/odm fix let vold get that
            # far, so it is a symptom of progress, not a regression.
            /^[[:space:]]*installkey \/data[[:space:]]*$/ {
                $0 = "    # HALIUM-SOL: no FBE on a tmpfs /data -- " $0
            }
            # ...and with no FBE key, every `encryption=Require` mkdir fails the
            # policy read and init reboots the container just the same:
            #     init: Unable to read system policy with name /data/unencrypted/ref
            #     init: Rebooting into recovery
            # 28 Require plus 5 DeleteIfNecessary. DeleteIfNecessary is worse
            # than Require here: it does not just fail, it DELETES the directory
            # ("Setting policy failed, deleting: /data/app-staging"). Downgrade all
            # of them to None rather
            # than dropping the mkdir, so the directories still get created with
            # the right owner and mode -- only the encryption policy is skipped.
            /^[[:space:]]*mkdir .*encryption=(Require|Attempt|DeleteIfNecessary)/ {
                sub(/encryption=(Require|Attempt|DeleteIfNecessary)/, "encryption=None")
            }
            # `wait_for_prop apexd.status activated` in on post-fs-data blocks
            # init forever. apexd never runs here -- our apexes are flattened and
            # the apexd-bootstrap exec is commented out a few lines above -- so
            # nothing ever sets that property and init waits in post-fs-data,
            # never reaching on boot or class_start hal. Confirmed on hardware
            # 2026-08-13: the property read back EMPTY while init sat there, and
            # setting it by hand let init continue immediately.
            #
            # Comment the wait out rather than setprop-ing the value early: after
            # a manual `setprop apexd.status activated` the property read back as
            # "ready", i.e. something else rewrites it, so an early setprop would
            # be racy against that writer. Removing the wait has no such race.
            #
            # The two other wait_for_prop lines nearby (odsign.key.done,
            # odsign.verification.done) are NOT blockers -- both already read 1.
            # `vdc checkpoint markBootAttempt` (on post-fs) and its sibling are
            # WAITING execs that ask vold to do A/B filesystem checkpointing.
            # With the userdata fstab entry commented out just above, vold has no
            # checkpointable filesystem and the call never returns, so init parks
            # in on post-fs forever: procs plateaus around 10, class_start hal is
            # never reached and the display composer never starts. Measured on
            # hardware 2026-08-13:
            #     28046 /system/bin/vdc checkpoint markBootAttempt
            #           state=S wchan=futex_wait_queue_me   (init.rc:592)
            # Before the userdata line was commented out this same exec returned
            # in 0.093s ("exited with status 0"), so this stall is a direct
            # consequence of that fix -- one stall traded for another, and both
            # need removing.
            # A HAL-only container on a tmpfs /data has no use for A/B
            # checkpointing at all.
            # `vdc keymaster earlyBootEnded` (on post-fs-data) is another WAITING
            # exec. It tells keystore to stop accepting early-boot keys, via vold.
            # It hangs here, so init parks in post-fs-data and never reaches
            # class_start hal. Measured 2026-08-13: pid stuck as
            #     /system/bin/vdc keymaster earlyBootEnded
            # with the last init action being post-fs-data. Nothing in a HAL-only
            # container consumes early-boot keys, so the signal is pointless.
            # EVERY `exec ... /system/bin/vdc ...` in init.rc is a WAITING exec that
            # hands off to vold. On this container /data is a tmpfs, there is no
            # real userdata, no FBE and no A/B checkpointing, so these calls hang
            # instead of returning and init parks wherever the first one sits.
            # Hit in sequence on 2026-08-13, each one only visible after the
            # previous was neutered:
            #     vdc checkpoint markBootAttempt   (on post-fs)      -> procs ~10
            #     vdc keymaster earlyBootEnded     (on post-fs-data) -> procs 21
            #     vdc --wait cryptfs init_user0    (on post-fs-data) -> procs 21
            # Rather than chase them one at a time, drop the whole family.
            # `init_user0` is a BUILTIN init command, not an exec line, so the
            # vdc rule below does not catch it -- but it calls vold internally
            # (it shows up as `/system/bin/vdc --wait cryptfs init_user0`) and
            # hangs for the same reason. Same family as the installkey neuter
            # further up.
            # apexd cannot work here at all: our apexes are FLATTENED and there is
            # no apexd running (the apexd-bootstrap exec is already commented out
            # further down for the same reason). `exec_start apexd-snapshotde`
            # (on post-fs-data) is a BLOCKING exec, so init parks on it forever.
            # Observed 2026-08-13 as the stall after init_user0 was neutered:
            #     /system/bin/apexd --snapshotde   (service apexd-snapshotde)
            # Covers any other apexd exec_start the same way.
            # `exec_start update_verifier` (on zygote-start) is the A/B update
            # verifier that marks a successful boot. It is a BLOCKING exec and it
            # hangs here (observed stuck in pipe_read), so init never gets from
            # zygote-start to `on boot` -- i.e. never reaches class_start hal and
            # the composer never starts. There is no A/B update in progress in a
            # HAL-only container, so there is nothing to verify.
            /^[[:space:]]*exec_start update_verifier/ {
                $0 = "    # HALIUM-SOL: no A/B update to verify here -- " $0
            }
            /^[[:space:]]*exec_start apexd/ {
                $0 = "    # HALIUM-SOL: apexes are flattened, apexd never runs -- " $0
            }
            # `start zygote` (on zygote-start) launches the app runtime and the
            # system server. Neither exists in a HAL-only container, and without a
            # framework BOOTCLASSPATH is empty, so app_process aborts
            #   Check failed: !location.empty() BOOTCLASSPATH and
            #   DEX2OATBOOTCLASSPATH must not be empty
            # and init restarts it about every five seconds forever. Each cycle
            # also re-takes the zygote_kwl wakelock and restarts audioserver.
            # `disabled` in init.zygote32.rc cannot stop this: an explicit start
            # overrides it, the same way `restart surfaceflinger` did.
            /^[[:space:]]*start zygote(_secondary)?[[:space:]]*$/ {
                $0 = "    # HALIUM-SOL: no framework in a HAL-only container -- " $0
            }
            /^[[:space:]]*init_user0[[:space:]]*$/ {
                $0 = "    # HALIUM-SOL: no real user0 on a tmpfs /data -- " $0
            }
            /^[[:space:]]*exec .*\/system\/bin\/vdc / {
                $0 = "    # HALIUM-SOL: vold lifecycle is meaningless on tmpfs /data -- " $0
            }
            /^[[:space:]]*wait_for_prop apexd\.status activated[[:space:]]*$/ {
                $0 = "    # HALIUM-SOL: apexes are flattened, apexd never runs -- " $0
            }
            { print }
            /^on (early-init|init|late-init|post-fs|post-fs-data)$/ {
                print "    # HALIUM-SOL: restore flattened /apex hidden by init'"'"'s tmpfs"
                print "    mount none " stash " /apex bind rec"
            }
            # Disable UBWC in QTI gralloc, BEFORE any display service starts.
            #
            # monaco'"'"'s only launcher-eligible SDE plane (plane 70, a DMA pipe)
            # cannot scan UBWC-compressed buffers. With UBWC on, the kernel
            # rejects the atomic commit outright:
            #   [drm:_sde_plane_sspp_atomic_check_helper] [sde error]plane70 ubwc not supported
            #   [drm:drm_atomic_check_only] atomic driver check ... failed: -22
            #   E SDM: DRMAtomicReq::Commit: drmModeAtomicCommit failed with error 22
            # and crtc-0 never leaves enable=0/active=0. With it off, the commit
            # succeeds and the panel lights. Hardware-verified 2026-08-13.
            #
            # This must be set here, not later: the property is read AT STARTUP
            # by BOTH the allocator and the composer (the string is in both
            # binaries and in libsdmutils.so). Setting it after they are already
            # running changes nothing, which is exactly why this looked like a
            # dead end for several rounds -- only the allocator had been
            # restarted, and the composer was still handing out UBWC.
            #
            # `on init` rather than `on early-init` purely for safety margin on
            # property-service availability; both run long before the
            # `class_start hal` in `on boot` that starts these two services.
            #
            # NOT sufficient on its own. The launcher'"'"'s own window buffer is
            # allocated by libhybris'"'"'s HWComposerNativeWindow, which ORs in
            # GRALLOC_USAGE_HW_COMPOSER -- an explicit UBWC trigger that survives
            # this property. That half is fixed by
            # libhybris-sol-disable-ubwc-usage.patch in meta-sol'"'"'s libhybris
            # bbappend. Confirmed by a clean single-variable test: with the
            # property but stock libhybris the display comes up yet plane_mask
            # stays 0 with every plane fb=0, and a QCOM_COMPRESSED framebuffer
            # is still present. Both pieces are needed.
            /^on init$/ {
                print "    # HALIUM-SOL: plane 70 cannot scan UBWC -- see sol-lxc-android-start.sh"
                print "    setprop vendor.gralloc.disable_ubwc 1"
            }
            # Drive the service from the EXISTING post-fs-data block. An APPENDED
            # `on post-fs-data` section at the end of the file was tried and its
            # marker never fired, even though init demonstrably processes
            # post-fs-data and injecting INTO the original block works. So inject
            # here instead of adding a second section.
            /^on post-fs-data$/ {
                print "    write /dev/kmsg HALIUM-SOL-MARKER-apexfix"
                print "    start halium-apexfix"
            }
            # Generate the REAL linker config at early-init, not post-fs-data.
            #
            # init.rc runs `perform_apex_config --bootstrap` here and the full
            # `perform_apex_config` only in on post-fs-data. On a stock boot the
            # first stage has already activated real apexes so that is early
            # enough. Our apexes are flattened, first-stage apexd never runs, and
            # the result is a deadlock:
            #   late-fs -> vold does fscrypt metadata encryption
            #           -> needs keystore2
            #           -> CANNOT LINK EXECUTABLE "/system/bin/keystore2":
            #              library "libandroidicu.so" not found   (it is in
            #              /apex/com.android.i18n, unreachable because
            #              /linkerconfig/ld.config.txt is still the 1-byte "#"
            #              stub written at line 63 above)
            #           -> vold retries forever, init floods with
            #              "Too many pending control messages, dropped
            #               interface_start for ...IKeystoreService"
            #           -> post-fs-data is never reached, so the real config is
            #              never generated. Boot stops at late-init, before the
            #              class where the display composer would start.
            # Running linkerconfig here breaks the cycle: verified by hand in the
            # container, it turns the 1-byte stub into a 60KB config.
            /^on early-init$/ {
                print "    exec - root root -- /apex/com.android.runtime/bin/linkerconfig --target /linkerconfig"
            }
            # And once more AFTER perform_apex_config, which is the thing that
            # wipes us. It re-creates the tmpfs on /apex, and it sits partway
            # through the post-fs-data block -- so a rebind at the START of that
            # block runs too early and is destroyed moments later. Injecting here
            # puts the bind after it. Regenerate the linker config too, since the
            # apexes only become visible again at this point.
            # perform_apex_config --bootstrap is the one that actually runs, at
            # early-init line ~87 -- AFTER our rebind at the top of early-init,
            # which is why the bind kept vanishing. Rebind again right after it.
            /^[[:space:]]*perform_apex_config --bootstrap[[:space:]]*$/ {
                print "    # HALIUM-SOL: restore flattened /apex hidden by init'"'"'s tmpfs"
                print "    mount none " stash " /apex bind rec"
                print "    exec - root root -- /apex/com.android.runtime/bin/linkerconfig --target /linkerconfig"
            }
            /^[[:space:]]*perform_apex_config[[:space:]]*$/ {
                print "    # HALIUM-SOL: restore flattened /apex hidden by init'"'"'s tmpfs"
                print "    mount none " stash " /apex bind rec"
                print "    exec - root root -- /apex/com.android.runtime/bin/linkerconfig --target /linkerconfig"
            }
            # APPEND-ONLY block. Everything above stays exactly as it was; this
            # only adds a service at the end of the file.
            #
            # Why a service: init switches mount namespace mid-boot (measured,
            # bootstrap mnt:[...809] -> default mnt:[...814]), and EVERY `on
            # <stage>` rebind above runs in the bootstrap namespace, so the
            # switch discards it. Services are forked AFTER the switch, into
            # init'"'"'s current namespace, so a mount made by one is visible
            # namespace-wide and survives.
            #
            # /system/bin/bootstrap/linker is invoked explicitly with toybox as
            # its argument because /apex is empty at this point, so the normal
            # interpreter (/system/bin/linker -> /apex/...) is unavailable.
            # servicemanager, logd and lmkd already prove that path works: they
            # run with /apex empty by linking through bootstrap bionic.
            #
            # No "restore flattened" marker here on purpose -- the guard counts
            # those and must stay at 7.
            END {
                print ""
                print "service halium-apexfix /system/bin/bootstrap/linker /system/bin/toybox mount -o bind " stash " /apex"
                print "    class core"
                print "    user root"
                print "    group root"
                print "    oneshot"
                # init validates the exec target'"'"'s SELinux label and refuses:
                #   Could not start service: File /system/bin/bootstrap/linker
                #   (labeled "u:object_r:system_linker_exec:s0") has incorrect label
                # That is an init-side check, not a kernel denial, so being
                # permissive does not help. An explicit seclabel bypasses the
                # domain-transition lookup.
                print "    seclabel u:r:su:s0"
                print ""
                print "on post-fs-data"
                print "    write /dev/kmsg HALIUM-SOL-MARKER-apexfix"
                print "    start halium-apexfix"
            }' "$ROOTFS/system/etc/init/hw/init.rc" > "$_irc"
        if [ "$(grep -c 'HALIUM-SOL: restore flattened' "$_irc")" = 7 ]; then
            mount --bind "$_irc" "$ROOTFS/system/etc/init/hw/init.rc" \
                && echo "sol-lxc-android: init.rc patched to rebind /apex from $APEX_STASH"
        else
            echo "sol-lxc-android: WARNING init.rc apex rebind injection failed, not binding" >&2
        fi
    fi
fi

echo "sol-lxc-android: /apex now: $(ls $ROOTFS/apex 2>/dev/null | tr '\n' ' ')"
echo "sol-lxc-android: linker present: $([ -x $ROOTFS/apex/com.android.runtime/bin/linker ] && echo yes || echo NO)"

echo "sol-lxc-android: /config/usb_gadget before container start:"
for g in /config/usb_gadget/*; do
    [ -d "$g" ] || continue
    echo "  $g UDC=$(cat "$g/UDC" 2>/dev/null)"
done

api_level=$(sed -n 's/^ro.build.version.sdk=//p' $ROOTFS/system/build.prop)
echo "sol-lxc-android: starting container 'android' (api ${api_level:-?})..."

# Launch second-stage init directly. A bare /init runs FirstStageMain, which is
# wrong here (the host did that job) and whose re-exec SIGSEGVs.
# /apex is restored after init's namespace switch by sol-apex-restore.service,
# which runs on the HOST and enters init's CURRENT namespace. It cannot be done
# from init.rc or from an init service -- see that script's header for the
# measurements. Deliberately a separate unit rather than a background subshell
# here: this script runs under `set -e` and execs lxc-start, and a backgrounded
# subshell did not survive that.

exec /usr/bin/lxc-start -n android -F -P /var/lib/lxc -- \
    /system/bin/env -i \
        PATH=/product/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin:/sbin:/system/sbin:/system_ext/bin:/system/bin:/system/xbin:/odm/bin:/vendor/bin:/vendor/xbin \
        INIT_STARTED_AT=0 \
        /init second_stage
