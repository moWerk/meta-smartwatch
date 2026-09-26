#! /bin/sh

. /machine.conf

# Log to /dev/kmsg (printk ring buffer) rather than /dev/ttyprintk:
# this kernel has CONFIG_TTY_PRINTK=n (gki_defconfig default), so the
# ttyprintk node never exists and every info() was silently dropped.
# /dev/kmsg is provided by CONFIG_PRINTK + printk.devkmsg=on (set on
# our cmdline), so it's available as soon as devtmpfs is mounted.
info() { echo "init: $1" > /dev/kmsg 2>/dev/null; }
# HOLD, never reboot. The upstream version slept 15s and rebooted, which on an
# A/B device is actively harmful: the reboot loops, each cycle burns one of the
# 7 slot retries until the bootloader marks the slot unbootable and silently
# falls back to stock, and every reset overwrites the persistent RAM console
# that logdump would have carried the reason away in. A single diagnosable
# failure became a self-erasing bootloop -- that is exactly what cost us the
# 2026-08-09 install attempt.
#
# There is only one caller (the sdcard mount, far below) and `adbd &` is already
# running by then, so holding here leaves a live root shell standing precisely at
# the point of failure. Diagnose with:
#   adb -s 0123456789ABCDEF shell
# and no logdump, reset or button gesture is needed.
fail() {
    echo "init: Failed" > /dev/kmsg 2>/dev/null
    echo "init: $1" > /dev/kmsg 2>/dev/null
    # Dump the state that explains a rootfs-stage failure, while we still have it.
    { echo "init: FAILDIAG sdcard_partition=$sdcard_partition"
      echo "init: FAILDIAG mmcblk_nodes=$(ls -d /dev/mmcblk* 2>/dev/null | wc -l)"
      echo "init: FAILDIAG p81_present=$([ -e /dev/mmcblk0p81 ] && echo yes || echo no)"
      echo "init: FAILDIAG mounts=[$(cat /proc/mounts 2>/dev/null | awk '{print $1":"$3}' | tr '\n' ' ')]"
      echo "init: FAILDIAG BOOT_DIR=$BOOT_DIR"
    } > /dev/kmsg 2>/dev/null
    echo "init: HOLDING with adb alive -- NOT rebooting. Shell in and look around." > /dev/kmsg 2>/dev/null
    while true; do
        sleep 60
        echo "init: still holding after failure: $1" > /dev/kmsg 2>/dev/null
    done
}

setup_devtmpfs() {
    mount -t devtmpfs -o mode=0755,nr_inodes=0 devtmpfs $1/dev
    mkdir $1/dev/pts
    mount -t devpts none $1/dev/pts/
    test -c $1/dev/fd     || ln -sf /proc/self/fd $1/dev/fd
    test -c $1/dev/stdin  || ln -sf fd/0 $1/dev/stdin
    test -c $1/dev/stdout || ln -sf fd/1 $1/dev/stdout
    test -c $1/dev/stderr || ln -sf fd/2 $1/dev/stderr
    test -c $1/dev/socket || mkdir -m 0755 $1/dev/socket
}

info "Mounting relevant filesystems ..."
mkdir -m 0755 /proc;  mount -t proc proc /proc
mkdir -m 0755 /sys;   mount -t sysfs sys /sys
mkdir -p /dev;        setup_devtmpfs ""

# The cmdline carries loglevel=6, so the console prints only levels STRICTLY
# BELOW 6 -- every pr_info/dev_info is dropped before it reaches the RAM console
# and therefore before seluna flushes that console into the logdump partition.
# That filter is why our captures never showed "Registered RPM clocks",
# "Registered Monaco ICC" or "Registered GCC clocks" (all dev_info) while
# happily showing "Failed to register GCC clocks" (dev_err) -- a driver that
# fails once and then recovers on a deferred-probe retry is indistinguishable
# from one that never recovers. Raise the console level here, at ~0.6s, which is
# well before the clock/regulator/interconnect bring-up at ~1.4s.
#
# 7, not 8: the console prints levels strictly below this number, so 7 admits
# KERN_INFO (6) -- exactly what we are missing -- while still excluding
# KERN_DEBUG (7). That matters because the RAM console seluna flushes to logdump
# is a fixed-size buffer: a debug-level flood could wrap it and evict the early
# bring-up window we actually care about.
echo 7 > /proc/sys/kernel/printk 2>/dev/null

