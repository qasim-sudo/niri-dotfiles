#!/usr/bin/env bash
# lib/detect.sh — portable environment detection.
#
# Everything here is derived from the running machine. No hostname, username,
# monitor name, interface name, GPU model or resolution is ever hard-coded in
# the repository; it is all discovered at install time.
#
# Sourced by install.sh / uninstall.sh / verify.sh.

[ -n "${DOTFILES_DETECT_SH:-}" ] && return 0
DOTFILES_DETECT_SH=1

# Populated by the detect_* functions below.
DETECT_ID=""            # arch | other
DETECT_ARCH=""          # x86_64 | aarch64
DETECT_KERNEL=""
DETECT_SESSION=""       # wayland | tty | headless
DETECT_SESSION_TYPE=""  # wayland | x11
DESKTOP_CURRENT=""      # $XDG_CURRENT_DESKTOP
DETECT_AUR_HELPER=""    # yay | paru | pikaur | ""
DETECT_GPU_VENDOR=""    # intel | amd | nvidia | nouveau | unknown
DETECT_GPU_DRIVER=""    # i915 | xe | amdgpu | nvidia | nouveau | ""
DETECT_GPU_NAME=""
DETECT_CPU_VENDOR=""    # GenuineIntel | AuthenticAMD | other
DETECT_MACHINE_KIND=""  # laptop | desktop
DETECT_HAS_BACKLIGHT=0
DETECT_HAS_SOF=0
DETECT_DEFAULT_IFACE=""
DETECT_NIRI_RUNNING=0
DETECT_OUTPUTS=""       # newline-separated niri output connector names
DETECT_OUTPUT_DATA=""    # tab-separated: name, WxH, scale, x, y, transform

# ---------------------------------------------------------------------------
detect_os() {
    DETECT_ID="$( . /etc/os-release 2>/dev/null; printf '%s' "${ID:-}" )"
    DETECT_ARCH="$(uname -m)"
    DETECT_KERNEL="$(uname -r)"
}

# Which desktop session are we running inside? Needed so we know whether we can
# query niri and whether installing packages is safe (e.g. not mid-update).
detect_session() {
    DETECT_SESSION_TYPE="${XDG_SESSION_TYPE:-}"
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then
        DETECT_SESSION="wayland"
    elif [ -n "${DISPLAY:-}" ]; then
        DETECT_SESSION="x11"
    else
        DETECT_SESSION="tty"
    fi
    DESKTOP_CURRENT="${XDG_CURRENT_DESKTOP:-}"
    if [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/niri.wayland-1" ] \
       || [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/niri.wayland-2" ] \
       || pgrep -x niri >/dev/null 2>&1; then
        DETECT_NIRI_RUNNING=1
    else
        DETECT_NIRI_RUNNING=0
    fi
}

# ---------------------------------------------------------------------------
# AUR helper: use an existing one, otherwise say so and let the caller bootstrap.
# ---------------------------------------------------------------------------
detect_aur_helper() {
    local c
    for c in yay paru pikaur; do
        if command -v "$c" >/dev/null 2>&1; then DETECT_AUR_HELPER="$c"; return 0; fi
    done
    DETECT_AUR_HELPER=""
    return 1
}

# ---------------------------------------------------------------------------
# GPU vendor + kernel driver, from lspci (no hard-coded PCI IDs in the repo).
# ---------------------------------------------------------------------------
detect_gpu() {
    DETECT_GPU_VENDOR=""; DETECT_GPU_DRIVER=""; DETECT_GPU_NAME=""

    command -v lspci >/dev/null 2>&1 || return 0

    local line vendor
    # Prefer a wired VGA/3D controller; a wireless NIC also exposes a
    # "Network controller" but never a "VGA compatible controller", so this
    # filter is specific enough.
    line="$(lspci -nnk 2>/dev/null | awk '
        /VGA compatible controller|3D controller|Display controller/ {
            name = $0
            getline a; getline b
            print name "\n" a "\n" b
            exit
        }')"
    [ -z "$line" ] && return 0

    DETECT_GPU_NAME="$(printf '%s\n' "$line" | head -1 | cut -d: -f2- | sed 's/^ *//')"

    vendor="$(printf '%s\n' "$line" | head -1)"
    case "$vendor" in
        *Intel*)  DETECT_GPU_VENDOR="intel"  ;;
        *AMD*|*ATI*) DETECT_GPU_VENDOR="amd" ;;
        *NVIDIA*) DETECT_GPU_VENDOR="nvidia" ;;
        *)        DETECT_GPU_VENDOR="unknown" ;;
    esac

    DETECT_GPU_DRIVER="$(printf '%s\n' "$line" \
        | grep -oE 'Kernel driver in use: [a-z0-9_-]+' \
        | head -1 | awk '{print $NF}')"

    # An NVIDIA card still on the nouveau module means the open driver.
    if [ "$DETECT_GPU_VENDOR" = "nvidia" ] && [ "$DETECT_GPU_DRIVER" = "nouveau" ]; then
        DETECT_GPU_VENDOR="nouveau"
    fi
    case "$DETECT_GPU_DRIVER" in
        i915|xe)     DETECT_GPU_VENDOR="${DETECT_GPU_VENDOR:-intel}" ;;
        amdgpu)      DETECT_GPU_VENDOR="amd" ;;
    esac
    return 0
}

