#!/usr/bin/env bash
# lib/packages.sh — pacman transactions, AUR bootstrap, hardware tiers.
#
# Rules:
#   * pacman is ALWAYS invoked with --needed, so a re-run installs nothing.
#   * No package is ever REMOVED. Not as a dependency, not as a conflict
#     resolution, not implicitly. If pacman reports a conflict, we die and
#     print the manual command.
#   * The installer never runs as root; it calls sudo for the pacman call.

[ -n "${DOTFILES_PACKAGES_SH:-}" ] && return 0
DOTFILES_PACKAGES_SH=1

PKG_LIST_DIR="$DOTFILES_ROOT/packages"

# ---------------------------------------------------------------------------
# Install a list of packages. Prints the command it would run.
# ---------------------------------------------------------------------------
_pkgs_to_install() {
    local missing=() p
    for p in "$@"; do
        [ -z "$p" ] && continue
        have_pkg "$p" || missing+=("$p")
    done
    printf '%s\n' "${missing[@]:-}"
}

# pacman_install <label> <pkg...>
pacman_install() {
    local label="$1"; shift
    local todo=()
    while IFS= read -r p; do [ -n "$p" ] && todo+=("$p"); done < <(_pkgs_to_install "$@")
    [ ${#todo[@]} -eq 0 ] && return 0

    local list; list="$(printf '%s ' "${todo[@]}")"
    if [ "$DRY_RUN" = 1 ]; then
        dry "$label: $(printf '%s' "$list" | wc -w) package(s) -> $list"
        STATS_PACKAGES=$((STATS_PACKAGES + ${#todo[@]}))
        return 0
    fi
    info "$label: installing ${#todo[@]} package(s)"
    note "$list"
    if ! sudo pacman -S --needed --noconfirm "${todo[@]}" 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
        die "pacman failed while installing: $list
       The installer never removes packages. Resolve the conflict manually:
         sudo pacman -S ${todo[*]}"
    fi
    STATS_PACKAGES=$((STATS_PACKAGES + ${#todo[@]}))
    return 0
}

# ---------------------------------------------------------------------------
# AUR helper bootstrap. Uses an existing helper; otherwise clones and builds
# yay. yay is never assumed to be present.
# ---------------------------------------------------------------------------
aur_bootstrap() {
    detect_aur_helper
    if [ -n "$DETECT_AUR_HELPER" ]; then
        ok "using AUR helper: $DETECT_AUR_HELPER"
        return 0
    fi

    warn "no AUR helper found; bootstrapping yay"
    if [ "$DRY_RUN" = 1 ]; then
        dry "clone + build AUR/yay into /tmp (yay is then symlinked to /usr/local/bin/yay)"
        DETECT_AUR_HELPER="yay"
        return 0
    fi
    require_cmd git base-devel 2>/dev/null || true
    command -v git >/dev/null 2>&1 || die "git is required to bootstrap the AUR helper"
    command -v makepkg >/dev/null 2>&1 || die "base-devel (makepkg) is required to bootstrap the AUR helper"
    pacman -Qq base-devel >/dev/null 2>&1 || die "base-devel is required to bootstrap the AUR helper"

    local build; build="$(mktemp -d)"
    trap 'rm -rf "$build"' RETURN
    if ! git clone --depth 1 https://aur.archlinux.org/yay.git "$build/yay" >/dev/null 2>&1; then
        die "failed to clone https://aur.archlinux.org/yay.git
       Install an AUR helper manually, then re-run the installer."
    fi
    ( cd "$build/yay" && makepkg -si --noconfirm --needed ) \
        || die "failed to build yay. Install an AUR helper manually, then re-run."
    command -v yay >/dev/null 2>&1 || die "yay built but is not on PATH"
    DETECT_AUR_HELPER="yay"
    ok "AUR helper ready: yay"
    return 0
}

# ---------------------------------------------------------------------------
# aur_install <label> <pkg...>
# ---------------------------------------------------------------------------
aur_install() {
    local label="$1"; shift
    local helper="${DETECT_AUR_HELPER:-yay}"
    local todo=()
    while IFS= read -r p; do [ -n "$p" ] && todo+=("$p"); done < <(_pkgs_to_install "$@")
    [ ${#todo[@]} -eq 0 ] && return 0

    if [ "$DRY_RUN" = 1 ]; then
        dry "$label (AUR): ${todo[*]}"
        STATS_PACKAGES=$((STATS_PACKAGES + ${#todo[@]}))
        return 0
    fi
    info "$label: installing ${#todo[@]} AUR package(s): ${todo[*]}"
    if ! "$helper" -S --needed --noconfirm "${todo[@]}" 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
        die "AUR helper failed on: ${todo[*]}
       Nothing was removed. Fix the build manually with:
         cd ~/build && $helper -S ${todo[*]}"
    fi
    STATS_PACKAGES=$((STATS_PACKAGES + ${#todo[@]}))
    return 0
}

# ---------------------------------------------------------------------------
# packages_install_all — the full package phase.
# ---------------------------------------------------------------------------
packages_install_all() {
    # --skip-packages: deploy the configuration only, touch nothing else.
    #
    # A real feature, not just a testing hook. Some people manage their Arch
    # packages declaratively — chezmoi, a Puppet/Chef manifest, an image they
    # already built — and want the desktop configuration without a second tool
    # fighting over pacman. It is also the only way to exercise the config
    # pipeline on a machine where installing packages is not appropriate.
    #
    # What still runs: the package *lists* are read and reported, so the user
    # can see exactly what they are being asked to install by hand. Only the
    # installation itself is skipped. AUR bootstrapping is skipped too, since
    # its only purpose is to enable the install.
    if [ "${OPT_SKIP_PACKAGES:-0}" = 1 ]; then
        step "Packages: SKIPPED (--skip-packages)"
        local list n
        for list in core utilities aur-required; do
            n="$(read_list "$PKG_LIST_DIR/$list.txt" | wc -l)"
            [ "$n" -gt 0 ] || continue
            printf '     %s%-22s %3s package(s) NOT installed%s\n' \
                   "$C_DIM" "$list.txt" "$n" "$C_RESET"
            printf '       %spacman -S --needed %s%s\n' \
                   "$C_DIM" "$(read_list "$PKG_LIST_DIR/$list.txt" | tr '\n' ' ')" "$C_RESET"
        done
        for list in "$PKG_LIST_DIR"/hardware/*.txt; do
            [ -f "$list" ] || continue
            n="$(read_list "$list" | wc -l)"
            [ "$n" -gt 0 ] || continue
            printf '     %s%-22s %3s package(s), only if this hardware applies%s\n' \
                   "$C_DIM" "hardware/$(basename "$list")" "$n" "$C_RESET"
        done
        note "run ./verify.sh afterwards to list what is still missing"
        return 0
    fi

    step "Packages: core desktop"
    pacman_install "core"       $(read_list "$PKG_LIST_DIR/core.txt")

    step "Packages: desktop utilities"
    pacman_install "utilities"  $(read_list "$PKG_LIST_DIR/utilities.txt")

    step "Hardware detection"
    local tiers tierfile
    tiers="$(hardware_resolve_tiers)"
    if [ -z "$tiers" ]; then
        note "no hardware tiers apply"
    else
        while IFS= read -r tierfile; do
            [ -z "$tierfile" ] && continue
            [ -f "$PKG_LIST_DIR/hardware/$tierfile" ] || continue
            note "tier: $tierfile"
            pacman_install "$tierfile" $(read_list "$PKG_LIST_DIR/hardware/$tierfile")
            STATS_HARDWARE=$((STATS_HARDWARE + 1))
        done <<<"$tiers"
    fi

    # AUR is required for four packages that supply literal strings in shipped
    # config files (see packages/aur-required.txt).
    if [ -n "$(read_list "$PKG_LIST_DIR/aur-required.txt")" ]; then
        step "Packages: AUR (required)"
        aur_bootstrap
        aur_install "aur-required" $(read_list "$PKG_LIST_DIR/aur-required.txt")
    fi

    if [ "${OPT_EXTRAS:-0}" = 1 ]; then
        step "Packages: optional extras (--with-extras)"
        pacman_install "optional" $(read_list "$PKG_LIST_DIR/optional.txt")
        if [ -n "$(read_list "$PKG_LIST_DIR/aur-optional.txt")" ]; then
            aur_bootstrap
            aur_install "aur-optional" $(read_list "$PKG_LIST_DIR/aur-optional.txt")
        fi
    fi

    # Anything the user pinned in ~/.config/dotfiles/local.conf. Sourced as a
    # plain shell array, so it can hold either repo or AUR packages.
    if [ -n "${EXTRA_PACKAGES[*]:-}" ]; then
        step "Packages: EXTRA_PACKAGES (from local.conf)"
        note "${EXTRA_PACKAGES[*]}"
        pacman_install "local.conf" "${EXTRA_PACKAGES[@]}"
    fi

    return 0
}

# ---------------------------------------------------------------------------
# packages_ensure_groups — supplementary groups the desktop needs.
# Never removes a user from a group.
# ---------------------------------------------------------------------------
packages_ensure_groups() {
    step "Groups"
    if [ "${OPT_SKIP_PACKAGES:-0}" = 1 ]; then
        note "skipped (--skip-packages): you are not a member of every group the"
        note "desktop needs. Check with:  id -nG | tr ' ' '\\n' | grep -E 'video|input|audio|render|seat'"
        return 0
    fi
    local want=(video input audio render seat wheel) have=() missing=()
    mapfile -t have < <(id -nG "$TARGET_USER" 2>/dev/null | tr ' ' '\n')
    for g in "${want[@]}"; do
        printf '%s\n' "${have[@]}" | grep -qx "$g" || missing+=("$g")
    done
    if [ ${#missing[@]} -eq 0 ]; then
        ok "all required groups already present"
        return 0
    fi
    if [ "$DRY_RUN" = 1 ]; then
        dry "usermod -aG ${missing[*]} $TARGET_USER"
        return 0
    fi
    confirm "Add $TARGET_USER to: ${missing[*]}?" || { note "skipped group changes"; return 0; }
    sudo usermod -aG "${missing[*]}" "$TARGET_USER" || die "usermod failed"
    ok "groups updated: ${missing[*]} (log out and back in for them to take effect)"
    return 0
}

# ---------------------------------------------------------------------------
# packages_set_login_shell
# ---------------------------------------------------------------------------
packages_set_login_shell() {
    step "Login shell"
    local current; current="$(getent passwd "$TARGET_USER" | cut -d: -f7)"
    if [ "${OPT_NO_CHSH:-0}" = 1 ]; then
        note "skipped (--no-chsh); current shell is $current"
        return 0
    fi
    if [ "${OPT_SKIP_PACKAGES:-0}" = 1 ]; then
        note "skipped (--skip-packages); current shell is ${current:-unknown}"
        note "  once fish is installed:  chsh -s /usr/bin/fish $TARGET_USER"
        return 0
    fi
    if [ "$current" = "/usr/bin/fish" ]; then
        ok "login shell is already fish"
        return 0
    fi
    if ! have_pkg fish; then
        warn "fish is not installed; cannot set the login shell"
        return 0
    fi
    if [ "$DRY_RUN" = 1 ]; then
        dry "chsh -s /usr/bin/fish $TARGET_USER"
        return 0
    fi
    confirm "Change the login shell for $TARGET_USER from '${current:-unknown}' to /usr/bin/fish?" \
        || { note "login shell unchanged"; return 0; }
    sudo chsh -s /usr/bin/fish "$TARGET_USER" || die "chsh failed"
    ok "login shell set to /usr/bin/fish"
    return 0
}

# ---------------------------------------------------------------------------
# packages_assert_service_disabled
#
# These five units must never run in this desktop. dms/quickshell/dunst would
# compete with Noctalia for org.freedesktop.Notifications; hypridle and
# cliphist would fight Noctalia's own idle handling and clipboard manager.
# A second notification daemon or clipboard watcher on the same bus is the
# single most common cause of "notifications stop appearing" in this setup.
# ---------------------------------------------------------------------------
MUST_BE_DISABLED=(dms.service dunst.service quickshell.service hypridle.service cliphist.service)

packages_assert_service_disabled() {
    step "Asserting conflicting services are disabled"
    local u state changed=0
    for u in "${MUST_BE_DISABLED[@]}"; do
        # Only units that actually exist on this machine are considered.
        if ! systemctl --user list-unit-files "$u" >/dev/null 2>&1 \
           || ! systemctl --user list-unit-files "$u" 2>/dev/null | grep -q "^$u"; then
            continue
        fi
        state="$(unit_state "$u" user)"
        case "$state" in
            disabled|masked|static|not-found) ok "$u is $state" ;;
            enabled|linked|alias|indirect|enabled-runtime)
                if [ "${OPT_STRICT:-0}" = 1 ]; then
                    if [ "$DRY_RUN" = 1 ]; then
                        dry "systemctl --user mask $u  (--strict)"
                    else
                        systemctl --user mask "$u" >/dev/null 2>&1 \
                            && { ok "masked $u (it would break Noctalia's notifications/clipboard)"; changed=1; } \
                            || warn "could not mask $u; disable it manually: systemctl --user disable --now $u"
                    fi
                else
                    warn "$u is $state and will fight Noctalia. Run: systemctl --user disable --now $u   (or re-run with --strict)"
                fi
                ;;
        esac
    done
    [ "$changed" = 1 ] && note "log out and back in for the unit masks to take effect"
    return 0
}

# ---------------------------------------------------------------------------
# packages_enable_services — system units the desktop needs.
# niri.service is deliberately NOT touched: it is a static unit started by
# niri-session via SDDM, and enabling or disabling it breaks the session.
# ---------------------------------------------------------------------------
packages_enable_services() {
    step "System services"
    if [ "${OPT_SKIP_PACKAGES:-0}" = 1 ]; then
        note "skipped (--skip-packages): nothing was enabled"
        note "  these are normally already enabled by their packages; check with:"
        note "    systemctl is-enabled NetworkManager bluetooth power-profiles-daemon"
        return 0
    fi
    local units=(NetworkManager.service NetworkManager-wait-online.service bluetooth.service power-profiles-daemon.service)
    [ "${OPT_EXTRAS:-0}" = 1 ] && have_pkg firewalld && units+=(firewalld.service)
    local u
    for u in "${units[@]}"; do
        if ! systemctl list-unit-files "$u" >/dev/null 2>&1 \
           || ! systemctl list-unit-files "$u" 2>/dev/null | grep -q "^$u"; then
            continue
        fi
        if systemctl is-enabled "$u" >/dev/null 2>&1; then
            ok "$u already enabled"
            continue
        fi
        if [ "$DRY_RUN" = 1 ]; then
            dry "systemctl enable $u"
            continue
        fi
        sudo systemctl enable "$u" >/dev/null 2>&1 && ok "enabled $u" || warn "could not enable $u"
    done
    note "niri.service is intentionally left untouched (static unit, started by SDDM via niri-session)"
    return 0
}
