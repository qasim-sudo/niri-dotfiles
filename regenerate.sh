#!/usr/bin/env bash
# regenerate.sh — rebuild the two files that cannot be committed.
#
#   ./regenerate.sh
#
# Why this exists:
#
#   ~/.config/niri/cfg/output.kdl
#       Which monitor is called what, its mode, its scale, and where it sits.
#       All four are properties of the hardware plugged in right now. Commit
#       them and the repository hard-codes a monitor name, a resolution and a
#       layout that is wrong on every other machine and wrong here the moment
#       you undock.
#
#   ~/.local/state/noctalia/settings.toml
#       Noctalia's runtime overlay: which wallpaper each display shows, and one
#       login box per display, positioned in that display's own pixel space.
#       Same reason: it is a description of the current monitor layout.
#
# Both are described in the shipped Noctalia config only by @TOKEN@ and
# generated keys, so the repository stays portable and the desktop stays
# correct. Run this after changing monitors, changing resolution or scale, or
# docking a second display.
#
# With no niri session running, the generator still writes valid output: the
# Noctalia overlay falls back to a single display-agnostic login box, and
# output.kdl gets no output block so niri auto-detects. Run it from inside your
# session for exact modes and positions.

set -uo pipefail

DOTFILES_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
export DOTFILES_ROOT

. "$DOTFILES_ROOT/lib/common.sh"
. "$DOTFILES_ROOT/lib/detect.sh"
. "$DOTFILES_ROOT/lib/hardware.sh"
. "$DOTFILES_ROOT/lib/backup.sh"
. "$DOTFILES_ROOT/lib/noctalia.sh"

DRY_RUN=0
FORCE=0

usage() {
    cat <<'REGEN_USAGE'
regenerate.sh — rebuild the per-host config files

USAGE
    ./regenerate.sh [--dry-run] [--force]

Writes
    ~/.config/niri/cfg/output.kdl
    ~/.local/state/noctalia/settings.toml

Both are backed up first, into ~/.local/state/dotfiles/backups/<timestamp>/.
Run this after a monitor change. See the header of this file for why these two
are generated rather than committed.
REGEN_USAGE
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)  usage 0 ;;
        --dry-run)  DRY_RUN=1 ;;
        --force)    FORCE=1 ;;
        *) err "unknown option: $1"; printf '\n'; usage 1 ;;
    esac
    shift
done

_log_init
banner "regenerate"
assert_not_root
# The Noctalia overlay references WALLPAPER_DIR, so the same override the
# installer honoured has to be applied here too.
load_local_conf

detect_all

printf '\n'
printf '    niri running   : %s\n' "$([ "$DETECT_NIRI_RUNNING" = 1 ] && echo yes || echo no)"
printf '    outputs seen   : %s\n' "${DETECT_OUTPUTS:-(none)}"
printf '\n'

if [ "$DETECT_NIRI_RUNNING" != 1 ]; then
    warn "no niri session is running"
    note "output.kdl will be written with no output block, so niri auto-detects"
    note "the login box will be display-agnostic rather than per-monitor"
    note "log into your session and re-run for exact modes and positions"
    printf '\n'
fi

# lib/hardware.sh and lib/noctalia.sh both back up the file they are about to
# replace, so there is no separate confirmation needed for either. Both are
# marked GENERATED in their first line, which is what lets uninstall.sh and
# restore.sh tell them apart from a file you edited by hand.
hardware_generate_output
noctalia_generate_settings
backup_close

printf '\n'
if [ "$DRY_RUN" = 1 ]; then
    printf '%sDry run complete. Nothing was changed.%s\n\n' "$C_BOLD" "$C_RESET"
else
    cat <<'DONE'
  Done.

  niri reads output.kdl at startup, so log out and back in (or run
  `niri msg action load-config-file` if your version supports it) to apply.

  Noctalia picks up settings.toml on its next start.

DONE
fi
