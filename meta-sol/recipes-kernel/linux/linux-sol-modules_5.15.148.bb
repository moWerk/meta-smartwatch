SUMMARY = "Pixel Watch 3 (sol) Qualcomm/Google vendor kernel modules"
DESCRIPTION = "Builds the sw5100 EXT_MODULES (audio/bt/dataipa/datarmnet/ \
display/graphics/mm/mmrm/securemsm/video/wlan...) from source against \
linux-sol with the same clang + config, so vermagic/CRC/ABI match \
by construction (no KMI/AOSP-clang/prebuilt reuse). Repo set + revisions \
follow Google's kernel-platform repo manifest for this device \
(android.googlesource.com/kernel/manifest, branch \
android-msm-eos-5.15-tm-wear-kr3-dr-eos; google-modules/* pinned on the \
sibling -pixel-watch branch where noted)."
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"
COMPATIBLE_MACHINE = "sol"
# OE auto-appends "@PRSERV_PV_AUTOINC@+<every SRCREV concatenated>" to PKGV for
# a multi-SRCREV git recipe (package version-uniqueness), which is INDEPENDENT
# of PV/SRCPV — so the .ipk filename blew past the 255-byte NAME_MAX ("File
# name too long" in do_package_write_ipk) once the 18th repo (nvttouch) was
# added. Pin PKGV to a constant to stop the SRCREV-soup suffix. Source pinning
# is unaffected: the SRCREV_<name> lines pin every repo and bitbake task-hashes
# still track SRCREV changes; only the package version string is fixed.
require linux-sol-version.inc
PV = "${SOL_KERNEL_VERSION}"
PKGV = "${SOL_KERNEL_VERSION}"

# Module repos laid out at the private/ paths build.config.sw5100 / the
# kernel-platform manifest expect (EXT_MODULES dirs live under
# private/msm-google-modules/, glue under private/google-modules/).
AGM = "git://android.googlesource.com/kernel"
SRC_URI = "\
  ${AGM}/msm-extra;protocol=https;branch=${KBR};name=audio;destsuffix=git/private/msm-google-modules/audio \
  ${AGM}/msm-modules/bt;protocol=https;branch=${KBR};name=bt;destsuffix=git/private/msm-google-modules/bt \
  ${AGM}/msm-extra/dataipa;protocol=https;branch=${KBR};name=dataipa;destsuffix=git/private/msm-google-modules/dataipa \
  ${AGM}/msm-modules/datarmnet;protocol=https;branch=${KBR};name=datarmnet;destsuffix=git/private/msm-google-modules/datarmnet \
  ${AGM}/msm-modules/datarmnet-ext;protocol=https;branch=${KBR};name=datarmnetext;destsuffix=git/private/msm-google-modules/datarmnet-ext \
  ${AGM}/msm-extra/display-drivers;protocol=https;branch=${KBR};name=display;destsuffix=git/private/msm-google-modules/display \
  ${AGM}/msm-modules/graphics;protocol=https;branch=${KBR};name=graphics;destsuffix=git/private/msm-google-modules/graphics \
  ${AGM}/msm-modules/mm;protocol=https;branch=${KBR};name=mm;destsuffix=git/private/msm-google-modules/mm \
  ${AGM}/msm-modules/mmrm;protocol=https;branch=${KBR};name=mmrm;destsuffix=git/private/msm-google-modules/mmrm \
  ${AGM}/msm-modules/securemsm;protocol=https;branch=${KBR};name=securemsm;destsuffix=git/private/msm-google-modules/securemsm \
  ${AGM}/msm-extra/video-driver;protocol=https;branch=${KBR};name=video;destsuffix=git/private/msm-google-modules/video \
  ${AGM}/msm-modules/wlan-platform;protocol=https;branch=${KBR};name=wlanplat;destsuffix=git/private/msm-google-modules/wlan/platform \
  ${AGM}/msm-modules/qcacld;protocol=https;branch=${KBR};name=qcacld;destsuffix=git/private/msm-google-modules/wlan/qcacld-3.0 \
  ${AGM}/msm-modules/qca-wfi-host-cmn;protocol=https;branch=${KBR};name=qcacmn;destsuffix=git/private/msm-google-modules/wlan/qca-wifi-host-cmn \
  ${AGM}/msm-modules/wlan-fw-api;protocol=https;branch=${KBR};name=wlanfwapi;destsuffix=git/private/msm-google-modules/wlan/fw-api \
  ${AGM}/google-modules/soc/msm;protocol=https;branch=android-msm-seluna-5.15-android14-wear;name=socmsm;destsuffix=git/private/google-modules/soc/msm \
  ${AGM}/google-modules/bms;protocol=https;branch=${KBR};name=bms;destsuffix=git/private/google-modules/bms \
  ${AGM}/google-modules/touch/novatek_touch;protocol=https;branch=${KBR};name=nvttouch;destsuffix=git/private/google-modules/touch/novatek \
  ${AGM}/google-modules/nanohub;protocol=https;branch=android-msm-seluna-5.15-android14-wear;name=nanohub;destsuffix=git/private/google-modules/nanohub \
  ${AGM}/google-modules/rotary-encoders;protocol=https;branch=android-msm-seluna-5.15-android14-wear;name=rotary;destsuffix=git/private/google-modules/rotary-encoders \
  ${AGM}/google-modules/sound/mcu_mic_codec;protocol=https;branch=android-msm-seluna-5.15-android14-wear;name=mcumic;destsuffix=git/private/google-modules/sound/mcu_mic_codec \
  ${AGM}/google-modules/amplifiers;protocol=https;branch=android-msm-eos-5.15-tm-wear-kr3-pixel-watch;name=amplifiers;destsuffix=git/private/google-modules/amplifiers \
  ${AGM}/google-modules/display/watch/mcu-offload;protocol=https;branch=${KBR};name=mcudisp;destsuffix=git/private/google-modules/display/watch/mcu-offload \
  ${AGM}/google-modules/bluetooth/broadcom;protocol=https;branch=${KBR};name=btbrcm;destsuffix=git/private/google-modules/bluetooth/broadcom \
  ${AGM}/google-modules/wlan/syna/dhd4381;protocol=https;branch=${KBR};name=synadhd;destsuffix=git/private/google-modules/wlan/syna/dhd4381 \
  file://mcu_display-Kbuild \
  file://0004-amplifiers-cs40l26-set-loaded-before-mfd-add-devices.patch \
  file://0005-amplifiers-cl_dsp-return-ENOENT-when-coeff-control-i.patch \
  file://0006-amplifiers-cs40l26-pin-codec-MFD-child-platform-id.patch \
  file://0007-amplifiers-cs40l26-drive-reset-by-physical-level.patch \
  file://0001-audio-monaco-bind-haptics-codec-by-deterministic-MFD.patch \
  file://0008-amplifiers-cs40l26-codec-report-state-to-monaco-asoc.patch \
  file://cs40l26-Kbuild \
"
KBR = "android-msm-seluna-5.15-android14-wear"
# sol's connectivity drivers. PINNED, unlike the rest of this recipe: these were
# located via Google's kernel manifest (branch android-msm-seluna-5.15-android14-qpr3,
# note NO "-wear" suffix on the manifest branch) and a moving AUTOREV on a driver
# we cannot test quickly is a bad trade -- see the AUTOREV/SRCREV cache trap.
SRCREV_btbrcm = "30c9f3d04c698274f234c67afba82c19d2c5ca42"
SRCREV_synadhd = "b2da16bf1b0523c2e8c35e3cf2bcd47d608da6df"
SRCREV_audio = "${AUTOREV}"
SRCREV_bt = "${AUTOREV}"
SRCREV_dataipa = "${AUTOREV}"
SRCREV_datarmnet = "${AUTOREV}"
SRCREV_datarmnetext = "${AUTOREV}"
SRCREV_display = "${AUTOREV}"
SRCREV_graphics = "${AUTOREV}"
SRCREV_mm = "${AUTOREV}"
SRCREV_mmrm = "${AUTOREV}"
SRCREV_securemsm = "${AUTOREV}"
SRCREV_nvttouch = "${AUTOREV}"
SRCREV_video = "${AUTOREV}"
SRCREV_wlanplat = "${AUTOREV}"
SRCREV_qcacld = "${AUTOREV}"
SRCREV_qcacmn = "${AUTOREV}"
SRCREV_wlanfwapi = "${AUTOREV}"
# socmsm is pinned to the PIXEL-WATCH branch (sol variant) — its
# build.config.sw5100 EXT_MODULES authoritatively includes 'usb_shim' (the
# google,extcon-usb-shim driver our DT requires). The dr-eos branch is a strict
# subset (LTE variant; lacks usb_shim). See SRC_URI override.
SRCREV_socmsm = "${AUTOREV}"
SRCREV_bms = "${AUTOREV}"
# nanohub (sensor-hub MCU driver): Google-specific module pinned to the same
# pixel-watch branch as socmsm. Single-dir Kbuild; CONFIG_NANOHUB_* vars aren't
# in any Kconfig (invented for this tree) so we pass them via modroot + the
# corresponding `-DCONFIG_NANOHUB_*` flags via KMOD_MAKE's KCFLAGS (the source
# uses #ifdef gates on these names).
SRCREV_nanohub = "${AUTOREV}"
# rotary-encoders ships petc_input_filter (input event filter that hooks into
# nanohub via nanohub_register_listener) + ots_pat9126 (optical touch sensor);
# we build petc_input_filter so the MCU's input-channel messages have a
# kernel-side consumer -- without it the MCU may sit in pre-handshake state and
# mcu_mgmtd retries the firmware-download cycle.
SRCREV_rotary = "${AUTOREV}"
# sound/mcu_mic_codec is the ASoC codec that consumes nanohub's audio channel.
# Same role as petc_input_filter on a different nanohub_io channel.
SRCREV_mcumic = "${AUTOREV}"
# Pinned to the revision aurora runs. sol's own seluna branch of this repo is
# bazel-only and its cs40l26 does not bind here; aurora is the working reference
# on the same CS40L26A (chip ID 0x40A260) and this tree ships real build files.
SRCREV_amplifiers = "06552df7596558c5b9b0fe1ad39fefc4ae116ef7"
SRCREV_mcudisp = "${AUTOREV}"
SRCREV_FORMAT = "audio_bt_dataipa_datarmnet_datarmnetext_display_graphics_mm_mmrm_securemsm_video_wlanplat_qcacld_qcacmn_wlanfwapi_socmsm_bms_nvttouch_nanohub_rotary_mcumic_amplifiers_mcudisp_btbrcm_synadhd"

