#!/bin/sh
# Recreate the dm-linear mappings for sol's stock Android-14 logical partitions
# inside /super (/dev/mmcblk0p80, slot _a) and mount them under /android/ so the
# Halium LXC container can bind them in.
#
# Offsets from `lpdump` on stock AW2A.240903 (see meta-sol/docs/
# sol-hardware-harvest.md). Slot A. Re-derive if Google reflashes super.
#   system_a       : single segment, offset 2048,    len 3679272 (~1.75 GiB)
#   vendor_a       : single segment, offset 3681320, len 521392  (~254 MiB)
#   vendor_dlkm_a  : single segment, offset 6792968, len 120512  (~59 MiB)
#   system_dlkm_a  : single segment, offset 6913480, len 21616   (~10.5 MiB)
set -e
SUPER="/dev/mmcblk0p80"
if [ ! -b "$SUPER" ]; then
    echo "sol-vendor-mount: $SUPER not present, aborting" >&2
    exit 1
fi
dm_create_if_missing() {
    name=$1; shift; table=$1
    if [ -b /dev/mapper/$name ]; then
        echo "sol-vendor-mount: /dev/mapper/$name exists, skipping"
    else
        printf "%s" "$table" | dmsetup create $name
        echo "sol-vendor-mount: created /dev/mapper/$name"
    fi
}
# system_ext and product are logical partitions too, and they were missing here
# until 2026-08-11. They are not optional decoration: they carry sepolicy
# fragments that the vendor policy references. Android init compiles the CIL at
# boot (sol ships no precompiled_sepolicy), and without system_ext's fragment
# secilc dies on the first vendor rule that uses a type it declares:
#     /system/bin/secilc: Invalid genfscon at /vendor/etc/selinux/vendor_sepolicy.cil:76
# that line uses sysfs_rootdisk_tuning, which is declared in
# /system_ext/etc/selinux/system_ext_sepolicy.cil and nowhere else we mounted.
# Offsets from the lpdump table in meta-sol/docs/sol-hardware-harvest.md.
dm_create_if_missing product_a      "0 2365104 linear $SUPER 4202712"
dm_create_if_missing system_ext_a   "0 222032 linear $SUPER 6567816"
dm_create_if_missing vendor_a       "0 521392 linear $SUPER 3681320"
dm_create_if_missing vendor_dlkm_a  "0 120512 linear $SUPER 6792968"
dm_create_if_missing system_a       "0 3679272 linear $SUPER 2048"
dm_create_if_missing system_dlkm_a  "0 21616 linear $SUPER 6913480"
# odm_a: mapped for vold, which enumerates super's logical partitions and
# aborts outright when one is absent:
#     Abort message: 'could not find logical partition odm_a: No such device'
#     init: Service 'vold' (pid 136) received signal 6
# vold then crash-loops, `late-fs` fails, and the boot chain stalls before the
# vendor rc stage where the display composer would start. Mapping it is enough
# to satisfy vold; the container gets its /odm content from the image.
dm_create_if_missing odm_a          "0 3120 linear $SUPER 6789848"

