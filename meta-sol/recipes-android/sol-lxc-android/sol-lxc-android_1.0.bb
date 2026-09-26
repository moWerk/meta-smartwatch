SUMMARY = "sol: Halium Android system image (mount only, container not started)"
DESCRIPTION = "Ships the Halium android-rootfs.img and the systemd glue that \
loop-mounts it and binds its flattened APEXes over /apex. It does NOT start the \
LXC container yet -- that is the next step, and this stage is separable and \
independently testable. \
\
Why the image is needed at all: sol's own stock Android 14 /system cannot be \
used under libhybris. libhybris deliberately skips libc.so's constructors, and \
stock A14 bionic then dereferences NULL (SIGSEGV at 0x410) before main() is \
reached. A Halium-built system is made to be loaded this way. Swapping only the \
system image -- sol kernel, sol A14 vendor, Halium A13 system -- took the \
launcher from crashing inside bionic to running all the way into EGL \
initialisation against the real Adreno driver, with libui_compat_layer.so \
loaded and the gralloc4 path taken. Measured on hardware 2026-08-10."

LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-3.0-only;md5=c79ff39f19dfec6d293b95dea7b07891"

COMPATIBLE_MACHINE = "sol"
PACKAGE_ARCH = "${MACHINE_ARCH}"
INHIBIT_PACKAGE_STRIP = "1"
INSANE_SKIP:${PN} = "already-stripped arch ldflags dev-so file-rdeps"

inherit systemd

# INTERIM, AND THE MAIN REASON THIS IS NOT PR-READY: this reuses meta-aurora's
# hosted Halium-13 bundle verbatim. It is aurora's image, built for aurora, and
# sol is borrowing it because the two share the monaco SoC -- dodo's frankenport
# reasoning taken one layer further in. It works well enough to have cleared the
# bionic wall, but before this ships sol should either have its own Halium
# system built against its A14 vendor, or this dependency must be made explicit
# and agreed with kido, who owns that image and its hosting.
SRC_URI = "https://dl.dropboxusercontent.com/scl/fi/insvp7s5wp516iv56a4vx/aurora-lxc-android.tar.gz?rlkey=xp4m8ayfwyn12nqae87o3sm3t&dl=1;downloadfilename=aurora-lxc-android-bundle.tar.gz \
           file://sol-android-rootfs.mount \
           file://sol-hybris-system.mount \
           file://sol-android-apex.service \
           file://sol-android-apex.sh \
           file://sol-lxc-android-start.sh \
           file://sol-lxc-android.service \
           file://mount-binder.sh"
SRC_URI[md5sum] = "145a40e6e863afa6a00be6ad0fa28ea4"

S = "${UNPACKDIR}"

RDEPENDS:${PN} = "sol-vendor-mount lxc"