# ---- AURORA-SPECIFIC: load the vendor module chain ----
# Our 85+ SoC modules are =m. Load them now so /dev/mmcblk0pN appears,
# the WLAN/sensor/audio drivers are ready, etc.
#
# vendor_kernel_boot ships .ko's at a FLAT /lib/modules/*.ko (no
# $(uname -r) subdirectory). busybox modprobe DOES expect /lib/modules/$(uname
# -r)/{modules.dep,*.ko}, so we symlink the version subdir to the flat root.
# modules.dep is already at /lib/modules/modules.dep (shipped by VKB) and
# contains absolute paths like "/lib/modules/clk-qcom.ko" -- those resolve
# directly, the symlink only exists so modprobe's chdir() lands in the right
# place to load modules.dep.
#
# With modprobe + modules.dep, dep order in modules.load.sol is IRRELEVANT
# -- modprobe walks the dep tree per module. This matters because hand-ordering
# 96 modules across all SoC subsystems is fragile.
KREL=$(uname -r)
[ ! -e "/lib/modules/$KREL" ] && ln -sf . "/lib/modules/$KREL"

# Pre-load the google-extcon-usb-shim with usb_force_disable_boot=0 BEFORE the
# bulk modprobe loop. The DT default has the shim force-disabling USB at boot
# ("disable-param:0x1" in dmesg) which keeps dwc3-msm from registering a UDC --
# no UDC, no adb. We can't rely on /etc/modprobe.d/*.conf because the busybox
# modprobe in our initramfs doesn't honor it. Passing the param directly to
# modprobe IS honored.
# sol's USB gate module is google_extcon_shim. aurora's google-extcon-usb-shim does
# NOT exist on sol, and stock's cmdline google_extcon_usb_shim.usb_force_disable_boot=1
# is therefore a no-op here. The gate is exposed as DEVICE sysfs attrs, not module
# params, so it is opened below rather than via a modprobe argument.
info "Pre-loading google-extcon-shim ..."
modprobe google-extcon-shim 2>/dev/kmsg

info "Loading aurora kernel modules from /etc/modules.load.sol ..."
while read mod; do
    case "$mod" in ''|\#*) continue ;; esac
    modprobe "${mod%.ko}" 2>/dev/kmsg
done < /etc/modules.load.sol
info "Loaded aurora kernel modules: $(ls /sys/bus/platform/drivers/ 2>/dev/null | wc -l) platform drivers registered"