mount_if_unmounted() {
    src=$1; dst=$2; mkdir -p $dst
    if mountpoint -q $dst; then echo "sol-vendor-mount: $dst already mounted"
    else mount -o ro,nosuid,nodev $src $dst; echo "sol-vendor-mount: $dst <- $src"; fi
}
mount_if_unmounted /dev/mapper/system_a      /android/system
mount_if_unmounted /dev/mapper/vendor_a      /android/vendor
mount_if_unmounted /dev/mapper/vendor_dlkm_a /android/vendor_dlkm
mount_if_unmounted /dev/mapper/product_a    /android/product
mount_if_unmounted /dev/mapper/system_ext_a /android/system_ext
# odm: mounted, not just mapped, to break a symlink LOOP that silently disables
# ALL vendor VINTF data.
#
# The container image has /odm/etc -> /vendor/odm/etc, and sol's vendor
# partition has /vendor/odm -> /odm. Together those are a cycle. libvintf looks
# for the SKU-specific ODM manifest (ro.boot.hardware.sku=GGE4J), hits it, and
# the whole device-manifest fetch fails hard:
#     hwservicemanager: getDeviceHalManifest: -40 VINTF parse error:
#       Cannot read /odm/etc/vintf/manifest_GGE4J.xml:
#       Too many symbolic links encountered
# ELOOP is fatal to the fetch, so servicemanager ends up with NO vendor manifest
# at all -- not the fragments, not even /vendor/etc/vintf/manifest.xml -- and
# then rejects every vendor HAL with "Could not find <X> in the VINTF manifest".
# That is what stopped the display composer, keymint (so keystore2 died with
# "Cannot connect to Keymint"), boot, power, nfc, qseecom and qteeconnector.
#
# Mounting the real odm_a makes /odm/etc a real directory, so the lookup returns
# a plain ENOENT instead. libvintf tolerates a missing optional SKU manifest;
# it does not tolerate ELOOP. The partition has no etc/vintf/ at all, which is
# fine -- absent is not the same as unreadable.
mount_if_unmounted /dev/mapper/odm_a        /android/odm

# Halium/libhybris expect /vendor and /system. libhybris's android linker
# searches /usr/libexec/hal-droid/system/lib:/vendor/lib:/system/lib (set at
# build time in meta-asteroid's libhybris bbappend), so these two symlinks are
# how the stock Android libraries become reachable at all.
[ -L /vendor ] || { rm -rf /vendor 2>/dev/null; ln -sf /android/vendor /vendor; }

# /system: which Android system tree libhybris's linker searches.
#
# CORRECTED 2026-08-10 -- an earlier version of this comment claimed sol could
# use its OWN stock A14 system and did not need a Halium image. That was tested
# and is FALSE. Keeping the history because the failure order matters:
#
#   1. Originally this pointed at aurora's container path verbatim, which does
#      not exist on sol, so /system dangled and the launcher died with
#      `library "libEGL.so" not found`.
#   2. Repointing it at sol's own stock system (/android/system/system) fixed
#      that: libEGL.so and libGLESv2.so are there, 32-bit ARM for Android 34,
#      and there is no lib64 anywhere in system or vendor, which confirms the
#      armv7 tune. Real progress, but not the end.
#   3. It then failed further in, and finally in bionic itself: libhybris
#      deliberately skips libc.so's constructors, and stock A14 bionic
#      dereferences NULL (SIGSEGV at 0x410) before main() is reached. No amount
#      of path or apex work fixes that -- it is what a Halium-built system is
#      built to avoid.
#   4. Mounting aurora's Halium-13 system instead, with nothing else changed,
#      took the launcher all the way into EGL initialisation against the real
#      Adreno driver, with libui_compat_layer.so loaded.
#
# So a Halium system is REQUIRED here, and sol-lxc-android ships one. sol's own
# stock system stays mounted at /android/system regardless: /vendor comes from
# it, and it is where the Adreno firmware and the vendor HALs live.
#
# Note the doubled path in the stock case: that partition is system-as-root, so
# mounting it at /android/system puts the libraries at
# /android/system/system/lib.
# Test for the IMAGE, not the mounted directory: var-lib-lxc-android-rootfs.mount
# is ordered After= this service, so at this point the Halium system is not
# mounted yet. A symlink does not need its target to exist when it is created,
# only when it is followed, and by then the mount has happened.
# DECOUPLED from the container 2026-08-11. /system here is the HOST's Android
# system -- what libhybris in asteroid-launcher, sensorfwd, ngfd and bluebinder
# load from. It is deliberately NOT the container's rootfs any more.
#
# They want different things, and both answers are established on hardware:
#   host      -> Halium A13 works. The launcher reaches EGL init against the
#                real Adreno driver with libui_compat_layer loaded. Against
#                stock A14 it dies in bionic at NULL+0x410 before main().
#   container -> A14 is required. A13 init cannot parse sol's A14
#                vendor_property_contexts and aborts in PropertyInit.
# Pointing both at one image meant one of them was always wrong, and the last
# attempt to share the A14 image wedged the boot.
if [ -f /var/lib/lxc/android/hybris-system.img ]; then
    SYSTEM_TARGET=/android/hybris/system
