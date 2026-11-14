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
# OE appends "+<every SRCREV>" to PKGV for multi-SRCREV git recipes, which
# pushed the .ipk filename past NAME_MAX. Pin PKGV; SRCREV_<name> still pins
# every repo and task hashes still track it.
require linux-sol-version.inc
PV = "${SOL_KERNEL_VERSION}"
PKGV = "${SOL_KERNEL_VERSION}"

# Module repos at the private/ paths build.config.sw5100 and the
# kernel-platform manifest expect.
AGM = "git://android.googlesource.com/kernel"
S = "${UNPACKDIR}/src"
SRC_URI = "\
  ${AGM}/msm-extra;protocol=https;branch=${KBR};name=audio;destsuffix=src/private/msm-google-modules/audio \
  ${AGM}/msm-modules/bt;protocol=https;branch=${KBR};name=bt;destsuffix=src/private/msm-google-modules/bt \
  ${AGM}/msm-extra/dataipa;protocol=https;branch=${KBR};name=dataipa;destsuffix=src/private/msm-google-modules/dataipa \
  ${AGM}/msm-modules/datarmnet;protocol=https;branch=${KBR};name=datarmnet;destsuffix=src/private/msm-google-modules/datarmnet \
  ${AGM}/msm-modules/datarmnet-ext;protocol=https;branch=${KBR};name=datarmnetext;destsuffix=src/private/msm-google-modules/datarmnet-ext \
  ${AGM}/msm-extra/display-drivers;protocol=https;branch=${KBR};name=display;destsuffix=src/private/msm-google-modules/display \
  ${AGM}/msm-modules/graphics;protocol=https;branch=${KBR};name=graphics;destsuffix=src/private/msm-google-modules/graphics \
  ${AGM}/msm-modules/mm;protocol=https;branch=${KBR};name=mm;destsuffix=src/private/msm-google-modules/mm \
  ${AGM}/msm-modules/mmrm;protocol=https;branch=${KBR};name=mmrm;destsuffix=src/private/msm-google-modules/mmrm \
  ${AGM}/msm-modules/securemsm;protocol=https;branch=${KBR};name=securemsm;destsuffix=src/private/msm-google-modules/securemsm \
  ${AGM}/msm-extra/video-driver;protocol=https;branch=${KBR};name=video;destsuffix=src/private/msm-google-modules/video \
  ${AGM}/msm-modules/wlan-platform;protocol=https;branch=${KBR};name=wlanplat;destsuffix=src/private/msm-google-modules/wlan/platform \
  ${AGM}/msm-modules/qcacld;protocol=https;branch=${KBR};name=qcacld;destsuffix=src/private/msm-google-modules/wlan/qcacld-3.0 \
  ${AGM}/msm-modules/qca-wfi-host-cmn;protocol=https;branch=${KBR};name=qcacmn;destsuffix=src/private/msm-google-modules/wlan/qca-wifi-host-cmn \
  ${AGM}/msm-modules/wlan-fw-api;protocol=https;branch=${KBR};name=wlanfwapi;destsuffix=src/private/msm-google-modules/wlan/fw-api \
  ${AGM}/google-modules/soc/msm;protocol=https;branch=android-msm-seluna-5.15-android14-wear;name=socmsm;destsuffix=src/private/google-modules/soc/msm \
  ${AGM}/google-modules/bms;protocol=https;branch=${KBR};name=bms;destsuffix=src/private/google-modules/bms \
  ${AGM}/google-modules/touch/novatek_touch;protocol=https;branch=${KBR};name=nvttouch;destsuffix=src/private/google-modules/touch/novatek \
  ${AGM}/google-modules/nanohub;protocol=https;branch=android-msm-seluna-5.15-android14-wear;name=nanohub;destsuffix=src/private/google-modules/nanohub \
  ${AGM}/google-modules/rotary-encoders;protocol=https;branch=android-msm-seluna-5.15-android14-wear;name=rotary;destsuffix=src/private/google-modules/rotary-encoders \
  ${AGM}/google-modules/sound/mcu_mic_codec;protocol=https;branch=android-msm-seluna-5.15-android14-wear;name=mcumic;destsuffix=src/private/google-modules/sound/mcu_mic_codec \
  ${AGM}/google-modules/amplifiers;protocol=https;branch=android-msm-eos-5.15-tm-wear-kr3-pixel-watch;name=amplifiers;destsuffix=src/private/google-modules/amplifiers \
  ${AGM}/google-modules/display/watch/mcu-offload;protocol=https;branch=${KBR};name=mcudisp;destsuffix=src/private/google-modules/display/watch/mcu-offload \
  ${AGM}/google-modules/bluetooth/broadcom;protocol=https;branch=${KBR};name=btbrcm;destsuffix=src/private/google-modules/bluetooth/broadcom \
  ${AGM}/google-modules/wlan/syna/dhd4381;protocol=https;branch=${KBR};name=synadhd;destsuffix=src/private/google-modules/wlan/syna/dhd4381 \
  file://mcu_display-Kbuild \
  file://0004-amplifiers-cs40l26-set-loaded-before-mfd-add-devices.patch \
  file://0005-amplifiers-cl_dsp-return-ENOENT-when-coeff-control-i.patch \
  file://0006-amplifiers-cs40l26-pin-codec-MFD-child-platform-id.patch \
  file://0007-amplifiers-cs40l26-drive-reset-by-physical-level.patch \
  file://0001-audio-monaco-bind-haptics-codec-by-deterministic-MFD.patch \
  file://0008-amplifiers-cs40l26-codec-report-state-to-monaco-asoc.patch \
  file://0010-display-sde-connector-show-the-always-on-face-on-sol.patch \
  file://0011-touch-nt383x0-report-tap-to-wake-as-a-power-key-on-sol.patch \
  file://cs40l26-Kbuild \
  file://sol_vidc_stub.c \
  file://sol-vidc-stub-Kbuild \
"
KBR = "android-msm-seluna-5.15-android14-wear"
# Connectivity drivers are pinned rather than AUTOREV: a moving revision on
# a driver that is slow to test is a bad trade. Found via Google's kernel
# manifest, branch android-msm-seluna-5.15-android14-qpr3 (no "-wear").
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
# socmsm comes from the pixel-watch branch (sol variant): its EXT_MODULES
# include usb_shim (google,extcon-usb-shim), which the dr-eos branch lacks.
SRCREV_socmsm = "${AUTOREV}"
SRCREV_bms = "${AUTOREV}"
# nanohub (sensor-hub MCU driver), pixel-watch branch like socmsm. Its
# CONFIG_NANOHUB_* gates are in no Kconfig; see modroot and KMOD_MAKE.
SRCREV_nanohub = "${AUTOREV}"
# rotary-encoders: petc_input_filter (nanohub input-channel consumer) and
# ots_pat9126. Not in EXT_MODULES today.
SRCREV_rotary = "${AUTOREV}"
# mcu_mic_codec: the ASoC codec on nanohub's audio channel.
SRCREV_mcumic = "${AUTOREV}"
# Pinned to aurora's revision: sol's seluna branch is bazel-only and its
# cs40l26 does not bind here. Same CS40L26A (chip ID 0x40A260).
SRCREV_amplifiers = "06552df7596558c5b9b0fe1ad39fefc4ae116ef7"
SRCREV_mcudisp = "${AUTOREV}"
SRCREV_FORMAT = "audio_bt_dataipa_datarmnet_datarmnetext_display_graphics_mm_mmrm_securemsm_video_wlanplat_qcacld_qcacmn_wlanfwapi_socmsm_bms_nvttouch_nanohub_rotary_mcumic_amplifiers_mcudisp_btbrcm_synadhd"


