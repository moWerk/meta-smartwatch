SUMMARY = "sol: HIDL sensors HAL front-end so sensorfw can see the sensors"
DESCRIPTION = "sol's A14 vendor ships only the AIDL sensors service, while \
AsteroidOS's sensorfw-hybris-binder-plugins is a HIDL client that looks up \
android.hardware.sensors@{1.0,2.0,2.1}::ISensors on hwbinder. Nothing answered, \
so sensorfw reported 'HYBRIS CTL invalid sensor handle: -1' and spun in a 1s \
retry loop, which in turn made mce's sensor plugin loads fail with DBus NoReply. \
\
This ships android.hardware.sensors@2.1-service.multihal, built from AOSP \
sources in the Halium 14 tree, plus the VINTF manifest fragment that A14's \
hwservicemanager requires before it will accept the registration. Only the \
front-end changes: both sol and aurora name a single sub-HAL in \
/vendor/etc/sensors/hals.conf (/vendor/lib/hw/sensors.usf.so) and both copies of \
it export sensorsHalGetSubHal_2_1, so sol's own USF sub-HAL already speaks the \
HIDL 2.1 sub-HAL ABI. \
\
Hardware-verified on sol 2026-08-15: lshal shows @2.0 and @2.1 ISensors/default \
registered and sensorfw prints 'Hybris sensor manager initialized', with only \
proximityadaptor failing -- byte-for-byte the signature of aurora, which has \
working sensors. \
\
This is a bridge, not a destination. If sensorfw/libhybris ever gains an AIDL \
sensors client upstream, that is the better answer and this recipe should go."

LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

COMPATIBLE_MACHINE = "sol"
PACKAGE_ARCH = "${MACHINE_ARCH}"

# Prebuilt 32-bit ARM Android executable: our toolchain QA does not apply.
INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_SYSROOT_STRIP = "1"
EXCLUDE_FROM_SHLIBS = "1"
# libdir for the same reason as sol-hwc2-aidl: the payload lives under
# ${datadir} because it is bind-mounted into the container, not used on the host.
INSANE_SKIP:${PN} = "already-stripped arch ldflags dev-so file-rdeps textrel staticdev libdir"

# NOTE FOR REVIEW / NOT YET HOSTED: per this tree's no-binaries-in-git rule the
# multihal executable is not committed. It is packed into
# sol-sensors-hidl-1.0.tar.gz (40290 bytes) which needs hosting alongside the
# other pinned sol artifacts. The checksums below are of that exact file and are
# final, so publishing it is the only remaining step and the URL is the only
# line that changes. The VINTF fragment IS committed -- it is ten lines of our
# own XML, not a build product.
SRC_URI = "https://REPLACE-WITH-HOSTED-URL/sol-sensors-hidl-1.0.tar.gz \
           file://android.hardware.sensors@2.1-multihal.xml \
           file://android.hardware.bluetooth@1.0.xml \
           file://sol-sensors-hidl.sh"
SRC_URI[sha256sum] = "d2aa498f93db27cba808437f685a6fad21545b2c4633267b0af9c773d2409b89"
SRC_URI[md5sum] = "a04166ce79bbc304a24cccaeb9d18919"

S = "${UNPACKDIR}"

do_install() {
    install -d ${D}${datadir}/sol-sensors-hidl
    install -m 0755 "${UNPACKDIR}/android.hardware.sensors@2.1-service.multihal" \
        "${D}${datadir}/sol-sensors-hidl/android.hardware.sensors@2.1-service.multihal"
    install -m 0644 "${UNPACKDIR}/android.hardware.sensors@2.1-multihal.xml" \
        "${D}${datadir}/sol-sensors-hidl/android.hardware.sensors@2.1-multihal.xml"
    # Bluetooth VINTF fragment: same mechanism, same root cause (sol declares only
    # the AIDL BT HAL, so the HIDL one bluebinder needs cannot register).
    install -m 0644 "${UNPACKDIR}/android.hardware.bluetooth@1.0.xml" \
        "${D}${datadir}/sol-sensors-hidl/android.hardware.bluetooth@1.0.xml"
    install -m 0644 ${UNPACKDIR}/README.txt ${D}${datadir}/sol-sensors-hidl/README.txt

    install -d ${D}${libexecdir}
    install -m 0755 ${UNPACKDIR}/sol-sensors-hidl.sh ${D}${libexecdir}/sol-sensors-hidl.sh
}

# Under ${datadir} on purpose: nothing on the host executes these, they exist
# only to be bind-mounted/overlaid into the container at runtime.
FILES:${PN} = "${datadir}/sol-sensors-hidl \
               ${libexecdir}/sol-sensors-hidl.sh"

RDEPENDS:${PN} = "sol-vendor-mount sol-lxc-android"

# NO systemd unit on purpose. This is invoked from sol-lxc-android-start.sh,
# immediately after setup_selinux and before lxc-start, because it needs a
# loaded SELinux policy (it mounts a tmpfs with -o context=, which is rejected
# without one) AND must be in place before Android init execs the sensors
# service. As a standalone unit ordered Before=sol-lxc-android it failed every
# clean boot with mount exit 32 while succeeding by hand afterwards. The start
# script guards on [ -x ], so this package and sol-lxc-android can be installed
# in either order.
