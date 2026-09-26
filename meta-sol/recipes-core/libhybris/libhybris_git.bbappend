# sol runs Android-14 system libraries under libhybris. Everything here is
# :sol-scoped, so no other machine is affected -- same shape and same
# device-layer location as meta-aurora's libhybris bbappend, which is the
# precedent this follows.
#
# libhybris-a13-hooks.patch is Florent's, copied verbatim from meta-aurora with
# his Signed-off-by intact. It is not adapted, because nothing in it is
# A13-specific: it bridges libc/runtime symbols that the Android system libs
# import and that upstream libhybris does not provide (the ARM EHABI unwinder
# family, memfd_create, android_get_device_api_level, __system_properties_init,
# and the missing fdsan members). All of those exist unchanged in A14, and both
# layers pin the same libhybris SRCREV, so it applies identically.
#
# SEE THE NOTE AT THE BOTTOM: carrying the same file in two device layers is
# duplication, and the right end state is probably meta-asteroid.
FILESEXTRAPATHS:prepend := "${THISDIR}/libhybris:"
SRC_URI:append:sol = " file://libhybris-a13-hooks.patch \
                       file://libhybris-skip-bionic-property-init-without-area.patch \
                       file://libhybris-sol-disable-ubwc-usage.patch"

# NO SRCREV BUMP HERE, AND HERE IS WHY (tested 2026-08-12, do not retry blind).
#
# It is tempting: sol's vendor publishes ONLY the AIDL composer
#     <hal format="aidl"> android.hardware.graphics.composer3 v2 IComposer/default
# with no android.hardware.graphics.composer@2.x anywhere, our pin (9362799,
# 2024-09-01) is HIDL-only, and upstream HEAD (7079712) has AidlComposerHal.cpp
# with automatic selection:
#     if (AidlComposer::isDeclared(serviceName)) return make_unique<AidlComposer>(...)
#     return make_unique<HidlComposer>(...)
# so a bump looks like it would just work.
#
# It does not, because THIS RECIPE DOES NOT BUILD THAT CODE. The shared recipe
# sets S = "${WORKDIR}/git/hybris", so compat/hwc2/ -- where every Composer
# implementation lives -- is outside the build entirely. Bumped to upstream HEAD
# the recipe still builds clean (patches apply, 0 errors) and the resulting
# /usr/lib/libhwc2.so contains no composer code at all: zero hits for
# composer3, AidlComposer, HidlComposer, or the failing string.
#
# The code that actually runs is a PREBUILT inside aurora's Halium A13 image:
#     /android/hybris/system/lib/libhwc2_compat_layer.so
# which is the only binary on the device containing
# "failed to get hwcomposer service". compat/hwc2 is built by Android.mk inside
# a Halium/AOSP build, not by Yocto.
#
# So fixing the composer means producing a newer libhwc2_compat_layer.so, i.e.
# rebuilding the Halium system image, NOT bumping this SRCREV. See
# .investigation-logs/20260812_sol_display_drm_bringup.txt.

