#!/usr/bin/env bash
# lib/deploy.sh — manifest-driven file deployment + @TOKEN@ templating.
#
# Four deployment modes, selected per line of deploy.manifest:
#
#   link   <src> <dest>     symlink. For static config the desktop never writes.
#   copy   <src> <dest>     real copy. For files Noctalia rewrites at runtime
#                           (it would fight a symlink and write through it).
#   seed   <src> <dest>     copy only if <dest> does not exist. For the theme
#                           files Noctalia generates on first run, so the very
#                           first login already looks themed.
#   root   <src> <dest>     sudo install. For /etc files.
#
# Safety:
#   * Every destination is backed up before the first write of a run.
#   * A destination is only overwritten if it is listed in deployed.json from a
#     previous run, or if it does not exist, or if --force was given.
#     A pre-existing file this repository has never managed is left alone and
#     reported, so a fresh install on a configured machine loses nothing.

[ -n "${DOTFILES_DEPLOY_SH:-}" ] && return 0
DOTFILES_DEPLOY_SH=1

MANIFEST="$DOTFILES_ROOT/deploy.manifest"

# ---------------------------------------------------------------------------
# @TOKEN@ substitution.
# ---------------------------------------------------------------------------
render_template() {
    local src="$1"
    # The filename is passed to sed. It is easy to leave it off, because sed
    # works fine without one — reading stdin — and that is exactly what it did:
    # render_template is called from inside a `while read` loop whose stdin is
    # deploy.manifest, so every templated file was deployed as manifest text
    # (and the rest of the manifest was silently consumed). -- stops a source
    # path beginning with a dash being read as an option.
    sed -e "s|@HOME@|$HOME|g" \
        -e "s|@USER@|$TARGET_USER|g" \
        -e "s|@WALLPAPER_DIR@|${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}|g" \
        -e "s|@ASSETS@|${ASSETS_DIR:-$HOME/.local/share/dotfiles/assets}|g" \
        -e "s|@DOTFILES@|$DOTFILES_ROOT|g" \
        -- "$src"
}

# Expand a leading ~ and make the path absolute.
abspath() {
    local p="$1"
    case "$p" in
        "~") p="$HOME" ;;
        "~/"*) p="$HOME/${p#\~/}" ;;
    esac
    printf '%s' "$p"
}

# ---------------------------------------------------------------------------
# Should we write this destination?
# ---------------------------------------------------------------------------
_claim_ok() {
    local dest="$1" reason="$2"
    if [ "$FORCE" = 1 ]; then return 0; fi
    if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then return 0; fi   # nothing to lose
    if [ -L "$dest" ] && [ "$(readlink -f "$dest" 2>/dev/null)" != "$(readlink -f "$DOTFILES_ROOT" 2>/dev/null)" ]; then
        # A symlink that does not point into this repo. Still treat as foreign.
        :
    fi
    if previously_deployed "$dest"; then return 0; fi
    warn "$reason: $dest"
    note "left untouched (this repository has never managed it). Re-run with --force to overwrite."
    STATS_SKIPPED=$((STATS_SKIPPED + 1))
    return 1
}