# Build against the exact linux-sol kernel (same clang and config, so vermagic,
# CRCs and ABI match) plus the host tools modules_prepare needs.
DEPENDS += "virtual/kernel clang-native lld-native"
DEPENDS += "bc-native bison-native flex-native openssl-native kmod-native rsync-native coreutils-native"
do_configure[depends] += "virtual/kernel:do_shared_workdir"

LLVM_BIN = "${STAGING_BINDIR_NATIVE}"
PATH:prepend = "${STAGING_BINDIR_NATIVE}:"
# linux-sol builds out of tree: source in STAGING_KERNEL_DIR, .config,
# Module.symvers and genksyms in STAGING_KERNEL_BUILDDIR.
KDIR = "${STAGING_KERNEL_DIR}"
KOUT = "${STAGING_KERNEL_BUILDDIR}"

# EXT_MODULES build order from build.config.sw5100 (M= dirs relative to S).
#
# Order matters: do_compile's $extra accumulator offers a module only the
# Module.symvers of the modules before it. The display chain is
# nanohub <- mcu_display <- msm_drm (mcu_display calls into nanohub;
# dsi_display.c calls mcu_display_register_panel_power_notifier()).
#
# Not built, because sol does not need them to boot or lacks the hardware:
#   video, bt, mm/{sync_fence,hw_fence,msm_ext_display}, dataipa, datarmnet,
#   datarmnet-ext, wlan/{platform,qcacld-3.0}, soc/msm/wlan_mac,
#   rotary-encoders.
# mmrm also does not build on this branch (mmrm/Kbuild has "obj-m += test/"
# with no test/ sources). The repos stay in SRC_URI to keep SRCREV_FORMAT
# stable.
#
# WLAN and BT are Synaptics/Broadcom on sol, not Qualcomm as on aurora: the DT
# has /soc/wlan-gpios "android,syna_wlan" and /soc/btbcm "goog,nitrous", and
# stock loads synadhd4381.ko with BCM4381A1.hcd / fw_bcmdhd.bin. rfkill and
# btbcm are built in (CONFIG_RFKILL=y, CONFIG_BT_BCM=y in sw5100.fragment).
# Firmware comes from sol-connectivity-firmware; the stock modules themselves
# cannot be reused (CRC mismatches, CFI symbols this kernel does not export).
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
# qcacld-3.0 (not built today) needs, for an out-of-tree M= build:
#  - linux-sol's cmd-mod-file-func.patch and cc-o-c-respfile.patch, since its
#    object list and compile flags exceed MAX_ARG_STRLEN;
#  - the full KBUILD_OPTIONS and a broad qcacmn -I set (see modroot);
#  - WLAN_COMMON_ROOT as the relative `cmn` symlink;
#  - -DCFG80211_SINGLE_NETDEV_MULTI_LINK_SUPPORT, since the kernel backported
#    the 4-arg cfg80211_ch_switch_notify and qcacld cannot detect it.