elif [ -d /android/system/system ]; then
    SYSTEM_TARGET=/android/system/system
else
    SYSTEM_TARGET=/android/system
fi
# Re-point unconditionally rather than `[ -L /system ] || ...`: -L is true for a
# DANGLING symlink too, so the old guard could never repair the broken link it
# had itself created on a previous boot.
if [ ! -L /system ] || [ "$(readlink /system)" != "$SYSTEM_TARGET" ]; then
    rm -rf /system 2>/dev/null
    ln -sfn "$SYSTEM_TARGET" /system
fi
echo "sol-vendor-mount: /system -> $SYSTEM_TARGET"

# --- APEX: mount the runtime apexes so /system/lib's bionic symlinks resolve ---
#
# On Android 10+ the bionic libraries are not files in /system/lib, they are
# symlinks into an APEX:
#   /system/lib/libc.so  -> /apex/com.android.runtime/lib/bionic/libc.so
#   /system/lib/libm.so  -> /apex/com.android.runtime/lib/bionic/libm.so
#   /system/lib/libdl.so -> /apex/com.android.runtime/lib/bionic/libdl.so
# apexd mounts these, and apexd runs inside Android init, which we do not run.
# So with /system alone the launcher got past libEGL.so and then died on
# `library "libc.so" not found`. Confirmed on hardware 2026-08-10.
#
# An .apex is an ordinary zip whose apex_payload.img is an ext4 filesystem, and
# crucially it is STORED rather than deflated and zipalign-padded to a page
# boundary -- precisely so it can be loop-mounted in place. So we mount it
# directly out of the .apex at its offset: no unzip, no temp copy, no RAM cost
# on a watch. (Verified: first zip entry is apex_payload.img with a 4050-byte
# extra field, putting the payload at offset 4096, ext4 magic present there.)
#
# The offset is parsed from the zip local header rather than hardcoded, since
# the alignment padding is a build artifact and not a guarantee.
#
# Names differ between file and mountpoint for the ART apex; the mapping below
# is file:mountpoint and matches the three apexes aurora's container binds.
mount_apex() {
    _file="/system/apex/$1.apex"; _name="$2"
    [ -f "$_file" ] || { echo "sol-vendor-mount: apex $1 absent, skipping"; return 0; }
    mountpoint -q "/apex/$_name" && return 0
    # local file header: 26=filename len, 28=extra len, data starts at 30+n+e
    _n=$(od -An -tu2 -j26 -N2 "$_file" 2>/dev/null | tr -d ' ')
    _e=$(od -An -tu2 -j28 -N2 "$_file" 2>/dev/null | tr -d ' ')
    case "$_n$_e" in ''|*[!0-9]*) echo "sol-vendor-mount: apex $1 header unreadable, skipping" >&2; return 0 ;; esac
    # Only a plain apex has apex_payload.img as its FIRST entry, stored and
    # page-aligned. A COMPRESSED apex instead holds a deflated `original_apex`,
    # which cannot be mounted in place at any offset -- it would have to be
    # inflated to disk first. Check the name rather than assuming, otherwise the
    # arithmetic above happily produces a nonsense offset for the wrong layout
    # (com.google.android.art.apex is compressed, and yielded offset 60).
    _nm=$(dd if="$_file" bs=1 skip=30 count="$_n" 2>/dev/null)
    if [ "$_nm" != "apex_payload.img" ]; then
        echo "sol-vendor-mount: apex $1 is not mountable in place (first entry '$_nm'), skipping"
        return 0
    fi
    _off=$((30 + _n + _e))
    mkdir -p "/apex/$_name"
    if mount -o ro,loop,offset=$_off "$_file" "/apex/$_name" 2>/dev/null; then
        echo "sol-vendor-mount: /apex/$_name <- $1.apex (offset $_off)"
        return 0
    fi
    # Fallback for a mount(8) without offset= support: explicit loop device.
    _ld=$(losetup -f 2>/dev/null)
    if [ -n "$_ld" ] && losetup -r -o $_off "$_ld" "$_file" 2>/dev/null \
            && mount -o ro "$_ld" "/apex/$_name" 2>/dev/null; then
        echo "sol-vendor-mount: /apex/$_name <- $1.apex via $_ld (offset $_off)"
    else
        echo "sol-vendor-mount: WARNING could not mount apex $1 (offset $_off)" >&2
    fi
}
# Only mount sol's OWN apexes when the Halium system is not in use. When it is,
# sol-android-apex.service binds Halium's flattened A13 apexes instead, and the
# two must not be mixed: pairing an A13 system with A14 bionic is an ABI
# mismatch.
if [ ! -f /var/lib/lxc/android/android-rootfs.img ] && [ -d /system/apex ]; then
    # runtime is the one that matters: it carries bionic, which /system/lib's
    # libc/libm/libdl symlinks point into. i18n carries ICU and mounts the same
    # way for a few KB of loop device.
    #
    # com.google.android.art is deliberately NOT mounted. It is a compressed
    # apex (deflated original_apex, ~28 MB inflated), so it cannot be mounted in
    # place, and nothing needs it here: no entry in /system/lib symlinks into
    # /apex/com.android.art -- checked against the partition. It is the Java/ART
    # runtime, which a Wayland compositor going through libhybris never touches.
    # aurora binds it because its container runs Android userspace; we do not.
    mount_apex com.android.runtime     com.android.runtime
    mount_apex com.android.i18n        com.android.i18n