# Library search path for the hybris linker, sol-specific.
#
# The default from meta-asteroid is
#     /usr/libexec/hal-droid/system/lib:/vendor/lib:/system/lib
# and the ORDER is the problem: /vendor/lib comes before /system/lib, so for any
# library shipped in both, vendor's VNDK snapshot wins -- and it is an older
# ABI. On sol that broke the launcher with
#     cannot locate symbol "_ZN7android26openDeclaredPassthroughHalERKNS_8String16ES2_i"
#     referenced by "libbinder_ndk.so"
# because libbinder.so resolved from /vendor/lib (482128 bytes, symbol absent)
# while libbinder_ndk.so came from /system/lib (499040 bytes, symbol present).
# Verified against the partition dumps, and confirmed on hardware 2026-08-10.
#
# Putting /system/lib first fixes that class of mismatch generally, instead of
# shadowing one library at a time. Vendor still wins for anything system does
# not ship, which is what vendor HALs actually need.
#
# /apex/com.android.runtime/lib/bionic is listed explicitly because sol's bionic
# lives in an APEX: /system/lib/libc.so is a symlink into it, and the apex is
# loop-mounted by sol-vendor-mount. Naming the real directory means resolution
# does not depend on the symlink surviving.
#
# /usr/libexec/hal-droid/system/lib is kept last. sol does not install
# meta-asteroid's `android` recipe (IMAGE_INSTALL:remove drops android-system),
# so it is empty today, but it is where a sol libui_compat_layer.so would go.
# /vendor/lib/egl is NOT optional: the Adreno EGL driver dlopens
# eglSubDriverAndroid.so from there, and without it EGL init fails with
# `library "eglSubDriverAndroid.so" not found`. /vendor/lib/hw carries the
# passthrough HAL implementations (including the gralloc4 mapper).
#
# asteroid-launcher additionally sets HYBRIS_LD_LIBRARY_PATH in its own
# config, following aurora, because it needs the Halium system path too.
# This compiled-in default covers the other hybris consumers (sensorfwd,
# ngfd, bluebinder) that have no such config.
EXTRA_OECONF:append:sol = " --with-default-hybris-ld-library-path=/android/hybris/system/lib:/system/lib:/vendor/lib:/vendor/lib/egl:/vendor/lib/hw:/apex/com.android.runtime/lib/bionic:/usr/libexec/hal-droid/system/lib"

# libhybris-sol-disable-ubwc-usage.patch -- NOW TAKEN, on its own evidence.
#
# An earlier version of this comment said the aurora UBWC patch was deliberately
# not taken, because the launcher had never got far enough to composite and
# bundling it with the symbol-bridging work would have made two variables out of
# one. The launcher now composites, and the predicted symptom appeared exactly as
# described, so the condition that paragraph set has been met.
#
# HWComposerNativeWindow default-ORs GRALLOC_USAGE_HW_COMPOSER into the buffer
# usage, which on Monaco's QTI gralloc4 path triggers UBWC allocation. The only
# SDE plane available to SDM for the launcher's client-composition layer is
# plane 70, a DMA pipe with no UBWC support, so the kernel rejects the atomic
# commit. Measured on sol hardware 2026-08-13, from the composer's own logs:
#     E SDM: DRMAtomicReq::Commit: drmModeAtomicCommit failed with error 22
#     E SDM: HWDeviceDRM::AtomicCommit: AtomicCommit failed with error -22 crtc 80
#            (layer dumped as pipe_id = 70, src 512x464, dst 456x456)
# Everything upstream of that commit is healthy: composer client acquired,
# primary display hotplugged, Qt sees the real 456x456 panel, and validate and
# present run in a continuous loop. Only the commit fails, which is why the
# connector stays "disabled" and crtc-0 stays enable=0/active=0.
#
# The patch is aurora's, by Florent, with his Signed-off-by intact. The diff is
# identical to aurora's apart from one comment line naming the device, and it
# applies to the SRCREV this layer pins with zero fuzz and zero offset (checked
# against quilt's own pre-patch copy under .pc/, not against the work tree --
# the work tree had already been through a patch cycle and reading it produced a
# diff that applied with fuzz, which do_patch rejects as a QA error).
#
# Note it is NOT gated on HYBRIS_HWC_DISABLE_COMPOSER_USAGE. meta-aurora's
# bbappend comment describes its copy as gated on that variable, but neither
# aurora's patch nor this one reads it anywhere -- verified by grep over both
# patch files and by the absence of any HYBRIS_HWC_* string in the built
# libhybris on device. The real gating is the per-machine SRC_URI append. sol's
# launcher config therefore does NOT set that variable, because setting it would
# imply a switch that does not exist.

# FLEET NOTE, for planning rather than for this change: if sol needs
# libhybris-a13-hooks.patch byte-for-byte -- and it does -- then the patch is
# not device-specific at all, it is "Android 13+ system libs under libhybris",
# and two device layers now carry identical copies. The tidy end state is to
# move it to meta-asteroid's libhybris bbappend, unconditionally or gated on the
# android-headers version, and drop both copies. That is a fleet-wide change
# affecting every hybris device, so it belongs in a separate PR with
# co-maintainer review and cross-device testing, not in the sol port.