KMOD_MAKE = "make -C ${KDIR} O=${KOUT} ARCH=arm64 LLVM=1 LLVM_IAS=1 \
  CROSS_COMPILE=aarch64-linux-gnu- \
  CC='${LLVM_BIN}/clang --target=aarch64-linux-gnu -fuse-ld=lld' \
  LD='${LLVM_BIN}/ld.lld' AR='${LLVM_BIN}/llvm-ar' \
  NM='${LLVM_BIN}/llvm-nm' OBJCOPY='${LLVM_BIN}/llvm-objcopy' \
  KERNEL_SRC=${KDIR} OUT_DIR=${KDIR} \
  KCFLAGS='-Wno-error -Wno-error=implicit-int -Wno-error=int-conversion -Wno-error=incompatible-function-pointer-types -Wno-error=incompatible-pointer-types -Wno-error=implicit-function-declaration -Wno-error=strict-prototypes -I${KDIR}/drivers/clk/qcom -I${KDIR}/drivers/devfreq -I${KDIR}/include/linux -I${KDIR}/drivers/iommu -I${S}/private/msm-google-modules/wlan/qca-wifi-host-cmn/utils/sys -I${S}/private/google-modules/soc/msm/include/dtc -I${S}/private/google-modules/nanohub -DCONFIG_NANOHUB -DCONFIG_NANOHUB_SPI -DCONFIG_NANOHUB_BL_NXP -DCONFIG_NANOHUB_DISPLAY' \
  KBUILD_MODPOST_WARN=1 CONFIG_ARCH_MONACO=y WLAN_PROFILE=wear \
  CONFIG_CNSS_QCA6750=m CONFIG_QCA_CLD_WLAN=m CONFIG_TOUCHSCREEN_NT383x0=m"
# KERNEL_SRC / OUT_DIR: the bms and power/supply/qcom wrapper Makefiles include
# $(KERNEL_SRC)/../google-modules/soc/msm/Makefile.include and chain
# $(OUT_DIR)/../google-modules/bms/misc/Module.symvers. Both default to the host
# kernel; ${KDIR}'s parent holds the module-tree symlinks made in do_compile.

