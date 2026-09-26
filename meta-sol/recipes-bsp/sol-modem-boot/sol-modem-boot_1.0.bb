SUMMARY = "sol: boot the modem subsystem, where the GNSS engine lives"
DESCRIPTION = "Nothing binds or starts 6080000.remoteproc-mss at boot, so \
geoclue's provider comes up and waits forever for an engine that is not running. \
This binds and starts it, borrowing the firmware loader's search path (the modem \
firmware sits in firmware_mnt/image, not the ADSP's directory) and restoring it \
afterwards. Ships DISABLED: positioning against this modem used to reset the SoC \
and what changed is not isolated."

LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-3.0-only;md5=c79ff39f19dfec6d293b95dea7b07891"

COMPATIBLE_MACHINE = "sol"
PACKAGE_ARCH = "${MACHINE_ARCH}"

inherit systemd

SRC_URI = "file://sol-modem-boot.sh \
           file://sol-modem-boot.service"

S = "${UNPACKDIR}"

do_install() {
    install -d ${D}${libexecdir}
    install -m 0755 ${UNPACKDIR}/sol-modem-boot.sh ${D}${libexecdir}/sol-modem-boot.sh

    install -d ${D}${systemd_unitdir}/system
    install -m 0644 ${UNPACKDIR}/sol-modem-boot.service \
        ${D}${systemd_unitdir}/system/sol-modem-boot.service
}

SYSTEMD_SERVICE:${PN} = "sol-modem-boot.service"
# NOT auto-enabled -- and this is now measured, not precautionary. Enabling it
# put sol into a RESET LOOP: uptime never exceeded ~55s across six consecutive
# observations (41, 4, 49, unreachable, 54, 16), and masking the unit stopped it
# dead (83, 143, 203, 263, 323s, climbing clean).
#
# So the reset is NOT retired, and the earlier "114 polled calls over ~19 minutes
# with no reset" stands only for a modem started BY HAND on an already-running
# system. Started at boot it resets, repeatedly. Whatever the difference is --
# the container coming up alongside a live modem, or something in early-boot
# power sequencing -- it is unexplained, and it is the thing to understand before
# this is enabled again.
#
# Enable by hand to test GPS: /usr/libexec/sol-modem-boot.sh
SYSTEMD_AUTO_ENABLE:${PN} = "disable"

FILES:${PN} = "${libexecdir}/sol-modem-boot.sh \
               ${systemd_unitdir}/system/sol-modem-boot.service"
