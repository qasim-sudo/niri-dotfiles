#!/usr/bin/env bash
# install.sh — reproducible Arch + Niri + Noctalia desktop installer.
#
#   git clone <this repo> && cd <repo> && ./install.sh
#
# Read the README before running. Run with --dry-run first if you like; it
# performs no writes at all.
#
# This installer:
#   * never runs as root (it calls sudo where it needs privilege)
#   * never removes a package
#   * never touches the bootloader, grub, or efibootmgr
#   * never overwrites a file it has not previously managed, unless --force
#   * backs up every path it is about to change, before changing it
#   * is idempotent: a second run installs nothing and changes nothing
#
# Exit status: 0 on success, non-zero if any phase failed.

set -uo pipefail

DOTFILES_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
export DOTFILES_ROOT

# shellcheck source=lib/common.sh
. "$DOTFILES_ROOT/lib/common.sh"
. "$DOTFILES_ROOT/lib/detect.sh"
. "$DOTFILES_ROOT/lib/hardware.sh"
. "$DOTFILES_ROOT/lib/packages.sh"
. "$DOTFILES_ROOT/lib/backup.sh"
. "$DOTFILES_ROOT/lib/deploy.sh"
. "$DOTFILES_ROOT/lib/xdg.sh"
. "$DOTFILES_ROOT/lib/noctalia.sh"
. "$DOTFILES_ROOT/lib/sddm.sh"

# ===========================================================================
# Defaults for every flag. Overridden below.
# ===========================================================================
DRY_RUN=0
FORCE=0
OPT_EXTRAS=0
OPT_NOCTALIA_PLUGINS=0
OPT_WITH_WALLPAPERS=0
OPT_NO_CHSH=0
OPT_FORCE_MIMEAPPS=0
OPT_ENABLE_SDDM=0
OPT_NVIDIA=0
OPT_STRICT=0
OPT_BACKUP_ONLY=0
OPT_SKIP_PACKAGES=0
ONLY_SET=""
SKIP_SET=""
# TARGET_USER, WALLPAPER_DIR, ASSETS_DIR and LOCAL_CONF come from lib/common.sh,
# so verify.sh / regenerate.sh / restore.sh / uninstall.sh see the same values.

# ===========================================================================
usage() {
    cat <<'USAGE_TEXT'
install.sh — Arch + Niri + Noctalia desktop

USAGE
    ./install.sh [options]
    bash install.sh [options]

MODES
    --dry-run           Print every action, change nothing. Start here.
    --backup-only       Take a snapshot of everything that would change, then stop.
    --force             Answer yes to every confirmation and overwrite files
                        this repository has not managed before.

SCOPE
    --with-extras       Also install packages/optional.txt and aur-optional.txt.
    --with-noctalia-plugins
                        Also enable the optional Noctalia plugins (implies
                        --with-extras for their dependencies).
    --with-wallpapers   Copy wallpapers/current/ into your wallpaper directory.

SELECTIVE
    --only=SUBSTR       Only deploy manifest entries matching SUBSTR.
    --skip=SUBSTR       Skip manifest entries matching SUBSTR.
    --skip-packages     Deploy the configuration only. Install no packages,
                        change no groups, no login shell, no system services.
                        For people who manage Arch declaratively elsewhere.
                        The package lists are still printed so you know what to
                        install by hand; ./verify.sh then lists what is missing.
    --no-chsh           Do not change the login shell.
    --force-mimeapps    REPLACE ~/.config/mimeapps.list instead of adding to it.
                        Backs up the old file first. Asks for confirmation.

HARDWARE
    --nvidia            Install the proprietary NVIDIA driver on an NVIDIA GPU.
                        Without this, an NVIDIA machine gets a warning and no
                        driver from this repository.

SYSTEM
    --enable-sddm       Enable sddm as the display manager. Without this, the
                        installer will not change your display manager.
    --strict            Mask (not merely warn about) dms/dunst/quickshell/
                        hypridle/cliphist user units that are enabled.
    --user=NAME         Operate on NAME's home instead of the current user.
    --repo=DIR          Use DIR as the repository root (for testing).

SAFETY
    The installer never runs as root, never removes a package, never touches the
    bootloader, and never overwrites a file it has not previously managed.
USAGE_TEXT
    exit "${1:-0}"
}