# --- diagnostics: everything goes to /dev/kmsg, which seluna flushes to logdump ---
# The misc-partition sink this replaced could never fire: soldiag() opened with
# `[ -e /dev/mmcblk0p55 ] || return 0`, and on a boot where the eMMC does not
# enumerate that node never appears, so it silently no-op'd. logdump (mmcblk0p2)
# is the working channel -- it holds the persistent RAM console, which the
# bootloader writes out across a reset, so it captures storage-down boots too.
# Read it back from rooted stock with:
#   dd if=/dev/block/by-name/logdump bs=1M count=8 | strings
#
# Report BOUND DEVICES, not registered drivers. "N platform drivers registered"
# counts driver registrations and says nothing about whether any device attached
# to them; a bound device shows up as a symlink inside the driver's sysfs dir.
soldiag() {
    info "DIAG $1: uptime=$(cut -d. -f1 /proc/uptime)s dev=$(ls /dev 2>/dev/null | wc -l) modules=$(wc -l < /proc/modules)"
    # Count, don't list. /dev/kmsg truncates a write at ~1KB, and once the eMMC
    # enumerates `ls -d /dev/mmcblk*` expands to ~90 partitions -- which silently
    # ate this whole line on the previous run and made storage look absent when
    # it was in fact fully up.
    info "DIAG $1: mmcblk_nodes=$(ls -d /dev/mmcblk* 2>/dev/null | wc -l) rootdisk=$([ -e /dev/mmcblk0 ] && echo yes || echo no) udc=[$(ls /sys/class/udc 2>/dev/null | tr '\n' ' ')]"
    # The USB chain end to end: which extcons exist, and whether the dwc3-msm
    # platform device is present at all (as opposed to present-but-unbound).
    for e in /sys/class/extcon/*; do
        [ -e "$e/name" ] && info "DIAG $1: extcon $(basename "$e") name=$(cat "$e/name" 2>/dev/null)"
    done
    info "DIAG $1: hsusb_dev=[$(ls -d /sys/bus/platform/devices/*hsusb* /sys/bus/platform/devices/*dwc3* 2>/dev/null | sed 's|.*/||' | tr '\n' ' ')]"
    # The SPMI/PMIC layer. No pm5100 child device probes at all on our boots (0 vs
    # stock's 52), so qpnp-smblite -- the USB extcon supplier -- is never even
    # created. drivers/mfd/qcom-spmi-pmic.c:pmic_spmi_probe() ends in
    # devm_of_platform_populate(), which is what creates those children. Three
    # possibilities, and these dumps separate them in one boot: the spmi device
    # 0-00 is never created; it is created but its probe never runs; or the probe
    # runs and fails before populate.
    info "DIAG $1: spmi_drivers=[$(ls /sys/bus/spmi/drivers 2>/dev/null | tr '\n' ' ')]"
    for d in /sys/bus/spmi/devices/*; do
        [ -e "$d" ] || continue
        info "DIAG $1: spmi dev $(basename "$d") driver=$(basename "$(readlink -f "$d/driver" 2>/dev/null)" 2>/dev/null)"
    done
    info "DIAG $1: pm5100_children=$(ls /sys/bus/platform/devices 2>/dev/null | grep -c pm5100)"
    # devices_deferred lists every device still on the deferred-probe list TOGETHER
    # WITH its deferral reason string (drivers/base/dd.c:deferred_devs_show). If
    # 0-00 is in here, the reason names the blocker outright. Emit one line at a
    # time: /dev/kmsg truncates a single write at ~1KB.
    mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null
    if [ -r /sys/kernel/debug/devices_deferred ]; then
        n=0
        while read -r dl; do
            n=$((n+1))
            info "DIAG $1: deferred[$n] $dl"
        done < /sys/kernel/debug/devices_deferred
        info "DIAG $1: deferred_total=$n"
    else
        info "DIAG $1: devices_deferred UNAVAILABLE"
    fi
    for a in force_disable spoof_connected; do
        for f in /sys/bus/platform/devices/*extcon*/$a; do
            [ -e "$f" ] && info "DIAG $1: shim $a=$(cat "$f" 2>/dev/null)"
        done
    done
    for drv in rpm-smd qcom-smd-rpm clk-smd-rpm qcom_glink_rpm rpm-smd-regulator \
               qnoc-monaco gcc-monaco sdhci_msm msm-dwc3 dwc3 gdsc-regulator; do
        d=/sys/bus/platform/drivers/$drv
        [ -d "$d" ] || { info "DIAG $1: drv $drv ABSENT"; continue; }
        # Everything in a driver dir except these four standard attrs is a bound
        # device. Plain ls + grep, because busybox find is not guaranteed here.
        info "DIAG $1: drv $drv bound=[$(ls "$d" 2>/dev/null | grep -vE '^(bind|unbind|uevent|module)$' | tr '\n' ' ')]"
    done
}
soldiag after-modules

# Re-emit the pre-init part of the ring buffer. Our loglevel bump above only
# affects messages printed from ~0.6s on, so the built-in-init window is still
# filtered in the console copy -- but the ring buffer itself is unfiltered, and
# `dmesg` reads the ring. Snapshot it to a file FIRST and replay from that: piping
# dmesg straight into /dev/kmsg would append to the very buffer being read.
dmesg 2>/dev/null | head -200 > /predmesg.txt
while read -r l; do echo "PRE: $l" > /dev/kmsg 2>/dev/null; done < /predmesg.txt

