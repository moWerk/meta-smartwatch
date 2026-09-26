#!/bin/sh
# Second lxc.hook.mount: create /dev/{binder,hwbinder,vndbinder} inside the
# container. Without them servicemanager dies "cannot open /dev/binder" and
# Android init crash-loops it. lxc.hook.mount is cumulative, so this runs after
# the bundle's own mount.sh.
# Stash the real /apex before Android init can hide it.
#
# This image carries FLATTENED apexes: /apex holds 31 real directories and
# /system/apex is empty (the opposite of aurora's layout, where /apex is empty
# and the payloads sit in /system/apex -- do not assume either one).
#
# Android init mounts a tmpfs over /apex very early and expects apexd to
# populate it from payload images. There are none here, so /apex becomes and
# stays empty. init itself execs fine, because at container start the real
# /apex is still visible and /system/bin/linker resolves through it; every
# binary exec'd AFTER the tmpfs lands loses its interpreter and dies:
#     init: cannot execv('/vendor/bin/sscrpcd'): No such file or directory
#     init: Service 'vendor.sensors' (pid 2172) exited with status 127
# That one mount is the whole 127 cascade.
#
# We cannot stop init mounting it (it is in init's own code, not in any .rc we
# can edit), so instead we keep a second, independent path to the same
# directory. This hook runs in the container's mount namespace BEFORE init
# starts, so the bind here survives init's tmpfs landing on /apex afterwards.
# /postinstall is used as the stash because it is empty, unmounted, and unused
# by anything in this container. The start script rebinds it back over /apex
# once init's tmpfs is in place.
if [ -d "${LXC_ROOTFS_MOUNT}/apex" ] && [ -d "${LXC_ROOTFS_MOUNT}/postinstall" ]; then
    mount --bind "${LXC_ROOTFS_MOUNT}/apex" "${LXC_ROOTFS_MOUNT}/postinstall" 2>/dev/null \
        && echo "sol-lxc-android: stashed /apex -> /postinstall ($(ls "${LXC_ROOTFS_MOUNT}/postinstall" 2>/dev/null | wc -l) entries)"
fi

# SYMLINKS, never copies. A binderfs device node cannot be copied.
#
# This used to `cp -a` (falling back to mknod) the host's
# /dev/binderfs/{binder,hwbinder,vndbinder} into the container's /dev. The
# copies looked perfect -- right type, right major/minor, mode 0666, and even
# openable by a plain reader -- but every real binder client died:
#     ProcessState: Opening '/dev/binder' failed: No such device or address
#     Abort message: 'Binder driver '/dev/binder' could not be opened.'
# 56 aborts across servicemanager, vndservicemanager, wificond, surfaceflinger,
# the composer and most vendor HALs, all from this one cause.
#
# The reason: unlike the old misc /dev/binder, a binderfs device is identified
# by the binderfs inode itself, not by its major/minor. A copied node is a plain
# tmpfs node with the same numbers and no backing device, so binder_open() finds
# nothing and returns ENXIO. cp -a cannot carry that identity, and neither can
# mknod -- the device number is not the device.
#
# A symlink resolves to the real binderfs inode, so open() reaches the actual
# driver. Confirmed on hardware 2026-08-11: swapping the three copied nodes for
# symlinks took the container from 43 processes and 0 registered binder services
# to 105 processes and 10 registered services (IServiceManager, ISystemSuspend,
# IWificond, IApexService...), with all three servicemanagers alive.
#
# NOTE, next decision point: init mounts its OWN binderfs at /dev/binderfs, so
# the container's instance is separate from the host's. These symlinks therefore
# point at the CONTAINER's instance, which is what made it work. Binder contexts
# do not span binderfs instances, so before host-side libhybris can reach the
# container's composer, the two will have to be unified -- bind the host's
# /dev/binderfs in here and stop init remounting it. Deliberately not done in
# the same change as the fix above; test it as its own variable.
for n in binder hwbinder vndbinder; do
    if [ -e "/dev/binderfs/$n" ]; then
        rm -f "${LXC_ROOTFS_MOUNT}/dev/$n"
        ln -s "/dev/binderfs/$n" "${LXC_ROOTFS_MOUNT}/dev/$n" 2>/dev/null || true
        chmod 666 "/dev/binderfs/$n" 2>/dev/null || true
    fi
done

# Share the HOST's binderfs instance with the container.
#
# This is the other half of the note above. Android init mounts its own binderfs
# at /dev/binderfs, which creates a SECOND, independent instance: the host's
# binder/hwbinder/vndbinder came out as minors 1/2/3 while the container's were
# 5/6/... Binder contexts do not span binderfs instances, so with two of them
# the host's /dev/binder is a different driver context from the container's, and
# libhybris in the launcher can never see the composer the container registers.
# Sharing the IPC namespace (lxc.namespace.keep = net user ipc) is necessary but
# NOT sufficient for that reason.
#
# Binding the host's binderfs here makes the symlinks above resolve to the
# host's real binderfs inodes (which is what makes them work at all -- see the
# ENXIO note). init's own `mount binder binder /dev/binderfs` is neutered by the
# start script's init.rc injection so it cannot shadow this again.
#
# Ordering matters: this runs in the container's mount namespace before init
# starts, so init's chmod 0666 on /dev/binderfs/* lands on the host's nodes,
# which is exactly what container services need (the host ships them 0600).
if [ -d /dev/binderfs ] && [ -d "${LXC_ROOTFS_MOUNT}/dev/binderfs" ]; then
    mount --bind /dev/binderfs "${LXC_ROOTFS_MOUNT}/dev/binderfs" 2>/dev/null \
        && echo "sol-lxc-android: shared host binderfs into container"
elif [ -d /dev/binderfs ]; then
    mkdir -p "${LXC_ROOTFS_MOUNT}/dev/binderfs" 2>/dev/null
    mount --bind /dev/binderfs "${LXC_ROOTFS_MOUNT}/dev/binderfs" 2>/dev/null \
        && echo "sol-lxc-android: shared host binderfs into container (created mountpoint)"
fi
