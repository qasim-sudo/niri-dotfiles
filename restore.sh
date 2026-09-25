#!/usr/bin/env bash
# restore.sh — roll back to a specific backup snapshot.
#
#   ./restore.sh --list          list available snapshots
#   ./restore.sh --latest        roll back to the newest snapshot
#   ./restore.sh 20260926-014512 roll back to that one
#   ./restore.sh --latest --dry-run    show what would happen, change nothing
#
# A snapshot is the state of every path the installer was about to change,
# captured just before it changed it. Restoring one is therefore the exact
# inverse of a single installer run: your previous files come back, and files
# the installer created are removed.
#
# This is a recovery tool. Restoring an OLD snapshot on top of a NEW install
# is how you get a mixed state, so the default is --latest and the script tells
# you which snapshot it picked.

set -uo pipefail

DOTFILES_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
export DOTFILES_ROOT

. "$DOTFILES_ROOT/lib/common.sh"
. "$DOTFILES_ROOT/lib/backup.sh"

DRY_RUN=0
FORCE=0
WHICH=""
LIST_ONLY=0

usage() {
    cat <<'RESTORE_USAGE'
restore.sh — roll back to a backup snapshot

USAGE
    ./restore.sh --list
    ./restore.sh --latest
    ./restore.sh TIMESTAMP

OPTIONS
    --list        List snapshots, newest first, with how many paths each holds.
    --latest      Use the newest snapshot that recorded any paths.
    --dry-run     Show the plan, change nothing.
    --force       Do not ask for confirmation.
    --user=NAME   Act on NAME's home instead of the current user.
    -h, --help    This text.

EXAMPLES
    ./restore.sh --list
    ./restore.sh --latest --dry-run
    ./restore.sh 20260926-014512
RESTORE_USAGE
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)  usage 0 ;;
        --list)     LIST_ONLY=1 ;;
        --latest)   WHICH="--latest" ;;
        --dry-run)  DRY_RUN=1 ;;
        --force)    FORCE=1 ;;
        --user=*)   TARGET_USER="${1#*=}" ;;
        -*) err "unknown option: $1"; printf '\n'; usage 1 ;;
        *)          WHICH="$1" ;;
    esac
    shift
done

_log_init
banner "restore"
assert_not_root

# ---------------------------------------------------------------------------
step "Available snapshots"

if [ ! -d "$BACKUP_ROOT" ]; then
    die "no backup directory at ${BACKUP_ROOT/#$HOME/\$HOME}"
fi

COUNT=0
for d in $(backup_list); do
    n=0
    [ -s "$BACKUP_ROOT/$d/deployed.json" ] && n="$(grep -c '"' "$BACKUP_ROOT/$d/deployed.json" 2>/dev/null || echo 0)"
    printf '    %-18s %s path(s) recorded\n' "$d" "$n"
    COUNT=$((COUNT + 1))
done

if [ "$COUNT" = 0 ]; then
    note "no snapshots found"
    exit 0
fi
printf '\n'

if [ "$LIST_ONLY" = 1 ]; then
    exit 0
fi

# ---------------------------------------------------------------------------
# Resolve which snapshot to use.
# ---------------------------------------------------------------------------
if [ -z "$WHICH" ]; then
    usage 1
fi

if [ "$WHICH" = "--latest" ]; then
    SNAP=""
    for d in $(backup_list); do
        if [ -s "$BACKUP_ROOT/$d/deployed.json" ]; then SNAP="$BACKUP_ROOT/$d"; fi
    done
    if [ -z "$SNAP" ]; then
        die "no snapshot recorded any paths, so there is nothing to roll back to"
    fi