# ---------------------------------------------------------------------------
# deploy_one <mode> <src> <dest>
#
# RETURN-CODE CONTRACT
#   0  the destination was written (or would be, in a dry run)
#   2  a soft failure: it was reported and the run CONTINUES
#   3  deliberately left alone — a seed that already existed, or a file this
#      repository has never managed. Not an error; nothing was lost.
#   1  a hard error: the manifest is broken, so the run STOPS
#
# This distinction matters for the summary. When "kept" was reported as
# "deployed", the summary said 26 files deployed while the run had in fact
# written 25 and left one alone, which is precisely the sort of number that
# makes a partial install look complete.
# ---------------------------------------------------------------------------
deploy_one() {
    local mode="$1" src="$2" dest="$3"
    local abs_src="$DOTFILES_ROOT/$src"
    dest="$(abspath "$dest")"

    [ -e "$abs_src" ] || { err "manifest references a missing source: $src"; return 1; }

    # Validated up front: the two `case` blocks below have no `*)` arm, so an
    # unknown mode would otherwise silently fall through and report success.
    case "$mode" in
        link|copy|seed|root) : ;;
        *) err "unknown deploy mode '$mode' for $src"; return 1 ;;
    esac

    mkdir -p "$(dirname "$dest")" 2>/dev/null || true

    # --- seed: never clobber --------------------------------------------
    if [ "$mode" = "seed" ]; then
        if [ -e "$dest" ] || [ -L "$dest" ]; then
            note "seed (exists, kept): ${dest/#$HOME/\$HOME}"
            STATS_SKIPPED=$((STATS_SKIPPED + 1))
            return 3
        fi
        if [ "$DRY_RUN" = 1 ]; then
            dry "seed  $dest"
        else
            local sseed; sseed="$(mktemp)"
            if ! render_template "$abs_src" >"$sseed" 2>/dev/null; then
                cp -p -- "$abs_src" "$sseed"
            fi
            install -m 0644 "$sseed" "$dest" || { rm -f "$sseed"; err "could not write $dest"; return 1; }
            rm -f "$sseed"
        fi
        if [ "$DRY_RUN" != 1 ]; then
            # A seed is created by this repository, so it is owned by it and
            # uninstall.sh must be able to remove it. Not recording these left
            # seven files behind on every uninstall.
            _record_deployed "$dest"
            record_written "$dest"
        fi
        STATS_DEPLOYED=$((STATS_DEPLOYED + 1))
        return 0
    fi

    if ! _claim_ok "$dest" "not previously managed by this repository"; then
        # Kept, not deployed. See the return-code contract above.
        return 3
    fi

    # ------------------------------------------------------------------------
    # DECIDE, THEN BACK UP, THEN WRITE.
    #
    # The "would this actually change anything?" test happens here, BEFORE
    # backup_file(). Doing it afterwards meant a run that wrote nothing still
    # copied every managed file into a fresh timestamped snapshot — so the
    # backup history filled up with snapshots of files that were never touched,
    # and "idempotent" was only ever true of the files, not of the run.
    #
    # This matters beyond tidiness: these snapshots are what restore.sh and
    # uninstall.sh trust, and a directory full of snapshots of unchanged files
    # makes "the most recent snapshot" a much weaker thing to point at.
    # ------------------------------------------------------------------------
    local staged="" rc=0

    case "$mode" in
        link)
            # `ln -sfn` unlinks and recreates even when the target is already
            # correct, which bumps the parent directory's mtime. niri and
            # Noctalia watch their config directories, so that turned a no-op
            # re-run into a spurious reload.
            if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$abs_src" ]; then
                note "link (already correct): ${dest/#$HOME/\$HOME}"
                STATS_SKIPPED=$((STATS_SKIPPED + 1))
                return 3
            fi
            if [ "$DRY_RUN" = 1 ]; then
                dry "link  ${dest/#$HOME/\$HOME} -> $abs_src"
                STATS_DEPLOYED=$((STATS_DEPLOYED + 1))
                return 0
            fi
            # A rendered template cannot be a symlink, so it is materialised.
            if grep -qE '@(HOME|USER|WALLPAPER_DIR|ASSETS|DOTFILES)@' "$abs_src" 2>/dev/null; then
                staged="$(mktemp)"
                # Staged to a real file, not a pipe: install(1) refuses a fifo,
                # so process substitution is not an option here.
                if ! render_template "$abs_src" >"$staged" 2>/dev/null; then
                    cp -p -- "$abs_src" "$staged"
                fi
                if [ -f "$dest" ] && cmp -s "$staged" "$dest"; then
                    rm -f "$staged"
                    note "rendered (already current): ${dest/#$HOME/\$HOME}"
                    STATS_SKIPPED=$((STATS_SKIPPED + 1))
                    return 3
                fi
            fi
            ;;
        copy)
            if [ "$DRY_RUN" = 1 ]; then
                dry "copy  ${dest/#$HOME/\$HOME}"
                STATS_DEPLOYED=$((STATS_DEPLOYED + 1))
                return 0
            fi
            staged="$(mktemp)"
            if ! render_template "$abs_src" >"$staged" 2>/dev/null; then
                cp -p -- "$abs_src" "$staged"
            fi
            if [ -f "$dest" ] && cmp -s "$staged" "$dest"; then
                rm -f "$staged"
                note "copy (already current): ${dest/#$HOME/\$HOME}"
                STATS_SKIPPED=$((STATS_SKIPPED + 1))
                return 3
            fi
            ;;
        root)
            if [ "$DRY_RUN" = 1 ]; then
                dry "root  $dest"
                STATS_DEPLOYED=$((STATS_DEPLOYED + 1))
                return 0
            fi
            staged="$(mktemp)"
            if ! render_template "$abs_src" >"$staged" 2>/dev/null; then
                cp -p -- "$abs_src" "$staged"
            fi
            if [ -f "$dest" ] && cmp -s "$staged" "$dest" 2>/dev/null; then
                rm -f "$staged"
                note "root (already current): $dest"
                STATS_SKIPPED=$((STATS_SKIPPED + 1))
                return 3
            fi
            ;;
    esac

    # A real change is coming. Now it is safe — and correct — to snapshot.
    case "$mode" in
        root) backup_root "$dest" 2>/dev/null || true ;;
        *)     backup_file "$dest" 2>/dev/null || true ;;
    esac

    case "$mode" in
        link)
            if [ -n "$staged" ]; then
                install -m 0644 "$staged" "$dest" || { rm -f "$staged"; err "could not write $dest"; return 1; }
            else
                ln -sfn "$abs_src" "$dest"
            fi
            ;;
        copy)
            install -m 0644 "$staged" "$dest" || { rm -f "$staged"; err "could not write $dest"; return 1; }
            ;;
        root)
            if sudo install -D -m 0644 "$staged" "$dest" 2>/dev/null; then
                ok "root $dest written"
            else
                # SOFT failure. Returning 2, not dying.
                #
                # This entry used to call die(). That aborted the whole manifest
                # loop, so a declined or unavailable sudo — for a single /etc
                # file at the end of the list — silently skipped every entry
                # after it and still exited looking like a partial success. An
                # /etc file is not worth losing the rest of a desktop over; by
                # now the rest is already correct.
                warn "could not write $dest (sudo failed or was declined)"
                note "  this is a system file; everything else is unaffected."
                note "  to apply it by hand:"
                note "    sudo install -m 0644 $DOTFILES_ROOT/$src $dest"
                STATS_FAILED=$((STATS_FAILED + 1))
                rm -f "$staged"
                return 2
            fi
            ;;
    esac
    rm -f "$staged"
    [ "$rc" = 0 ] || return "$rc"

    if [ "$DRY_RUN" != 1 ]; then
        _record_deployed "$dest"
        # Hash what we just wrote, so restore.sh can tell an untouched file from
        # one the user has since edited. See record_written() in lib/backup.sh.
        record_written "$dest"
    fi
    STATS_DEPLOYED=$((STATS_DEPLOYED + 1))
    return 0
}