# Belt-and-braces: even with usb_force_disable_boot=0 the shim may have latched
# the gate via DT before our param applied. The runtime sysfs attr
# `force_disable` is changeable -- write 0 to flip USB on.
# sol needs BOTH attrs: force_disable=0 to un-gate, and spoof_connected=1 because on
# the charging cradle there is no real USB connect event for the extcon to report.
for base in /sys/bus/platform/devices/*extcon*/ /sys/devices/platform/soc/*extcon*/ ; do
    [ -e "${base}force_disable" ]   && echo 0 > "${base}force_disable"   2>/dev/kmsg && info "USB gate: force_disable=0 at $base"
    [ -e "${base}spoof_connected" ] && echo 1 > "${base}spoof_connected" 2>/dev/kmsg && info "USB gate: spoof_connected=1 at $base"
done

# Cache cmdline contents while /proc is still mounted. The proc/sys move
# (umount -l /proc, mount -t proc proc $BOOT_DIR/proc) happens before
# switch_root, so any LATER `grep /proc/cmdline` would fail.
CMDLINE=$(cat /proc/cmdline 2>/dev/null)

# Checks whether we need to start adbd for interactive debugging
# ALWAYS start adbd on sol, regardless of `debug-ramdisk`.
#
# The flag is not a dependable signal here. It was present on every boot for
# most of this bring-up, then vanished after a WearOS factory reset -- and a
# reset clears the `misc` bootloader control block, which is the most likely
# place it was coming from (the bootloader appends the BCB to the cmdline).
# That is also why it appears in NONE of our build artifacts: not CONFIG_CMDLINE,
# not boot.img's or vendor_kernel_boot's cmdline fields, not the shipped DTB's
# /chosen/bootargs, not the vkb bootconfig (size 0). Kido was right that no
# firmware would invent an AsteroidOS-spelled flag; it was never ours to begin
# with, and it is not ours to rely on.
#
# The cost of that dependency was severe: once the flag disappeared, adbd stopped
# starting, so every failed boot became an unreachable reboot loop with no shell
# and no way to read anything -- which is precisely the state that stalled
# 2026-08-09. On a port that is still being brought up, an initramfs shell is not
# a debug luxury, it is the only diagnostic channel that does not need a working
# rootfs, a working display, or a button gesture. Always pay for it.
#
# This does NOT keep us in the initramfs: adbd is backgrounded below and boot
# continues to switch_root either way.
case "$CMDLINE" in *debug-ramdisk*) DEBUG_RAMDISK=1 ;; *) DEBUG_RAMDISK=0 ;; esac
info "adbd: starting unconditionally (debug-ramdisk on cmdline: $DEBUG_RAMDISK)"
if true; then
    # On this 5.15 GKI kernel CONFIG_USB_F_FS=y but functionfs_init() is NOT a
    # fs_initcall -- f_fs.c's filesystem registration happens lazily when
    # _ffs_alloc_dev sees its first device (configfs mkdir functions/ffs.X). So
    # `mount -t functionfs` only works AFTER we've created an ffs.X function
    # via configfs.
    #
    # android-gadget-setup adb does that for us, but its first line is `cd
    # /sys/kernel/config/usb_gadget` so it REQUIRES configfs to be mounted.
    # systemd auto-mounts it in the rootfs but we're pre- systemd in the
    # initramfs -- do it ourselves.
    mkdir -p /sys/kernel/config
    mount -t configfs none /sys/kernel/config 2>/dev/null || true

    # android-gadget-setup adb creates the configfs gadget, the
    # functions/ffs.usb0 function (which triggers functionfs_init() and
    # registers the `functionfs` fs type), AND mounts it at /dev/usb-ffs/adb.
    # We don't need a separate mount call.
    /usr/bin/android-gadget-setup adb

    # Legacy /sys/class/android_usb writes -- silently no-op on our 5.15 GKI
    # kernel which doesn't have CONFIG_USB_ANDROID. Kept for parity with the
    # upstream init.sh.
    echo 0 > /sys/class/android_usb/android0/enable 2>/dev/null
    echo 18d1 > /sys/class/android_usb/android0/idVendor 2>/dev/null
    echo d002 > /sys/class/android_usb/android0/idProduct 2>/dev/null
    echo adb > /sys/class/android_usb/android0/f_ffs/aliases 2>/dev/null
    echo ffs > /sys/class/android_usb/android0/functions 2>/dev/null
    echo AsteroidOS > /sys/class/android_usb/android0/iManufacturer 2>/dev/null
    echo InitRamDisk > /sys/class/android_usb/android0/iProduct 2>/dev/null
    serial="$(sed 's/.*androidboot.serialno=//;s/ .*//' /proc/cmdline)"
    echo "$serial" > /sys/class/android_usb/android0/iSerial 2>/dev/null
    echo 1 > /sys/class/android_usb/android0/enable 2>/dev/null

    /usr/bin/adbd &

    # Bind to the first available UDC -- writing the UDC name into
    # configfs/usb_gadget/<g>/UDC is what makes the USB device visible to the
    # host. dwc3-msm probes via deferred-init module load (it's =m, loaded from
    # modules.load.sol after sdhci-msm), so the UDC appears 2-10s into boot.
    # Poll up to 30s in 0.5s steps and verify an entry actually exists in
    # /sys/class/udc/.
    info "adbd: usb_gadget=$(cd /sys/kernel/config/usb_gadget 2>/dev/null && echo *)"
    # Poll WITHOUT command substitution. The previous $(cd /sys/class/udc && echo *)
    # form hung indefinitely on sol: the last log line ever emitted was
    # "adbd: usb_gadget=adb" and the 30s timeout branch never printed, even after 700s.
    UDC=""
    i=0
    while [ $i -lt 60 ]; do
        set -- /sys/class/udc/*
        if [ -e "$1" ]; then UDC=${1##*/}; break; fi
        sleep 1
        i=$((i+1))
    done
    if [ -n "$UDC" ]; then
        UDC=$(echo "$UDC" | awk '{print $1}')
        info "adbd: found UDC=$UDC after $((i+1))s"
        if echo "$UDC" > /sys/kernel/config/usb_gadget/adb/UDC 2>/dev/kmsg; then
            info "adbd: bound UDC=$UDC successfully"
        else
            info "adbd: bind to $UDC FAILED (write error)"
        fi
    else
        info "adbd: NO UDC found after 60s -- dwc3-msm gate still off?"
        set -- /sys/class/udc/*; info "adbd: /sys/class/udc entries = '$1'"
        soldiag no-udc
        # Hang here rather than panicking. The previous version triggered sysrq-c so
        # the A/B retry counter would drain slot B back to stock unattended -- but
        # that boot left NOTHING in logdump, while the earlier boot that ended in a
        # manual power cycle was captured in full. Working theory: seluna flushes the
        # persistent RAM console on a normal reset and not on the panic path. Idling
        # here keeps the console intact for the operator's power cycle, and doubles
        # as the test of that theory: if this boot shows up in logdump, it is confirmed.
        info "DIAG: idling for the operator -- power-cycle now, then read logdump"
        while true; do sleep 3600; done
    fi

    # NOTE: adbd is up; we deliberately fall through to switch_root from here.
    #
    # The inherited aurora code treated `debug-ramdisk` as a sticky mode and
    # idled here forever ("never switching to rootfs"). That is wrong on sol,
    # because the flag is not a choice: seluna appends `debug-ramdisk` itself
    # whenever it boots our unsigned init_boot, so it is present on EVERY
    # AsteroidOS boot and the sticky branch would make switch_root impossible.
    # Established by elimination -- stock WearOS's own cmdline does not carry it,
    # vendor_boot_a and vendor_boot_b have byte-identical cmdlines that do not
    # carry it, our boot.img/vendor_kernel_boot.img cmdlines are empty, and
    # vkb-base.dtb's /chosen/bootargs does not have it either.
    #
    # The fleet already settles what this flag means: in the canonical
    # meta-asteroid initramfs-scripts-android/init.sh it gates ONLY the adbd
    # block and boot then proceeds to switch_root unconditionally. Restore that.
    # If the rootfs is not there yet, the safety net further down (no
    # $BOOT_DIR/lib/systemd/systemd -> hold in the initramfs) keeps adb alive,
    # so this is safe even before an asteroidos.ext4 has been installed.
    info "debug-ramdisk: adbd started; continuing to rootfs (canonical behaviour)"
fi

rotation=0
[ -e /etc/rotation ] && read rotation < /etc/rotation
[ -x /usr/bin/msm-fb-refresher ] && /usr/bin/msm-fb-refresher
/usr/bin/psplash --angle $rotation --no-console-switch &

info "Mounting sdcard..."
mkdir -m 0777 /sdcard /loop
# Bounded on purpose: an unbounded wait hangs the boot with no diagnosis.
# fail() parks with adbd alive instead, which is recoverable.
i=0
while [ ! -e /dev/$sdcard_partition ] && [ $i -lt 30 ]; do
    info "Waiting for $sdcard_partition..."
    sleep 1
    i=$((i+1))
done
[ -e /dev/$sdcard_partition ] || fail "$sdcard_partition never appeared"

/sbin/fsck.ext4 -p /dev/$sdcard_partition
mount -t auto -o rw,noatime,nodiratime /dev/$sdcard_partition /sdcard
[ $? -eq 0 ] || fail "Failed to mount the sdcard. Cannot continue."

info "Checking for loop rootfs image on the sdcard..."
ANDROID_MEDIA_DIR="/sdcard/media/"
[ -d /sdcard/media/0 ]            && ANDROID_MEDIA_DIR="/sdcard/media/0"
[ -e /sdcard/asteroidos.ext4 ]    && ANDROID_MEDIA_DIR="/sdcard/"

BOOT_DIR="/sdcard"
if [ -e $ANDROID_MEDIA_DIR/asteroidos.ext4 ] ; then
    /sbin/fsck.ext4 -p $ANDROID_MEDIA_DIR/asteroidos.ext4
    info "Rootfs image found at $ANDROID_MEDIA_DIR/asteroidos.ext4; mounting it now ..."
    mount -o noatime,nodiratime,sync,rw,loop $ANDROID_MEDIA_DIR/asteroidos.ext4 /loop
    [ $? -ne 0 ] || BOOT_DIR="/loop"
fi

if [ ! -e $system_partition ] && [ -n "$system_partition" ] ; then
    info "Mounting system..."
    mkdir -m 0777 $BOOT_DIR/system
    mount -t auto -o ro /dev/$system_partition $BOOT_DIR/system
    mount --bind $BOOT_DIR/system /system
fi

if [ ! -e $vendor_partition ] && [ -n "$vendor_partition" ] ; then
    info "Mounting vendor..."
    mkdir -m 0777 $BOOT_DIR/vendor
    mount -t auto -o ro /dev/$vendor_partition $BOOT_DIR/vendor
    mount --bind $BOOT_DIR/vendor /vendor
fi

if [ ! -e $firmware_partition ] && [ -n "$firmware_partition" ] ; then
    info "Mounting firmware..."
    mkdir -m 0777 $BOOT_DIR/firmware
    mount -t auto -o ro /dev/$firmware_partition $BOOT_DIR/firmware
    mount --bind $BOOT_DIR/firmware /firmware
fi

if [ -x /init.machine ]; then
    info "Run machine specific init"
    /init.machine $BOOT_DIR > /dev/kmsg 2>&1 || true
fi

setup_devtmpfs $BOOT_DIR

# --- hand USB over to the rootfs so we keep a shell after switch_root ----------
# Two separate problems, both of which left AsteroidOS unreachable once it booted:
#
# 1. The rootfs DOES ship adbd (android-tools-adbd.service, WantedBy=basic.target)
#    but the unit carries `ConditionPathExists=/etc/usb-debugging-enabled`, and
#    nothing creates that file. So userland adbd silently never starts. We are
#    holding the rootfs mounted right here, so just create it.
# 2. Our initramfs adbd still owns the configfs gadget with the UDC bound. After
#    switch_root that process is orphaned in a torn-down namespace: the gadget
#    stays enumerated (host sees 18d1:d002) but serves nothing, and usb-moded /
#    android-gadget-setup in userland cannot claim the UDC. Release it cleanly:
#    unbind the UDC first, then stop adbd, so userland starts from a clean slate.
#
# This is bring-up scaffolding, not a shipping default -- enabling adb
# unconditionally is a debug convenience and should be revisited before any
# release image.
if [ -d "$BOOT_DIR/etc" ]; then
    : > "$BOOT_DIR/etc/usb-debugging-enabled" 2>/dev/null \
        && info "rootfs: enabled userland adbd (/etc/usb-debugging-enabled)" \
        || info "rootfs: could NOT create /etc/usb-debugging-enabled"
fi
# DELIBERATELY NOT releasing the UDC / killing adbd here.
#
# Tried that on 2026-08-09 and it was a net loss: userland adbd still did not come
# up (so we gained nothing) and sol stopped enumerating USB entirely (so we lost
# everything). Keeping the initramfs adbd alive across switch_root leaves the
# gadget enumerated as 18d1:d002; the shell dies with the old namespace, but there
# is a window in which we are still root with /dev populated, and that window is
# what lets us run
#     adb exec-out "dd if=/dev/mmcblk0p2 bs=1M count=6"   # logdump
# to recover the PREVIOUS boot's full kernel console. That single technique is how
# the watchdog root cause was found; it is the only diagnostic channel that
# survives a userland that cannot talk to us, and it must not be traded away for a
# speculative improvement.
#
# Revisit only once userland USB is independently proven to work.

# --- release USB so userland's usb-moded stack can own it ----------------------
# Done HERE, immediately before switch_root, so the rootfs starts from a clean
# slate.
#
# Why this is required (2026-08-09/10): meta-sol's usb-moded port brings up
# init_gfs, which stages the g1 gadget and first tears down whatever the
# initramfs left behind. With our adbd still alive and holding the UDC, that
# teardown BLOCKS -- the boot log ends at
#     init_gfs: unbinding 4e00000.dwc3 from /config/usb_gadget/adb/UDC
# and init_gfs sits in D state ("blocked for more than 120 seconds", then 241).
# sysinit never completes, so usb-moded and adbd never start and the watch is
# unreachable. Aurora never sees this because its initramfs does not keep adbd
# running -- that teardown path is dormant there and load-bearing here.
#
# An earlier attempt released the UDC and got no userland USB at all, which
# looked like a failure but was not: the usb-moded stack did not exist yet, so
# nothing was there to take over. With that stack in place, releasing is right.
#
# Order matters: unbind the UDC first, then stop adbd, then drop the gadget
# directory, so nothing is holding an endpoint when init_gfs runs.
if [ -w /sys/kernel/config/usb_gadget/adb/UDC ]; then
    echo "" > /sys/kernel/config/usb_gadget/adb/UDC 2>/dev/null \
        && info "usb: unbound UDC from the initramfs gadget"
fi
for p in $(pidof adbd 2>/dev/null); do kill "$p" 2>/dev/null; done
if mountpoint -q /dev/usb-ffs/adb 2>/dev/null; then
    umount /dev/usb-ffs/adb 2>/dev/null || umount -l /dev/usb-ffs/adb 2>/dev/null
fi
info "usb: handed over to the rootfs (init_gfs/usb-moded own the gadget now)"

info "Move the /proc and /sys filesystems..."
umount -l /proc
umount -l /sys
mount -t proc proc $BOOT_DIR/proc
mount -t sysfs sys $BOOT_DIR/sys
mount -t tmpfs run $BOOT_DIR/run

# Tell psplash where its FIFO lives under the new root, then wait for that path
# to exist rather than sleeping a magic second. switch_root pulls the initramfs
# out from under psplash; if the path is not there yet the splash dies and the
# screen goes black across handover.
echo FIFO $BOOT_DIR/run > /run/psplash_fifo
i=0
while [ ! -e "$BOOT_DIR/run/psplash_fifo" ] && [ $i -lt 20 ]; do
    sleep 0.1
    i=$((i+1))
done

# Safety net: if BOOT_DIR's systemd doesn't exist, don't even try
# switch_root -- it would fail exec("..."), PID 1 would exit, and the
# kernel would panic ("Attempted to kill init"). Instead, stay alive
# in the initramfs so adb (debug-ramdisk) can be used to investigate.
if [ ! -x "$BOOT_DIR/lib/systemd/systemd" ]; then
    info "FATAL: $BOOT_DIR/lib/systemd/systemd missing or not executable!"
    info "BOOT_DIR=$BOOT_DIR  -- staying in initramfs for adb debugging."
    info "Contents of $BOOT_DIR: $(ls -la $BOOT_DIR 2>&1)"
    # Don't proceed: panic-on-PID1-exit is worse than holding here.
    while true; do sleep 60; info "init: waiting for adb (rootfs not switchable)"; done
fi

info "Switching to rootfs..."
exec switch_root -c /dev/console $BOOT_DIR /lib/systemd/systemd
