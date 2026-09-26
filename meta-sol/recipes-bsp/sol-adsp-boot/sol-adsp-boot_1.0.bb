SUMMARY = "sol: bring up the ADSP for the Qualcomm USF sensor sub-HAL"
DESCRIPTION = "sol's sensor stack needs both the Google MCU (nanohub, brought up \
by loading spi-msm-geni) and the Qualcomm ADSP, where the USF sub-HAL named in \
/vendor/etc/sensors/hals.conf runs as a protection domain. The kernel's firmware \
loader searches only /lib/firmware, which on our rootfs holds GPU firmware and \
no adsp.*, so remoteproc0 stayed offline from boot and sscrpcd looped forever \
trying to spawn the sensor PD. This points the loader at the vendor image's \
firmware and starts the remoteproc. Hardware-verified 2026-08-15: remoteproc0 \
goes offline -> running with no reset, and adsprpc then registers the \
sensors_pdr service locator exactly as sol's stock dmesg does."

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

COMPATIBLE_MACHINE = "sol"
PACKAGE_ARCH = "${MACHINE_ARCH}"

SRC_URI = "file://sol-adsp-boot.sh \
           file://sol-adsp-boot.service"

S = "${UNPACKDIR}"

inherit systemd

do_install() {
    install -d ${D}${libexecdir}
    install -m 0755 ${UNPACKDIR}/sol-adsp-boot.sh ${D}${libexecdir}/sol-adsp-boot.sh
    install -d ${D}${systemd_unitdir}/system
    install -m 0644 ${UNPACKDIR}/sol-adsp-boot.service ${D}${systemd_unitdir}/system/sol-adsp-boot.service
}

FILES:${PN} = "${libexecdir}/sol-adsp-boot.sh \
               ${systemd_unitdir}/system/sol-adsp-boot.service"

RDEPENDS:${PN} = "sol-vendor-mount"

SYSTEMD_SERVICE:${PN} = "sol-adsp-boot.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"