fi
# The whole point of the above: this must now be a real file, not a dangling link.
if [ -e /system/lib/libc.so ]; then
    echo "sol-vendor-mount: bionic OK (/system/lib/libc.so resolves)"
else
    echo "sol-vendor-mount: WARNING /system/lib/libc.so does not resolve -- the launcher will fail" >&2
fi

# VNDK shadowing (vendor's older libbinder.so winning over system's, breaking
# libbinder_ndk.so with a missing openDeclaredPassthroughHal) used to be worked
# around here by symlinking the system copy into
# /usr/libexec/hal-droid/system/lib, which outranks both. That is now solved
# properly and generally in meta-sol's libhybris bbappend, which compiles the
# search path with /system/lib AHEAD of /vendor/lib, so the per-library shim is
# gone. The directory is still created because it is where a future
# libui_compat_layer.so belongs.
#
# If the "cannot locate symbol ... openDeclaredPassthroughHal" error ever comes
# back, that means the compiled-in path order is not in effect -- check
# libhybris's configure line before re-adding a shim here.
mkdir -p /usr/libexec/hal-droid/system/lib

# cs40l26 haptics: request_firmware from /vendor/firmware fails at initramfs time
# (no /vendor yet); re-bind now that /vendor exists.
if [ -d /sys/bus/i2c/drivers/cs40l26 ] && [ -d /sys/bus/i2c/devices/0-0043 ] \
        && [ ! -L /sys/bus/i2c/devices/0-0043/driver ]; then
    echo 0-0043 > /sys/bus/i2c/drivers/cs40l26/bind 2>/dev/null \
        && echo "sol-vendor-mount: bound cs40l26 to 0-0043"
fi

# Modem firmware lives on the modem partition (sol = /dev/mmcblk0p43), VFAT,
# under image/. Needed for WLAN (icnss/WLFW) and BT. Mount it host-side and
# point firmware_class.path at it.
if [ -b /dev/mmcblk0p43 ] && ! mountpoint -q /vendor/firmware_mnt 2>/dev/null; then
    mkdir -p /vendor/firmware_mnt 2>/dev/null || true
    mount -t vfat -o ro,uid=1000,gid=1000,fmask=0337,dmask=0227 \
            /dev/mmcblk0p43 /vendor/firmware_mnt 2>/dev/null \
        && echo "sol-vendor-mount: mounted firmware_mnt (mmcblk0p43)" || true
