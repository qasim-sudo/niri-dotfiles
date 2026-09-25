#!/usr/bin/env bash
# lib/backup.sh — one timestamped snapshot per installer run.
#
# Design:
#   * The snapshot directory is created lazily, on the FIRST call to
#     backup_file()/backup_root(). A run that writes nothing makes no backup.
#   * Every backed-up path is recorded in deployed.json inside the snapshot,
#     so uninstall.sh / restore.sh know exactly what this repository owns.
#   * A SHA256SUMS manifest is written at snapshot close (backup_close).
#   * Symlinks are recorded by their target, not followed, so restoring a
#     managed symlink restores the link and not the target's contents.

[ -n "${DOTFILES_BACKUP_SH:-}" ] && return 0
DOTFILES_BACKUP_SH=1

BACKUP_TS=""
BACKUP_DIR=""
BACKUP_OPEN=0

# Paths this repository has written, as an absolute-path manifest.
DEPLOYED_INDEX=""

# The ownership record itself, kept OUTSIDE the snapshot directories so it
# survives snapshot rotation and does not depend on there being a snapshot.
#
# This is what "does this repository already manage this file?" is answered
# from, and it is a plain sorted, de-duplicated list of absolute paths. Each
# snapshot's deployed.json is a documented copy of it plus the run metadata.
DEPLOYED_PATHS=()        # this run

_backup_open() {
    [ "$BACKUP_OPEN" = 1 ] && return 0
    BACKUP_TS="$(date +%Y%m%d-%H%M%S)"
    BACKUP_DIR="$BACKUP_ROOT/$BACKUP_TS"
    DEPLOYED_INDEX="$BACKUP_DIR/deployed.json"
    if [ "$DRY_RUN" != 1 ]; then
        mkdir -p "$BACKUP_DIR/files" 2>/dev/null || true
    fi
    BACKUP_OPEN=1
    return 0
}

# Record a path as owned by this repository.
#
# In memory only. This used to open the snapshot directory, which meant a run
# that changed nothing still created a timestamped backup every single time the
# installer ran — the exact opposite of the "created lazily, on the first call
# to backup_file()" the header of this file promises. The snapshot is now
# opened only when there is real file content to preserve, and the ownership
# list is flushed once, by backup_close.
_record_deployed() {
    local p="$1"
    case " ${DEPLOYED_PATHS[*]-} " in
        *" $p "*) return 0 ;;   # already recorded this run
    esac
    DEPLOYED_PATHS+=("$p")
    return 0
}

# Strip $HOME so the manifest is portable between accounts.
_portable_path() {
    local p="$1"
    printf '%s' "${p/#$HOME/\$HOME}"
}

# _portable_path, escaped for use as a grep ERE pattern.
_portable_path_escaped() {
    local p
    p="$(_portable_path "$1")"
    printf '%s' "${p//./\\.}"
}

