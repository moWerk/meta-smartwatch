#!/bin/sh
# Derive PulseAudio's droid audio policy configuration for sol from the vendor
# image's own, which module-droid-card cannot be pointed at as it ships.
#
# Two things are in the way:
#
#   * libdroid-util searches exactly four paths for a policy file --
#     /odm/etc/audio_policy_configuration.xml,
#     /system/etc/audio_policy_configuration.xml,
#     /vendor/etc/audio/audio_policy_configuration.xml and
#     /vendor/etc/audio_policy_configuration.xml -- while sol's A14 vendor keeps
#     its copy one level deeper, in a per-SKU directory
#     (/vendor/etc/audio/sku_monaco/). PulseAudio therefore found no
#     configuration at all and fell back to a null sink: every stream accepted,
#     nothing audible.
#
#   * sol's policy declares LE Audio device ports, AUDIO_DEVICE_OUT_BLE_HEADSET
#     and AUDIO_DEVICE_IN_BLE_HEADSET. Those device types are newer than the
#     module, and building the default profile set over them segfaults
#     PulseAudio in pa_droid_profile_set_default_new() -- on the devicePort
#     immediately after the A2DP ones, which is where the debug log stops.
#     aurora runs the same module version and declares no BLE ports, which is
#     why it never hit this.
#
# The vendor file is copied with three things removed: the BLE device ports, the
# routes whose sink is one, and the BLE entries in other routes' source lists.
# Everything else passes through byte for byte, so a vendor image update carries
# over without editing this script. The watch has no LE Audio support to lose:
# BlueZ on the host owns Bluetooth audio here, not the Android policy manager.
set -eu

DST=${1:-/etc/pulse/sol-audio-policy.xml}
SRC=

# Per-SKU directory first, since that is where this device keeps it, then the
# conventional locations, so a differently-laid-out vendor image still works.
for candidate in /vendor/etc/audio/sku_*/audio_policy_configuration.xml \
                 /vendor/etc/audio/audio_policy_configuration.xml \
                 /vendor/etc/audio_policy_configuration.xml; do
    if [ -r "$candidate" ]; then
        SRC=$candidate
        break
    fi
done

if [ -z "$SRC" ]; then
    echo "sol-audio-policy: no vendor audio policy configuration found" >&2
    exit 1
fi

awk '
    # LE Audio device ports, children and all.
    /<devicePort[^>]*BLE/       { if ($0 ~ /\/>[[:space:]]*$/) next; drop_port = 1; next }
    drop_port                   { if (/<\/devicePort>/) drop_port = 0; next }

    # Routes into an LE Audio sink. These span more than one line and end on />.
    /<route[^>]*sink="[^"]*BLE/ { if ($0 ~ /\/>/) next; drop_route = 1; next }
    drop_route                  { if (/\/>/) drop_route = 0; next }

    # LE Audio sources listed in the routes that are kept.
    {
        gsub(/,[[:space:]]*BLE In/, "")
        gsub(/BLE In[[:space:]]*,/, "")
        print
    }
' "$SRC" > "$DST.new"

# Refuse to install a result that lost the mixPort every sink is built from, or
# that still carries a device type known to crash the module. A stale working
# file beats a fresh broken one, since PulseAudio reads this on every start.
if ! grep -q 'mixPort name="primary output"' "$DST.new"; then
    echo "sol-audio-policy: no primary output in result derived from $SRC" >&2
    rm -f "$DST.new"
    exit 1
fi
if grep -q BLE "$DST.new"; then
    echo "sol-audio-policy: BLE device ports survived filtering of $SRC" >&2
    rm -f "$DST.new"
    exit 1
fi

mv "$DST.new" "$DST"
echo "sol-audio-policy: derived $DST from $SRC"

# --- speaker protection ---------------------------------------------------
#
# PAL's speaker protection opens a second graph for the amplifier's VI feedback
# alongside every playback stream. Resuming a suspended sink over that path
# deadlocks PulseAudio: the sink resumes, the daemon stops answering clients,
# and every one of them times out at 30s while the process is still alive.
# Measured both ways, five rounds each with an 8s idle before the play so
# module-suspend-on-idle has fired: enabled 5/5 wedged, disabled 5/5 clean.
#
# Sol's vendor enables it in two of its seven resourcemanager variants,
# including the one this device selects. aurora ships 0 in the variant it uses
# and has never shown this, which is the whole difference between them: the
# rest of the audio configuration matches.
#
# The speaker keeps its protection. Sol's amplifier is the CS40L26, whose own
# DSP does excursion and thermal limiting on the part itself; what is switched
# off here is PAL's host-side VI feedback loop on top of that.
#
# /vendor is read-only and belongs to the vendor image, so the variants are
# copied, edited and bind-mounted back over themselves rather than patched.
RUNDIR=/run/sol-audio-policy
mkdir -p "$RUNDIR"

for rm_xml in /vendor/etc/audio/sku_*/resourcemanager_*.xml; do
    [ -r "$rm_xml" ] || continue
    grep -q '<speaker_protection_enabled>1</speaker_protection_enabled>' "$rm_xml" || continue

    copy="$RUNDIR/$(basename "$rm_xml")"
    sed 's|<speaker_protection_enabled>1</speaker_protection_enabled>|<speaker_protection_enabled>0</speaker_protection_enabled>|' \
        "$rm_xml" > "$copy"

    # Already bound from an earlier start: replace it rather than stacking.
    # Nothing mounted is the normal case and umount exits 32 for it, so this
    # must not be allowed to end the script.
    umount "$rm_xml" 2>/dev/null || :
    if mount --bind "$copy" "$rm_xml"; then
        echo "sol-audio-policy: speaker protection off in $(basename "$rm_xml")"
    else
        echo "sol-audio-policy: failed to bind $copy over $rm_xml" >&2
    fi
done
