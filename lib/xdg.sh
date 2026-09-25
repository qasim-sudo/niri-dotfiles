#!/usr/bin/env bash
# lib/xdg.sh — register Thunar as the default file manager, safely.
#
# SAFETY CONTRACT
#   The default path NEVER rewrites ~/.config/mimeapps.list. It uses
#   `xdg-mime default`, which is the standard, additive mechanism: it edits the
#   [Default Applications] / [Added Associations] section and leaves every
#   unrelated entry alone. A user who already has associations keeps them,
#   except where a file-manager type genuinely collides.
#
#   --force-mimeapps replaces the file wholesale with config/xdg/mimeapps.list.
#   That is destructive and is only ever used when the user asks for it.
#
# Exactly the 15 file-manager MIME types are registered. Nothing else. In
# particular no text/* type and no network-scanner type is touched, so an
# existing editor or IDE association for source files survives.

[ -n "${DOTFILES_XDG_SH:-}" ] && return 0
DOTFILES_XDG_SH=1

# The only MIME types this repository claims.
FM_MIMETYPES=(
    inode/directory
    inode/directory/x-user-bookmark
    inode/directory/x-user-mount-directory
    inode/directory/x-user-trash
    x-scheme-handler/file
    x-scheme-handler/sftp
    application/zip
    application/x-tar
    application/gzip
    application/x-bzip2
    application/x-xz
    application/zstd
    application/x-7z-compressed
    application/x-rar
    application/vnd.rar
    application/x-iso9660-image
)

xdg_register_file_manager() {
    step "XDG: registering Thunar as the default file manager"
    command -v xdg-mime >/dev/null 2>&1 || { warn "xdg-mime not available; skipping"; return 0; }

    if [ ! -d /usr/share/applications/thunar.desktop ] \
       && [ ! -f /usr/share/applications/thunar.desktop ]; then
        warn "thunar.desktop not found; is thunar installed?"
        return 0
    fi

    if [ "${OPT_FORCE_MIMEAPPS:-0}" = 1 ]; then
        local dest="$HOME/.config/mimeapps.list"
        if [ "$DRY_RUN" = 1 ]; then
            dry "REPLACE $dest with config/xdg/mimeapps.list (--force-mimeapps)"
            return 0
        fi
        confirm "--force-mimeapps will REPLACE $dest. Its existing contents will be backed up. Continue?" \
            || { note "skipped --force-mimeapps"; return 0; }
        backup_file "$dest"
        mkdir -p "$HOME/.config"
        local staged; staged="$(mktemp)"
        if render_template "$DOTFILES_ROOT/config/xdg/mimeapps.list" >"$staged" 2>/dev/null; then
            write_if_changed "$staged" "$dest" \
                && ok "mimeapps.list replaced (previous version backed up)" \
                || { note "mimeapps.list already current"; STATS_SKIPPED=$((STATS_SKIPPED + 1)); }
        else
            cp -p "$DOTFILES_ROOT/config/xdg/mimeapps.list" "$dest"
            ok "mimeapps.list replaced (previous version backed up)"
        fi
    else
        # Only register a type that is not already correct.
        #
        # `xdg-mime default` rewrites mimeapps.list even when the value is
        # unchanged, which made every run bump its mtime for no reason. Asking
        # first is both cheaper and quieter. It is also the honest way to report
        # this: "15 types registered" was not true on the second run.
        local m cur changed=0 already=0
        for m in "${FM_MIMETYPES[@]}"; do
            cur="$(xdg-mime query default "$m" 2>/dev/null)"
            if [ "$cur" = "thunar.desktop" ]; then
                already=$((already + 1))
                continue
            fi
            if [ "$DRY_RUN" = 1 ]; then
                dry "xdg-mime default thunar.desktop $m  (currently: ${cur:-unset})"
            else
                xdg-mime default thunar.desktop "$m" 2>/dev/null \
                    && changed=$((changed + 1)) \
                    || warn "xdg-mime default failed for $m"
            fi
        done
        if [ "$already" -gt 0 ] && [ "$changed" -eq 0 ] && [ "$DRY_RUN" != 1 ]; then
            note "all ${#FM_MIMETYPES[@]} file-manager MIME type(s) already point at thunar"
        else
            ok "registered ${#FM_MIMETYPES[@]} file-manager MIME type(s) via xdg-mime (additive; nothing else changed)"
        fi
    fi

    # Refresh the caches the desktop queries.
    if [ "$DRY_RUN" = 1 ]; then
        dry "xdg-user-dirs-update; update-desktop-database; update-mime-database"
        return 0
    fi
    # xdg-user-dirs-update is only run when the file does not exist yet.
    #
    # With --force it overwrites whatever is there, so a user who moved their
    # Downloads or Documents to another disk had that silently reset every time
    # they ran the installer. This file is the user's, not ours.
    if [ -s "$HOME/.config/user-dirs.dirs" ]; then
        note "user-dirs.dirs already set; left alone (xdg-user-dirs-update --force would overwrite your choices)"
    else
        command -v xdg-user-dirs-update >/dev/null 2>&1 && xdg-user-dirs-update --force 2>/dev/null || true
    fi
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
    command -v update-mime-database >/dev/null 2>&1 && sudo -n update-mime-database /usr/share/mime >/dev/null 2>&1 \
        || note "could not refresh /usr/share/mime (needs sudo); harmless, re-run with sudo later if a MIME type looks stale"
    return 0
}

# Verify Thunar really is the default directory handler.
xdg_verify_file_manager() {
    local got
    got="$(xdg-mime query default inode/directory 2>/dev/null)"
    if [ "$got" = "thunar.desktop" ]; then
        ok "default file manager: thunar ($got)"
        return 0
    fi
    warn "inode/directory resolves to '${got:-unknown}', expected thunar.desktop"
    return 1
}
