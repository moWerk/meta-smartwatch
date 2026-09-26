#!/bin/sh
# /usr/libexec/sol-sensors-hidl.sh
#
# Give sol a HIDL sensors HAL, because AsteroidOS's sensor client only speaks HIDL.
#
# THE MISMATCH: sol's A14 vendor ships exactly one sensors service,
# android.hardware.sensors-service.multihal, and it is AIDL -- it registers on
# /dev/binderfs/binder. AsteroidOS's sensorfw-hybris-binder-plugins
# (/usr/lib/libhybrissensorfw-qt6.so) is a HIDL client: it looks up
# android.hardware.sensors@{1.0,2.0,2.1}::ISensors on hwbinder. Nothing answered,
# so sensorfw sat in a 1s retry loop logging "HYBRIS CTL invalid sensor handle:
# -1" and never returned to its main loop, which also made mce's plugin loads
# time out with DBus NoReply. aurora (A13) ships the HIDL multihal and works.
#
# THE SWAP IS SAFE because only the FRONT-END differs. Both devices'
# /vendor/etc/sensors/hals.conf name a single sub-HAL, /vendor/lib/hw/sensors.usf.so,
# and both copies of that library export sensorsHalGetSubHal_2_1 -- so sol's A14
# USF sub-HAL already speaks the HIDL 2.1 sub-HAL ABI.
#
# TWO NON-OBVIOUS THINGS, both of which cost a debugging round:
#
#  1. SELINUX LABEL ON A BIND MOUNT. Bind-mounting our binary over the vendor
#     path makes it inherit the source filesystem's label. From /run that is
#     u:object_r:tmpfs:s0, and Android init then REFUSES to exec it -- EVEN IN
#     PERMISSIVE MODE, which is easy to misread as something else:
#         init: Could not restart process 'vendor.sensors-hal-multihal': File
#         ... (labeled "u:object_r:tmpfs:s0") has incorrect label or no domain
#         transition ... this error shows up even in permissive mode
#     chcon does not help (/run's tmpfs has no security xattr support:
#     "Operation not supported"). The fix is a dedicated tmpfs mounted with a
#     FORCED context, which is what this script does. The required label comes
#     from the container's own vendor_file_contexts:
#         .../bin/hw/android\.hardware\.sensors@[0-9]\.[0-9]-service(\.multihal)?
#             u:object_r:hal_sensors_default_exec:s0
#
#  2. VINTF. A14's hwservicemanager validates HIDL registrations against the
#     vendor manifest. sol declares only the AIDL sensors HAL, so
#     registerAsService() failed, main() returned, and the process then SIGSEGV'd
#     in its static destructors -- which looks like a startup crash and is not.
#     So the manifest fragment is not optional garnish; without it the binary
#     runs and dies in a loop.
#
# Binding OVER the AIDL binary's own path is deliberate: it means the AIDL and
# HIDL multihals can never run simultaneously against the same sub-HAL, which is
# a real hazard, enforced structurally instead of by convention.
#
# Hardware-verified on sol 2026-08-15: lshal shows @2.0 and @2.1 ISensors/default
# registered, sensorfw prints "Hybris sensor manager initialized", and only
# proximityadaptor fails -- byte-for-byte aurora's working signature.
set -eu

# Act on /android/vendor, NOT on /var/lib/lxc/android/rootfs/vendor.
#
# They are the same filesystem and a mount on either shows up at both (verified:
# the bind appears twice in /proc/mounts). But the rootfs/vendor path is a bind
# created by sol-lxc-android-start.sh, which by design runs AFTER this unit --
# so at boot that path does not exist yet and the first version of this script
# failed there every time while working perfectly when run by hand afterwards.
# /android/vendor comes straight from sol-vendor-mount.service, which we order
# after, so it is present when we run.
VENDOR=/android/vendor
BIN_SRC=/usr/share/sol-sensors-hidl/android.hardware.sensors@2.1-service.multihal
FRAG_SRC=/usr/share/sol-sensors-hidl/android.hardware.sensors@2.1-multihal.xml
BT_FRAG_SRC=/usr/share/sol-sensors-hidl/android.hardware.bluetooth@1.0.xml
BIN_DST="$VENDOR/bin/hw/android.hardware.sensors-service.multihal"
VINTF_DIR="$VENDOR/etc/vintf/manifest"
CTX=/run/sol-sensors-hidl-ctx
LABEL=u:object_r:hal_sensors_default_exec:s0

# Fail LOUDLY, not silently. An earlier version exited 0 here, which left the
# unit reporting "active" while having done nothing -- sensors were simply
# missing later with no clue why. If these paths are absent it means the unit
# ordering is wrong (see the .service header), and that should be visible as a
# failed unit, not inferred three layers downstream.
[ -f "$BIN_SRC" ] || { echo "sol-sensors-hidl: $BIN_SRC missing -- recipe not installed?"; exit 1; }
[ -e "$BIN_DST" ] || { echo "sol-sensors-hidl: $BIN_DST absent -- container rootfs and/or vendor not mounted yet; check unit ordering"; exit 1; }

# --- 1. the binary, on a tmpfs whose files are force-labelled -----------------
if ! mountpoint -q "$CTX"; then
    mkdir -p "$CTX"
    mount -t tmpfs -o "context=$LABEL" sol-sensors-hidl "$CTX"
fi
cp "$BIN_SRC" "$CTX/multihal"
chmod 0755 "$CTX/multihal"

mountpoint -q "$BIN_DST" && umount "$BIN_DST"
mount --bind "$CTX/multihal" "$BIN_DST"
echo "sol-sensors-hidl: bound HIDL multihal ($(stat -c %s "$BIN_DST") bytes) over the AIDL path"

# --- 2. the VINTF fragment ----------------------------------------------------
# The manifest dir lives in the read-only vendor image, so it needs an overlay
# rather than a copy. We overwrite the AIDL fragment's *content* instead of
# adding a second file, so exactly one sensors HAL is declared and it is the one
# actually running -- a declared-but-absent AIDL service just makes clients wait.
if [ -d "$VINTF_DIR" ]; then
    if ! mountpoint -q "$VINTF_DIR"; then
        mkdir -p /run/sol-vintf-upper /run/sol-vintf-work
        mount -t overlay sol-vintf \
            -o "lowerdir=$VINTF_DIR,upperdir=/run/sol-vintf-upper,workdir=/run/sol-vintf-work" \
            "$VINTF_DIR"
    fi
    cp "$FRAG_SRC" "$VINTF_DIR/android.hardware.sensors-multihal.xml"

    # Bluetooth needs the SAME treatment and for the same reason: bluebinder is a
    # HIDL client (it looks up android.hardware.bluetooth@1.0::IBluetoothHci on
    # hwbinder), sol's vendor manifest declares only the AIDL bluetooth HAL, so
    # A14's hwservicemanager refuses to let /vendor/bin/hw/android.hardware.
    # bluetooth@1.0-service-qti register even though that service is running and
    # holds an hwbinder fd. Without this fragment bluebinder dies instantly with
    # "g_main_loop_quit: assertion 'loop != NULL' failed" and ENODEV, and no hci0
    # is ever created. aurora ships the equivalent declaration in its own
    # manifest.xml, which is why it never needed this.
    [ -f "$BT_FRAG_SRC" ] && cp "$BT_FRAG_SRC" "$VINTF_DIR/android.hardware.bluetooth@1.0.xml"

    sync
    echo "sol-sensors-hidl: VINTF now declares the HIDL sensors + bluetooth HALs"
fi