do_install() {
    install -d ${D}${localstatedir}/lib/lxc/android/rootfs
    # Shipped as hybris-system.img, NOT as the container rootfs.
    #
    # The host and the container want DIFFERENT Android systems and coupling
    # them to one image was a mistake. libhybris on the host works against this
    # Halium A13 system (the launcher reaches EGL and gralloc4 with it, and
    # crashes in bionic against stock A14). The container needs an A14 system,
    # because A13 init cannot parse sol's A14 vendor files. Both results are
    # established; they simply are not the same image.
    #
    # So: this image serves the host. The container rootfs is
    # android-rootfs.img, which is not shipped here -- see the tools/ script
    # that builds it.
    #
    # OPERATIONAL WARNING: because android-rootfs.img is NOT shipped by any
    # recipe, it lives on the device only as a manual ~2.2GB adb push, and
    # EVERY `fastboot flash userdata` wipes it. The container then fails with
    # nothing but:
    #     sol-lxc-android.service: Main process exited, code=exited, status=1
    # which looks like a container bug and is not one. After any userdata
    # flash, re-push it (~4.5 min) before debugging anything else:
    #     adb push sol-halium-a14-labeled.img \
    #              /var/lib/lxc/android/android-rootfs.img
    # This cost a full diagnosis cycle on 2026-08-12. It goes away once the
    # image is hosted and fetched like any other SRC_URI, which is blocked on
    # deciding what the tarball should contain.
    install -m 0644 ${UNPACKDIR}/android-rootfs.img ${D}${localstatedir}/lib/lxc/android/hybris-system.img

    install -d ${D}${libexecdir}
    install -m 0755 ${UNPACKDIR}/sol-android-apex.sh ${D}${libexecdir}/sol-android-apex.sh

    # LXC bundle: config plus the container's own hooks.
    install -m 0644 ${UNPACKDIR}/config       ${D}${localstatedir}/lib/lxc/android/
    install -m 0755 ${UNPACKDIR}/mount.sh     ${D}${localstatedir}/lib/lxc/android/
    install -m 0755 ${UNPACKDIR}/pre-start.sh ${D}${localstatedir}/lib/lxc/android/
    install -m 0755 ${UNPACKDIR}/post-stop.sh ${D}${localstatedir}/lib/lxc/android/
    install -m 0755 ${UNPACKDIR}/mount-binder.sh ${D}${localstatedir}/lib/lxc/android/

    # meta-virtualization's liblxc is built without AppArmor.
    sed -i '/^lxc\.apparmor\./d' ${D}${localstatedir}/lib/lxc/android/config

    # Share the host's IPC namespace. Binder state is per-IPC-namespace, so with
    # a separate one the host's /dev/hwbinder is an empty context and libhybris
    # in the launcher cannot reach the container's composer.
    sed -i 's/^lxc\.namespace\.keep[[:space:]]*=.*$/lxc.namespace.keep = net user ipc/' \
        ${D}${localstatedir}/lib/lxc/android/config

    # Android init reboots the host if a critical service crash-loops.
    echo 'lxc.cap.drop = sys_boot' >> ${D}${localstatedir}/lib/lxc/android/config
    # CLOCK_REALTIME is not namespaced; without this the container sets the
    # host clock from a volatile RTC.
    echo 'lxc.cap.drop = sys_time' >> ${D}${localstatedir}/lib/lxc/android/config

    echo 'lxc.console.logfile = /var/log/lxc-android-console.log' >> ${D}${localstatedir}/lib/lxc/android/config
    echo 'lxc.console.buffer.size = 1MB' >> ${D}${localstatedir}/lib/lxc/android/config
    echo 'lxc.hook.mount = /var/lib/lxc/android/mount-binder.sh' >> ${D}${localstatedir}/lib/lxc/android/config

    install -m 0755 ${UNPACKDIR}/sol-lxc-android-start.sh ${D}${libexecdir}/sol-lxc-android-start.sh

    install -d ${D}${systemd_unitdir}/system
    install -m 0644 ${UNPACKDIR}/sol-android-rootfs.mount \
        ${D}${systemd_unitdir}/system/var-lib-lxc-android-rootfs.mount
    install -m 0644 ${UNPACKDIR}/sol-hybris-system.mount \
        ${D}${systemd_unitdir}/system/android-hybris.mount
    install -m 0644 ${UNPACKDIR}/sol-android-apex.service \
        ${D}${systemd_unitdir}/system/sol-android-apex.service
    install -m 0644 ${UNPACKDIR}/sol-lxc-android.service \
        ${D}${systemd_unitdir}/system/sol-lxc-android.service
}

# Shipped Android binaries; skip the QA that assumes our own toolchain.
do_package_qa() {
}

# sol-lxc-android.service was deliberately left out of this list for most of the
# bring-up: if Android init wedged the boot we lost adb, the only debugging
# channel this port has. The standing condition for adding it was "until it has
# proven itself across reboots".
#
# Enabled 2026-08-15, once that condition was actually met. The container used
# to reset the SoC every time it parsed the vendor USB rc file; with that masked
# it boots unattended, reaching ~74 processes with the composer up and staying
# there. Verified on hardware by enabling the unit and rebooting: the container
# came up through this unit with no reset and no intervention.
#
# Honest limit on that evidence: it is a small number of clean boots, not a long
# soak. If a future boot wedges, `systemctl disable sol-lxc-android` from adb is
# the recovery, and adb comes up independently of the container.
SYSTEMD_SERVICE:${PN} = "android-hybris.mount var-lib-lxc-android-rootfs.mount sol-android-apex.service sol-lxc-android.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"
FILES:${PN} = "${localstatedir}/lib/lxc/android \
               ${libexecdir}/sol-android-apex.sh \
               ${libexecdir}/sol-lxc-android-start.sh \
               ${systemd_unitdir}/system/sol-lxc-android.service \
               ${systemd_unitdir}/system/var-lib-lxc-android-rootfs.mount \
               ${systemd_unitdir}/system/android-hybris.mount \
               ${systemd_unitdir}/system/sol-android-apex.service"
EXCLUDE_FROM_SHLIBS = "1"
