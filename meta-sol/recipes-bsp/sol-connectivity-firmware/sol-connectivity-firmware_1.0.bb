SUMMARY = "sol: Broadcom/Synaptics BCM4381 WiFi + Bluetooth firmware"
DESCRIPTION = "Firmware for sol's BCM4381 combo part, extracted from the \
device's own stock vendor image. sol's connectivity silicon is Synaptics/ \
Broadcom, NOT the Qualcomm WCN that aurora uses -- confirmed four ways: the \
dtbo declares android,syna_wlan, sol's own init.insmod.sol.cfg modprobes \
synadhd4381.ko, the BT node is compatible goog,nitrous, and this firmware is \
Broadcom. \
\
Firmware is shipped here while the kernel MODULES are built from source, and \
the asymmetry is deliberate: firmware is loaded by the driver at runtime and is \
ABI-independent, so stock blobs are directly reusable. Stock's modules are not. \
Measured 2026-08-16: roughly half of every vendor_dlkm module's symbol CRCs \
differ from our kernel's, and stock is built with CFI so its modules reference \
__cfi_slowpath_diag and __ubsan_handle_cfi_check_fail_abort, which our kernel \
does not export at all -- a hard link failure no config flag can bypass. \
\
Installs to /lib/firmware, the kernel's default search path. The host rootfs \
previously carried only GPU firmware (18 files, all a702_*/a740_*)."

LICENSE = "Proprietary"
LIC_FILES_CHKSUM = "file://README.txt;md5=${SOL_FW_README_MD5}"
SOL_FW_README_MD5 = "fd984496b11aa9bb63f9f2c1528053f5"

COMPATIBLE_MACHINE = "sol"
PACKAGE_ARCH = "${MACHINE_ARCH}"

# Vendor firmware blobs: none of our toolchain QA applies.
INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_SYSROOT_STRIP = "1"
EXCLUDE_FROM_SHLIBS = "1"
INSANE_SKIP:${PN} = "already-stripped arch ldflags dev-so file-rdeps textrel staticdev libdir"

# NOTE FOR REVIEW / NOT YET HOSTED: per this tree's no-binaries-in-git rule these
# blobs are not committed. They are packed into
# sol-connectivity-firmware-1.0.tar.gz (1056633 bytes) which needs hosting
# alongside the other pinned sol artifacts. The checksums below are of that exact
# file and are final, so publishing it is the only remaining step and the URL is
# the only line that changes.
SRC_URI = "https://REPLACE-WITH-HOSTED-URL/sol-connectivity-firmware-1.0.tar.gz"
SRC_URI[sha256sum] = "93e316f096342326adefc13408db92645b456cd39f448654c010ce69a182b449"
SRC_URI[md5sum] = "624bcf64a7ffe18d2d06d63f6209fdb9"

S = "${UNPACKDIR}"

do_install() {
    install -d ${D}${nonarch_base_libdir}/firmware
    # BT patchram: nitrous/btbcm request it by name at HCI setup time.
    install -m 0644 ${UNPACKDIR}/BCM4381A1.hcd     ${D}${nonarch_base_libdir}/firmware/
    install -m 0644 ${UNPACKDIR}/BCM4381A1_SIP.hcd ${D}${nonarch_base_libdir}/firmware/
    # The kernel's btbcm driver does NOT look for the vendor filename -- it asks
    # the firmware loader for 'brcm/BCM.hcd' (seen live: "BCM: firmware Patch
    # file not found, tried: 'brcm/BCM.hcd'"). brcm_patchram_plus is given an
    # explicit path so it does not need this, but shipping it means the in-kernel
    # path also finds the patch if anything ever attaches via btattach/serdev.
    install -d ${D}${nonarch_base_libdir}/firmware/brcm
    install -m 0644 ${UNPACKDIR}/BCM4381A1.hcd ${D}${nonarch_base_libdir}/firmware/brcm/BCM.hcd
    install -m 0644 ${UNPACKDIR}/BCM4381A1.hcd ${D}${nonarch_base_libdir}/firmware/brcm/BCM4381A1.hcd
    # WLAN: firmware + regulatory blob + calibration. The _FL22/_FSE22 cal
    # variants are board-specific; ship all three and let the driver pick.
    install -m 0644 ${UNPACKDIR}/fw_bcmdhd.bin     ${D}${nonarch_base_libdir}/firmware/
    install -m 0644 ${UNPACKDIR}/bcmdhd_clm.blob   ${D}${nonarch_base_libdir}/firmware/
    install -m 0644 ${UNPACKDIR}/bcmdhd.cal        ${D}${nonarch_base_libdir}/firmware/
    install -m 0644 ${UNPACKDIR}/bcmdhd.cal_FL22   ${D}${nonarch_base_libdir}/firmware/
    install -m 0644 ${UNPACKDIR}/bcmdhd.cal_FSE22  ${D}${nonarch_base_libdir}/firmware/
    install -d ${D}${datadir}/sol-connectivity-firmware
    install -m 0644 ${UNPACKDIR}/README.txt ${D}${datadir}/sol-connectivity-firmware/README.txt
}

FILES:${PN} = "${nonarch_base_libdir}/firmware \
               ${datadir}/sol-connectivity-firmware"
