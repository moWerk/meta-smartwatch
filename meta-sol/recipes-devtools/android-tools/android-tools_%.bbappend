# Ported from meta-aurora (Kido / Florent Revest).
#
# usb-moded triggers android-tools-adbd via StartUnit() after its
# configfs_set_function() has created the FunctionFS configfs dir;
# auto-starting at basic.target instead races configfs setup and leaves adbd
# holding the abstract socket "local:5037" with no /dev/usb-ffs/adb.
#
# Observed on sol 2026-08-09 before this was ported: `adb devices` reported the
# watch as `offline` while the gadget enumerated (18d1:d002) and flapped,
# because android-tools-adbd.service carries Restart=on-failure and each
# restart re-ran android-gadget-setup.
SYSTEMD_AUTO_ENABLE:${PN}-adbd:sol = "disable"