fi
# --- Adreno GPU firmware reachability ---
#
# Opening /dev/kgsl-3d0 makes the KGSL driver request_firmware(a702_sqe.fw). The
# file ships at /vendor/firmware/a702_sqe.fw, but the kernel only searches
# /lib/firmware (plus firmware_class.path), so the load failed with -2 and the
# open returned ENOENT -- which looked like a missing device node but was a
# missing firmware. Confirmed on hardware 2026-08-10:
#     kgsl-3d 5900000.qcom,kgsl-3d0: Direct firmware load for a702_sqe.fw failed with error -2
#
# Symlinks rather than firmware_class.path because that parameter holds exactly
# one directory and the modem path below wants it too; and note it is
# write-only (--w-------), so it cannot even be read back to check.
if [ -d /vendor/firmware ]; then
    mkdir -p /lib/firmware
    for _f in /vendor/firmware/a[0-9][0-9][0-9]_* /vendor/firmware/gen[0-9]*; do
        [ -e "$_f" ] || continue
        ln -sf "$_f" "/lib/firmware/$(basename "$_f")"
    done
    echo "sol-vendor-mount: linked Adreno firmware into /lib/firmware"
fi

if [ -f /vendor/firmware_mnt/image/modem.mdt ]; then
    echo /vendor/firmware_mnt/image > /sys/module/firmware_class/parameters/path
    echo "sol-vendor-mount: firmware_class.path -> /vendor/firmware_mnt/image"
fi
# DO NOT START THE MODEM REMOTEPROC. This line used to read
#
#     echo start > /sys/class/remoteproc/remoteproc1/state
#
# and it was the cause of the reset that had gone unexplained across several
# sessions -- the one previously described as happening at ~139.5 s and blamed,
# by correlation, on asteroid-launcher.
#
# THIS UNIT HAS NO MODEM. The kernel says so on every boot, at 0.79 s:
#
#     [    0.789245][  T123] modem_supported=0x0
#
# sol ships in an LTE variant and a Bluetooth/WiFi variant, and this is the
# latter. Starting 6080000.remoteproc-mss therefore asks the SoC to bring up a
# subsystem that is not present: the MSS firmware load fails, and Qualcomm's
# subsystem-restart path escalates a failed MSS bring-up to a full SoC reset.
# That is why the reset was so deterministic, and why it always landed a fixed
# ~35-40 s after userland started rather than at a fixed uptime -- it was timed
# from this script running, not from power-on.
#
# Measured on hardware 2026-08-10, with everything else identical:
#   kick enabled  -> reset at ~165 s uptime, every boot, repeatedly
#   kick disabled -> 370 s+ and still running, through what would have been two
#                    reset cycles
#
# Eliminated first, each verified rather than assumed: asteroid-launcher
# (masked, still reset), the QCOM watchdog modules (loading them changed
# nothing, and no /dev/watchdog exists at all), a boot-time or bootloader timer
# (removing the initramfs hold moved the reset with userland, not with uptime),
# the Google battery-management stack (blacklisted so it genuinely did not
# load -- confirmed by lsmod and by battery/bms disappearing from
# /sys/class/power_supply -- and it still reset), and dsme (masked, still
# reset).
#
# The kick bought us nothing even when it "worked": WLAN is not up either way
# (icnss2 and wlan are not loaded, there is no wlan interface), so this was
# pure cost.
#
# IF AN LTE SOL IS EVER PORTED: this needs to come back, but gated on actual
# modem presence rather than on the node merely existing -- remoteproc1 is
# present and reports "offline" on this hardware too, which is exactly why the
# old guard passed. modem_supported is only a kernel log line here, not a sysfs
# attribute, so a real gate needs finding first.
#
# The firmware mount above is deliberately KEPT: it is where WLAN and BT
# firmware are read from, and it is unrelated to starting the MSS subsystem.
