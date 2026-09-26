#!/bin/sh
# Expose the Halium system's FLATTENED APEXes at /apex.
#
# /system/lib's libc.so, libm.so and libdl.so are symlinks into
# /apex/com.android.runtime/lib/bionic/. On Android that path is mounted by
# apexd, which runs inside Android's init; we do not run it, so without this the
# symlinks dangle and every Android library load fails with
# `library "libc.so" not found`.
#
# Halium ships the apexes already flattened -- real directories under
# /system/apex -- so a bind mount is all that is needed. That is NOT true of
# sol's own stock system, where they are .apex archives (and one, ART, is a
# compressed apex that cannot be mounted in place at all); sol-vendor-mount
# loop-mounts those separately for its own /system. Whichever /system is in
# use, /apex must match it: pairing Halium's A13 system with sol's A14 bionic
# is an ABI mismatch.
set -e
# Follow the HOST's Halium system (see sol-vendor-mount), not the container
# rootfs -- /apex here must match whatever /system libhybris resolves to, or the
# bionic symlinks in /system/lib point at a different bionic than the libraries
# beside them.
if [ -d /android/hybris/system ]; then R=/android/hybris; else R=/var/lib/lxc/android/rootfs; fi

# Two image layouts exist and both must work:
#
#   aurora's Halium-13 image  -> /apex is an EMPTY mountpoint, the flattened
#                                apexes live under /system/apex
#   our A14 image             -> the apexes are flattened directly into /apex
#                                and /system/apex is empty (a real
#                                TARGET_FLATTEN_APEX build ships no archives)
#
# Getting this wrong is not a warning, it is a hung boot: with /apex empty the
# host's /system/lib/libc.so symlink dangles, every libhybris consumer
# (sensorfwd, ngfd, bluebinder) fails to load, multi-user.target never
# completes and the watch sits on psplash indefinitely. Observed 2026-08-11.
for apex in com.android.runtime com.android.art com.android.i18n; do
    dst="/apex/$apex"
    mountpoint -q "$dst" && continue
    # Layout A: already flattened inside the image's own /apex -- bind it out
    # to the host so libhybris sees the same bionic the container does.
    if [ -d "$R/apex/$apex" ]; then
        mkdir -p "$dst"
        mount --bind "$R/apex/$apex" "$dst"
        mount -o remount,ro,bind "$dst" 2>/dev/null || true
        echo "sol-android-apex: $dst <- image /apex/$apex"
        continue
    fi
    # Layout B: under /system/apex, possibly with a .release/.debug suffix.
    for suffix in .release .debug ""; do
        src="$R/system/apex/$apex$suffix"
        [ -d "$src" ] || continue
        mkdir -p "$dst"
        mount --bind "$src" "$dst"
        mount -o remount,ro,bind "$dst" 2>/dev/null || true
        echo "sol-android-apex: $dst <- system/apex/$(basename "$src")"
        break
    done
done

if [ -e /apex/com.android.runtime/lib/bionic/libc.so ]; then
    echo "sol-android-apex: bionic OK"
else
    echo "sol-android-apex: WARNING bionic missing -- Android libs will not load" >&2
fi