else
    case "$WHICH" in
        */*|*..*) die "invalid snapshot name: $WHICH" ;;
    esac
    SNAP="$BACKUP_ROOT/$WHICH"
    [ -d "$SNAP" ] || die "no such snapshot: $SNAP"
fi

ok "selected: ${SNAP/#$HOME/\$HOME}"

# ---------------------------------------------------------------------------
# A snapshot taken AFTER another install describes that install's changes, not
# this one's. Warn if it is not the newest, because that is almost always a
# mistake.
# ---------------------------------------------------------------------------
NEWEST="$(backup_list | head -1)"
if [ "$SNAP" != "$BACKUP_ROOT/$NEWEST" ] && [ -n "$NEWEST" ]; then
    warn "this is NOT the newest snapshot (newest is $NEWEST)"
    note "rolling back past a later install leaves a mixed state on purpose"
    note "only continue if you know that is what you want"
fi

# ---------------------------------------------------------------------------
# Read the paths from this snapshot's deployed.json.
#
# Only the entries of the "paths" array. `grep -oE '"[^"]+"'` over the whole
# file also returns the JSON's own header values — the key names and, more
# dangerously, the values of "run", "user" (your account name) and "host" —
# and those would then be resolved as paths relative to $HOME by a script whose
# entire job is to overwrite files.
# ---------------------------------------------------------------------------
if [ -s "$SNAP/deployed.json" ]; then
    # Only the entries INSIDE the "paths" array. Matching to end-of-file also
    # picks up the array's own key, so the literal string "paths" became a
    # candidate path — harmless, but it showed up as a warning on every run and
    # it meant the extraction was not actually reading the array.
    mapfile -t PATHS < <(sed -n '/"paths"[[:space:]]*:[[:space:]]*\[/,$p' "$SNAP/deployed.json" \
        | tail -n +2 | grep -oE '"[^"]+"' | tr -d '"')
elif [ -s "$STATE_DIR/deployed-paths" ]; then
    mapfile -t PATHS < <(grep -v '^[[:space:]]*$' "$STATE_DIR/deployed-paths")
else
    die "the snapshot records no paths"
fi

# And only an absolute path is ever restored.
KEPT_PATHS=()
for p in "${PATHS[@]}"; do
    case "$p" in
        /*)    KEPT_PATHS+=("$p") ;;
        '~'/*) KEPT_PATHS+=("$HOME/${p#\~/}") ;;
        *)     warn "ignoring non-path entry in the snapshot: $p" ;;
    esac
done
PATHS=("${KEPT_PATHS[@]-}")
[ ${#PATHS[@]} -gt 0 ] || die "the snapshot records no restorable paths"

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
step "Integrity check"
# Verify every backed-up file still matches the hash recorded when the snapshot
# was taken. A mismatch means the backup itself is damaged, and restoring it
# would put back something you never had.
if [ -s "$SNAP/SHA256SUMS" ]; then
    BAD=0
    while IFS= read -r line; do
        sum="${line%%  *}"
        rel="${line#*  }"
        rel="${rel#./}"
        f="$SNAP/files/${rel#./}"
        if [ ! -f "$f" ]; then continue; fi
        actual="$(sha256sum "$f" 2>/dev/null | awk '{print $1}')"
        if [ "$actual" != "$sum" ]; then
            warn "checksum mismatch (backup is damaged): $rel"
            BAD=$((BAD + 1))
        fi
    done < <(grep -vE '^\.' "$SNAP/SHA256SUMS" 2>/dev/null | grep -vE '^\S+  \.' || true)
    [ "$BAD" = 0 ] && ok "all backed-up files match their recorded checksums" \
                   || warn "$BAD file(s) failed the checksum; review before restoring"
else
    note "no SHA256SUMS in this snapshot (older format); skipping integrity check"
fi

# ---------------------------------------------------------------------------
step "Plan"
printf '    %-58s %s\n' "PATH" "ACTION"
printf '    %-58s %s\n' "----------------------------------------------------------" "------"
for p in "${PATHS[@]}"; do
    flat="$(printf '%s' "${p#/}" | tr '/' '%')"
    src="$SNAP/files/$flat"
    if [ ! -e "$p" ] && [ ! -L "$p" ]; then
        a="skip (already gone)"
    elif [ -e "$src" ]; then
        a="restore from snapshot"
    else
        a="remove (created by that install)"
    fi
    printf '    %-58s %s\n' "$p" "$a"
done
printf '\n'

confirm "Restore this snapshot?" || { note "cancelled; nothing changed"; exit 0; }

# ---------------------------------------------------------------------------
step "Restoring"
DONE=0
SKIPPED=0

for p in "${PATHS[@]}"; do
    flat="$(printf '%s' "${p#/}" | tr '/' '%')"
    src="$SNAP/files/$flat"

    if [ ! -e "$p" ] && [ ! -L "$p" ]; then
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    case "$p" in
        /etc/*|/usr/*)
            if [ -e "$src" ]; then
                if [ "$DRY_RUN" = 1 ]; then
                    dry "sudo restore $p"
                else
                    sudo install -D -m 0644 "$src" "$p" 2>/dev/null \
                        && { ok "restored $p"; DONE=$((DONE + 1)); } \
                        || warn "could not restore $p"
                fi
            else
                if [ "$DRY_RUN" = 1 ]; then
                    dry "sudo rm $p"
                else
                    sudo rm -f "$p" 2>/dev/null && { ok "removed $p"; DONE=$((DONE + 1)); }
                fi
            fi
            continue
            ;;
    esac

    if [ -e "$src" ]; then
        if grep -q ' -> ' "$src" 2>/dev/null; then
            link_dst="$(sed 's/.* -> //' "$src")"
            if [ "$DRY_RUN" = 1 ]; then
                dry "restore symlink $p -> $link_dst"
            else
                rm -f "$p"
                ln -s "$link_dst" "$p" && { ok "restored symlink ${p/#$HOME/\$HOME}"; DONE=$((DONE + 1)); }
            fi
        elif [ "$DRY_RUN" = 1 ]; then
            dry "restore $p"
        else
            mkdir -p "$(dirname "$p")"
            cp -a -- "$src" "$p" && { ok "restored ${p/#$HOME/\$HOME}"; DONE=$((DONE + 1)); }
        fi
        continue
    fi

    # Not backed up: the file did not exist before that install created it, so
    # the undo is to remove it — but only if it still holds what we wrote.
    #
    # The previous check here was `test -f` plus a grep for the "generated"
    # marker, which classified EVERY deployed file as user-edited: a symlink
    # satisfies `test -f` and carries no marker. So a rollback refused to touch
    # anything, printed a warning per file, and quietly achieved nothing.
    #
    # written.sha256 in the snapshot records each path as this repository wrote
    # it, so this is now a comparison rather than a guess.
    # undo_written returns non-zero only when it cannot tell, which means the
    # snapshot predates written.sha256 or never recorded this path. Do not delete
    # a file we cannot prove we created unmodified.
    if undo_written "$SNAP" "$p"; then
        case "$UNDO_ACTION" in
            removed)
                if [ "$DRY_RUN" = 1 ]; then
                    dry "remove $p  (unchanged since that install)"
                else
                    ok "removed ${p/#$HOME/\$HOME}  (unchanged since that install)"
                    DONE=$((DONE + 1))
                fi
                ;;
            kept-edited)
                if [ "$DRY_RUN" = 1 ]; then
                    dry "KEEP $p  (you have edited it since that install)"
                else
                    warn "$p has been edited since that install; leaving it in place"
                fi
                ;;
        esac
        continue
    fi
    if [ "$DRY_RUN" = 1 ]; then
        dry "KEEP $p  (this snapshot does not record what was written for it)"
    else
        warn "$p has no recorded original; leaving it in place"
        note "  that install predates written.sha256, or the file was not written by that run"
    fi
done

printf '\n'
if [ "$DRY_RUN" = 1 ]; then
    printf '%sDry run complete. %d path(s) would change, %d already gone.%s\n\n' \
        "$C_BOLD" "$DONE" "$SKIPPED" "$C_RESET"
else
    ok "restored $DONE path(s), skipped $SKIPPED already-absent path(s)"
    printf '\n  Log out and back in to see the reverted configuration.\n\n'
fi