# ===========================================================================
# Argument parsing
# ===========================================================================
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)      usage 0 ;;
        --dry-run)      DRY_RUN=1 ;;
        --backup-only)  OPT_BACKUP_ONLY=1 ;;
        --force)        FORCE=1 ;;
        --with-extras)  OPT_EXTRAS=1 ;;
        --with-noctalia-plugins) OPT_NOCTALIA_PLUGINS=1; OPT_EXTRAS=1 ;;
        --with-wallpapers) OPT_WITH_WALLPAPERS=1 ;;
        --no-chsh)      OPT_NO_CHSH=1 ;;
        --force-mimeapps) OPT_FORCE_MIMEAPPS=1 ;;
        --enable-sddm)  OPT_ENABLE_SDDM=1 ;;
        --nvidia)       OPT_NVIDIA=1 ;;
        --strict)       OPT_STRICT=1 ;;
        --skip-packages) OPT_SKIP_PACKAGES=1 ;;
        --only=*)       ONLY_SET="${1#*=}" ;;
        --skip=*)       SKIP_SET="${1#*=}" ;;
        --user=*)       TARGET_USER="${1#*=}" ;;
        --repo=*)       DOTFILES_ROOT="${1#*=}" ;;
        *)              err "unknown option: $1"; printf '\n'; usage 1 ;;
    esac
    shift
done

# ===========================================================================
# 0. Preflight
# ===========================================================================
_log_init
banner

assert_not_root
[ "$(id -un)" = "$TARGET_USER" ] || {
    # --user=NAME means we act on someone else's home. Warn loudly.
    warn "targeting $TARGET_USER's home, but running as $(id -un)"
}

[ "$DETECT_ID" = "arch" ] || . /etc/os-release 2>/dev/null
[ "${ID:-}" = "arch" ] || die "this installer targets Arch Linux; /etc/os-release reports ID='${ID:-unknown}'"
case "$(uname -m)" in
    x86_64|aarch64) : ;;
    *) die "unsupported architecture: $(uname -m)" ;;
esac
ok "preflight passed (Arch, $(uname -m), running as $TARGET_USER)"

if [ "$DRY_RUN" = 1 ]; then
    printf '%s*** DRY RUN — nothing will be written ***%s\n\n' "$C_YELLOW$C_BOLD" "$C_RESET"
fi

# Load machine-local settings last, so they win over every default above.
if [ -f "$LOCAL_CONF" ]; then
    note "reading $LOCAL_CONF"
fi
load_local_conf
export WALLPAPER_DIR ASSETS_DIR

# ===========================================================================
# 1. Detect
# ===========================================================================
detect_all
detect_report

# ===========================================================================
# 2. Packages
# ===========================================================================
if [ "$OPT_BACKUP_ONLY" = 1 ]; then
    step "Backup-only mode"
    note "no packages will be installed; snapshotting the paths that would change"
else
    packages_install_all
fi

packages_ensure_groups

if [ "$OPT_BACKUP_ONLY" != 1 ]; then
    packages_set_login_shell
fi

# ===========================================================================
# 3. Directories and wallpaper
# ===========================================================================
step "Directories"
for d in "$WALLPAPER_DIR" "$HOME/Pictures/Screenshots" "$ASSETS_DIR" \
         "$HOME/.config/dotfiles"; do
    if [ -d "$d" ]; then
        note "have ${d/#$HOME/\$HOME}"
    else
        run "create $d" -- mkdir -p "$d"
    fi
done

