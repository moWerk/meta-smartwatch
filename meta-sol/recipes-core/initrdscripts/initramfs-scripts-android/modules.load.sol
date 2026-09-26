# sol first-stage module load order.
#
# CAPTURED FROM STOCK sol (AW2A.240903.001.A4) — the exact sequence AOSP's
# libmodprobe emitted ('init: Loading module ...' in dmesg), which is
# dependency-resolved by construction (it honours modules.dep AND
# modules.softdep; note qcom_hwspinlock loads BEFORE smem).
#
# This MUST NOT be replaced by aurora's list: aurora is a different board with a
# different module set. Using aurora's list on sol left sdhci-msm without
# sdhci-msm-scaling/cqhci/qcom-scm (storage never enumerated) and dwc3-msm
# without its phy supplier (USB never probed). busybox modprobe does not
# resolve deps here, so this order is load-bearing.
qcom-cpufreq-hw.ko
sched-walt.ko
qcom_hwspinlock.ko
smem.ko
minidump.ko
qcom_ipc_logging.ko
msm_sysstats.ko
qcom-mpm.ko
qcom-scm.ko
pinctrl-msm.ko
pinctrl-monaco.ko
proxy-consumer.ko
debug-regulator.ko
gdsc-regulator.ko
clk-qcom.ko
clk-dummy.ko
rpm-smd.ko
clk-smd-rpm.ko
dispcc-monaco.ko
gcc-monaco.ko
gpucc-monaco.ko
qcom_aoss.ko
mdt_loader.ko
smp2p.ko
secure_buffer.ko
socinfo.ko
mem_buf_dev.ko
mem_buf.ko
dcc_v2.ko
panel_event_notifier.ko
# --- QCOM Apps Watchdog: DELIBERATELY NOT LOADED -------------------------------
# These two arm a hardware watchdog that nothing in AsteroidOS pets, so it
# resets the watch mid-boot. Root-caused 2026-08-09 from a logdump capture:
#
#   CONFIG_QCOM_WATCHDOG_BARK_TIME=11000   (11 s)
#   CONFIG_QCOM_WATCHDOG_PET_TIME=9360     (9.36 s)
#   [ 0.829282] msm_watchdog f017000.qcom,wdt: QCOM Apps Watchdog Initialized
#   [11.161883] sched: RT throttling activated      <- last line in the log, ever
#
# The kernel log stops dead at 11.16 s, i.e. exactly the bark time, with no panic
# and no oops -- the signature of a hardware reset rather than a software fault.
# That also matches the observed ~33-39 s reboot period (~22 s bootloader + 11 s
# Linux), and it explains why our idle initramfs survived 5.8 hours while a real
# userland boot never got past ~11 s: only the loaded userland generates enough
# work to delay the pet path past the deadline.
#
# Stock loads these (they are in stock's own modules.load.charger at lines 22-23,
# which is where our list inherited them) because Android pets /dev/watchdog.
# AsteroidOS does not, so on our side arming it is pure self-destruction.
#
# Not loading them is the correct bring-up choice. If we ever want the watchdog
# back, the right way is to have something pet it -- systemd can, via
# RuntimeWatchdogSec= in system.conf -- and NOT to re-add these blind.
# qcom_wdt_core.ko
# qcom_soc_wdt.ko
memory_dump_v2.ko
qcom_logbuf_vh.ko
qcom-pmu-lib.ko
qcom-dcvs.ko
hwkm_v1.ko
crypto-qti-hwkm.ko
crypto-qti-common.ko
qcom_cpu_vendor_hooks.ko
msm_performance.ko
rpm-smd-regulator.ko
stub-regulator.ko
qcom_iommu_util.ko
iommu-logger.ko
arm_smmu.ko
msm_dma_iommu_mapping.ko
qti-regmap-debugfs.ko
qseecom_proxy.ko
qcom-spmi-pmic.ko
qcom_dma_heaps.ko
spmi-pmic-arb.ko

# --- PMIC GPIO + charger chain: the supplier of the USB extcon -----------------
# These are shipped in our vendor_kernel_boot but were NOT in the list above,
# because the list above is stock's FIRST-STAGE set and stock loads these later,
# from second-stage init via modprobe out of /vendor (~10.2s on stock). AsteroidOS
# stays in the initramfs and never runs a second stage, so without this block they
# were simply never loaded on our boots.
#
# Why it matters for USB: google-extcon-shim's probe calls
# supplier_notification_setup() -> get_supplier_extcon(), which resolves the DT
# phandle `google,supplier-extcon`. On sol that phandle is 0x134 =
# qcom,qpnp-smblite (DT label pm5100_charger) -- confirmed by reading
# /proc/device-tree on stock. Until qpnp-smblite registers its extcon, the shim
# returns -EPROBE_DEFER *silently* and retries forever, so msm-dwc3 never binds
# 4e00000.hsusb, no dwc3 child is created, no UDC appears and adb never comes up.
# Loading them here, after spmi-pmic-arb and before dwc3-msm, means the supplier
# exists before USB probes rather than relying on a deferred re-probe.
#
# pinctrl-spmi-gpio is the PMIC GPIO provider; without it gpio-keys hits
# "deferred probe timeout, ignoring dependency" (11x on our boots, 0 on stock).
#
# Order is topological per modules.dep, NOT Google's modules.load.charger order:
# that file lists qcom-spmi-adc5-gen3 before qcom-vadc-common, which is fine for
# AOSP's libmodprobe (it resolves modules.dep) but would fail under the plain
# busybox modprobe loop in our init.
pinctrl-spmi-gpio.ko
qcom-vadc-common.ko
qcom-spmi-adc5-gen3.ko
gvotable.ko
logbuffer.ko
qpnp-smblite-main.ko
qti-qbg-main.ko
google-bms.ko
google-battery.ko
google-charger.ko

# sw5100_bms.ko is not listed here. It needs QBG's IIO channels to exist at
# probe time, so a udev rule loads it on QBG's own add event instead --
# see 71-sol-battery-gauge.rules.

# NOTE: the side button's driver (qpnp-power-on) is deliberately NOT here even
# though the vkb manifest builds it. Its .ko is also on the rootfs, and loading
# it from modules-load.d avoids needing a vkb rebuild and flash for a key that
# is only useful once mce is running anyway. See sol-post-rootfs.conf.

phy-msm-snps-hs.ko
phy-generic.ko
eud.ko
dwc3-msm.ko
rtc-pm8xxx.ko
qcom-dload-mode.ko
qcom-reboot-reason.ko
cpu_hotplug.ko
bcl_pmic5.ko
sdhci-msm-scaling.ko
cqhci.ko
sdhci-msm.ko
qcom-apcs-ipc-mailbox.ko
qcom_glink.ko
qcom_glink_smem.ko
qcom_smd.ko
rproc_qcom_common.ko
qcom_glink_rpm.ko
nvmem_qcom-spmi-sdam.ko
icc-rpm.ko
qnoc-qos-rpm.ko
qnoc-monaco.ko
coresight.ko
qrtr.ko
nanohub.ko
mcu_display.ko
msm_drm.ko
msm_kgsl.ko
qseecom_dlkm.ko
smcinvoke_dlkm.ko