# ---------------------------------------------------------------------------
# deploy_all — walk the manifest.
# ---------------------------------------------------------------------------
deploy_all() {
    step "Configuration files"
    [ -f "$MANIFEST" ] || die "deploy.manifest not found at $MANIFEST"

    local mode src dest line lineno=0 applied=0 attempted=0 soft=0 kept=0 rc

    # The manifest is read on a dedicated file descriptor, NOT on stdin.
    #
    # With `done <"$MANIFEST"` the loop shares fd 0 with every command it runs,
    # so any of them that reads stdin — sed without a filename, sudo, a stray
    # `read` — silently eats the rest of the manifest. That happened here and
    # cost two thirds of the configuration. fd 3 makes it impossible.
    exec 3<"$MANIFEST"
    while IFS= read -r line <&3 || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        # strip comments and blanks
        line="${line%%#*}"
        line="$(printf '%s' "$line" | sed -e 's/[[:space:]]*$//')"
        [ -z "$line" ] && continue
        # shellcheck disable=SC2086
        set -- $line
        [ $# -lt 3 ] && { err "manifest line $lineno malformed: $line"; continue; }
        mode="$1"; src="$2"; dest="$3"

        if [ -n "${ONLY_SET:-}" ]; then
            case "$src $dest" in
                *$ONLY_SET*) : ;;
                *) continue ;;
            esac
        fi
        if [ -n "${SKIP_SET:-}" ]; then
            case "$src $dest" in
                *$SKIP_SET*) continue ;;
            esac
        fi

        attempted=$((attempted + 1))
        deploy_one "$mode" "$src" "$dest"
        rc=$?
        case "$rc" in
            0) applied=$((applied + 1)) ;;
            2) soft=$((soft + 1)) ;;   # warned about; the rest must still run
            3) kept=$((kept + 1)) ;;   # deliberately left alone
            *) err "failed to deploy $src -> $dest (exit $rc)"
               exec 3<&-
               return 1 ;;
        esac
    done
    exec 3<&-

    # A manifest that silently deployed only part of itself is the kind of bug
    # that leaves a half-configured desktop and no error message, so every entry
    # in the file is accounted for: applied, deliberately kept, or warned about.
    local expected
    expected="$(grep -cE '^(link|copy|seed|root)[[:space:]]' "$MANIFEST" 2>/dev/null || echo 0)"
    if [ -n "${ONLY_SET:-}${SKIP_SET:-}" ]; then
        ok "$applied file(s) deployed (filtered from $expected by --only/--skip)"
        return 0
    fi
    if [ "$attempted" -lt "$expected" ]; then
        err "only $attempted of $expected manifest entries were reached"
        note "this is a bug in the installer, not your machine. Re-run with --dry-run"
        note "and compare the entries it reports against deploy.manifest."
        return 1
    fi
    if [ "$soft" -gt 0 ]; then
        warn "$((applied + soft + kept)) of $expected entries handled: $applied deployed, $kept left alone, $soft failed (see above)"
        return 0
    fi
    if [ "$kept" -gt 0 ]; then
        ok "$applied file(s) deployed, $kept left alone (already correct, or never managed here)"
        return 0
    fi
    ok "$applied file(s) deployed"
    return 0
}
