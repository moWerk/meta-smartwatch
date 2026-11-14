FILESEXTRAPATHS:prepend:sol := "${THISDIR}/${PN}:"
COMPATIBLE_MACHINE:sol = "sol"

# As on aurora, init.sh modprobes the vendor modules early from
# /etc/modules.load.sol: sdhci_msm.ko and ~85 other SoC drivers are =m on GKI.
SRC_URI:append:sol = " file://init.sh file://modules.load.sol file://google-extcon-usb-shim.conf"

do_install:append:sol() {
    install -m 0755 ${UNPACKDIR}/init.sh ${D}/init

    # Module list in UBPorts' order (geni serial, q6v5_pas, ADSP audio,
    # nanohub, WLAN); modprobe resolves dependencies itself.
    install -m 0644 -D ${UNPACKDIR}/modules.load.sol ${D}/etc/modules.load.sol

    # Inherited from aurora, where it clears the shim's DT USB force-disable.
    # sol's module is google_extcon_shim, so this has no effect here; init.sh
    # opens the sol gate through sysfs.
    install -m 0644 -D ${UNPACKDIR}/google-extcon-usb-shim.conf ${D}/etc/modprobe.d/google-extcon-usb-shim.conf
}

FILES:${PN}:append:sol = " /etc/modules.load.sol /etc/modprobe.d/google-extcon-usb-shim.conf"