# ---------------------------------------------------------------------------
# CPU vendor, from /proc/cpuinfo (no hard-coded model names).
# ---------------------------------------------------------------------------
detect_cpu() {
    DETECT_CPU_VENDOR="$(grep -m1 -E 'vendor_id' /proc/cpuinfo 2>/dev/null | awk -F': ' '{print $2}')"
    case "$DETECT_CPU_VENDOR" in
        GenuineIntel)    DETECT_CPU_VENDOR="GenuineIntel" ;;
        AuthenticAMD)    DETECT_CPU_VENDOR="AuthenticAMD" ;;
        *)               DETECT_CPU_VENDOR="other" ;;
    esac
}

# ---------------------------------------------------------------------------
# Laptop vs desktop: DMI chassis_type 8|9|10|14|30|31 are portable, plus the
# presence of a battery as a fallback for DMI-less firmware.
# ---------------------------------------------------------------------------
detect_machine() {
    local chassis=""
    chassis="$(cat /sys/class/dmi/id/chassis_type 2>/dev/null | tr -d '\0')"
    case "$chassis" in
        8|9|10|14|30|31) DETECT_MACHINE_KIND="laptop" ;;
    esac
    if [ -z "$DETECT_MACHINE_KIND" ]; then
        if compgen -G "/sys/class/power_supply/BAT*" >/dev/null 2>&1 \
           || compgen -G "/sys/class/power_supply/*BAT*" >/dev/null 2>&1; then
            DETECT_MACHINE_KIND="laptop"
        else
            DETECT_MACHINE_KIND="desktop"
        fi
    fi
    DETECT_HAS_BACKLIGHT=0
    if compgen -G "/sys/class/backlight/*" >/dev/null 2>&1; then
        DETECT_HAS_BACKLIGHT=1
    fi
}

# ---------------------------------------------------------------------------
# SOF (Smart Sound Open Firmware) audio — needed for internal mic/speaker on
# modern thin laptops.
# ---------------------------------------------------------------------------
detect_sof() {
    DETECT_HAS_SOF=0
    if grep -qE '(^|-)sof|snd_sof' /proc/asound/cards 2>/dev/null; then
        DETECT_HAS_SOF=1; return 0
    fi
    if command -v aplay >/dev/null 2>&1; then
        if aplay -l 2>/dev/null | grep -qE 'sof|CPU [0-9]+ HD Audio'; then
            DETECT_HAS_SOF=1
        fi
    fi
}

# ---------------------------------------------------------------------------
# Default-route network interface (used only for logging; never written to a
# deployed file).
# ---------------------------------------------------------------------------
detect_default_iface() {
    DETECT_DEFAULT_IFACE="$(ip -o route show default 2>/dev/null | awk '{print $5; exit}')"
    if [ -z "$DETECT_DEFAULT_IFACE" ] && command -v nmcli >/dev/null 2>&1; then
        DETECT_DEFAULT_IFACE="$(nmcli -t -f DEVICE,TYPE device 2>/dev/null \
            | awk -F: '$2=="connected" && $1!="lo" {print $1; exit}')"
    fi
}

