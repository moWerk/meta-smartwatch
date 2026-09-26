# sol vibrates through ffmemless on the CS40L26A's FF_PERIODIC sine, the same
# path aurora uses -- same chip, same patches from meta-asteroid. See
# ngfd/50-ffmemless.ini for why the stock effect list cannot be used here.
#
# Durations are tuned for cs40l26's BUZZGEN, whose single-shot ceiling is about
# 1020ms (255 * 4ms), so 1000 is the practical maximum per pulse.

FILESEXTRAPATHS:prepend:sol := "${THISDIR}/ngfd:"

do_install:append:sol() {
    # sol vibrates through ffmemless only. The droid-vibrator plugin is not
    # installed, so drop it from plugins-optional and avoid a spurious
    # "unable to open plugin 'droid-vibrator'" ERROR at every ngfd start.
    sed -i 's/droid-vibrator;//' ${D}/usr/share/ngfd/ngfd.ini

    # Button-tap acknowledgement -- short and crisp.
    f=${D}/usr/share/ngfd/events.d/press.ini
    if [ -f "$f" ]; then
        sed -i '/^haptic\.duration/d; /^sound\.repeat/d' "$f"
        echo 'haptic.duration = 80' >> "$f"
    fi

    # Normal notification -- noticeable but unobtrusive.
    f=${D}/usr/share/ngfd/events.d/notif_normal.ini
    if [ -f "$f" ]; then
        sed -i '/^haptic\.duration/d; /^sound\.repeat/d' "$f"
        echo 'haptic.duration = 400' >> "$f"
    fi

    # Strong notification -- distinctly longer.
    f=${D}/usr/share/ngfd/events.d/notif_strong.ini
    if [ -f "$f" ]; then
        sed -i '/^haptic\.duration/d; /^sound\.repeat/d' "$f"
        echo 'haptic.duration = 800' >> "$f"
    fi

    # Alarm and ringtone already carry sound.repeat = true upstream, so they
    # loop ffmemless. Pin each pulse to the BUZZGEN ceiling.
    for e in alarm ringtone; do
        f=${D}/usr/share/ngfd/events.d/${e}.ini
        if [ -f "$f" ]; then
            sed -i '/^haptic\.duration/d' "$f"
            echo 'haptic.duration = 1000' >> "$f"
        fi
    done
}
