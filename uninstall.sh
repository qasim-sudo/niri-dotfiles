#!/usr/bin/env bash
# uninstall.sh — remove everything this repository deployed.
#
# WHAT IT DOES
#   1. Reads the most recent snapshot's deployed.json to learn exactly which
#      paths this repository wrote.
#   2. Restores each of them from the snapshot (putting your previous file
#      back), or removes the path if it did not exist before.
#   3. Removes the generated per-host files (niri output.kdl, the Noctalia
#      runtime overlay).
#   4. Removes the deployed symlinks it owns.
#
# WHAT IT DOES NOT DO
#   * It does NOT remove any package. Uninstalling niri, pipewire, sddm or a
#     theme package is a decision for you, and several of those packages are
#     shared with things this repository has nothing to do with.
#   * It does NOT touch the bootloader, grub, efibootmgr, or your partitions.
#   * It does NOT disable or unmask any systemd unit.
#   * It does NOT delete ~/.local/state/dotfiles/backups/ — your snapshots are
#     the only way back, so they are kept. Delete that directory by hand once
#     you are satisfied.
#   * It does NOT remove ~/.config/dotfiles/local.conf (your secrets).
#
# If the repository is not on disk any more, run it from a fresh clone: the
# only thing it needs is the snapshot directory in your home.

set -uo pipefail

DOTFILES_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
export DOTFILES_ROOT

. "$DOTFILES_ROOT/lib/common.sh"
. "$DOTFILES_ROOT/lib/backup.sh"

DRY_RUN=0
FORCE=0
KEEP_SNAPSHOTS=1

usage() {
    cat <<'UNINSTALL_USAGE'
uninstall.sh — remove what the dotfiles installer deployed

USAGE
    ./uninstall.sh [options]

OPTIONS
    --dry-run    List everything that would be removed or restored. Change
                 nothing. Start here.
    --force      Do not ask for confirmation.
    --purge      Also delete ~/.local/state/dotfiles/backups/ afterwards.
                 This is irreversible; there is no way back once done.
    --user=NAME  Act on NAME's home instead of the current user.
    -h, --help   This text.

NOTES
    No package is removed. No systemd unit is changed. No bootloader setting is
    touched. Your own pre-existing files are restored from the snapshot, not
    deleted.
UNINSTALL_USAGE
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)  usage 0 ;;
        --dry-run)  DRY_RUN=1 ;;
        --force)    FORCE=1 ;;
        --purge)    KEEP_SNAPSHOTS=0 ;;
        --user=*)   TARGET_USER="${1#*=}" ;;
        *) err "unknown option: $1"; printf '\n'; usage 1 ;;
    esac
    shift
done

_log_init
banner "uninstall"
assert_not_root

# ---------------------------------------------------------------------------
# Find the ownership record.
#
# $STATE_DIR/deployed-paths is a plain newline-separated list of absolute paths
# and nothing else, so it can be read with `mapfile` and cannot yield anything
# that is not a path.
#
# It used to be scraped out of a snapshot's deployed.json with
# `grep -oE '"[^"]+"' | tr -d '"'`, which also matched the JSON's own metadata —
# so PATHS contained "run", the timestamp, "user", YOUR ACCOUNT NAME, "host",
# the hostname, and "paths". The plan below then offered to rm each of those
# relative to $HOME. A snapshot is the last thing that should be able to delete
# your home directory by accident.
# ---------------------------------------------------------------------------
step "Locating the ownership record"

PATHS_FILE="$STATE_DIR/deployed-paths"
SNAP=""
if [ ! -s "$PATHS_FILE" ]; then
    # Fall back to the newest snapshot's manifest, for a state directory written
    # by an older version of this repository.
    for d in $(backup_list); do
        if [ -s "$BACKUP_ROOT/$d/deployed.json" ]; then SNAP="$BACKUP_ROOT/$d"; fi
    done
    if [ -n "$SNAP" ]; then
        PATHS_FILE="$SNAP/deployed.json"
        warn "no deployed-paths record; falling back to $SNAP/deployed.json"
        note "only paths inside the \"paths\" array are considered, not the metadata"
    fi
