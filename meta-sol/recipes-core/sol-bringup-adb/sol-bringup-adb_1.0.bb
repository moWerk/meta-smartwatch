SUMMARY = "sol BRING-UP: bind the adb gadget without usb-moded"
DESCRIPTION = "Brings adb up after switch_root by doing the one thing usb-moded's \
adb_mode does that we still need, and masks usb-moded so the two cannot fight \
over configfs. REMOVE THIS once usb-moded works on sol."

# WHY THIS EXISTS
#
# On sol, usb-moded starts, detects configfs, and then stops:
#     usb_moded: CONFIGFS detected
#     usb_moded: udev io watch disabled     <- log_crit, G_IO_ERR/HUP on the
#                                              udev monitor fd (usb_moded-udev.c)
# and never sets a mode at all: no adb_mode, no set_udc, not even a
# charging_only fallback. Cable state on sol comes from udev/extcon, that watch
# dies at startup, so the event that would apply adb_mode never arrives. The
# gadget is left as the empty g1 skeleton init_gfs staged, the host sees a
# mass-storage-only composition (18d1:0afe, bInterfaceClass 8) with an empty
# LUN, and there is no adb after switch_root at all.
#
# That is a REGRESSION IN usb-moded's cable detection on this device, not a
# config error, and it is NOT diagnosed yet. Checked and ruled out:
#   - /etc/usb-moded/sol-defaults.ini IS installed and says mode=adb_mode
#     (verified with debugfs against the flashed ext4).
#   - The rndis mkdir failure in the log is mode ENUMERATION, not the selected
#     mode. CONFIG_USB_CONFIGFS_RNDIS is unset on beluga/hoki/koi too.
#   - systemd-udevd.service, systemd-udev-trigger.service and both udevd
#     sockets are enabled; udevd is not missing.
#   - The FFS_ACTIVE/ep1 wait patch IS applied in the built usb-moded.
#   - USB_MODED_ARGS=--fallback (usbmoded_hw_fallback, documented as making
#     cable-detection failure non-fatal) does NOT fix it. Tested on hardware.
#
# MASKING usb-moded is required, not incidental: it is the sole writer of
# functions and configs/b.1, and its configfs_init() zeroes UDC and wipes
# configs/b.1. Running both means it destroys the gadget this unit built.
#
# Masking it also means android-tools-adbd must be enabled directly, because
# meta-sol's 10-sol-android-tools.preset deliberately disables it so that
# usb-moded's appsync owns adbd startup. With usb-moded masked there is no
# appsync, so nothing would start adbd otherwise.
#
# Hardware-verified on sol 2026-08-12. Boot log:
#     sol-bringup-adb: FunctionFS ready (ep1 present after 100ms)
#     sol-bringup-adb: linked ffs.adb into configs/b.1
#     sol-bringup-adb: bound UDC=4e00000.dwc3 -- adb gadget should be live
# and confirmed by an unplanned test: a dead-man's-switch reboot brought the
# watch back on adb in ~95s with no physical intervention, which is the whole
# point. Before this, every failed boot cost a fastboot button combo.

# SECOND FAILURE MODE, found 2026-08-16: sol-bringup-adb.sh is a ONE-SHOT. It
# binds the UDC once at boot and returns early if it is already bound, and with
# usb-moded masked nothing else owns cable state. So a VBUS loss is a ONE-WAY
# DOOR: the watch keeps running on battery, but when power returns the gadget
# never re-enumerates and the host sees POWER ON with no device on the port. The
# only recovery is the fastboot button combo -- human hands.
# Measured: a 75 s docking-bay VBUS cut, then 5 s and 30 s cycles plus 90 s of
# waiting, produced no enumeration while aurora on the next port was fine.
# This blocks every off-charger investigation (kido's mce/sensorfwd lockup chain
# reproduces only while unplugged), so sol-usb-recover.service now watches
# /sys/class/udc/<udc>/state and rebinds when VBUS is present but the link has
# stayed "not attached". See sol-usb-recover.sh for why it is deliberately slow
# to act.

LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-3.0-only;md5=c79ff39f19dfec6d293b95dea7b07891"

COMPATIBLE_MACHINE = "sol"
PACKAGE_ARCH = "${MACHINE_ARCH}"

inherit systemd

SRC_URI = "file://sol-bringup-adb.sh \
           file://sol-bringup-adb.service \
           file://sol-usb-recover.sh \
           file://sol-usb-recover.service \
           file://sol-usb-network.sh \
           file://sol-usb-network.service"

S = "${UNPACKDIR}"

RDEPENDS:${PN} = "android-tools-adbd"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${UNPACKDIR}/sol-bringup-adb.sh ${D}${bindir}/sol-bringup-adb.sh

    install -m 0755 ${UNPACKDIR}/sol-usb-recover.sh ${D}${bindir}/sol-usb-recover.sh
    install -m 0755 ${UNPACKDIR}/sol-usb-network.sh ${D}${bindir}/sol-usb-network.sh

    install -d ${D}${systemd_unitdir}/system
    install -m 0644 ${UNPACKDIR}/sol-bringup-adb.service \
        ${D}${systemd_unitdir}/system/sol-bringup-adb.service
    install -m 0644 ${UNPACKDIR}/sol-usb-recover.service \
        ${D}${systemd_unitdir}/system/sol-usb-recover.service
    install -m 0644 ${UNPACKDIR}/sol-usb-network.service \
        ${D}${systemd_unitdir}/system/sol-usb-network.service

    # Mask usb-moded. /etc wins over /lib, and a symlink to /dev/null is the
    # standard mask; doing it here rather than by hand keeps the two changes
    # (mask + this unit) inseparable, because either alone leaves no adb.
    install -d ${D}${sysconfdir}/systemd/system
    ln -sf /dev/null ${D}${sysconfdir}/systemd/system/usb-moded.service

    # android-tools-adbd is preset-disabled by 10-sol-android-tools.preset.
    # With usb-moded masked, enable it explicitly or nothing starts adbd.
    install -d ${D}${sysconfdir}/systemd/system/multi-user.target.wants
    ln -sf ${systemd_unitdir}/system/android-tools-adbd.service \
        ${D}${sysconfdir}/systemd/system/multi-user.target.wants/android-tools-adbd.service
}

SYSTEMD_SERVICE:${PN} = "sol-bringup-adb.service sol-usb-recover.service sol-usb-network.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

FILES:${PN} = "${bindir}/sol-bringup-adb.sh \
               ${bindir}/sol-usb-recover.sh \
               ${bindir}/sol-usb-network.sh \
               ${systemd_unitdir}/system/sol-bringup-adb.service \
               ${systemd_unitdir}/system/sol-usb-recover.service \
               ${systemd_unitdir}/system/sol-usb-network.service \
               ${sysconfdir}/systemd/system/usb-moded.service \
               ${sysconfdir}/systemd/system/multi-user.target.wants/android-tools-adbd.service"
