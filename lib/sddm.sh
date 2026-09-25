#!/usr/bin/env bash
# lib/sddm.sh — SDDM + SilentSDDM KEN login screen.
#
# The fragile part: /usr/share/sddm/themes/silent/metadata.desktop is a
# pacman-owned file that must be hand-patched to select the KEN variant
# (ConfigFile=configs/ken.conf). Any upgrade of sddm-silent-theme reverts it.
# The patch is therefore applied idempotently on every install AND re-checked
# by verify.sh, which is the only way this stays correct over time.
#
# The installer never touches the bootloader. If SDDM is not the display
# manager you use, pass --enable-sddm or leave it alone.

[ -n "${DOTFILES_SDDM_SH:-}" ] && return 0
DOTFILES_SDDM_SH=1

SDDM_THEME_DIR="/usr/share/sddm/themes/silent"

# ---------------------------------------------------------------------------
# sddm_patch_theme — point metadata.desktop at the KEN config.
# Idempotent: safe to run on every install.
# ---------------------------------------------------------------------------
sddm_patch_theme() {
    step "SDDM: SilentSDDM KEN login theme"

    if [ ! -d "$SDDM_THEME_DIR" ]; then
        warn "$SDDM_THEME_DIR not found. Is sddm-silent-theme installed? (it is in packages/aur-required.txt)"
        return 1
    fi
    if [ ! -f "$SDDM_THEME_DIR/configs/ken.conf" ]; then
        warn "$SDDM_THEME_DIR/configs/ken.conf not found; the KEN variant is unavailable in this theme version"
        return 1
    fi

    local meta="$SDDM_THEME_DIR/metadata.desktop"
    local staged="/tmp/.dotfiles-metadata.$$"
    backup_root "$meta" 2>/dev/null || true

    if [ "$DRY_RUN" = 1 ]; then
        dry "patch $meta -> ConfigFile=configs/ken.conf (idempotent)"
        return 0
    fi

    # Uncomment every ConfigFile variant, then set exactly one active line to
    # ken.conf. Doing it in this order means the result does not depend on how
    # the file looked before.
    sed -e 's/^[#[:space:]]*ConfigFile=/ConfigFile=/' "$meta" >"$staged" \
        || { rm -f "$staged"; die "could not read $meta"; }

    if grep -q '^ConfigFile=' "$staged"; then
        # Comment out all active lines, then append the one we want.
        sed -i 's/^ConfigFile=/#ConfigFile=/' "$staged"
        printf 'ConfigFile=configs/ken.conf\n' >>"$staged"
    else
        printf 'ConfigFile=configs/ken.conf\n' >>"$staged"
    fi

    if ! sudo install -m 0644 "$staged" "$meta"; then
        rm -f "$staged"
        # Warn, do not die. By the time this runs the whole desktop config is
        # already deployed and working; aborting here over a login-screen
        # nicety leaves a working desktop and a non-zero exit code, which reads
        # as "the install failed" and sends people looking in the wrong place.
        # The file is pacman-owned, so the patch also has to be reapplied after
        # every sddm-silent-theme upgrade regardless — see docs/TROUBLESHOOTING.
        warn "could not write $meta (sudo failed or was declined)"
        note "the login screen will use the theme's default variant, not KEN."
        note "to apply it by hand:"
        note "  sudo sed -i 's/^#\\{0,1\\}ConfigFile=.*/ConfigFile=configs\\/ken.conf/' $meta"
        note "and re-run ./install.sh, or ./verify.sh, after upgrading"
        note "sddm-silent-theme — the upgrade reverts this patch every time."
        return 1
    fi
    rm -f "$staged"
    ok "metadata.desktop patched: ConfigFile=configs/ken.conf"
    return 0
}

# ---------------------------------------------------------------------------
# sddm_enable — only when asked, or when it is already the only display manager.
# ---------------------------------------------------------------------------
sddm_enable() {
    step "SDDM: display manager"
    if systemctl is-enabled sddm.service >/dev/null 2>&1; then
        ok "sddm.service already enabled"
        return 0
    fi
    if [ "${OPT_ENABLE_SDDM:-0}" != 1 ]; then
        local others
        others="$(systemctl list-unit-files '*.service' 2>/dev/null \
            | grep -oE '^(gdm|lightdm|ly|lynis|xfce4-session-manager|weston|plasma-login)\.service' \
            | sort -u | tr '\n' ' ')"
        if [ -n "$others" ]; then
            warn "another display manager is enabled ($others). Not touching it. Pass --enable-sddm to switch."
            return 0
        fi
        warn "sddm is not enabled. Pass --enable-sddm to enable it now, or enable it yourself before logging out."
        return 0
    fi
    if [ "$DRY_RUN" = 1 ]; then
        dry "systemctl enable sddm.service"
        return 0
    fi
    confirm "Enable sddm as the display manager? You will be prompted for a password at the next boot." \
        || { note "sddm not enabled"; return 0; }
    sudo systemctl enable sddm.service && ok "sddm enabled" || die "could not enable sddm"
    note "if you are not currently logged in graphically, verify you can still log in before rebooting"
    return 0
}

# ---------------------------------------------------------------------------
sddm_verify() {
    local meta="$SDDM_THEME_DIR/metadata.desktop"
    [ -f "$meta" ] || { warn "SilentSDDM theme metadata.desktop missing"; return 1; }
    if grep -q '^ConfigFile=configs/ken.conf$' "$meta"; then
        ok "SDDM theme is set to KEN"
        return 0
    fi
    warn "SDDM theme is NOT set to KEN (a theme upgrade reverted metadata.desktop). Fix with: sudo ~/dotfiles/install.sh --only=sddm"
    return 1
}
