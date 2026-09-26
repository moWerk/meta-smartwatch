# sol runs on a Halium-14 Android base. meta-asteroid's stock bbappend adds
# pulseaudio-modules-droid-jb2q to pulseaudio-server's RDEPENDS for every
# hybris machine, and jb2q's audio_policy_configuration parser only handles
# Android <= 10 schemas. On sol it aborts on the first mixPort of the primary
# module:
#
#   module-droid-card.c: Create new droid-card-jb2q
#   conversion.c: Unknown flags entries: AUDIO_OUTPUT_FLAG_PRIMARY
#                 AUDIO_OUTPUT_FLAG_FAST
#   config-parser-xml.c: parsing aborted at line 34
#   droid-config.c: Failed to parse any configuration.
#
# module-droid-card then fails to initialise, so PulseAudio has no card at all
# and falls back to module-always-sink. Every stream, including every ngfd
# sound event, is accepted into a null sink: the UI works, the volume slider
# moves, and nothing is audible.
#
# pulseaudio-modules-droid (RPROVIDED by the merhybris recipe) parses A11+
# schemas. The HIDL bridge and the audiosystem-passthrough helper are what the
# A12+ binderized audio HAL needs.
RDEPENDS:pulseaudio-server:remove:sol = "pulseaudio-modules-droid-jb2q"
RDEPENDS:pulseaudio-server:append:sol = " pulseaudio-modules-droid pulseaudio-modules-droid-hidl audiosystem-passthrough"

# default.pa is the stock file with one line changed: module-droid-card is given
# an explicit config=. It cannot find sol's policy by itself, because
# libdroid-util searches four fixed paths and sol's A14 vendor keeps the file one
# level below all of them, in /vendor/etc/audio/sku_monaco/. sol-audio-policy
# writes the file named here before the user session starts.
FILESEXTRAPATHS:prepend:sol := "${THISDIR}/pulseaudio:"