# ---------------------------------------------------------------------------
# Connected niri outputs.
#
# Parsed ONCE, into DETECT_OUTPUT_DATA, as tab-separated:
#
#     NAME <TAB> MODE <TAB> SCALE <TAB> X <TAB> Y <TAB> TRANSFORM <TAB> LOGICAL SIZE
#
# one line per connected output, e.g.
#
#     eDP-1   1920x1200   1   0   0   normal   1920x1200
#
# MODE is the physical mode ("WxH", no refresh rate) and is what niri's output
# block wants. LOGICAL SIZE is "WxH" after scaling and is what the lock screen
# needs; it is empty if niri did not report it, in which case divide MODE by
# SCALE. DETECT_OUTPUTS holds just the names.
#
# Read it with output_field / output_geometry — never re-parse `niri msg outputs`
# anywhere else. Two independent parsers of a format that has changed between
# niri releases is exactly how the lock screen ended up laid out for a 16:9
# display on a 16:10 panel.
#
# The shape of `niri msg outputs` changed between niri releases, so the parser
# accepts both:
#
#   current:   Output "Chimei Innolux Corporation 0x162A Unknown" (eDP-1)
#              Current mode: 1920x1200 @ 60.003 Hz (preferred)
#              Logical position: 0, 0
#              Scale: 1
#
#   older:     Output eDP-1
#              Current mode: 1920x1200@60.003
#              Position: 0, 0
#              Scale: 1
#
# The connector name is therefore taken from the trailing parentheses when they
# are present, and from the bare word after "Output " when they are not. Note
# that the make/model string in the first form contains spaces, which is why the
# name cannot simply be "the second field".
# ---------------------------------------------------------------------------
detect_niri_outputs() {
    DETECT_OUTPUTS=""
    DETECT_OUTPUT_DATA=""
    [ "$DETECT_NIRI_RUNNING" = 1 ] || return 0
    command -v niri >/dev/null 2>&1 || return 0

    DETECT_OUTPUT_DATA="$(niri msg outputs 2>/dev/null | awk '
        function flush() {
            if (name != "" && mode != "")
                printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", name, mode, \
                       (scale == "" ? 1 : scale), (x == "" ? 0 : x), \
                       (y == "" ? 0 : y), tf, lsize
            name = ""; mode = ""; scale = ""; x = ""; y = ""; tf = "normal"; lsize = ""
        }

        # A new Output line ends the previous block, so flush BEFORE resetting.
        /^Output[ \t]+/ {
            flush()
            line = $0
            if (match(line, /\([A-Za-z0-9_-]+\)[ \t]*$/)) {
                # current form:  Output "Make Model Serial" (eDP-1)
                # The name is the parenthesised group at the END of the line. It
                # has to be end-anchored, because the make/model string in front
                # can contain parentheses of its own — e.g.
                #   Output "Chimei Innolux (0x162A) Unknown" (eDP-1)
                # where (0x162A) is not the connector.
                name = substr(line, RSTART + 1, RLENGTH - 2)
                sub(/[ \t].*$/, "", name)
            } else if (match(line, /^Output[ \t]+/)) {
                # older form:  Output eDP-1
                name = substr(line, RLENGTH + 1)
                sub(/[ \t].*$/, "", name)
            }
            next
        }

        # A blank line also ends a block, in case a future niri separates them.
        /^[ \t]*$/ { flush(); next }

        name != "" {
            # "Current mode: 1920x1200 @ 60.003 Hz (preferred)"  or
            # "Current mode: 1920x1200@60.003"
            if ($1 == "Current" && $2 == "mode:") {
                if (match($0, /[0-9]+x[0-9]+/)) mode = substr($0, RSTART, RLENGTH)
            }
            if ($1 == "Scale:") scale = $2

            # "Logical size: 1920x1200" is the size in logical pixels, i.e. after
            # scaling. Preferred over mode/scale when present, because it is what
            # the compositor is actually using right now.
            if ($1 == "Logical" && $2 == "size:" && match($0, /[0-9]+x[0-9]+/))
                lsize = substr($0, RSTART, RLENGTH)

            # "Logical position: 0, 0"  or  "Position: 0,0"  or
            # "Position: 1920, 0". Match the pair on the whole line so every
            # spacing variant works, rather than counting whitespace fields.
            if ($1 == "Logical" && $2 == "position:") {
                if (match($0, /-?[0-9]+[ \t]*,[ \t]*-?[0-9]+/)) {
                    pair = substr($0, RSTART, RLENGTH)
                    gsub(/[ \t]/, "", pair)
                    split(pair, c, ",")
                    x = c[1]; y = c[2]
                }
            }
            if ($1 == "Position:") {
                if (match($0, /-?[0-9]+[ \t]*,[ \t]*-?[0-9]+/)) {
                    pair = substr($0, RSTART, RLENGTH)
                    gsub(/[ \t]/, "", pair)
                    split(pair, c, ",")
                    x = c[1]; y = c[2]
                }
            }

            # A rotated panel: record it so the generated block matches what the
            # compositor is actually doing instead of silently undoing it.
            if ($1 == "Transform:" && $2 != "") tf = $2
        }

        END { flush() }
    ')"

    [ -n "$DETECT_OUTPUT_DATA" ] || return 0
    DETECT_OUTPUTS="$(printf '%s' "$DETECT_OUTPUT_DATA" | cut -f1)"
    return 0
}

