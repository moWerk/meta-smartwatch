SUMMARY = "sol: pin the Bluetooth UART awake only while Bluetooth is on"
DESCRIPTION = "sol's BT HCI runs over a geni UART whose device tree declares no \
wakeup interrupt, so a runtime-suspended port can never be woken by the \
controller and Bluetooth needs the port pinned runtime-active. A pinned port \
holds the driver's wakeup source, and one held wakeup source stops the kernel \
attempting suspend at all. This follows the adapter instead: pinned while \
Bluetooth is up, released while it is down."

LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-3.0-only;md5=c79ff39f19dfec6d293b95dea7b07891"

COMPATIBLE_MACHINE = "sol"
PACKAGE_ARCH = "${MACHINE_ARCH}"

inherit systemd

SRC_URI = "file://sol-bt-uart-pm.sh \
           file://sol-bt-uart-pm.service"

S = "${UNPACKDIR}"

# bluez provides hciconfig, which is how the adapter state is read.
RDEPENDS:${PN} = "bluez5"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${UNPACKDIR}/sol-bt-uart-pm.sh ${D}${bindir}/sol-bt-uart-pm.sh

    install -d ${D}${systemd_unitdir}/system
    install -m 0644 ${UNPACKDIR}/sol-bt-uart-pm.service \
        ${D}${systemd_unitdir}/system/sol-bt-uart-pm.service
}

SYSTEMD_SERVICE:${PN} = "sol-bt-uart-pm.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

FILES:${PN} = "${bindir}/sol-bt-uart-pm.sh \
               ${systemd_unitdir}/system/sol-bt-uart-pm.service"