# The machine is armv7, so default binutils choke on the aarch64 .ko; use
# llvm tools and do not strip.
OBJCOPY:class-target = "${LLVM_BIN}/llvm-objcopy"
STRIP:class-target = "${LLVM_BIN}/llvm-strip"
INHIBIT_SYSROOT_STRIP = "1"

do_configure[noexec] = "1"

# Each Qualcomm Kbuild expects a <NAME>_ROOT var pointing at its repo root.
# They concatenate without a separator (`-I$(SYNC_FENCE_ROOT)sync_fence/...`),
# so every *_ROOT value must end with a slash.
modroot() {
    P="${S}/private/msm-google-modules"
    case "$1" in
      mm/sync_fence)        echo "SYNC_FENCE_ROOT=$P/mm/" ;;
      mm/hw_fence)          echo "MSM_HW_FENCE_ROOT=$P/mm/" ;;
      mm/msm_ext_display)   echo "MSM_EXT_DISPLAY_ROOT=$P/mm/" ;;
      mmrm)                 echo "MMRM_ROOT=$P/mmrm/" ;;
      securemsm)            echo "SSG_MODULE_ROOT=$P/securemsm/" ;;
      # Audio needs MODNAME non-empty (external-build path) and
      # CONFIG_ARCH_MONACO=y; together they include config/sw5100auto.conf and
      # sw5100autoconf.h. Without them no audio .ko builds, including
      # adsp_loader_dlkm, which provides /sys/kernel/boot_adsp/boot. The modem
      # also needs the ADSP up (otherwise its watchdog reports "DOG detects
      # stalled initialization").
      audio)                echo "AUDIO_ROOT=$P/audio/ MODNAME=audio CONFIG_ARCH_MONACO=y" ;;
      # Display needs both gates, and neither is in any Kconfig we merge:
      # CONFIG_DRM_MSM for the top-level `obj-$(CONFIG_DRM_MSM) += msm/`, and
      # CONFIG_ARCH_MONACO for msm/Kbuild's branch that includes
      # config/gki_monacodisp.conf and gki_monacodispconf.h. Without them no
      # .ko is built and the composer aborts in CreatePrimaryDisplay.
      #
      # Make variables, not a kernel fragment: CONFIG_DRM_MSM is a real
      # in-tree tristate, and in .config it would also build upstream msm.ko,
      # which binds the same qcom,sde-kms nodes.
      #
      # EXTRA_CFLAGS: mcu_display_exports.h is in the repo's include/ subdir,
      # not where msm/Kbuild's -I points.
      display)              echo "DISPLAY_ROOT=$P/display/ CONFIG_ARCH_MONACO=y CONFIG_DRM_MSM=y EXTRA_CFLAGS=-I${S}/private/google-modules/display/watch/mcu-offload/mcu_display/include" ;;
      # mcu_display: nanohub headers; Module.symvers chains via EXT_MODULES order.
      private/google-modules/display/watch/mcu-offload/mcu_display)
        echo "EXTRA_CFLAGS=-I${S}/private/google-modules/nanohub" ;;
      graphics)             echo "KGSL_MODULE_ROOT=$P/graphics/" ;;
      video)                echo "VIDEO_ROOT=$P/video/" ;;
      # bt: bt/Kbuild descends into slimbus/ and pwr/ only with these set.
      # bt_fm_slim.ko provides the "btfmslim_slave" device that
      # monaco-asoc-snd's WCN dai_links reference.
      bt)                   echo "BT_ROOT=$P/bt/ CONFIG_BTFM_SLIM=m CONFIG_MSM_BT_POWER=m" ;;
      dataipa/*)            echo "IPA_ROOT=$P/dataipa/" ;;
      datarmnet/*)          echo "RMNET_CORE_ROOT=$P/datarmnet/" ;;
      datarmnet-ext/*)      echo "RMNET_EXT_ROOT=$P/datarmnet-ext/ RMNET_CORE_INC_DIR=$P/datarmnet/core RMNET_CORE_ROOT=$P/datarmnet/" ;;
      # wlan/platform (CNSS): the broker qcacld calls into. The wrapper sets
      # the CONFIG_*=m set only when WLAN_PLATFORM_ROOT is empty, and it must
      # be passed (subdir Kbuilds use it for -I), so pass them here. No
      # CONFIG_CNSS2 (PCIe variant). CONFIG_CNSS_OUT_OF_TREE=y points -I at
      # $(WLAN_PLATFORM_ROOT)/inc. CONFIG_ICNSS2_DEBUG stays unset: it turns
      # ICNSS_ASSERT() into BUG() on recoverable conditions.
      wlan/platform)        echo "WLAN_PLATFORM_ROOT=$P/wlan/platform/ CONFIG_CNSS_OUT_OF_TREE=y CONFIG_ICNSS2=m CONFIG_ICNSS2_QMI=y CONFIG_CNSS_UTILS=m CONFIG_CNSS_GENL=m CONFIG_WCNSS_MEM_PRE_ALLOC=m CONFIG_CNSS_QMI_SVC=m CONFIG_CNSS_PLAT_IPC_QMI_SVC=m" ;;
      # qcacld's Makefile sets its KBUILD_OPTIONS only when it computes
      # WLAN_ROOT itself; the M= build bypasses it, so pass the full set (the
      # Kbuild gates its -I dirs on them).
      #   WLAN_COMMON_ROOT=cmn must be relative: object paths are
      #     $(WLAN_ROOT)/$(WLAN_COMMON_ROOT)/..., absolute doubles the path.
      #   MODNAME=wlan: any other name sets MULTI_IF_NAME and adds a subdir to
      #     the WCNSS_qcom_cfg.ini / MAC file lookup path. Output is wlan.ko.
      #   PANIC_ON_BUG=n WLAN_WARN_ON_ASSERT=n: wear_defconfig enables both when
      #     CONFIG_SLUB_DEBUG=y, which turns every QDF_BUG() into BUG() and a
      #     recoverable error into a reboot loop. Command-line vars override
      #     the defconfig's `:=`.
      wlan/qcacld-3.0)      echo "WLAN_ROOT=$P/wlan/qcacld-3.0/ WLAN_COMMON_ROOT=cmn WLAN_COMMON_INC=$P/wlan/qcacld-3.0/cmn WLAN_FW_API=$P/wlan/fw-api/ MODNAME=wlan WLAN_WEAR_CHIPSET=qca_cld3 CONFIG_QCA_CLD_WLAN=m CONFIG_QCA_WIFI_ISOC=0 CONFIG_QCA_WIFI_2_0=1 WLAN_CTRL_NAME=wlan WLAN_PROFILE=wear PANIC_ON_BUG=n WLAN_WARN_ON_ASSERT=n CONFIG_CNSS_OUT_OF_TREE=y CONFIG_ICNSS2=m CONFIG_ICNSS2_QMI=y CONFIG_CNSS_GENL=m CONFIG_WCNSS_MEM_PRE_ALLOC=m CONFIG_CNSS_UTILS=m CONFIG_CONNECTIVITY_PKTLOG=y KERNEL_SUPPORTS_NESTED_COMPOSITES=n" ;;
      # bms{,/misc} and drivers/power/supply/qcom gate obj-* on CONFIG_GOOGLE_*
      # and CONFIG_QPNP_SMBLITE, which are in no Kconfig. EXT_MODULES order
      # bms/misc -> bms -> qcom -> usb_shim chains their Module.symvers.
      private/google-modules/bms/misc) echo "CONFIG_GOOGLE_VOTABLE=m CONFIG_GOOGLE_LOGBUFFER=m" ;;
      private/google-modules/bms)
        echo "CONFIG_GOOGLE_BMS=m CONFIG_GOOGLE_BATTERY=m CONFIG_GOOGLE_CHARGER=m CONFIG_GOOGLE_BMS_SW5100=m" ;;
      private/msm-google/drivers/power/supply/qcom)
        echo "CONFIG_QPNP_SMBLITE=m CONFIG_QTI_QBG=m" ;;
      # wlan_mac: its Kbuild's relative -I to wlan/platform/inc is one level
      # too deep for this layout; add the right absolute path.
      private/google-modules/soc/msm/wlan_mac)
        echo "EXTRA_CFLAGS=-I${S}/private/msm-google-modules/wlan/platform/inc" ;;
      # nanohub: invented CONFIG_NANOHUB* vars for the obj- lines. The matching
      # -D defines go in KMOD_MAKE's KCFLAGS, since modroot output is
      # shell-split and a multi-word KCFLAGS would be cut.
      private/google-modules/nanohub)
        echo "CONFIG_NANOHUB=m CONFIG_NANOHUB_SPI=y CONFIG_NANOHUB_BL_NXP=y CONFIG_NANOHUB_DISPLAY=y" ;;
      # nitrous: sol's Broadcom BT driver ("goog,nitrous", /soc/btbcm).
      # CONFIG_NITROUS=m comes from the bypassed wrapper Makefile. It links
      # logbuffer_* from bms/misc, which must stay ahead of it in EXT_MODULES.
      private/google-modules/bluetooth/broadcom)
        echo "CONFIG_NITROUS=m" ;;
      # syna dhd4381: sol's WLAN driver ("android,syna_wlan"). CONFIG_BCMDHD=m
      # turns the obj- line on (DRIVER_TYPE ?= $(CONFIG_BCMDHD)); the output is
      # synadhd4381.ko, as on stock. BCMDHD_ROOT comes from the bypassed wrapper.
      private/google-modules/wlan/syna/dhd4381)
        echo "CONFIG_BCMDHD=m BCMDHD_ROOT=${S}/private/google-modules/wlan/syna/dhd4381" ;;
      # petc_input_filter: the bypassed wrapper Makefile would add the nanohub
      # include; Module.symvers comes from the $extra accumulator.
      private/google-modules/rotary-encoders/petc_input_filter)
        echo "CONFIG_INPUT_PETC_INPUT_FILTER=m EXTRA_CFLAGS=-I${S}/private/google-modules/nanohub" ;;
      # mcu_mic_codec: nanohub headers, as above.
      private/google-modules/sound/mcu_mic_codec)
        echo "CONFIG_SND_SOC_MCU_MIC_CODEC=m EXTRA_CFLAGS=-I${S}/private/google-modules/nanohub" ;;
      # cs40l26: sol's haptic LRA driver (Cirrus CS40L26A, i2c 0x43), not a
      # speaker amp. -DCONFIG_INPUT_CS40L26_ATTR_UNDER_BUS and -DCONFIG_GOOG_CUST
      # are set in cs40l26-Kbuild.
      private/google-modules/amplifiers/cs40l26)
        echo "CONFIG_INPUT_CS40L26_I2C=m CONFIG_CIRRUS_FIRMWARE_CL_DSP=m CONFIG_SND_SOC_CS40L26=m" ;;
      *) echo "" ;;
    esac
}

do_compile() {
    # Without the kernel's Module.symvers modpost resolves no CRC, and with
    # KBUILD_MODPOST_WARN=1 every module ships an empty __versions; the KMI gate
    # in sol-boot-images then fails with a misleading CRC. A sstate-restored
    # kernel can leave it absent.
    [ -s "${KOUT}/Module.symvers" ] || bbfatal "${KOUT}/Module.symvers is missing: re-run virtual/kernel:do_shared_workdir (bitbake -f -c compile linux-sol) before building the modules"

    # sign-file (rebuilt by modules_prepare) needs openssl-native's headers and
    # libs. Set them compiler-wide: overriding HOST_EXTRACFLAGS breaks dtc's
    # libfdt include.
    export C_INCLUDE_PATH="${STAGING_INCDIR_NATIVE}${C_INCLUDE_PATH:+:$C_INCLUDE_PATH}"
    export LIBRARY_PATH="${STAGING_LIBDIR_NATIVE}${LIBRARY_PATH:+:$LIBRARY_PATH}"

    # qcacld's wlan.mod rule exceeds ARG_MAX; ARG_MAX scales with the stack limit.
    ulimit -s unlimited 2>/dev/null || ulimit -s 131072 2>/dev/null || true

    # meta-oe linux.inc does not prepare the kernel for M= builds
    # ("scripts/genksyms/genksyms: not found"); prepare it once.
    ${KMOD_MAKE} modules_prepare

    # Many Qualcomm Kbuilds include $(srctree)/../{msm-,}google-modules/...,
    # assuming the module trees are siblings of the kernel srctree.
    ln -sfn ${S}/private/msm-google-modules ${KDIR}/../msm-google-modules
    ln -sfn ${S}/private/google-modules     ${KDIR}/../google-modules
    # Expose the kernel as private/msm-google (the manifest layout) so
    # EXT_MODULES can name kernel-tree dirs like drivers/power/supply/qcom.
    ln -sfn ${KDIR} ${S}/private/msm-google

    # qcacld 'wear' profile: qcacmn public headers include feature-gated
    # headers unconditionally, so add every header dir under the wlan trees to
    # -I (cc-o-c-respfile.patch keeps the command line within limits).
    WL=${S}/private/msm-google-modules/wlan
    WINC=$(for d in "$WL/qca-wifi-host-cmn" "$WL/qcacld-3.0" "$WL/fw-api" "$WL/platform/inc"; do \
            find "$d" -name '*.h' -printf '%h\n' 2>/dev/null; done | sort -u | sed 's/^/-I/' | tr '\n' ' ')

    # mcu-offload is bazel-only; give it a Kbuild before the M= loop.
    MCUD=${S}/private/google-modules/display/watch/mcu-offload/mcu_display
    if [ -d "$MCUD" ]; then
        install -m 0644 ${UNPACKDIR}/mcu_display-Kbuild "$MCUD/Kbuild"
    else
        bbfatal "mcu_display source missing at $MCUD (SRC_URI/destsuffix wrong?)"
    fi

    # cs40l26 is bazel-only on some branches. Supply a Kbuild only when the
    # tree ships no build files of its own (the pinned aurora revision has a
    # Makefile).
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
            # securemsm provides smcinvoke_dlkm + qseecom_dlkm (the TEE). Without
            # /dev/smcinvoke and /dev/qseecom the keymint HAL never registers,
            # keystore2 restart-storms ("Too many pending control messages") and
            # the container stalls before the composer starts.
            #
            # smcinvoke/compat/trace_smcinvoke.h hardcodes
            #   SMCINVOKE_TRACE_INCLUDE_PATH ../../../../../vendor/qcom/opensource/...
            # (the AOSP layout). It is #ifndef-guarded, so override it to "." and
            # add a matching -I; define_trace.h includes it with angle brackets.
            # Passed here, not via modroot(), because modroot output is
            # shell-split and a multi-word EXTRA_CFLAGS would be cut.
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

    # sol_vidc_stub: a do-nothing driver for 5a00000.qcom,vidc. msm_video is not
    # built, so that node is the one gcc-monaco consumer that never binds, gcc's
    # sync_state never runs, and every clock the bootloader left on (USB, eMMC,
    # two QUP engines, gpll0) stays on through suspend: 35 clocks at suspend
    # instead of 8. Drop it once msm_video is built.
    VS=${S}/sol-vidc-stub
    install -d $VS
    install -m 0644 ${UNPACKDIR}/sol_vidc_stub.c $VS/sol_vidc_stub.c
    install -m 0644 ${UNPACKDIR}/sol-vidc-stub-Kbuild $VS/Kbuild
    ${KMOD_MAKE} M=$VS modules
}

KREL ?= "${SOL_KERNEL_VERSION}"
# Collect every built .ko flat under the kernel-release dir; nonarch_base_libdir
# lands in /usr/lib under usrmerge.
do_install() {
    install -d ${D}${nonarch_base_libdir}/modules/${KREL}/vendor
    # Out-of-tree modules emit their .ko next to the sources.
    find ${S} -name '*.ko' -exec sh -c \
      'cp -n "$1" ${D}${nonarch_base_libdir}/modules/${KREL}/vendor/' _ {} \;
    # The kernel-tree modules (drivers/power/supply/qcom) build under ${KDIR},
    # reached through the private/msm-google symlink, which find does not
    # follow. `find -L` would also collect linux-sol's own modules, so take
    # that one directory explicitly.
    if [ -d ${KDIR}/drivers/power/supply/qcom ]; then
      find ${KDIR}/drivers/power/supply/qcom -maxdepth 1 -name '*.ko' \
        -exec cp -n {} ${D}${nonarch_base_libdir}/modules/${KREL}/vendor/ \;
    fi
}

FILES:${PN} = "${nonarch_base_libdir}/modules"
# arm64 .ko files in an armv7 machine recipe, on purpose. No debug-split.
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
INHIBIT_PACKAGE_STRIP = "1"
INSANE_SKIP:${PN} += "arch buildpaths"

# Same icecream defect as linux-sol: with clang, icecream compiles remotely and
# synthesises its own -MF instead of honouring -Wp,-MD,<path>, so fixdep sees no
# header deps and module rebuilds go stale.
ICECC_DISABLED = "1"
