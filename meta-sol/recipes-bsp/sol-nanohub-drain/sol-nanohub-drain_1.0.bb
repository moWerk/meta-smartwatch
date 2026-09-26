SUMMARY = "sol: keep the nanohub shared buffer pool from being exhausted"
DESCRIPTION = "google-modules/nanohub shares ONE pool of 20 buffers \
(READ_QUEUE_DEPTH) across all 30 of its channels, and a buffer is only returned \
to that pool by a userspace read(). Its drop-if-nobody-is-listening guard in \
nanohub_process_buffer(), and the discard sweep in nanohub_release(), are both \
scoped to id == ID_NANOHUB_CLIENT. The ten other userspace channels (display, \
render, debug_log, metrics, console, rpc0, rpc1, brightness, pele, bt) therefore \
queue buffers unconditionally, and AsteroidOS opens none of them. Twenty unread \
messages on any one of them strands the entire pool, after which the reader \
kthread's non-blocking get_buf returns NULL and the driver stops reading the MCU \
altogether -- killing every sensor. \
\
That is the head of the lockup chain kido described but never fully root-caused: \
sensors stall, the hybris stack blocks, sensorfwd stops answering DBus, and mce \
blocks in an untimed DBus call while holding a wakelock, so the watch cannot \
suspend and drains. It also explains why he suspected screen brightness: \
ID_NANOHUB_BRIGHTNESS is one of the unguarded channels and the brightness ramp \
animation is exactly what generates traffic on it. \
\
This recipe is the DEVICE-SCOPED workaround: hold those nodes open and discard \
what arrives. The correct fix is in the driver, but nanohub is shared with \
aurora and the rest of the Google-watch fleet, so it needs maintainer review \
rather than a unilateral change from a sol bring-up branch. \
\
See .investigation-logs/20260816_sol_nanohub_pool_exhaustion.md for the full \
analysis, including the source quotes and the hardware test that still has to \
confirm it."

LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-3.0-only;md5=c79ff39f19dfec6d293b95dea7b07891"

COMPATIBLE_MACHINE = "sol"
PACKAGE_ARCH = "${MACHINE_ARCH}"

inherit systemd

SRC_URI = "file://sol-nanohub-drain.sh \
           file://sol-nanohub-drain.service"

S = "${UNPACKDIR}"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${UNPACKDIR}/sol-nanohub-drain.sh ${D}${bindir}/sol-nanohub-drain.sh

    install -d ${D}${systemd_unitdir}/system
    install -m 0644 ${UNPACKDIR}/sol-nanohub-drain.service \
        ${D}${systemd_unitdir}/system/sol-nanohub-drain.service
}

SYSTEMD_SERVICE:${PN} = "sol-nanohub-drain.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

FILES:${PN} = "${bindir}/sol-nanohub-drain.sh \
               ${systemd_unitdir}/system/sol-nanohub-drain.service"
