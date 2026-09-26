# sol has no modem: unbind the modem remoteproc so nothing can start it.
#
# See the unit's own header for the full reasoning and the hardware evidence.
# Short version: 6080000.remoteproc-mss on a unit reporting modem_supported=0x0
# fails its firmware load and Qualcomm's subsystem-restart escalates to a full
# SoC reset. With it bound, starting the Android container resets the watch in
# about ten seconds; with it unbound the container runs and the display composer
# and gralloc allocator come up normally.
#
# This is sol-specific on purpose. sol ships in LTE and BT/WiFi-only variants and
# this is the latter; a modem-equipped unit must NOT get this.
SUMMARY = "Unbind the modem remoteproc on modem-less sol units"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://sol-unbind-modem-remoteproc.service"

S = "${UNPACKDIR}"

inherit systemd

SYSTEMD_SERVICE:${PN} = "sol-unbind-modem-remoteproc.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/sol-unbind-modem-remoteproc.service \
        ${D}${systemd_system_unitdir}/sol-unbind-modem-remoteproc.service
}

FILES:${PN} = "${systemd_system_unitdir}/sol-unbind-modem-remoteproc.service"