# ---------------------------------------------------------------------------
# backup_file <path>
#
# Copies a user-owned file (or records a symlink's target) into the snapshot
# under files/<flattened-absolute-path>, and records it in deployed.json.
# A no-op if the path does not exist.
#
# The copy is staged OUTSIDE the snapshot and moved in only after it succeeds,
# so the snapshot directory is created if and only if it has content. Opening it
# first left an empty timestamped snapshot behind whenever the copy failed —
# which for a root-owned file is every time sudo was unavailable — so a run
# that changed nothing still grew the backup history.
# ---------------------------------------------------------------------------
backup_file() {
    local src="$1"
    [ -e "$src" ] || [ -L "$src" ] || return 0
    if [ "$DRY_RUN" = 1 ]; then
        _backup_open
        dry "back up ${_portable_path "$src"}"
        return 0
    fi

    local staging flat
    staging="$(mktemp -d)"
    flat="$(printf '%s' "${src#/}" | tr '/' '%')"

    if [ -L "$src" ]; then
        # Record the link target rather than following it.
        printf '%s -> %s\n' "$(_portable_path "$src")" "$(readlink "$src")" \
            >"$staging/$flat"
    elif ! cp -a -- "$src" "$staging/$flat" 2>/dev/null; then
        rm -rf "$staging"
        warn "could not back up $src"
        return 0
    fi

    _backup_open
    mv -f -- "$staging/$flat" "$BACKUP_DIR/files/$flat" 2>/dev/null \
        || cp -a -- "$staging/$flat" "$BACKUP_DIR/files/$flat" 2>/dev/null || true
    rm -rf "$staging"
    _record_deployed "$src"
    return 0
}

# ---------------------------------------------------------------------------
# backup_root <path>
#
# Same, for a root-owned file (e.g. /etc/sddm.conf). Sudo is used for the copy;
# the file is placed in the same snapshot so restore.sh can put it back.
# ---------------------------------------------------------------------------
backup_root() {
    local src="$1"
    [ -e "$src" ] || [ -L "$src" ] || return 0
    if [ "$DRY_RUN" = 1 ]; then
        _backup_open
        dry "back up (root) $src"
        return 0
    fi
    local staging flat
    staging="$(mktemp -d)"
    flat="$(printf '%s' "${src#/}" | tr '/' '%')"
    if ! sudo cp -a -- "$src" "$staging/$flat" 2>/dev/null; then
        rm -rf "$staging"
        warn "could not back up $src (this needs sudo)"
        return 0
    fi

    _backup_open
    mv -f -- "$staging/$flat" "$BACKUP_DIR/files/$flat" 2>/dev/null \
        || cp -a -- "$staging/$flat" "$BACKUP_DIR/files/$flat" 2>/dev/null || true
    rm -rf "$staging"
    _record_deployed "$src"
    return 0
}

# ---------------------------------------------------------------------------
# backup_close — flush the ownership record, finalise the manifest.
#
# A run that wrote nothing and owns nothing new does NOT create a snapshot. That
# is the whole point: the backup history should be a record of changes, not a
# record of how many times somebody ran the installer.
# ---------------------------------------------------------------------------
backup_close() {
    [ "$DRY_RUN" = 1 ] && return 0
    if [ ${#DEPLOYED_PATHS[@]} -eq 0 ] && [ "$BACKUP_OPEN" != 1 ]; then
        return 0
    fi

    # The ownership list, canonicalised, as the UNION of what was already
    # recorded and what this run touched.
    #
    # Union, not replacement. This record answers "does this repository already
    # manage this file?", so a run that changed one file must not drop the other
    # twenty-five from it. Replacing it made a mostly-idempotent re-run shrink
    # the record, after which the repository no longer recognised its own
    # previously deployed files and started refusing to update them as
    # "not previously managed" — which is the opposite of the intended
    # behaviour and quietly breaks every future update.
    local newlist prevlist paths_changed=0
    newlist="$(mktemp)"; prevlist="$(mktemp)"
    if [ -f "$STATE_DIR/deployed-paths" ]; then
        sort -u "$STATE_DIR/deployed-paths" >"$prevlist"
    fi
    cat "$prevlist" - >"$newlist" 2>/dev/null || cp "$prevlist" "$newlist"
    printf '%s\n' "${DEPLOYED_PATHS[@]-}" | grep -v '^$' >>"$newlist" || true
    sort -u -o "$newlist" "$newlist"
    cmp -s "$newlist" "$prevlist" || paths_changed=1
    rm -f "$prevlist"

    if [ "$paths_changed" = 1 ]; then
        install -m 0644 "$newlist" "$STATE_DIR/deployed-paths" 2>/dev/null || true
    fi

    if [ "$BACKUP_OPEN" != 1 ] && [ "$paths_changed" = 0 ]; then
        rm -f "$newlist"
        note "nothing changed since the last run; no new backup snapshot"
        return 0
    fi

    # There is real content to preserve, or the ownership set moved: open one.
    [ "$BACKUP_OPEN" = 1 ] || _backup_open
    [ -d "$BACKUP_DIR/files" ] || mkdir -p "$BACKUP_DIR/files" 2>/dev/null || true

    {
        printf '{\n  "run": "%s",\n  "user": "%s",\n  "host": "%s",\n  "paths": [\n' \
            "$BACKUP_TS" "$TARGET_USER" "$(uname -n)"
        local first=1 p
        while IFS= read -r p; do
            [ -n "$p" ] || continue
            [ "$first" = 1 ] || printf ',\n'
            printf '    "%s"' "$p"
            first=0
        done <"$newlist"
        [ "$first" = 1 ] || printf '\n'
        printf '  ]\n}\n'
    } >"$DEPLOYED_INDEX"
    rm -f "$newlist"

    if [ -d "$BACKUP_DIR/files" ]; then
        ( cd "$BACKUP_DIR/files" && find . -type f -print0 2>/dev/null \
            | sort -z | xargs -0 -r sha256sum >"$BACKUP_DIR/SHA256SUMS" 2>/dev/null ) || true
    fi
    if [ -n "$(ls -A "$BACKUP_DIR/files" 2>/dev/null)" ]; then
        ok "backup snapshot: ${BACKUP_DIR/#$HOME/\$HOME}"
    else
        # Nothing pre-existing to preserve. Keep the record (it documents what
        # was created) but say so plainly.
        rmdir "$BACKUP_DIR/files" 2>/dev/null || true
        ok "no existing files needed preserving (nothing was overwritten); manifest at ${BACKUP_DIR/#$HOME/\$HOME}/deployed.json"
    fi
    # Only ever repoint latest-backup at a snapshot that exists: restore.sh and
    # the README both read it, and a dangling pointer there is worse than a
    # slightly stale one.
    printf '%s' "$BACKUP_DIR" >"$STATE_DIR/latest-backup.tmp" 2>/dev/null \
        && mv -f "$STATE_DIR/latest-backup.tmp" "$STATE_DIR/latest-backup" 2>/dev/null || true
    return 0
}

# ---------------------------------------------------------------------------
# record_written <path>
#
# Record a hash of a file AS THIS REPOSITORY WROTE IT, in the snapshot's
# written.sha256.
#
# Why this is needed: SHA256SUMS covers the files we BACKED UP, i.e. the
# versions that existed before us. It says nothing about what we wrote. Without
# it, restore.sh has to guess whether a file has been edited since the install,
# and the guess it made was "yes" for every deployed file — a symlink satisfies
# `test -f` and carries no "generated" marker — so a rollback refused to touch
# anything and silently did nothing while printing dozens of warnings.
#
# With this, "has the user edited this since we wrote it?" becomes a fact
# rather than a heuristic: same hash means untouched, so removing it is the
# correct undo; different hash means the user owns it now, so leave it.
# ---------------------------------------------------------------------------
record_written() {
    local p="$1"
    [ "$DRY_RUN" = 1 ] && return 0
    [ -e "$p" ] || [ -L "$p" ] || return 0
    _backup_open

    local line
    if [ -L "$p" ]; then
        # Hash the link target, not the contents it points at, so an edit to the
        # target file does not read as an edit to the link.
        line="symlink $(_portable_path "$p") $(readlink "$p")"
    else
        # sha256sum prints "<hash>  <path>"; normalise the path so the record is
        # portable and comparable across machines and accounts.
        local h
        h="$(sha256sum -- "$p" 2>/dev/null | awk '{print $1}')"
        [ -n "$h" ] || return 0
        line="$h  $(_portable_path "$p")"
    fi

    # Replace any earlier entry for this path rather than appending, so calling
    # this more than once for the same file converges instead of growing the
    # record — and never makes an otherwise-identical run look like a change.
    local tmp
    tmp="$(mktemp)"
    if [ -f "$BACKUP_DIR/written.sha256" ]; then
        grep -vE "  $(_portable_path_escaped "$p")( |$)" \
                 "$BACKUP_DIR/written.sha256" >"$tmp" 2>/dev/null || true
    fi
    printf '%s\n' "$line" >>"$tmp"
    mv -f "$tmp" "$BACKUP_DIR/written.sha256"
    return 0
}

# ---------------------------------------------------------------------------
# undo_written <snapshot> <path>
#
# Decide what to do about a path that the install CREATED (so there is no
# earlier version in files/ to restore): remove it if it still holds exactly
# what we wrote, keep it if the user has edited it since.
#
# Sets UNDO_ACTION to one of:
#   removed       the file was untouched; it has been removed
#   kept-edited   the user has edited it; it is still there
#   unknown       no record for this path, so it has been left alone
# Returns 0 when it could tell, 1 when it could not.
#
# The record stores $HOME-relative paths so a snapshot stays portable between
# accounts, so the lookup must use the same form. Matching an absolute path
# against it finds nothing, and then every file looks unrecorded.
#
# The previous version of this decision was `test -f` plus a grep for a
# "generated" marker. A symlink satisfies `test -f` and carries no marker, and a
# seeded file has no marker either, so it classified essentially everything as
# user-edited. Both restore.sh and uninstall.sh then refused to act on their own
# files: a rollback printed a warning per path and removed nothing, and an
# uninstall left nine of its own files behind while reporting success.
# ---------------------------------------------------------------------------
UNDO_ACTION="unknown"
undo_written() {
    local snap="$1" p="$2"
    UNDO_ACTION="unknown"
    [ -f "$snap/written.sha256" ] || return 1

    local portable line
    portable="$(_portable_path "$p")"
    line="$(grep -F " $portable" "$snap/written.sha256" 2>/dev/null | head -n1)"
    [ -n "$line" ] || return 1

    local same=0 cur
    case "$line" in
        symlink\ *)
            # Compare the link TARGET, not the contents behind it: editing the
            # target file means editing the repository, not this link.
            cur="$([ -L "$p" ] && readlink "$p" || printf 'not-a-symlink')"
            [ "$cur" = "${line##* }" ] && same=1
            ;;
        *)
            local want have
            want="${line%%  *}"
            have="$(sha256sum -- "$p" 2>/dev/null | awk '{print $1}')"
            [ -n "$have" ] && [ "$have" = "$want" ] && same=1
            ;;
    esac

    if [ "$same" = 1 ]; then
        UNDO_ACTION="removed"
        rm -f "$p" 2>/dev/null
    else
        UNDO_ACTION="kept-edited"
    fi
    return 0
}

# Was this path previously written by the installer?
# Reads the ownership record, which is independent of snapshot rotation.
previously_deployed() {
    local path="$1"
    [ -f "$STATE_DIR/deployed-paths" ] || return 1
    grep -qxF -- "$path" "$STATE_DIR/deployed-paths" 2>/dev/null
}

# List the snapshots, newest first.
backup_list() {
    [ -d "$BACKUP_ROOT" ] || return 0
    find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -r
}
