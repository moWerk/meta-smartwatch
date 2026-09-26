# sol's GNSS HAL is AIDL, so it needs the binder backend rather than the
# libhybris one: /vendor/etc/init/android.hardware.gnss-aidl-service-qti.rc
# declares `interface aidl android.hardware.gnss.IGnss/default`, and the service
# registers under exactly that name. The provider's binder backend asks for
# `android.hardware.gnss.IGnss/default` with no version gating, so sol's version
# 3 is reachable through it.
#
# Everything it needs on the host is already there: /dev/binder is a symlink to
# /dev/binderfs/binder, which the container shares, and libgbinder is installed
# and proven against this container by sensorfw's binder plugins.
RDEPENDS:${PN}:append:sol = " geoclue-provider-hybris-binder "