fi

if [ ! -s "$PATHS_FILE" ]; then
    warn "no ownership record found in ${STATE_DIR/#$HOME/\$HOME}"
    note "nothing is known to have been installed; nothing to undo"
    exit 0
fi
ok "record: ${PATHS_FILE/#$HOME/\$HOME}"
[ -n "$SNAP" ] && ok "snapshot: ${SNAP/#$HOME/\$HOME}"

# undo_written() needs a snapshot holding written.sha256. When the paths came
# from the standalone ownership record, pick the newest snapshot that has one —
# falling back to the newest snapshot at all.
UNDO_SNAP=""
if [ -z "$SNAP" ]; then
    for d in $(backup_list); do
        if [ -f "$BACKUP_ROOT/$d/written.sha256" ]; then
            UNDO_SNAP="$BACKUP_ROOT/$d"; break
        fi
    done
    [ -n "$UNDO_SNAP" ] || { [ -n "$(backup_list | head -1)" ] && UNDO_SNAP="$BACKUP_ROOT/$(backup_list | head -1)"; }
fi
# Only fall back to $SNAP when the loop above found nothing. Written as
# `[ -z ... ] || UNDO_SNAP="$SNAP"`, this runs in exactly the case where a
# snapshot WAS found and overwrites it — with the empty $SNAP — so every
# undo_written() lookup failed and the uninstall left its own files behind.
[ -n "$UNDO_SNAP" ] || [ -z "$SNAP" ] || UNDO_SNAP="$SNAP"

# Paths to remove, and paths to restore.
if [ "$PATHS_FILE" = "$SNAP/deployed.json" ]; then
    # Only the entries of the "paths" array — the header values above it are
    # deliberately excluded.
    mapfile -t PATHS < <(sed -n '/"paths"[[:space:]]*:[[:space:]]*\[/,$p' "$PATHS_FILE" \
        | tail -n +2 | grep -oE '"[^"]+"' | tr -d '"')
else
    mapfile -t PATHS < <(grep -v '^[[:space:]]*$' "$PATHS_FILE")
fi