if [ "$OPT_WITH_WALLPAPERS" = 1 ] || [ "$OPT_BACKUP_ONLY" = 0 ]; then
    step "Wallpaper"
    _shopt_nullglob 2>/dev/null || true
    wall_found=0
    for w in "$DOTFILES_ROOT"/wallpapers/current/*; do
        [ -f "$w" ] || continue
        wall_found=1
        base="$(basename "$w")"
        if [ -f "$WALLPAPER_DIR/$base" ]; then
            note "already present: $base"
        else
            run "install wallpaper $base" -- install -m 0644 "$w" "$WALLPAPER_DIR/$base"
        fi
    done
    [ "$wall_found" = 1 ] || note "no wallpaper in wallpapers/current/"
    note "the theme derives its palette from the active wallpaper, so any image works"
fi

# ===========================================================================
# 4. Deploy configuration files
# ===========================================================================
deploy_all

# ===========================================================================
# 5. Generate per-host configuration
# ===========================================================================
hardware_generate_output
noctalia_generate_settings
noctalia_apply_plugins

# ===========================================================================
# 6. XDG: Thunar as the default file manager
# ===========================================================================
xdg_register_file_manager

# ===========================================================================
# 7. SDDM
# ===========================================================================
sddm_patch_theme
sddm_enable

# ===========================================================================
# 8. Services
# ===========================================================================
if [ "$OPT_BACKUP_ONLY" != 1 ]; then
    packages_enable_services
fi
packages_assert_service_disabled

# ===========================================================================
# 9. Finalise the backup snapshot
# ===========================================================================
backup_close

# ===========================================================================
# 10. Verify
# ===========================================================================
step "Verification"
VERIFY_FAILED=0

verify_cmd() { # description, command...
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        ok "$desc"
    else
        warn "$desc FAILED"
        VERIFY_FAILED=$((VERIFY_FAILED + 1))
    fi
}

# --- niri config -----------------------------------------------------------
if [ "$DETECT_NIRI_RUNNING" = 1 ] && command -v niri >/dev/null 2>&1; then
    if niri validate >/dev/null 2>&1; then
        ok "niri config is valid"
    else
        warn "niri validate failed:"
        niri validate 2>&1 | sed 's/^/        /'
        VERIFY_FAILED=$((VERIFY_FAILED + 1))
    fi
else
    niri validate -c "$HOME/.config/niri/config.kdl" >/dev/null 2>&1 \
        && ok "niri config is valid (checked offline)" \
        || { warn "niri config is invalid"; VERIFY_FAILED=$((VERIFY_FAILED + 1)); }
fi

# --- noctalia config -------------------------------------------------------
if [ "$DRY_RUN" = 1 ]; then
    noctalia_verify "repository copy, what a real run would install" || VERIFY_FAILED=$((VERIFY_FAILED + 1))
else
    noctalia_verify "deployed config" || VERIFY_FAILED=$((VERIFY_FAILED + 1))
fi

# --- login shell -----------------------------------------------------------
got_shell="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f7)"
[ "$got_shell" = "/usr/bin/fish" ] \
    && ok "login shell: /usr/bin/fish" \
    || { note "login shell is ${got_shell:-unknown} (use --no-chsh to keep it that way)"; }

# --- default file manager --------------------------------------------------
xdg_verify_file_manager || VERIFY_FAILED=$((VERIFY_FAILED + 1))

# --- fonts and theme providers --------------------------------------------
verify_cmd "font: Adwaita Sans"            fc-match -f '%{family[0]}' "Adwaita Sans"
verify_cmd "font: JetBrainsMono Nerd Font"  fc-match -f '%{family[0]}' "JetBrainsMono Nerd Font Mono"
verify_cmd "cursor: Bibata-Modern-Classic" fc-match -f '%{family[0]}' "Bibata-Modern-Classic"
verify_cmd "icons: Papirus-Dark"           test -d /usr/share/icons/Papirus-Dark
verify_cmd "gtk theme: adw-gtk3-dark"      test -d /usr/share/themes/adw-gtk3-dark

# --- keybinding targets ----------------------------------------------------
# Every binary a shipped keybinding invokes must be present, and the PACKAGE
# that provides it must be EXPLICITLY installed.
#
# Two failure modes, and the second is the subtler one:
#
#   not installed at all     -> the binding is dead
#   installed as a dependency -> nothing looks wrong, but an unrelated upgrade
#                                 that drops the dependency removes the binary and
#                                 silently breaks the binding
#
# The map below is binary -> package, because they are often not the same name.
# `wpctl` is the obvious one: it is not a package, it is a binary from
# `wireplumber`. Checking it with `pacman -Qq wpctl` would report a package that
# does not exist and suggest a `pacman -S wpctl` that cannot work.
echo
note "keybinding targets (binary present, package explicitly installed):"
while read -r bin pkg; do
    [ -n "$bin" ] || continue
    case "$bin" in '#'*) continue ;; esac

    if ! command -v "$bin" >/dev/null 2>&1; then
        warn "  $bin is NOT installed — a keybinding will fail"
        note "      sudo pacman -S --needed $pkg"
        VERIFY_FAILED=$((VERIFY_FAILED + 1))
        continue
    fi

    if ! pacman -Qq "$pkg" >/dev/null 2>&1; then
        warn "  $bin exists but $pkg is not installed as a package"
        note "      sudo pacman -S --needed $pkg"
        VERIFY_FAILED=$((VERIFY_FAILED + 1))
    elif ! explicit_pkg "$pkg"; then
        warn "  $bin is only a dependency of something else. Make it explicit:"
        note "      sudo pacman -S --needed $pkg"
    else
        printf '      %s%-16s%s %s\n' "$C_DIM" "$bin" "$C_RESET" "$pkg"
    fi
done <<'KEYBIND_TARGETS'
kitty          kitty
fuzzel         fuzzel
thunar         thunar
swaylock       swaylock
noctalia       noctalia
playerctl      playerctl
brightnessctl  brightnessctl
wpctl          wireplumber
KEYBIND_TARGETS

# Every binary named in binds.kdl, checked against the filesystem. This catches
# anything added to binds.kdl without adding it to the map above.
missing_cmds="$(grep -oE 'spawn(-sh)? "[^"]+"' "$DOTFILES_ROOT/config/niri/cfg/binds.kdl" 2>/dev/null \
    | sed -E 's/.*"([^"]+)"/\1/' | awk '{print $1}' | sort -u \
    | while read -r c; do
          case "$c" in *@*|'') continue ;; esac
          command -v "$c" >/dev/null 2>&1 || printf '%s\n' "$c"
      done)"
if [ -n "$missing_cmds" ]; then
    for c in $missing_cmds; do
        warn "  binds.kdl spawns '$c', which is not on PATH"
        VERIFY_FAILED=$((VERIFY_FAILED + 1))
    done
else
    ok "every command in binds.kdl resolves"
fi

# --- SDDM theme ------------------------------------------------------------
sddm_verify || warn "SDDM theme may need re-patching (see docs/TROUBLESHOOTING.md)"

# --- leak check ------------------------------------------------------------
# The tracked sources must contain no account name, hostname, interface name or
# credential. Documentation prose is deliberately NOT scanned: docs/ quotes the
# strings it explains were removed, and README.md contains the clone URL.
step "Leak check"
leak_check "tracked sources" "${LEAK_SCAN_PATHS[@]}" || VERIFY_FAILED=$((VERIFY_FAILED + 1))

# --- deployed config sanity -------------------------------------------------
# The generated files must describe THIS machine and only this machine. An
# absolute /home/<someone> that is not you would mean the file was copied from
# somewhere instead of generated here.
step "Generated config sanity"
for f in "$HOME/.config/niri/cfg/output.kdl" "$HOME/.local/state/noctalia/settings.toml"; do
    if [ ! -f "$f" ]; then
        warn "missing: ${f/#$HOME/\$HOME}"
        continue
    fi
    bad="$(grep -noE '/home/[A-Za-z0-9._-]+' "$f" 2>/dev/null | grep -vF "/home/$TARGET_USER" || true)"
    if [ -n "$bad" ]; then
        err "${f/#$HOME/\$HOME} contains an absolute path to another account:"
        printf '%s\n' "$bad" | sed 's/^/        /'
        VERIFY_FAILED=$((VERIFY_FAILED + 1))
    else
        ok "${f/#$HOME/\$HOME} is clean"
    fi
done

# ===========================================================================
# Summary
# ===========================================================================
print_summary

if [ "$VERIFY_FAILED" -gt 0 ]; then
    err "$VERIFY_FAILED verification check(s) failed — see above"
fi

if [ "$DRY_RUN" = 1 ]; then
    printf '%sDry run complete. Nothing was changed.%s\n' "$C_BOLD" "$C_RESET"
    printf 'Re-run without --dry-run to apply.\n\n'
    exit 0
fi

if [ "$OPT_BACKUP_ONLY" = 1 ]; then
    printf 'Backup-only run complete. No packages installed, no files deployed.\n'
    printf 'Restore with:  ./restore.sh --latest\n\n'
    exit "$VERIFY_FAILED"
fi

cat <<'NEXT'

  Next steps
  ----------
  1. Log out and back in. Required for the new group memberships, the login
     shell, and the enabled/disabled user units to take effect.

  2. If SDDM was not already enabled and you want it at next boot:
         sudo systemctl enable sddm
     Verify you can still log in graphically before rebooting.

  3. Regenerate the per-host config after changing monitors:
         ./regenerate.sh

  4. To undo everything this repository wrote:
         ./uninstall.sh
     To restore just the last snapshot:
         ./restore.sh --latest

NEXT
exit "$VERIFY_FAILED"
