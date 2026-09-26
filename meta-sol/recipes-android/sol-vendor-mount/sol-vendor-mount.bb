SUMMARY = "Recreate the dm-linear mapping for sol's /vendor partition and mount it"
DESCRIPTION = "On stock Android-13/Halium-13, sol's vendor partition is a \
logical partition packed inside /super (/dev/mmcblk0p80 on slot A). Android \
first-stage init parses LP metadata and creates /dev/mapper/vendor_a via dm-linear; \
our shell-script initramfs doesn't, and the Android-9 init we ship at \
/usr/libexec/hal-droid/system/bin/init pre-dates dynamic partitions and \
can't either. Workaround: hardcode the dm table observed from a working \
UBPorts install (dmsetup table | grep vendor_a), recreate it at boot \
before android-init runs. Avoids duplicating ~234 MB of vendor data into \
our rootfs.img."

LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-3.0-only;md5=c79ff39f19dfec6d293b95dea7b07891"

COMPATIBLE_MACHINE = "sol"
PACKAGE_ARCH = "${MACHINE_ARCH}"

inherit systemd

SRC_URI = "file://sol-vendor-mount.sh \
           file://sol-vendor-mount.service"
S = "${UNPACKDIR}"

RDEPENDS:${PN} = "lvm2 util-linux-mount"

do_install() {
    install -d ${D}${libexecdir}
    install -m 0755 ${UNPACKDIR}/sol-vendor-mount.sh ${D}${libexecdir}/sol-vendor-mount.sh

    install -d ${D}${systemd_unitdir}/system
    install -m 0644 ${UNPACKDIR}/sol-vendor-mount.service \
        ${D}${systemd_unitdir}/system/sol-vendor-mount.service

    install -d ${D}${sysconfdir}/systemd/system/local-fs.target.wants
    ln -sf ../../../systemd/system/sol-vendor-mount.service \
        ${D}${sysconfdir}/systemd/system/local-fs.target.wants/sol-vendor-mount.service

    install -d ${D}/vendor
}

SYSTEMD_SERVICE:${PN} = "sol-vendor-mount.service"
FILES:${PN} = "${libexecdir}/sol-vendor-mount.sh \
               ${systemd_unitdir}/system/sol-vendor-mount.service \
               ${sysconfdir}/systemd/system/local-fs.target.wants/sol-vendor-mount.service \
               /vendor"
