SUMMARY = "sol: release the Android zygote_kwl wakelock that blocks suspend"
DESCRIPTION = "The Halium container's init.rc takes a kernel wakelock named \
zygote_kwl every time zygote restarts: \
\
    onrestart write /sys/power/wake_lock zygote_kwl \
\
Android's contract is that SystemSuspend (android.system.suspend, which \
hardcodes the same name) releases it once the Java framework is back up. \
AsteroidOS runs the container for HALs only and never starts system_server, so \
nothing ever releases it and the wakelock is held for the life of the boot. \
\
Measured on sol: zygote_kwl present in /sys/power/wake_lock in essentially every \
sample of two long instrumented runs, on and off charger, screen on and blanked, \
while /sys/power/suspend_stats/success stayed at 0 -- the watch has never \
suspended once. \
\
This is the small reversible fix. Disabling zygote outright is cleaner (nothing \
on AsteroidOS needs the Java framework) but is a riskier change to container \
init, so it is deliberately left as a follow-up. The service's log also measures \
how often zygote restarts, which is currently unknown. \
\
WARNING: this may allow sol to suspend for the first time ever. Suspend/resume \
is completely unexercised on this device -- wakeup sources, MCU, BT and WiFi \
resume paths have never been tested. Enable it deliberately, with adb attached \
and a recovery path ready."

LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-3.0-only;md5=c79ff39f19dfec6d293b95dea7b07891"

COMPATIBLE_MACHINE = "sol"
PACKAGE_ARCH = "${MACHINE_ARCH}"

inherit systemd

SRC_URI = "file://sol-zygote-wakelock.sh \
           file://sol-zygote-wakelock.service"

S = "${UNPACKDIR}"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${UNPACKDIR}/sol-zygote-wakelock.sh ${D}${bindir}/sol-zygote-wakelock.sh

    install -d ${D}${systemd_unitdir}/system
    install -m 0644 ${UNPACKDIR}/sol-zygote-wakelock.service \
        ${D}${systemd_unitdir}/system/sol-zygote-wakelock.service
}

SYSTEMD_SERVICE:${PN} = "sol-zygote-wakelock.service"
# NOT auto-enabled: this can let the watch suspend for the first time, and
# suspend/resume is unproven here. Enable by hand for testing first.
SYSTEMD_AUTO_ENABLE:${PN} = "disable"

FILES:${PN} = "${bindir}/sol-zygote-wakelock.sh \
               ${systemd_unitdir}/system/sol-zygote-wakelock.service"