S = "${WORKDIR}/git"

# Build against the exact linux-sol kernel (same clang + config → matching
# vermagic/CRC/ABI). Use its shared build artifacts.  Host tools the kernel's
# modules_prepare/prepare0 needs (meta-oe linux.inc built these for the kernel;
# this recipe needs them too).
DEPENDS += "virtual/kernel clang-native"
DEPENDS += "bc-native bison-native flex-native openssl-native kmod-native rsync-native coreutils-native"
do_configure[depends] += "virtual/kernel:do_shared_workdir"

LLVM_BIN = "${STAGING_BINDIR_NATIVE}"
PATH:prepend = "${STAGING_BINDIR_NATIVE}:"
# linux-sol uilds out-of-tree (B != S): kernel SOURCE in STAGING_KERNEL_DIR,
# built artifacts (.config/Module.symvers/genksyms) in STAGING_KERNEL_BUILDDIR.
# Canonical OE external-module build: make -C <src> O=<builddir> M=...
KDIR = "${STAGING_KERNEL_DIR}"
KOUT = "${STAGING_KERNEL_BUILDDIR}"

# EXT_MODULES build order from build.config.sw5100 (M= dirs relative to S).
# NOTE: securemsm is also deliberately absent (TODO: restore). Its
# smcinvoke/compat/trace_smcinvoke.h hardcodes
#   SMCINVOKE_TRACE_INCLUDE_PATH ../../../../../vendor/qcom/opensource/monaco/securemsm-kernel/smcinvoke
# i.e. the AOSP tree layout, not our private/msm-google-modules/ one, so the build
# fails with "trace_smcinvoke.h file not found". The define is guarded by #ifndef, so
# it IS overridable via -DSMCINVOKE_TRACE_INCLUDE_PATH plus a matching -I; that is the
# proper fix. Dropped for now because smcinvoke/qseecom are in neither sol's 82-module
# first-stage order nor its stock vendor_kernel_boot, so they are not needed to boot.
#
# NOTE: mmrm is deliberately absent below. It is not in sol's 82-module first-stage
# order, not among the 98 modules sol's stock vendor_kernel_boot ships, and not in
# our vkb manifest -- it came from aurora's module set. It also does not build on
# the seluna branch: mmrm/Kbuild has "obj-m += test/" but that branch ships no
# test/ sources, so the build stops at "mmrm/test/Makefile: No such file or
# directory". The repo stays in SRC_URI (harmless, keeps SRCREV_FORMAT stable).
# FIRST-BOOT SUBSET. sol's vendor_kernel_boot needs only 16 techpack modules
# (google-battery google-bms google-charger google-extcon-shim gvotable logbuffer
# mcu_display msm_drm msm_kgsl nanohub qpnp-smblite-main qseecom_dlkm qti-qbg-main
# smcinvoke_dlkm sw5100_bms touch_nt383x0), so only the dirs producing those are built.
#
# Deliberately NOT built yet (none appear in sol's 98-module vkb set, so none are needed
# to boot; restore them when bringing up the corresponding hardware):
#   video, bt, mm/{sync_fence,hw_fence,msm_ext_display}, mmrm,
#   dataipa, datarmnet, datarmnet-ext, wlan/{platform,qcacld-3.0},
#   soc/msm/wlan_mac, rotary-encoders
# (amplifiers/cs40l26 WAS in this list; it is now built -- it needed a
#  hand-written Kbuild, not new hardware. See cs40l26-Kbuild.)
# qcacld alone is the largest single build here, and WLAN is post-boot functionality.
#
# securemsm is also absent for now: it provides smcinvoke_dlkm + qseecom_dlkm, which ARE
# in the vkb set but NOT in the 82-module first-stage order, so they are not loaded at
# boot. It needs a -DSMCINVOKE_TRACE_INCLUDE_PATH override (see the note above) before it
# can build against this source layout. Both are @drop'd in sol-vkb-modules.lst to match.
# ORDER MATTERS for the first three. do_compile's $extra accumulator only offers
# a module the Module.symvers of modules EARLIER in this list, and the display
# chain is nanohub <- mcu_display <- msm_drm:
#   - mcu_display includes nanohub_exports.h and calls into nanohub
#   - dsi_display.c includes mcu_display_exports.h and calls
#     mcu_display_register_panel_power_notifier()
#   - aurora's own modules.dep also lists nanohub as an msm_drm supplier
# nanohub used to sit last here, which is fine while nothing consumes it but
# wrong the moment the display chain is built.
# WLAN + BT, corrected 2026-08-16 after finding sol uses SYNAPTICS/BROADCOM
# connectivity, not Qualcomm.
#
# On 08-15 I added the Qualcomm set here (msm-google-modules/bt,
# wlan/platform, wlan/qcacld-3.0, soc/msm/wlan_mac) by copying aurora. They
# built cleanly and could never bind: `modprobe wlan` returns ENODEV because
# there is no Qualcomm WLAN in this watch. Removed again.
#
# sol's actual parts, confirmed four independent ways:
#   - the dtbo declares  /soc/wlan-gpios  compatible "android,syna_wlan"
#   - /soc/btbcm                          compatible "goog,nitrous"
#   - sol's own /vendor/etc/init.insmod.sol.cfg modprobes synadhd4381.ko
#   - the vendor firmware is BCM4381A1.hcd / fw_bcmdhd.bin (Broadcom)
# aurora IS genuinely Qualcomm (its vkb-base.dtb carries icnss/cnss; sol's
# carries none), so aurora is the WRONG reference for this subsystem.
#
# The two repos below come from Google's kernel manifest for this device
# (android.googlesource.com/kernel/manifest, branch
# android-msm-seluna-5.15-android14-qpr3 -- note the manifest branch has NO
# "-wear" suffix, unlike the module repos). They bind exactly the DT nodes the
# bootloader already provides:
#   bluetooth/broadcom  -> nitrous.ko,   nitrous.c: .compatible = "goog,nitrous"
#   wlan/syna/dhd4381   -> the DHD driver, handles "android,syna_wlan"
# rfkill.ko and btbcm.ko need no repo: they are upstream in-tree and are covered
# by CONFIG_RFKILL=y / CONFIG_BT_BCM=y in sw5100.fragment.
#
# Firmware is shipped separately by sol-connectivity-firmware (extracted from the
# device, ABI-independent) -- unlike the stock MODULES, which cannot be reused:
# ~half their symbol CRCs differ from our kernel and they need CFI symbols
# (__cfi_slowpath_diag) our kernel does not export at all.
EXT_MODULES = "\
  private/msm-google-modules/securemsm \
  private/google-modules/nanohub \
  private/google-modules/display/watch/mcu-offload/mcu_display \
  private/msm-google-modules/audio \
  private/msm-google-modules/display \
  private/msm-google-modules/graphics \
  private/google-modules/bms/misc \
  private/google-modules/bms \
  private/msm-google/drivers/power/supply/qcom \
  private/google-modules/soc/msm/drivers/extcon/google \
  private/google-modules/touch/novatek/nt383x0 \
  private/google-modules/bluetooth/broadcom \
  private/google-modules/wlan/syna/dhd4381 \
  private/google-modules/sound/mcu_mic_codec \
  private/google-modules/amplifiers/cs40l26 \
"
# qcacld-3.0 is the WiFi driver. Building it out-of-tree (via M=) against this
# kernel needs four accommodations, all applied here / in linux-sol:
#  - Two linux-sol kbuild patches (cmd-mod-file-func.patch,
#    cc-o-c-respfile.patch): qcacld's per-module object list and per-file
#    compile flags each exceed the kernel MAX_ARG_STRLEN single-argv limit; the
#    patches route them through a GNU make $(file ...) / clang @response-file
#    instead. Generic and harmless for every module.
#  - The full qcacld KBUILD_OPTIONS replicated in modroot() (qcacld's own
#    Makefile only sets them when WLAN_ROOT is unset; an M= build sets
#    WLAN_ROOT and bypasses that), plus a broad qca-wifi-host-cmn header path
#    set: the 'wear' profile feature-gates DFS/spectral but qcacmn's public
#    headers #include them unconditionally.
#  - WLAN_COMMON_ROOT passed as the relative `cmn` symlink (qcacld builds
#    object paths as $(WLAN_ROOT)/$(WLAN_COMMON_ROOT)/...; an absolute value
#    doubles the path).
#  - -DCFG80211_SINGLE_NETDEV_MULTI_LINK_SUPPORT: the google-eos kernel
#    backported the 4-arg MLO cfg80211_ch_switch_notify, which qcacld cannot
#    auto-detect, so it must be told to use the 4-arg path.