if [ ${#PATHS[@]} -eq 0 ]; then
    note "the record lists no deployed paths"
    exit 0
fi

# Last line of defence, and the one that matters most in an uninstall: only a
# plausible absolute path may reach a removal. Anything else is reported and
# dropped rather than being resolved relative to $HOME.
REJECTED=0
KEPT_PATHS=()
for p in "${PATHS[@]}"; do
    case "$p" in
        /*)                       KEPT_PATHS+=("$p") ;;
        '~'/*)                    KEPT_PATHS+=("$HOME/${p#\~/}") ;;
        /*)                       : ;;
        *) REJECTED=$((REJECTED + 1))
           warn "ignoring non-path entry in the record: $p" ;;
    esac
done
PATHS=("${KEPT_PATHS[@]-}")
if [ "$REJECTED" -gt 0 ]; then
    note "$REJECTED non-path entr(ies) ignored; an uninstall only ever acts on absolute paths"
fi
if [ ${#PATHS[@]} -eq 0 ]; then
    note "nothing left to undo"
    exit 0
fi

# ---------------------------------------------------------------------------
step "Plan"
printf '    %s path(s) recorded in the snapshot\n\n' "${#PATHS[@]}"
printf '    %-58s %s\n' "PATH" "ACTION"
printf '    %-58s %s\n' "----------------------------------------------------------" "------"

REMOVED=0
RESTORED=0
MISSING=0

for p in "${PATHS[@]}"; do
    flat="$(printf '%s' "${p#/}" | tr '/' '%')"
    src="$SNAP/files/$flat"
    is_root=0
    case "$p" in /etc/*|/usr/*) is_root=1 ;; esac

    if [ ! -e "$p" ] && [ ! -L "$p" ]; then
        action="already gone"
        MISSING=$((MISSING + 1))
    elif [ -e "$src" ] || [ -f "$src" ]; then
        if [ -L "$src" ] || grep -q ' -> ' "$src" 2>/dev/null; then
            action="restore symlink"
        else
            action="restore previous file"
        fi
        RESTORED=$((RESTORED + 1))
    else
        # Recorded as deployed but nothing was backed up: it did not exist
        # before the installer created it, so removing it is the undo.
        action="remove (was created by installer)"
        REMOVED=$((REMOVED + 1))
    fi
    printf '    %-58s %s\n' "$p" "$action"
done

printf '\n'

# ---------------------------------------------------------------------------
step "Undoing"

confirm "Restore/remove these ${#PATHS[@]} path(s)?" || { note "cancelled; nothing changed"; exit 0; }

for p in "${PATHS[@]}"; do
    flat="$(printf '%s' "${p#/}" | tr '/' '%')"
    src="$SNAP/files/$flat"

    if [ ! -e "$p" ] && [ ! -L "$p" ]; then
        continue
    fi

    # --- root-owned destination ---------------------------------------------
    case "$p" in
        /etc/*|/usr/*)
            if [ "$DRY_RUN" = 1 ]; then
                dry "sudo restore $p"
            elif [ -e "$src" ]; then
                sudo install -D -m 0644 "$src" "$p" 2>/dev/null \
                    && ok "restored $p" \
                    || warn "could not restore $p"
            else
                sudo rm -f "$p" 2>/dev/null && ok "removed $p" || warn "could not remove $p"
            fi
            continue
            ;;
    esac

    # --- a symlink this repository owns -------------------------------------
    if [ -L "$p" ]; then
        target="$(readlink "$p" 2>/dev/null)"
        # Only remove links that point into this repository. A link the user
        # made themselves is never touched.
        case "$target" in
            "$DOTFILES_ROOT"/*)
                if [ "$DRY_RUN" = 1 ]; then
                    dry "unlink $p (points into the repo)"
                else
                    rm -f "$p" && ok "unlinked ${p/#$HOME/\$HOME}"
                fi
                continue
                ;;
            *)
                note "leaving symlink in place (does not point into this repo): ${p/#$HOME/\$HOME}"
                continue
                ;;
        esac
    fi

    # --- restore a previous file --------------------------------------------
    if [ -e "$src" ]; then
        # The snapshot records a symlink as "path -> target".
        if grep -q ' -> ' "$src" 2>/dev/null; then
            link_dst="$(sed 's/.* -> //' "$src")"
            if [ "$DRY_RUN" = 1 ]; then
                dry "restore symlink $p -> $link_dst"
            else
                rm -f "$p"
                ln -s "$link_dst" "$p" && ok "restored symlink ${p/#$HOME/\$HOME} -> $link_dst"
            fi
            continue
        fi
        if [ "$DRY_RUN" = 1 ]; then
            dry "restore $p from snapshot"
        else
            mkdir -p "$(dirname "$p")"
            cp -a -- "$src" "$p" && ok "restored ${p/#$HOME/\$HOME}"
        fi
        continue
    fi

    # --- nothing was there before: remove it --------------------------------
    # Only if it is still exactly what this repository made. If the user has
    # edited it since, removing it would destroy their work.
    #
    # The check used to be `test -f` plus a grep for a "generated" marker, which
    # classified seeds and copied files as user-edited because neither carries
    # that marker. Nine of this repository's own files were left behind while
    # the uninstall reported success. undo_written() compares a recorded hash
    # instead, which is a fact rather than a guess.
    if undo_written "$UNDO_SNAP" "$p" 2>/dev/null; then
        case "$UNDO_ACTION" in
            removed)
                if [ "$DRY_RUN" = 1 ]; then
                    dry "remove $p (created by the installer, since unedited)"
                else
                    ok "removed ${p/#$HOME/\$HOME}"
                    REMOVED=$((REMOVED + 1))
                fi
                ;;
            kept-edited)
                if [ "$DRY_RUN" = 1 ]; then
                    dry "KEEP $p (you have edited it since install)"
                else
                    warn "$p has been edited since install; leaving it in place"
                    note "      remove it by hand if you are sure: rm ${p/#$HOME/\$HOME}"
                fi
                ;;
        esac
        continue
    fi
    if [ "$DRY_RUN" = 1 ]; then
        dry "remove $p (created by the installer)"
    else
        # No recorded hash: this snapshot predates written.sha256. Removing
        # blind could destroy a file the user wrote, so say what is unknown and
        # leave the decision to them.
        warn "$p has no recorded original; leaving it in place"
        note "      remove it by hand if you are sure: rm ${p/#$HOME/\$HOME}"
    fi
done

# ---------------------------------------------------------------------------
# Generated per-host files that may not be in the manifest snapshot.
# ---------------------------------------------------------------------------
step "Generated files"
for g in "$HOME/.config/niri/cfg/output.kdl" "$HOME/.local/state/noctalia/settings.toml"; do
    if [ ! -e "$g" ]; then
        note "absent: ${g/#$HOME/\$HOME}"
        continue
    fi
    if [ "$DRY_RUN" = 1 ]; then
        dry "remove $g"
    elif grep -q 'GENERATED by the dotfiles installer' "$g" 2>/dev/null; then
        rm -f "$g" && ok "removed ${g/#$HOME/\$HOME}"
    else
        warn "${g/#$HOME/\$HOME} was not written by this installer; left in place"
    fi
done

# ---------------------------------------------------------------------------
# Filesystem hygiene: remove directories this repository created that are now
# empty. Only ever removes an EMPTY directory, and only under ~/.config, so it
# can never take a directory with your content in it.
# ---------------------------------------------------------------------------
step "Empty directories"
for d in "$HOME/.config/kitty/themes" "$HOME/.config/fuzzel/themes" \
         "$HOME/.config/qt5ct/noctalia" "$HOME/.config/qt6ct/noctalia"; do
    [ -d "$d" ] || continue
    if [ -z "$(ls -A "$d" 2>/dev/null)" ]; then
        [ "$DRY_RUN" = 1 ] && dry "rmdir $d" || { rmdir "$d" 2>/dev/null && ok "removed empty ${d/#$HOME/\$HOME}"; }
    fi
done

# ---------------------------------------------------------------------------
if [ "$KEEP_SNAPSHOTS" = 1 ]; then
    step "Snapshots kept"
    note "your backups are still in ${BACKUP_ROOT/#$HOME/\$HOME}"
    note "they are the only way back — delete that directory by hand when you are done"
else
    step "Purging snapshots"
    if [ "$DRY_RUN" = 1 ]; then
        dry "rm -rf $BACKUP_ROOT"
    else
        confirm "Permanently delete every backup snapshot under ${BACKUP_ROOT/#$HOME/\$HOME}?" \
            || { note "snapshots kept"; }
        if [ "$FORCE" = 1 ] || [ -t 0 ]; then
            rm -rf "$BACKUP_ROOT" && ok "snapshots deleted"
        fi
    fi
fi

printf '\n'
if [ "$DRY_RUN" = 1 ]; then
    printf '%sDry run complete. Nothing was changed.%s\n\n' "$C_BOLD" "$C_RESET"
else
    cat <<'DONE'

  Done.

  Not removed, on purpose:
    * any package                — use your package manager if you want to
    * any systemd unit           — nothing was enabled by this repository
                                  except with --enable-sddm
    * the bootloader             — never touched
    * ~/.config/dotfiles/local.conf — your own file

  If you enabled sddm during install and want it off:
      sudo systemctl disable sddm

  Log out and back in to see the reverted configuration.

DONE
fi
