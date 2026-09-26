SUMMARY = "sol: AIDL-capable hwc2 compatibility layer for the Halium system"
DESCRIPTION = "libhwc2_compat_layer.so built with AidlComposerHal, plus the two \
AIDL stubs it links against, overlaid into /android/hybris/system/lib. \
\
sol's display composer is AIDL composer3 and registers \
android.hardware.graphics.composer3.IComposer/default on vndbinder. The \
libhwc2_compat_layer.so inside the borrowed Halium-13 system image predates \
AidlComposerHal and only knows the HIDL path, so libhybris finds no hwcomposer \
and asteroid-launcher aborts with 'failed to get hwcomposer service'. \
\
Built from Halium's libhybris (branch halium-13.0, which has AidlComposerHal) \
in a Halium 14 tree via `lunch aosp_arm-ap2a-eng && m libhwc2_compat_layer`, so \
these are build products of open source, not vendor blobs. The ABI is safe: \
hybris/include/hybris/hwc2/hwc2_compatibility_layer.h is byte-identical between \
our pinned libhybris and Halium's. \
\
Hardware-verified on 2026-08-15: the launcher goes from a SIGABRT restart loop \
to stable with NRestarts=0, and card0-DSI-1 goes from enabled=disabled to \
enabled with dpms=On. \
\
This recipe is a bridge, not a destination. When sol gets its own Halium system \
built against its A14 vendor, these three files belong inside that image and \
this recipe should be deleted."

LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

COMPATIBLE_MACHINE = "sol"
PACKAGE_ARCH = "${MACHINE_ARCH}"

# Prebuilt 32-bit ARM Android shared objects: none of our toolchain QA applies.
INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_SYSROOT_STRIP = "1"
EXCLUDE_FROM_SHLIBS = "1"
# libdir: these .so files live under ${datadir} on purpose -- nothing on the host
# links them, they exist only to be overlaid into the Halium system's own lib
# directory at runtime. QA's "found library in wrong location" check assumes a
# host library and does not apply.
INSANE_SKIP:${PN} = "already-stripped arch ldflags dev-so file-rdeps textrel staticdev libdir"

inherit systemd

# NOTE FOR REVIEW / NOT YET HOSTED: per this tree's no-binaries-in-git rule the
# three .so files are not committed. They are packed into
# sol-hwc2-aidl-1.0.tar.gz (274313 bytes) which needs hosting alongside the
# other pinned sol artifacts; the checksums below are of that exact file and are
# already final, so publishing it is the only remaining step and the URL is the
# only line that changes.
SRC_URI = "https://REPLACE-WITH-HOSTED-URL/sol-hwc2-aidl-1.0.tar.gz \
           file://sol-hwc2-aidl-overlay.sh \
           file://sol-hwc2-aidl.service"
SRC_URI[sha256sum] = "cf0cf7e2ba81c137901d410205c501323bb305d9854397a5f9fb2ca906fbdf28"
SRC_URI[md5sum] = "703a54aef9165c79ac751e746ac1dc9a"

S = "${UNPACKDIR}"

do_install() {
    install -d ${D}${datadir}/sol-hwc2-aidl
    install -m 0644 ${UNPACKDIR}/libhwc2_compat_layer.so \
        ${D}${datadir}/sol-hwc2-aidl/libhwc2_compat_layer.so
    install -m 0644 ${UNPACKDIR}/android.hardware.graphics.composer@2.4.so \
        ${D}${datadir}/sol-hwc2-aidl/android.hardware.graphics.composer@2.4.so
    install -m 0644 ${UNPACKDIR}/android.hardware.graphics.composer3-V4-ndk.so \
        ${D}${datadir}/sol-hwc2-aidl/android.hardware.graphics.composer3-V4-ndk.so
    install -m 0644 ${UNPACKDIR}/README.txt ${D}${datadir}/sol-hwc2-aidl/README.txt

    install -d ${D}${libexecdir}
    install -m 0755 ${UNPACKDIR}/sol-hwc2-aidl-overlay.sh \
        ${D}${libexecdir}/sol-hwc2-aidl-overlay.sh

    install -d ${D}${systemd_unitdir}/system
    install -m 0644 ${UNPACKDIR}/sol-hwc2-aidl.service \
        ${D}${systemd_unitdir}/system/sol-hwc2-aidl.service
}

# Installed under ${datadir} rather than a library path on purpose: nothing on
# the host should link these, they exist only to be overlaid into the Halium
# system's own lib directory at runtime.
FILES:${PN} = "${datadir}/sol-hwc2-aidl \
               ${libexecdir}/sol-hwc2-aidl-overlay.sh \
               ${systemd_unitdir}/system/sol-hwc2-aidl.service"

RDEPENDS:${PN} = "sol-lxc-android"

SYSTEMD_SERVICE:${PN} = "sol-hwc2-aidl.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"
