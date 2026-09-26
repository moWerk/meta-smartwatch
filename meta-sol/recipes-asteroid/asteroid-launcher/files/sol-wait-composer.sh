#!/bin/sh
# /usr/libexec/sol-wait-composer.sh
#
# Block until sol's Android container has published a composer, so that
# asteroid-launcher does not start before there is a hwcomposer to talk to.
#
# Why this exists at all: the composer is a service INSIDE the LXC container,
# so there is no systemd unit for it and no ordering dependency that can be
# expressed against it. sol-lxc-android.service is Type=simple around a
# foreground lxc-start, so it counts as "active" the moment the container is
# spawned -- long before Android init has walked its rc files and reached
# class_start hal. Its Before=user@1000.service therefore orders the session
# after the container STARTS, not after the container is USABLE.
#
# Without this wait the launcher aborts with "failed to get hwcomposer service"
# and burns systemd's default rate limit (5 starts in 10s) before the composer
# ever appears, landing in `failed` permanently:
#     asteroid-launcher.service: Start request repeated too quickly.
#
# Matching is on argv[0] from /proc/PID/cmdline, and both halves of that are
# deliberate:
#
#   argv[0], not a substring. A cmdline SUBSTRING match also matches any shell
#   whose own command line happens to contain the pattern -- including this
#   script. Ad-hoc probes written that way during this bring-up reported a
#   phantom second composer for exactly that reason. A shell's argv[0] is "sh",
#   so an anchored match can never self-match even when the path appears later
#   in its command line. Verified on device as ceres.
#
#   cmdline, not /proc/PID/exe. Reading exe needs PTRACE_MODE_READ, so for a
#   root-owned process it returns EACCES to an unprivileged reader. This service
#   runs as ceres. The first version of this script used exe, worked perfectly
#   when tested by hand over adb (which is root), and then span for four minutes
#   on the first real boot without ever matching. cmdline is world-readable.
#
# One more trap, load-bearing: cmdline has no trailing newline, so `read`
# returns non-zero at EOF even though it did populate the variable. A
# `read ... || continue` therefore discards every match. Do not add one back.
#
# This is a bounded wait, never a hard gate: on timeout it exits 0 and lets the
# launcher try anyway. Failing the compositor's start because a probe timed out
# would turn a slow boot into no UI at all. The launcher's own restart policy
# (see 50-sol-wait-for-composer.conf) is the backstop for the residual window
# between the process appearing and its AIDL service being registered.
set -u

COMPOSER=/vendor/bin/hw/vendor.qti.hardware.display.composer-service
TIMEOUT=${SOL_COMPOSER_TIMEOUT:-120}

composer_running() {
    for f in /proc/[0-9]*/cmdline; do
        # No `|| continue` here -- see the note above about read and EOF.
        read -r argv < "$f" 2>/dev/null
        case "$argv" in
            "$COMPOSER"*) return 0 ;;
        esac
    done
    return 1
}

# Polled with a builtin read rather than a fork per process: this walks ~300
# entries a round on this device, and the exe version forked readlink for every
# one of them, burning two and a half minutes of CPU in four minutes of waiting.
i=0
while [ "$i" -lt "$TIMEOUT" ]; do
    if composer_running; then
        # The service registers on vndbinder a moment after exec. Settle briefly
        # rather than racing it; a failed lookup costs a full restart cycle.
        sleep 2
        echo "sol-wait-composer: composer up after ${i}s"
        exit 0
    fi
    sleep 2
    i=$((i + 2))
done

echo "sol-wait-composer: no composer after ${TIMEOUT}s, starting anyway"
exit 0