KMOD_MAKE = "make -C ${KDIR} O=${KOUT} ARCH=arm64 LLVM=1 LLVM_IAS=1 \
  CROSS_COMPILE=aarch64-linux-gnu- \
  CC='${LLVM_BIN}/clang --target=aarch64-linux-gnu -fuse-ld=lld' \
  LD='${LLVM_BIN}/ld.lld' AR='${LLVM_BIN}/llvm-ar' \
  NM='${LLVM_BIN}/llvm-nm' OBJCOPY='${LLVM_BIN}/llvm-objcopy' \
  KERNEL_SRC=${KDIR} OUT_DIR=${KDIR} \
  KCFLAGS='-Wno-error -Wno-error=implicit-int -Wno-error=int-conversion -Wno-error=incompatible-function-pointer-types -Wno-error=incompatible-pointer-types -Wno-error=implicit-function-declaration -Wno-error=strict-prototypes -I${KDIR}/drivers/clk/qcom -I${KDIR}/drivers/devfreq -I${KDIR}/include/linux -I${KDIR}/drivers/iommu -I${S}/private/msm-google-modules/wlan/qca-wifi-host-cmn/utils/sys -I${S}/private/google-modules/soc/msm/include/dtc -I${S}/private/google-modules/nanohub -DCONFIG_NANOHUB -DCONFIG_NANOHUB_SPI -DCONFIG_NANOHUB_BL_NXP -DCONFIG_NANOHUB_DISPLAY' \
  KBUILD_MODPOST_WARN=1 CONFIG_ARCH_MONACO=y WLAN_PROFILE=wear \
  CONFIG_CNSS_QCA6750=m CONFIG_QCA_CLD_WLAN=m CONFIG_TOUCHSCREEN_NT383x0=m"