# ---------------------------------------------------------------------------
detect_all() {
    detect_os
    detect_session
    detect_gpu
    detect_cpu
    detect_machine
    detect_sof
    detect_default_iface
    detect_niri_outputs
    detect_aur_helper || true
}

detect_report() {
    step "Detected environment"
    printf '    os            : %s (%s, %s)\n' "${PRETTY_NAME:-arch}" "$DETECT_ARCH" "$DETECT_KERNEL"
    printf '    session       : %s  desktop=%s  niri=%s\n' "$DETECT_SESSION" "${DESKTOP_CURRENT:-none}" \
        "$([ "$DETECT_NIRI_RUNNING" = 1 ] && echo running || echo not-running)"
    printf '    gpu           : %s [%s]  %s\n' "${DETECT_GPU_VENDOR:-unknown}" "${DETECT_GPU_DRIVER:-none}" "${DETECT_GPU_NAME:-n/a}"
    printf '    cpu           : %s\n' "$DETECT_CPU_VENDOR"
    printf '    machine       : %s  backlight=%s\n' "$DETECT_MACHINE_KIND" \
        "$([ "$DETECT_HAS_BACKLIGHT" = 1 ] && echo yes || echo no)"
    printf '    sof audio     : %s\n' "$([ "$DETECT_HAS_SOF" = 1 ] && echo yes || echo no)"
    printf '    default iface : %s\n' "${DETECT_DEFAULT_IFACE:-none}"
    printf '    aur helper    : %s\n' "${DETECT_AUR_HELPER:-none (will bootstrap yay)}"
    if [ -n "$DETECT_OUTPUTS" ]; then
        printf '    niri outputs  : %s\n' "$(printf '%s' "$DETECT_OUTPUTS" | tr '\n' ' ')"
    else
        printf '    niri outputs  : (no live session; generated from defaults)\n'
    fi
    printf '\n'
}

# ---------------------------------------------------------------------------
# output_field <name> <column>
#
#   mode | scale | x | y | transform | logical
#
# Reads the cache; returns 1 if the output is not in it. This is the ONLY way any
# other file should read display information.
# ---------------------------------------------------------------------------
output_field() {
    [ -n "$DETECT_OUTPUT_DATA" ] || return 1

    # awk's $col is a NUMERIC field index. Passing the literal string "mode"
    # there evaluates to 0 and silently returns the whole line, so the names are
    # mapped to indices explicitly rather than relying on awk to understand them.
    local idx
    case "$2" in
        mode)      idx=2 ;;
        scale)     idx=3 ;;
        x)         idx=4 ;;
        y)         idx=5 ;;
        transform) idx=6 ;;
        logical)   idx=7 ;;
        *) return 1 ;;
    esac

    local v
    v="$(printf '%s\n' "$DETECT_OUTPUT_DATA" \
         | awk -F'\t' -v want="$1" -v n="$idx" '$1 == want { print $n; exit }')"
    [ -n "$v" ] || return 1
    printf '%s\n' "$v"
}

# output_geometry <name> -> "WIDTH HEIGHT X Y" in LOGICAL pixels
#
# The lock screen is laid out in logical coordinates, so a fractional-scaled
# HiDPI panel must be reported at 1920x1200, not 3840x2400. "Logical size" is
# used when niri reports it; otherwise MODE is divided by SCALE.
output_geometry() {
    local name="$1" mode scale lsize w h
    mode="$(output_field "$name" mode)" || return 1
    scale="$(output_field "$name" scale)" || scale=1
    lsize="$(output_field "$name" logical)" || lsize=""

    if [ -n "$lsize" ]; then
        w="${lsize%%x*}"; h="${lsize#*x}"
    else
        w="${mode%%x*}"; h="${mode#*x}"
        case "$scale" in ''|*[!0-9]*) scale=1 ;; esac
        [ "$scale" -ge 1 ] || scale=1
        w=$(( w / scale )); h=$(( h / scale ))
    fi

    [ -n "$w" ] && [ -n "$h" ] || return 1
    printf '%s %s %s %s\n' "$w" "$h" \
        "$(output_field "$name" x || echo 0)" "$(output_field "$name" y || echo 0)"
}