# KERNEL_SRC / OUT_DIR: google-modules/bms/Makefile and
# msm-google/drivers/power/supply/qcom/Makefile are "wrapper" Makefiles (not
# just Kbuild fragments). They `include $(KERNEL_SRC)/../google-modules/
# soc/msm/Makefile.include` and reference $(OUT_DIR)/../google-modules/bms/
# misc/Module.symvers for KBUILD_EXTRA_SYMBOLS chaining. Both default to
# `/lib/modules/$(uname -r)/build` (HOST kernel) — wrong for OE cross builds,
# breaks the include. Point both at ${KDIR}: its parent (work-shared) already
# holds our `google-modules` + `msm-google-modules` symlinks (created in
# do_compile), so `$(KERNEL_SRC)/../google-modules/...` and
# `$(OUT_DIR)/../google-modules/...` resolve to our trees.

# do_package debug-split/strip uses recipe binutils; machine is armv7 →
# defaults choke on the aarch64 .ko. Use clang/llvm-* + don't strip.
OBJCOPY = "${LLVM_BIN}/llvm-objcopy"
STRIP = "${LLVM_BIN}/llvm-strip"
INHIBIT_SYSROOT_STRIP = "1"

do_configure[noexec] = "1"

# Each Qualcomm module Kbuild expects a <NAME>_ROOT make var pointing at its
# *repo* root (Kbuild does e.g. include $(SYNC_FENCE_ROOT)/config/...); the
# kernel-platform build passes these. Map module dir -> "VAR=reporoot".  NOTE:
# Qualcomm Kbuilds concatenate WITHOUT a separator, e.g.
# `-I$(SYNC_FENCE_ROOT)sync_fence/include/`, so every *_ROOT value MUST end
# with a trailing slash.
modroot() {
    P="${S}/private/msm-google-modules"
    case "$1" in
      mm/sync_fence)        echo "SYNC_FENCE_ROOT=$P/mm/" ;;
      mm/hw_fence)          echo "MSM_HW_FENCE_ROOT=$P/mm/" ;;
      mm/msm_ext_display)   echo "MSM_EXT_DISPLAY_ROOT=$P/mm/" ;;
      mmrm)                 echo "MMRM_ROOT=$P/mmrm/" ;;
      securemsm)            echo "SSG_MODULE_ROOT=$P/securemsm/" ;;
      # Audio Kbuild gates the Monaco/sw5100 build on TWO things: MODNAME
      # non-empty (sets internal KERNEL_BUILD=0 -- the Android- style
      # external-build path) AND CONFIG_ARCH_MONACO=y (matches the
      # specific platform branch). Both together cause the Kbuild to `include
      # $(AUDIO_ROOT)/config/sw5100auto.conf` which exports
      # CONFIG_MSM_ADSP_LOADER=m, CONFIG_SPF_CORE=m, CONFIG_AUDIO_PKT=m,
      # CONFIG_MSM_QDSP6_NOTIFIER=m, CONFIG_MSM_QDSP6_PDR=m, etc., and
      # -includes config/sw5100autoconf.h for the matching #define CONFIG_*.
      # Without both, no audio .ko's compile — and adsp_loader_dlkm in
      # particular is required to create /sys/kernel/boot_adsp/boot, the sysfs
      # that triggers ADSP subsystem boot. ADSP boot is in turn a prerequisite
      # for the modem subsystem (modem fw waits for ADSP via tmr_slave2;
      # without ADSP the modem watchdog stalls at "DOG detects stalled
      # initialization" and recursively crashes).
      audio)                echo "AUDIO_ROOT=$P/audio/ MODNAME=audio CONFIG_ARCH_MONACO=y" ;;
      # Display needs BOTH gates, and neither is in any Kconfig we merge.
      #
      # CONFIG_DRM_MSM gates the top-level Kbuild (`obj-$(CONFIG_DRM_MSM) +=
      # msm/`), and CONFIG_ARCH_MONACO gates msm/Kbuild's monaco branch, which
      # includes config/gki_monacodisp.conf (exporting CONFIG_DRM_MSM_SDE,
      # CONFIG_DRM_MSM_DSI, CONFIG_QCOM_MDSS_PLL...) and force-includes
      # gki_monacodispconf.h for the matching #defines. Same shape as audio's
      # MODNAME + CONFIG_ARCH_MONACO pair above. With neither set, kbuild walks
      # into display/ and emits ZERO .ko -- which is exactly what happened: the
      # vkb manifest then @drop'd msm_drm and mcu_display as "not built in the
      # first-boot module subset", describing the symptom as if it were the
      # intent. There is no display driver on the device at all as a result:
      # /sys/class/drm holds only `version`, fb0 is the bootloader's leftover
      # cont-splash buffer (qcomsplash on 5c000000.cont-splash-fb, which is why
      # psplash draws and nothing else can), and the Android composer aborts in
      # sdm::HWCSession::CreatePrimaryDisplay.
      #
      # Passed as MAKE VARIABLES, deliberately not added to the kernel fragment.
      # CONFIG_DRM_MSM is a real in-tree tristate (drivers/gpu/drm/msm/Kconfig),
      # so setting it in .config would also build the upstream in-tree driver as
      # msm.ko alongside this techpack msm_drm.ko. Different filenames, so they
      # would not collide on disk, but both bind qcom,sde-kms and would fight
      # over the same DT nodes. Scoping it to this M= build avoids that entirely.
      #
      # EXTRA_CFLAGS: msm/Kbuild adds -I.../mcu-offload/mcu_display, but the
      # header actually lives in that repo's include/ subdir (its BUILD.bazel
      # ddk_headers sets includes = ["include"]), so the upstream -I alone does
      # not resolve "mcu_display_exports.h". Add the real path.
      display)              echo "DISPLAY_ROOT=$P/display/ CONFIG_ARCH_MONACO=y CONFIG_DRM_MSM=y EXTRA_CFLAGS=-I${S}/private/google-modules/display/watch/mcu-offload/mcu_display/include" ;;
      # mcu_display: nanohub headers, same trick as mcu_mic_codec above.
      # Module.symvers chaining is automatic (nanohub is earlier in EXT_MODULES).
      private/google-modules/display/watch/mcu-offload/mcu_display)
        echo "EXTRA_CFLAGS=-I${S}/private/google-modules/nanohub" ;;
      graphics)             echo "KGSL_MODULE_ROOT=$P/graphics/" ;;
      video)                echo "VIDEO_ROOT=$P/video/" ;;
      # bt techpack: top-level Kbuild descends into slimbus/ + pwr/ ONLY when
      # CONFIG_BTFM_SLIM=m and CONFIG_MSM_BT_POWER=m are passed (see
      # bt/Kbuild). Without these, kbuild visits bt/ but produces nothing.
      # bt_fm_slim.ko registers the "btfmslim_slave" slim device that
      # monaco-asoc-snd's WCN BT dai_links (qcom,wcn-btfm=1) reference --
      # without it, the sound card defers forever.
      bt)                   echo "BT_ROOT=$P/bt/ CONFIG_BTFM_SLIM=m CONFIG_MSM_BT_POWER=m" ;;
      dataipa/*)            echo "IPA_ROOT=$P/dataipa/" ;;
      datarmnet/*)          echo "RMNET_CORE_ROOT=$P/datarmnet/" ;;
      datarmnet-ext/*)      echo "RMNET_EXT_ROOT=$P/datarmnet-ext/ RMNET_CORE_INC_DIR=$P/datarmnet/core RMNET_CORE_ROOT=$P/datarmnet/" ;;
      # wlan/platform = CNSS WLAN PLATFORM = the kernel-side broker qcacld-3.0
      # calls into via icnss_* / cnss_utils_* / cnss_nl_* symbols (QMI to FW,
      # firmware load, SMP2P, mem preallocator, generic netlink). Its top
      # Kbuild has `obj-$(CONFIG_ICNSS2) += icnss2/` etc., gated on CONFIG_*=m
      # which AREN'T in any Kconfig; the wrapper Makefile auto-sets them only
      # when WLAN_PLATFORM_ROOT is empty (`ifeq($(WLAN_PLATFORM_ROOT),)`) — and
      # we MUST pass WLAN_PLATFORM_ROOT (subdir Kbuilds do
      # `-I$(WLAN_PLATFORM_ROOT)/inc`), so the auto-config block is skipped.
      # Pass the CONFIG_*=m set ourselves. Skip CONFIG_CNSS2 (PCIe variant, n/a
      # for sol which is integrated/ICNSS).  CONFIG_CNSS_OUT_OF_TREE=y
      # switches subdir -I paths from
      # $(srctree)/drivers/net/wireless/cnss_utils (Google addition, absent in
      # our kernel tree) to $(WLAN_PLATFORM_ROOT)/inc.
      # CONFIG_ICNSS2_DEBUG deliberately NOT set: its only effect is turning
      # ICNSS_ASSERT() from a no-op into BUG() (icnss2/debug.h). The asserts
      # fire on conditions that are recoverable-by-design — e.g. a WLFW
      # server-arrive while already connected (main.c
      # icnss_driver_event_server_arrive) or a failed BDF download
      # (qmi.c ICNSS_QMI_ASSERT) — turning a loggable error into a kernel
      # panic and, on a watch with no console, a reboot loop. The wrapper
      # Makefile itself only enables it in its everything-on developer
      # default block (which we bypass by passing WLAN_PLATFORM_ROOT).
      wlan/platform)        echo "WLAN_PLATFORM_ROOT=$P/wlan/platform/ CONFIG_CNSS_OUT_OF_TREE=y CONFIG_ICNSS2=m CONFIG_ICNSS2_QMI=y CONFIG_CNSS_UTILS=m CONFIG_CNSS_GENL=m CONFIG_WCNSS_MEM_PRE_ALLOC=m CONFIG_CNSS_QMI_SVC=m CONFIG_CNSS_PLAT_IPC_QMI_SVC=m" ;;
      # qcacld's own Makefile sets a full KBUILD_OPTIONS set ONLY when it
      # computes WLAN_ROOT (ifeq $(WLAN_ROOT),) — and we both pass WLAN_ROOT
      # and bypass that Makefile (generic M= loop, needed for our out-of-tree
      # O=). qcacld's Kbuild gates its per-subsystem -I dirs on exactly these
      # CONFIG_*; not setting them => cascading 'file not found' (queue.h,
      # wlan_dfs_ioctl.h, ...). So pass the wrapper's full option set
      # ourselves.  WLAN_COMMON_ROOT must be RELATIVE (qcacld builds object
      # paths as $(WLAN_ROOT)/$(WLAN_COMMON_ROOT)/...; absolute => doubled path
      # "No rule to make target"). qcacld-3.0 ships the symlink cmn ->
      # ../qca-wifi-host-cmn (Kbuild/Android.mk default WLAN_COMMON_ROOT=cmn);
      # use it. WLAN_COMMON_INC = the abs path through that symlink.
      # MODNAME=wlan is intentional: any other name triggers Kbuild line
      # 4430-4433 to define MULTI_IF_NAME=$(MODNAME), which makes the driver's
      # wlan_hdd_misc.h prefix WLAN_INI_FILE/WLAN_MAC_FILE with an extra
      # "$(MODNAME)/" path segment -- breaking firmware lookup because
      # /vendor/firmware/wlan/qca_cld/WCNSS_qcom_cfg.ini actually lives at that
      # exact path (no extra subdir). The .ko produced is "wlan.ko".
      # PANIC_ON_BUG=n WLAN_WARN_ON_ASSERT=n: WLAN_PROFILE=wear includes
      # configs/wear_defconfig, which force-enables both whenever the kernel
      # has CONFIG_SLUB_DEBUG=y (ours does — GKI default). With PANIC_ON_BUG
      # defined, every QDF_BUG()/QDF_DEBUG_PANIC() in qcacld/qca-wifi-host-cmn
      # calls BUG() (cmn qdf/linux/src/i_qdf_trace.h); without it they compile
      # to logged no-ops — the same asserts-off mode QC ships on perf builds.
      # A failed assert then costs us a wifi error message instead of a
      # PS_HOLD reboot loop (the 2026-06-06 cnss-daemon incident). Make
      # command-line vars override the defconfig's `:=` assignments, so
      # passing them here wins. CONFIG_ICNSS2_DEBUG dropped from this case
      # too: qcacld's Kbuild never references it (it was inert copy-paste
      # from the wlan/platform option set).
      wlan/qcacld-3.0)      echo "WLAN_ROOT=$P/wlan/qcacld-3.0/ WLAN_COMMON_ROOT=cmn WLAN_COMMON_INC=$P/wlan/qcacld-3.0/cmn WLAN_FW_API=$P/wlan/fw-api/ MODNAME=wlan WLAN_WEAR_CHIPSET=qca_cld3 CONFIG_QCA_CLD_WLAN=m CONFIG_QCA_WIFI_ISOC=0 CONFIG_QCA_WIFI_2_0=1 WLAN_CTRL_NAME=wlan WLAN_PROFILE=wear PANIC_ON_BUG=n WLAN_WARN_ON_ASSERT=n CONFIG_CNSS_OUT_OF_TREE=y CONFIG_ICNSS2=m CONFIG_ICNSS2_QMI=y CONFIG_CNSS_GENL=m CONFIG_WCNSS_MEM_PRE_ALLOC=m CONFIG_CNSS_UTILS=m CONFIG_CONNECTIVITY_PKTLOG=y KERNEL_SUPPORTS_NESTED_COMPOSITES=n" ;;
      # google-modules/bms{,/misc} & msm-google/drivers/power/supply/qcom are
      # out-of-tree Kbuilds that gate their obj-* on CONFIG_GOOGLE_* /
      # CONFIG_QPNP_SMBLITE which are NOT in any Kconfig (they're invented for
      # these external trees). Pass them as make vars so obj-$(CONFIG_*)
      # selects the right composites. Order in EXT_MODULES is bms/misc -> bms
      # -> qcom -> usb_shim so each successor sees the predecessors'
      # Module.symvers.
      private/google-modules/bms/misc) echo "CONFIG_GOOGLE_VOTABLE=m CONFIG_GOOGLE_LOGBUFFER=m" ;;
      private/google-modules/bms)
        echo "CONFIG_GOOGLE_BMS=m CONFIG_GOOGLE_BATTERY=m CONFIG_GOOGLE_CHARGER=m CONFIG_GOOGLE_BMS_SW5100=m" ;;
      private/msm-google/drivers/power/supply/qcom)
        echo "CONFIG_QPNP_SMBLITE=m CONFIG_QTI_QBG=m" ;;
      # google-modules/soc/msm/wlan_mac has a Kbuild with a buggy relative -I
      # path ("../../../../private/msm-google-modules/wlan/platform/inc") --
      # one level too deep, resolves to ../private/
      # private/msm-google-modules/... which doesn't exist. The kernel-
      # platform build doesn't hit this because its source tree layout is
      # different. Inject the correct absolute include via EXTRA_CFLAGS (kbuild
      # appends it to ccflags-y) -- the existing broken -I path remains in
      # ccflags but is silently ignored.
      private/google-modules/soc/msm/wlan_mac)
        echo "EXTRA_CFLAGS=-I${S}/private/msm-google-modules/wlan/platform/inc" ;;
      # nanohub's Kbuild gates compilation on CONFIG_NANOHUB and
      # CONFIG_NANOHUB_{SPI,BL_NXP,DISPLAY} (not in any Kconfig -- invented
      # vars). Pass them so obj-* lines resolve. The matching
      # `-DCONFIG_NANOHUB*` source #ifdef gates are armed via the global
      # KMOD_MAKE KCFLAGS additions; cannot pass them here because modroot
      # output is shell-split and KCFLAGS with embedded spaces survive only as
      # KCFLAGS=<first-word>.
      private/google-modules/nanohub)
        echo "CONFIG_NANOHUB=m CONFIG_NANOHUB_SPI=y CONFIG_NANOHUB_BL_NXP=y CONFIG_NANOHUB_DISPLAY=y" ;;
      # nitrous: Google's driver for sol's BROADCOM BT part. Binds
      # .compatible = "goog,nitrous", which is exactly what sol's DT node
      # /soc/btbcm declares. Its own Makefile sets KBUILD_OPTIONS
      # CONFIG_NITROUS=m, which we must pass ourselves because we bypass that
      # wrapper and drive kbuild with M= directly.
      # It also needs bms: Kbuild adds -I$(KERNEL_SRC)/../google-modules/bms and
      # links logbuffer_register/log/unregister from bms/misc, so bms/misc MUST
      # stay ahead of it in EXT_MODULES (it does) for the $extra Module.symvers
      # accumulator to offer those symbols.
      private/google-modules/bluetooth/broadcom)
        echo "CONFIG_NITROUS=m" ;;
      # syna dhd4381: sol's WLAN driver, binds "android,syna_wlan" (DT node
      # /soc/wlan-gpios). Kbuild builds synadhd$(BCM_WLAN_CHIP_SUFFIX).o with
      # the suffix defaulting to 4381, and gates the obj- line on
      # DRIVER_TYPE ?= $(CONFIG_BCMDHD) -- so CONFIG_BCMDHD=m is what actually
      # turns the module on. Output is synadhd4381.ko, matching both stock and
      # the repo's own BUILD.bazel outs. BCMDHD_ROOT is set by the wrapper
      # Makefile we bypass, so pass it explicitly.
      private/google-modules/wlan/syna/dhd4381)
        echo "CONFIG_BCMDHD=m BCMDHD_ROOT=${S}/private/google-modules/wlan/syna/dhd4381" ;;
      # petc_input_filter (rotary-encoders/petc_input_filter): the wrapper
      # Makefile sets EXTRA_INCLUDE=-I$(KERNEL_SRC)/../google-modules/nanohub
      # and KBUILD_EXTRA_SYMBOLS to nanohub's Module.symvers. We bypass the
      # wrapper (using kernel's M= build directly) so we pass the include path
      # via EXTRA_CFLAGS (same trick as wlan_mac). Module.symvers chaining
      # happens via our do_compile loop's $extra accumulator (which includes
      # nanohub's Module.symvers since nanohub is earlier in EXT_MODULES).
      private/google-modules/rotary-encoders/petc_input_filter)
        echo "CONFIG_INPUT_PETC_INPUT_FILTER=m EXTRA_CFLAGS=-I${S}/private/google-modules/nanohub" ;;
      # mcu_mic_codec uses nanohub.h headers via $(KERNEL_SRC)/../google-modules/nanohub.
      private/google-modules/sound/mcu_mic_codec)
        echo "CONFIG_SND_SOC_MCU_MIC_CODEC=m EXTRA_CFLAGS=-I${S}/private/google-modules/nanohub" ;;
      # cs40l26 -- sol's HAPTIC driver (Cirrus CS40L26A on i2c 0x43). Confirmed
      # from sol's own DTS: compatible "cirrus,cs40l26a" with LRA parameters
      # (cirrus,f0-default, cirrus,redc-default, cirrus,vibe-state, svc-le2/le3),
      # i.e. an LRA haptic actuator, NOT the speaker amp. Note there is no
      # wsa883x node anywhere in sol's DTS (base, shipped or merged) -- the
      # codec is besbev.
      #
      # CORRECTED: an earlier version of this comment claimed "the module's
      # Makefile auto-adds the -DCONFIG_INPUT_CS40L26_ATTR_UNDER_BUS +
      # -DCONFIG_GOOG_CUST defines via its own EXTRA_CFLAGS += lines". THERE IS
      # NO MAKEFILE -- upstream ships only BUILD.bazel, so nothing was adding
      # them. They are set explicitly in our cs40l26-Kbuild instead.
      private/google-modules/amplifiers/cs40l26)
        echo "CONFIG_INPUT_CS40L26_I2C=m CONFIG_CIRRUS_FIRMWARE_CL_DSP=m CONFIG_SND_SOC_CS40L26=m" ;;
      *) echo "" ;;
    esac
}

do_compile() {
    # The kernel's `make scripts` prep rebuilds host tools (sign-file etc.); sign-file
    # needs openssl headers/libs, which live in openssl-native's sysroot, not the host
    # default path. Expose them to HOSTCC via C_INCLUDE_PATH/LIBRARY_PATH (compiler-level,
    # so it neither guesses Kbuild per-target var names nor clobbers the kernel's own -I
    # flags — a bad global HOST_EXTRACFLAGS override broke dtc's libfdt include earlier).
    export C_INCLUDE_PATH="${STAGING_INCDIR_NATIVE}${C_INCLUDE_PATH:+:$C_INCLUDE_PATH}"
    export LIBRARY_PATH="${STAGING_LIBDIR_NATIVE}${LIBRARY_PATH:+:$LIBRARY_PATH}"

    # qcacld (wifi) is enormous; its wlan.mod rule expands thousands of object
    # paths into one argv -> "Argument list too long". Raise the stack limit
    # (ARG_MAX scales with it) — the standard qcacld out-of-tree build fix.
    ulimit -s unlimited 2>/dev/null || ulimit -s 131072 2>/dev/null || true

    # meta-oe linux.inc shares an in-tree-built kernel-source but doesn't
    # populate STAGING_KERNEL_BUILDDIR like kernel.bbclass; external module
    # builds then trip "scripts/genksyms/genksyms: not found" because the
    # kernel isn't prepared for M= builds. Prepare it once (writable
    # work-shared dir) so scripts/modpost/genksyms state is consistent.
    ${KMOD_MAKE} modules_prepare

    # Many Qualcomm Kbuilds use $(srctree)/../msm-google-modules/... and
    # $(srctree)/../google-modules/... relative includes — they assume the
    # kernel_platform layout where the module trees are SIBLINGS of the kernel
    # srctree. Recreate that with symlinks next to STAGING_KERNEL_DIR so those
    # relative paths resolve.
    ln -sfn ${S}/private/msm-google-modules ${KDIR}/../msm-google-modules
    ln -sfn ${S}/private/google-modules     ${KDIR}/../google-modules
    # Make the kernel source addressable from the modules tree as
    # `private/msm-google` (Google's manifest layout). Lets EXT_MODULES
    # reference kernel-tree subdirs like drivers/power/supply/qcom for
    # out-of-tree builds — qpnp-smblite-main.ko etc.
    ln -sfn ${KDIR} ${S}/private/msm-google

    # qcacld 'wear' profile disables DFS/spectral/etc. but qcacmn public
    # headers #include them unconditionally -> the Kbuild's feature-gated -I
    # dirs are absent -> cascading 'file not found' (queue.h in utils/sys,
    # wlan_dfs_ioctl.h in umac/dfs/.../inc, ...). Fix: add EVERY header dir
    # under the wlan trees to -I. This is huge but cc-o-c-respfile.patch routes
    # $(c_flags) through an @response-file so it no longer overflows the cc
    # command. Computed at build time.
    WL=${S}/private/msm-google-modules/wlan
    WINC=$(for d in "$WL/qca-wifi-host-cmn" "$WL/qcacld-3.0" "$WL/fw-api" "$WL/platform/inc"; do \
            find "$d" -name '*.h' -printf '%h\n' 2>/dev/null; done | sort -u | sed 's/^/-I/' | tr '\n' ' ')

    # mcu-offload ships no Kbuild/Makefile (bazel-only, see the file's header),
    # so give it one before the M= loop reaches it.
    MCUD=${S}/private/google-modules/display/watch/mcu-offload/mcu_display
    if [ -d "$MCUD" ]; then
        install -m 0644 ${UNPACKDIR}/mcu_display-Kbuild "$MCUD/Kbuild"
    else
        bbfatal "mcu_display source missing at $MCUD (SRC_URI/destsuffix wrong?)"
    fi

    # cs40l26 is bazel-only too (BUILD.bazel + Kconfig + defconfig, no Kbuild and
    # no Makefile), so it needs the same treatment as mcu-offload above.
    # Only supply a Kbuild if the tree does not ship its own build files. The
    # branch aurora uses carries a Makefile; other branches of this repo are
    # bazel-only and need one written for them.
    CSD=${S}/private/google-modules/amplifiers/cs40l26
    if [ ! -d "$CSD" ]; then
        bbfatal "cs40l26 source missing at $CSD (SRC_URI/destsuffix wrong?)"
    elif [ -f "$CSD/Makefile" ] || [ -f "$CSD/Kbuild" ]; then
        bbnote "cs40l26 ships its own build files; using them"
    else
        install -m 0644 ${UNPACKDIR}/cs40l26-Kbuild "$CSD/Kbuild"
    fi

    extra=""
    for m in ${EXT_MODULES}; do
        rel="${m#private/msm-google-modules/}"
        bbnote "Building vendor module: $rel"
        if [ "$m" = "private/msm-google-modules/securemsm" ]; then
            # securemsm provides smcinvoke_dlkm + qseecom_dlkm, i.e. the TEE.
            # Without them there is no /dev/smcinvoke or /dev/qseecom at all, so
            # android.hardware.security.keymint-service-qti can never reach the
            # TrustZone keymaster: it just sleeps in a retry loop and never
            # registers IKeyMintDevice. keystore2 then dies with
            #     globals.rs:339: Cannot connect to Keymint
            #     Failed to create service
            #       android.system.keystore2.IKeystoreService/default
            # and its restart storm floods init with "Too many pending control
            # messages", which stalls the container long before the display
            # composer starts. qseecom_dlkm is in sol's own 16-module first-boot
            # subset, so this was never really optional.
            #
            # The build fix is the one this recipe already predicted:
            # smcinvoke/compat/trace_smcinvoke.h hardcodes
            #   SMCINVOKE_TRACE_INCLUDE_PATH ../../../../../vendor/qcom/opensource/...
            # which is the AOSP tree layout, not private/msm-google-modules/.
            # It is #ifndef-guarded, so override it to "." and add a matching -I:
            # the kernel's define_trace.h resolves TRACE_INCLUDE_PATH as an
            # angle-bracket include, so <./trace_smcinvoke.h> is found via -I.
            #
            # Passed here rather than through modroot() because modroot output is
            # shell-split, so a multi-word EXTRA_CFLAGS would survive only as its
            # first word.
            ${KMOD_MAKE} M=${S}/$m $(modroot "$rel") \
                KBUILD_EXTRA_SYMBOLS="$extra" \
                EXTRA_CFLAGS="-DSMCINVOKE_TRACE_INCLUDE_PATH=. -I${S}/private/msm-google-modules/securemsm/smcinvoke/compat -I${S}/private/msm-google-modules/securemsm/include" modules
        elif [ "$m" = "private/msm-google-modules/wlan/qcacld-3.0" ]; then
            ${KMOD_MAKE} M=${S}/$m $(modroot "$rel") \
                KBUILD_EXTRA_SYMBOLS="$extra" \
                KCFLAGS="-Wno-error -Wno-implicit-function-declaration -Wno-error=implicit-int -Wno-error=int-conversion -Wno-error=incompatible-function-pointer-types -Wno-error=incompatible-pointer-types -Wno-error=implicit-function-declaration -Wno-error=strict-prototypes -DCFG80211_SINGLE_NETDEV_MULTI_LINK_SUPPORT $WINC" modules
        else
            ${KMOD_MAKE} M=${S}/$m $(modroot "$rel") \
                KBUILD_EXTRA_SYMBOLS="$extra" modules
        fi
        sym="${S}/$m/Module.symvers"
        [ -f "$sym" ] && extra="$extra $sym"
    done
}

KREL ?= "${SOL_KERNEL_VERSION}"
# Collect every built techpack .ko flat under the kernel-release dir. Use
# ${nonarch_base_libdir} so it lands in /usr/lib under the usrmerge distro
# feature.
do_install() {
    install -d ${D}${nonarch_base_libdir}/modules/${KREL}/vendor
    # The bulk of EXT_MODULES (out-of-tree under ${S}/private/...) emit .ko's
    # next to their sources — find ${S} catches them.
    find ${S} -name '*.ko' -exec sh -c \
      'cp -n "$1" ${D}${nonarch_base_libdir}/modules/${KREL}/vendor/' _ {} \;
    # The kernel-tree EXT_MODULES (drivers/power/supply/qcom --
    # qpnp-smblite-main.ko, qti-qbg-main.ko) build their .ko's in
    # ${KDIR}/drivers/... reachable via the ${S}/private/msm-google
    # symlink, but `find ${S}` doesn't traverse symlinks (and `find -L` would
    # also drag in every linux-sol-built kernel module — name conflict with
    # the kernel package). Collect those kernel-tree EXT modules by explicit
    # subdir to stay scoped.
    if [ -d ${KDIR}/drivers/power/supply/qcom ]; then
      find ${KDIR}/drivers/power/supply/qcom -maxdepth 1 -name '*.ko' \
        -exec cp -n {} ${D}${nonarch_base_libdir}/modules/${KREL}/vendor/ \;
    fi
}

FILES:${PN} = "${nonarch_base_libdir}/modules"
# aarch64 .ko on an armv7 machine recipe; these are intentionally arm64. No
# debug-split (kills the .debug arch QA + spurious -dbg package).
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
INHIBIT_PACKAGE_STRIP = "1"
INSANE_SKIP:${PN} += "arch buildpaths"

# Same icecream defect as linux-sol: icecream's client-side argument parser sees
# -Wp,-MD,<path>, sets seen_md, but never parses the path out, so seen_mf stays
# false and arg.cpp:837 synthesises its own -MF from the object name (empty.d
# instead of .empty.o.d). It is clang-specific: under gcc the argument is tagged
# local and local preprocessing honours the real path, but under clang icecream
# uses -frewrite-includes and compiles fully remote, so only the synthesised -MF
# lands. These modules build via `make -C $KDIR M=...`, i.e. the same
# scripts/Makefile.build + fixdep path, so disable up front rather than
# discovering it part-way through a very long build.
# (Diagnosed by bisecting an icecream-enabled build: the remote compile emits
#  only the synthesised -MF dependency file, so fixdep sees no real header
#  deps and the module rebuild goes stale.)
ICECC_DISABLED = "1"
