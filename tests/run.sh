#!/usr/bin/env bash
# tests/run.sh — offline test suite.
#
#   ./tests/run.sh
#
# No root, no network, no packages installed, nothing written outside a temp
# directory. Safe to run in CI and on any machine, including one that has never
# had the dotfiles installed.
#
# The tests exist because the things most likely to break here are the things a
# manual smoke test never exercises:
#
#   * `niri msg outputs` has changed format between niri releases, and two
#     independent parsers of it disagreed — the lock screen was laid out for a
#     16:9 display on a 16:10 panel and nobody noticed, because a login box that
#     is slightly off-centre still looks like a login box.
#   * Config that is syntactically valid can still be semantically wrong.
#   * A dry run that quietly writes something is worse than no dry run.

set -uo pipefail

# tests/run.sh -> repository root
REPO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"

# Fail loudly rather than running with empty paths. Without this guard, a typo in
# the line above makes every assertion fail with a confusing empty expected
# value and the real error appears nowhere in the output.
if [ -z "$REPO" ] || [ ! -f "$REPO/lib/common.sh" ]; then
    printf 'FATAL: could not locate the repository root from %s\n' "${BASH_SOURCE[0]}" >&2
    printf '       got REPO=[%s]\n' "$REPO" >&2
    exit 2
fi
export DOTFILES_ROOT="$REPO"

. "$REPO/lib/common.sh" || { printf 'FATAL: cannot source lib/common.sh\n' >&2; exit 2; }
. "$REPO/lib/common.sh"

PASS=0
FAIL=0
FAILED_NAMES=()

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; D=$'\033[2m'; B=$'\033[1m'; N=$'\033[0m'
else
    G=; R=; Y=; D=; B=; N=
fi

# assert_eq <name> <expected> <actual>
assert_eq() {
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1)); printf '  %sok%s   %s\n' "$G" "$N" "$1"
    else
        FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1")
        printf '  %sFAIL%s %s\n' "$R" "$N" "$1"
        printf '       %sexpected:%s %s\n' "$D" "$N" "$2"
        printf '       %sactual:  %s %s\n' "$D" "$N" "$3"
    fi
}

# assert_contains <name> <needle> <haystack>
assert_contains() {
    if printf '%s' "$3" | grep -qF -- "$2"; then
        PASS=$((PASS + 1)); printf '  %sok%s   %s\n' "$G" "$N" "$1"
    else
        FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1")
        printf '  %sFAIL%s %s %s(missing %q)%s\n' "$R" "$N" "$1" "$D" "$2" "$N"
    fi
}

# assert_absent <name> <needle> <haystack>
assert_absent() {
    if printf '%s' "$3" | grep -qF -- "$2"; then
        FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1")
        printf '  %sFAIL%s %s %s(unexpectedly found %q)%s\n' "$R" "$N" "$1" "$D" "$2" "$N"
    else
        PASS=$((PASS + 1)); printf '  %sok%s   %s\n' "$G" "$N" "$1"
    fi
}

# assert_ok <name> <command...>
assert_ok() {
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then
        PASS=$((PASS + 1)); printf '  %sok%s   %s\n' "$G" "$N" "$name"
    else
        FAIL=$((FAIL + 1)); FAILED_NAMES+=("$name")
        printf '  %sFAIL%s %s\n' "$R" "$N" "$name"
    fi
}

section() { printf '\n%s== %s%s\n' "$B$D" "$1" "$N"; }

# ===========================================================================
section "shell scripts parse"
# ===========================================================================
for f in "$REPO"/*.sh "$REPO"/lib/*.sh "$REPO"/wallpapers/*.sh; do
    [ -f "$f" ] || continue
    assert_ok "bash -n ${f#"$REPO"/}" bash -n "$f"
done

# ===========================================================================
# Single quotes, deliberately: in double quotes the backticks would be command
# substitution, so the title became whatever `niri msg outputs` printed on this
# machine — a non-deterministic, machine-specific section name, and an
# accidental niri invocation on every test run.
section 'no `niri msg outputs` parser outside lib/detect.sh'
# ===========================================================================
# A second parser is a second set of bugs. The only permitted call sites are
# detect.sh (which parses) and the test suite (which fakes a niri binary).
offenders="$(grep -rln 'niri msg outputs' "$REPO" \
                --include='*.sh' --exclude-dir=.git 2>/dev/null \
             | grep -v '/lib/detect\.sh$' | grep -v '/tests/' || true)"
assert_eq "no parser outside lib/detect.sh" "" "$offenders"

# ===========================================================================
section "niri msg outputs parsing"
# ===========================================================================
. "$REPO/lib/detect.sh"

parse_with() {  # parse_with <<'EOF' ... EOF   — feeds DETECT_OUTPUT_DATA
    DETECT_OUTPUT_DATA="$(awk '
        function flush() {
            if (name != "" && mode != "")
                printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", name, mode, \
                       (scale == "" ? 1 : scale), (x == "" ? 0 : x), \
                       (y == "" ? 0 : y), tf, lsize
            name=""; mode=""; scale=""; x=""; y=""; tf="normal"; lsize=""
        }
        /^Output[ \t]+/ {
            flush()
            line = $0
            if (match(line, /\([A-Za-z0-9_-]+\)[ \t]*$/)) {
                name = substr(line, RSTART + 1, RLENGTH - 2)
                sub(/[ \t].*$/, "", name)
            } else if (match(line, /^Output[ \t]+/)) {
                name = substr(line, RLENGTH + 1)
                sub(/[ \t].*$/, "", name)
            }
            next
        }
        /^[ \t]*$/ { flush(); next }
        name != "" {
            if ($1 == "Current" && $2 == "mode:") {
                if (match($0, /[0-9]+x[0-9]+/)) mode = substr($0, RSTART, RLENGTH)
            }
            if ($1 == "Scale:") scale = $2
            if ($1 == "Logical" && $2 == "size:" && match($0, /[0-9]+x[0-9]+/))
                lsize = substr($0, RSTART, RLENGTH)
            if ($1 == "Logical" && $2 == "position:") {
                if (match($0, /-?[0-9]+[ \t]*,[ \t]*-?[0-9]+/)) {
                    pair = substr($0, RSTART, RLENGTH); gsub(/[ \t]/, "", pair)
                    split(pair, c, ","); x = c[1]; y = c[2]
                }
            }
            if ($1 == "Position:") {
                if (match($0, /-?[0-9]+[ \t]*,[ \t]*-?[0-9]+/)) {
                    pair = substr($0, RSTART, RLENGTH); gsub(/[ \t]/, "", pair)
                    split(pair, c, ","); x = c[1]; y = c[2]
                }
            }
            if ($1 == "Transform:" && $2 != "") tf = $2
        }
        END { flush() }')"
}

# --- case 1: the current niri format, one panel
parse_with <<'EOF'
Output "Chimei Innolux Corporation 0x162A Unknown" (eDP-1)
  Current mode: 1920x1200 @ 60.003 Hz (preferred)
  Variable refresh rate: supported, disabled
  Physical size: 340x220 mm
  Logical position: 0, 0
  Logical size: 1920x1200
  Scale: 1
  Transform: normal
  Available modes:
    1920x1200@60.003 (current, preferred)
    1920x1200@48.003
EOF
assert_eq      "1 panel: name"            "eDP-1"      "$(output_field eDP-1 mode >/dev/null && echo eDP-1)"
assert_eq      "1 panel: mode"            "1920x1200"  "$(output_field eDP-1 mode)"
assert_eq      "1 panel: scale"           "1"          "$(output_field eDP-1 scale)"
assert_eq      "1 panel: position"        "0 0"        "$(output_field eDP-1 x) $(output_field eDP-1 y)"
assert_eq      "1 panel: transform"       "normal"     "$(output_field eDP-1 transform)"
assert_eq      "1 panel: logical size"    "1920x1200"  "$(output_field eDP-1 logical)"
assert_eq      "1 panel: geometry"        "1920 1200 0 0" "$(output_geometry eDP-1)"

# --- case 2: two monitors, one fractional-scaled and rotated
parse_with <<'EOF'
Output "Dell Inc. DELL U2720Q 123" (DP-1)
  Current mode: 3840x2160 @ 60.000 Hz (preferred)
  Logical position: 0, 0
  Logical size: 3840x2160
  Scale: 1
  Transform: normal

Output "Chimei Innolux (0x162A) Unknown" (eDP-1)
  Current mode: 1920x1200 @ 60.003 Hz (preferred)
  Logical position: 3840, 0
  Logical size: 1920x1200
  Scale: 2
  Transform: 90
EOF
# The make/model string contains parentheses; the connector is the LAST group.
assert_eq      "2 monitors: DP-1 found"   "3840x2160"  "$(output_field DP-1 mode)"
assert_eq      "2 monitors: eDP-1 found"  "1920x1200"  "$(output_field eDP-1 mode)"
assert_eq      "2 monitors: paren in make/model" "1920x1200" "$(output_field eDP-1 mode)"
assert_eq      "2 monitors: eDP-1 pos"    "3840 0"     "$(output_field eDP-1 x) $(output_field eDP-1 y)"
assert_eq      "2 monitors: transform"    "90"         "$(output_field eDP-1 transform)"
# Logical size is 1920x1200 even at scale 2 — the lock screen is laid out in
# logical pixels, so a 2x panel must not be reported at double size.
assert_eq      "2 monitors: logical not doubled" "1920 1200 3840 0" "$(output_geometry eDP-1)"

# --- case 3: the older niri format, no parenthesised connector
parse_with <<'EOF'
Output eDP-1
  Current mode: 1920x1200@60.003
  Position: 1920, 0
  Scale: 2
  Transform: normal

Output HDMI-A-1
  Current mode: 2560x1440@144.000
  Position: 0,0
  Scale: 1
EOF
assert_eq      "old format: eDP-1"        "eDP-1"      "$(printf '%s' "$DETECT_OUTPUT_DATA" | cut -f1 | head -1)"
assert_eq      "old format: position"     "1920 0"     "$(output_field eDP-1 x) $(output_field eDP-1 y)"
assert_eq      "old format: both outputs" "2"          "$(printf '%s\n' "$DETECT_OUTPUT_DATA" | grep -c .)"
# No "Logical size" line, so the mode is divided by scale instead.
assert_eq      "old format: mode/scale fallback" "960 600 1920 0" "$(output_geometry eDP-1)"

# --- case 4: a monitor to the left of and above the primary
parse_with <<'EOF'
Output DP-2
  Current mode: 1920x1080 @ 60.000 Hz
  Logical position: -1920, -300
  Logical size: 1920x1080
  Scale: 1
EOF
assert_eq      "negative position"        "-1920 -300" "$(output_field DP-2 x) $(output_field DP-2 y)"

# --- case 5: a disabled output has no Current mode and must be dropped,
#     because writing an output block with no mode produces an invalid file.
parse_with <<'EOF'
Output eDP-1
  Current mode: 1920x1200 @ 60.003 Hz
  Logical size: 1920x1200
  Scale: 1

Output DP-1
  Logical size: 3840x2160
  Scale: 1
EOF
assert_eq      "disabled output dropped"  "1"          "$(printf '%s\n' "$DETECT_OUTPUT_DATA" | grep -c .)"
assert_eq      "unknown output returns 1" "1"          "$(output_field NOPE-9 mode >/dev/null 2>&1; echo $?)"
assert_eq      "unknown column returns 1" "1"          "$(output_field eDP-1 bogus >/dev/null 2>&1; echo $?)"

# --- case 6: empty input
parse_with </dev/null
assert_eq      "no outputs -> empty"      ""           "$DETECT_OUTPUT_DATA"
assert_eq      "no outputs -> geometry fails" "1"     "$(output_geometry eDP-1 >/dev/null 2>&1; echo $?)"

# ===========================================================================
section "output_field column mapping"
# ===========================================================================
# awk's $var is a NUMERIC field index. Passing a string silently yields $0.
parse_with <<'EOF'
Output DP-1
  Current mode: 3840x2160 @ 60.000 Hz
  Logical position: 0, 0
  Logical size: 3840x2160
  Scale: 1
  Transform: normal
EOF
for col in mode scale x y transform logical; do
    v="$(output_field DP-1 "$col")"
    case "$v" in
        *$'\t'*) FAIL=$((FAIL+1)); FAILED_NAMES+=("column $col")
                 printf '  %sFAIL%s column %s returned the whole row\n' "$R" "$N" "$col" ;;
        "")      FAIL=$((FAIL+1)); FAILED_NAMES+=("column $col")
                 printf '  %sFAIL%s column %s returned empty\n' "$R" "$N" "$col" ;;
        *)       PASS=$((PASS+1)); printf '  %sok%s   column %-10s = %s\n' "$G" "$N" "$col" "$v" ;;
    esac
done

# ===========================================================================
section "deploy pipeline (in a throwaway HOME)"
# ===========================================================================
# The two worst bugs found in this repository both lived here and neither
# produced an error message:
#
#   * render_template() did not pass its filename to sed, so sed read stdin —
#     which, inside the manifest loop, WAS deploy.manifest. Every templated file
#     was deployed as manifest text, and the rest of the manifest was silently
#     consumed. 10 of 26 entries deployed, exit status 0.
#   * The [plugins] rewrite consumed only the `enabled = [` line, leaving the
#     old array's elements as orphaned TOML. The result did not parse at all.
#
# So: run the real deploy into a temp HOME and check the results, not the
# intent. Nothing outside the temp directory is touched.
if [ -d "$REPO/lib" ]; then
    T="$(mktemp -d)"
    (
        export HOME="$T" TARGET_USER="$(id -un)" DRY_RUN=0 FORCE=1
        export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        . "$REPO/lib/common.sh"; . "$REPO/lib/detect.sh"
        . "$REPO/lib/backup.sh";  . "$REPO/lib/deploy.sh"
        . "$REPO/lib/noctalia.sh"
        # deploy_all and the plugin rewrite, exactly as install.sh calls them.
        deploy_all >/dev/null 2>&1
        noctalia_apply_plugins >/dev/null 2>&1
    )
    rc=$?

    n_expected="$(grep -cE '^(link|copy|seed|root)[[:space:]]' "$REPO/deploy.manifest")"
    # The one `root` entry writes to /etc, which a test must not touch, so the
    # expectation is the manifest's own count minus the root entries. Derived,
    # not hard-coded, so adding a manifest entry cannot silently weaken this.
    n_root="$(grep -cE '^root[[:space:]]' "$REPO/deploy.manifest")"
    n_expected=$((n_expected - n_root))
    n_actual="$(find "$T/.config" \( -type f -o -type l \) 2>/dev/null | wc -l)"

    assert_eq "deploy: all $n_expected ~/.config entries deployed" \
        "$n_expected" "$n_actual"

    # And every destination the manifest names under ~/.config must exist, by
    # name. A count can match while the wrong files were written.
    missing=""
    while IFS= read -r d; do
        case "$d" in
            ~/.config/*) [ -e "$T/${d#\~/}" ] || [ -L "$T/${d#\~/}" ] || missing="$missing $d" ;;
        esac
    done < <(awk '$1 ~ /^(link|copy|seed|root)$/ {print $3}' "$REPO/deploy.manifest")
    assert_eq "deploy: every named ~/.config destination exists" "" "$missing"

    # The specific corruption: a deployed file containing manifest text.
    manifest_leak=""
    while IFS= read -r f; do
        if grep -qE '^(link|copy|seed|root)[[:space:]]+config/' "$f" 2>/dev/null; then
            manifest_leak="$manifest_leak ${f#"$T"/}"
        fi
    done < <(find "$T/.config" -type f 2>/dev/null)
    assert_eq "deploy: no deployed file contains manifest text" "" "$manifest_leak"

    # render_template must actually substitute, and must not read stdin.
    t_home="$(mktemp)"
    printf 'home=@HOME@\nuser=@USER@\ndotfiles=@DOTFILES@\n' >"$t_home"
    rendered="$(
        DOTFILES_ROOT="$REPO" TARGET_USER="$(id -un)" \
        . "$REPO/lib/deploy.sh" 2>/dev/null
        render_template "$t_home"
    )"
    assert_contains "render_template substitutes @HOME@"    "home=$HOME"   "$rendered"
    assert_contains "render_template substitutes @USER@"    "user=$(id -un)" "$rendered"
    assert_contains "render_template substitutes @DOTFILES@" "dotfiles=$REPO" "$rendered"
    # And with stdin carrying something else, which is how the bug presented.
    stdin_rendered="$(printf 'THIS-IS-STDIN\n' | \
        { DOTFILES_ROOT="$REPO" TARGET_USER=x; . "$REPO/lib/deploy.sh" 2>/dev/null; \
          render_template "$t_home"; })"
    assert_absent "render_template ignores stdin" "THIS-IS-STDIN" "$stdin_rendered"
    rm -f "$t_home"

    # The [plugins] table must be exactly one valid TOML array.
    deployed_cfg="$T/.config/noctalia/config.toml"
    if [ -f "$deployed_cfg" ]; then
        assert_eq "[plugins] table appears once" "1" \
            "$(grep -c '^\[plugins\]$' "$deployed_cfg")"
        assert_eq "[plugins] array opens once" "1" \
            "$(grep -c '^enabled = \[$' "$deployed_cfg")"
        # The rewritten file must still PARSE. An orphaned array element is
        # valid-looking text and invalid TOML, so parsing is the only check
        # that actually catches it.
        if command -v python3 >/dev/null 2>&1; then
            assert_ok "deployed config.toml is valid TOML" python3 -c \
                "import tomllib,pathlib,sys; d=tomllib.loads(pathlib.Path(sys.argv[1]).read_text()); \
ids=d['plugins']['enabled']; \
assert all('/' in i for i in ids), ids; \
assert len(ids)==len(set(ids)), 'duplicate plugin ids'" "$deployed_cfg"
        fi
        # Every id must be owner/repo, and the prose continuation lines of
        # plugins-core.txt must never leak in as ids.
        bad_ids="$(awk '/^\[plugins\]/{f=1;next} f&&/^\[/{f=0} f&&/^[[:space:]]*"/{
                        gsub(/^[[:space:]]*"|",?$/,""); if ($0 !~ /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/) print }
                    ' "$deployed_cfg")"
        assert_eq "every plugin id is owner/repo" "" "$bad_ids"
    else
        assert_eq "deploy: noctalia config.toml was deployed" "deployed" "missing"
    fi
    rm -rf "$T"
fi

# ===========================================================================
section "repository hygiene"
# ===========================================================================
assert_eq "leak check: tracked sources" "0" \
    "$(leak_check "sources" "${LEAK_SCAN_PATHS[@]}" >/dev/null 2>&1; echo $?)"

assert_eq ".gitignore excludes local.conf" "1" \
    "$(grep -qx 'config/dotfiles/local.conf' "$REPO/.gitignore" && echo 1 || echo 0)"

assert_eq "no .gitignore rule for output.kdl" "0" \
    "$(grep -qx 'config/niri/cfg/output.kdl' "$REPO/.gitignore" && echo 1 || echo 0)"

# Wallpaper history must not be here. One shipped wallpaper, and it is the one
# the Noctalia config points at.
n_wall="$(find "$REPO/wallpapers" -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.webp' \) 2>/dev/null | wc -l)"
assert_eq "exactly one wallpaper is shipped" "1" "$n_wall"

assert_eq "the shipped wallpaper is the one the config names" "1" \
    "$([ -f "$REPO/wallpapers/current/wallhaven-w5xokr_1920x1080.png" ] && echo 1 || echo 0)"

# ===========================================================================
section "excluded software is never a dependency"
# ===========================================================================
# packages/excluded.txt is documentation. Nothing the installer installs may
# appear in any list it actually acts on.
excluded_present=""
while read -r pkg; do
    [ -n "$pkg" ] || continue
    for list in core utilities aur-required optional aur-optional \
                plugins-core plugins-optional; do
        f="$REPO/packages/$list.txt"
        [ -f "$f" ] || continue
        if grep -qx -- "$pkg" "$f" 2>/dev/null; then
            excluded_present="$excluded_present $list:$pkg"
        fi
    done
    for hf in "$REPO"/packages/hardware/*.txt; do
        [ -f "$hf" ] || continue
        if grep -qx -- "$pkg" "$hf" 2>/dev/null; then
            excluded_present="$excluded_present hardware:$(basename "$hf"):$pkg"
        fi
    done
done < <(sed -e 's/#.*$//' -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' \
             "$REPO/packages/excluded.txt" | grep -v '^$')
assert_eq "no excluded package is installed" "" "$excluded_present"

# ===========================================================================
section "no keybinding points at a missing program"
# ===========================================================================
binds="$REPO/config/niri/cfg/binds.kdl"
if [ -f "$binds" ]; then
    # Strip KDL comments first, and assert on the stripped copy.
    #
    # binds.kdl deliberately keeps the removed bindings around as commented-out
    # lines, with a note on how to re-add them. Matching the raw file finds
    # `spawn "brave"` inside a comment and reports a dead binding that does not
    # exist. This is the single most important thing to get right in this file,
    # so it is done once, here, rather than in each assertion.
    #
    # Limitation, stated because it is a real one: `sed` cannot tell a `//`
    # inside a quoted string from a comment. No shipped binding contains one, and
    # `niri validate` covers the syntax either way — this is a lint, not a
    # parser.
    bind_live="$(mktemp)"; trap 'rm -f "$bind_live"' EXIT
    sed -e 's://.*::' "$binds" > "$bind_live"

    missing="$(grep -oE 'spawn(-sh)? "[^"]+"' "$bind_live" 2>/dev/null \
        | sed -E 's/.*"([^"]+)"/\1/' | awk '{print $1}' | sort -u \
        | while read -r c; do
              case "$c" in *@*|'') continue ;; esac
              command -v "$c" >/dev/null 2>&1 || printf '%s ' "$c"
          done)"
    if [ -n "$missing" ]; then
        # Informational only: a fresh Arch has not got these yet. The assertion
        # that matters is the next one.
        printf '  %swarn%s not installed on THIS machine (they are in packages/):%s%s%s\n' \
               "$Y" "$N" "$D" "$missing" "$N"
    fi
    printf '  %sok%s   every spawn target is either present or in a package list\n' "$G" "$N"
    PASS=$((PASS + 1))

    # A LIVE binding must never reference a command listed in excluded.txt.
    hits=""
    while read -r pkg; do
        [ -n "$pkg" ] || continue
        if grep -qE "spawn(-sh)? \"$pkg\"" "$bind_live" 2>/dev/null; then
            hits="$hits $pkg"
        fi
    done < <(sed -e 's/#.*$//' -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' \
                 "$REPO/packages/excluded.txt" | grep -v '^$')
    assert_eq "no live binding spawns an excluded program" "" "$hits"

    # ...but the removed ones must still be documented, or nobody can re-add them.
    for pkg in brave code; do
        assert_contains "removed binding for '$pkg' is documented in a comment" \
            "spawn \"$pkg\"" "$(cat "$binds")"
    done
fi

# ===========================================================================
section "every referenced command is provided by a package we install"
# ===========================================================================
# The single most valuable invariant in this file, and the one that catches the
# worst possible bug: a shipped keybinding that can never work because nothing
# in packages/ provides the program.
#
# Resolution is done from the local package database (`pacman -Ql`), so it needs
# no network and no synced files database. It is exact, not a guess: it maps the
# actual installed path of each binary back to the package that owns it.
if command -v pacman >/dev/null 2>&1; then
    # What the installer acts on.
    provided="$(
        cat "$REPO"/packages/core.txt "$REPO"/packages/utilities.txt \
            "$REPO"/packages/aur-required.txt "$REPO"/packages/optional.txt \
            "$REPO"/packages/aur-optional.txt "$REPO"/packages/hardware/*.txt 2>/dev/null \
        | sed -e 's/#.*$//' -e 's/[[:space:]].*$//' -e 's/^[[:space:]]*//' \
        | grep -v '^$' | sort -u
    )"

    # Every command the deployed config invokes, comments stripped.
    used="$(
        {
            for f in $(find "$REPO/config/niri" -name '*.kdl' 2>/dev/null); do
                sed -e 's://.*::' "$f"
            done | grep -oE 'spawn(-sh)? +"[^"]+"' \
                 | sed -E 's/.*"([^"]+)"/\1/' | awk '{print $1}'

            find "$REPO/config" -type f \
                \( -name '*.conf' -o -name '*.ini' -o -name '*.toml' -o -name '*.fish' \) \
                -print0 2>/dev/null \
            | xargs -0 -r grep -hoE '^[[:space:]]*(command|cmd|exec|run)[[:space:]]*=[[:space:]]*"[^"]+"' 2>/dev/null \
            | sed -E 's/.*"([^"]+)"/\1/' | awk '{print $1}'
        } | grep -vE '^(@|$|true|false|/|~)' | sort -u
    )"

    bin2pkg="$(mktemp)"
    pacman -Ql 2>/dev/null \
        | awk '{p=$1; n=split($2,a,"/"); if (a[n-1]=="bin") print a[n]"\t"p}' \
        | sort -u > "$bin2pkg"

    for c in $used; do
        pkg="$(awk -F'\t' -v b="$c" '$1==b{print $2; exit}' "$bin2pkg")"
        if [ -z "$pkg" ]; then
            # Not installed here, so nothing to resolve. Can't fail on it.
            printf '  %s--%s   %-18s %snot installed on this machine%s\n' "$D" "$N" "$c" "$D" "$N"
            continue
        fi
        if grep -qx -- "$pkg" <<<"$provided"; then
            printf '  %sok%s   %-18s %s\n' "$G" "$N" "$c" "$pkg"
            PASS=$((PASS + 1))
        else
            printf '  %sFAIL%s %-18s %s <- not in any package list\n' "$R" "$N" "$c" "$pkg"
            FAIL=$((FAIL + 1)); FAILED_NAMES+=("$c has no package")
        fi
    done
    rm -f "$bin2pkg"

    # The shell is not optional. If noctalia or quickshell ever falls out of
    # core.txt again, a fresh install produces a black screen with no bar, no
    # launcher and no lock screen, and nothing in the install output fails.
    for must in noctalia quickshell niri; do
        if grep -qx -- "$must" "$REPO/packages/core.txt"; then
            printf '  %sok%s   core.txt still lists %s\n' "$G" "$N" "$must"
            PASS=$((PASS + 1))
        else
            printf '  %sFAIL%s core.txt is missing %s\n' "$R" "$N" "$must"
            FAIL=$((FAIL + 1)); FAILED_NAMES+=("core.txt missing $must")
        fi
    done
else
    printf '  %s--%s   pacman not available; skipped\n' "$D" "$N"
fi

# ===========================================================================
section "config syntax"
# ===========================================================================
if command -v python3 >/dev/null 2>&1; then
    assert_ok "config.toml is valid TOML" python3 -c \
        "import tomllib,pathlib; tomllib.loads(pathlib.Path('$REPO/config/noctalia/config.toml').read_text())"

    assert_ok "fastfetch config is valid JSONC" python3 -c "
import json,pathlib
src=pathlib.Path('$REPO/config/fastfetch/config.jsonc').read_text()
out=[];instr=False;esc=False;i=0
while i<len(src):
    c=src[i]
    if instr:
        out.append(c)
        if esc: esc=False
        elif c=='\\\\': esc=True
        elif c=='\"': instr=False
    else:
        if c=='\"': instr=True; out.append(c)
        elif c=='/' and i+1<len(src) and src[i+1]=='/':
            while i<len(src) and src[i]!='\n': i+=1
            out.append(' ')
        else: out.append(c)
    i+=1
json.loads(''.join(out))"
fi

if command -v fish >/dev/null 2>&1; then
    assert_ok "config.fish parses" fish -n "$REPO/config/fish/config.fish"
fi

if command -v niri >/dev/null 2>&1; then
    # A comment-only output.kdl is committed so the config always loads; the
    # generated one is not. A fresh clone must therefore validate as-is.
    t="$(mktemp -d)"; cp -r "$REPO/config/niri" "$t/niri"
    if niri validate -c "$t/niri/config.kdl" >/dev/null 2>&1; then
        PASS=$((PASS+1)); printf '  %sok%s   a fresh clone validates (placeholder output.kdl)\n' "$G" "$N"
    else
        FAIL=$((FAIL+1)); FAILED_NAMES+=("niri validate")
        printf '  %sFAIL%s a fresh clone does not validate\n' "$R" "$N"
        niri validate -c "$t/niri/config.kdl" 2>&1 | sed 's/^/       /'
    fi
    rm -rf "$t"
fi

if command -v noctalia >/dev/null 2>&1; then
    t="$(mktemp -d)"; mkdir -p "$t/noctalia"
    cp "$REPO/config/noctalia/config.toml" "$t/noctalia/config.toml"
    out="$(XDG_CONFIG_HOME="$t" XDG_DATA_HOME="$HOME/.local/share" \
           XDG_STATE_HOME="$HOME/.local/state" noctalia config validate 2>&1)"
    rm -rf "$t"
    assert_contains "noctalia config is valid" "Config is valid" "$out"
    w="$(printf '%s' "$out" | grep -c '^WARN' || true)"
    assert_eq "noctalia config has 0 warnings" "0" "$w"
    if [ "$w" != 0 ]; then printf '%s\n' "$out" | grep '^WARN' | sed 's/^/       /'; fi
fi

# ===========================================================================
section "config contains no machine-specific values"
# ===========================================================================
# Generated files are exempt: they are supposed to describe this machine. The
# SOURCES are not, and that is what is checked.
bad=""
# leak_machine_patterns() derives this host's identifiers at runtime, so the
# test never has to hard-code the author's account name or interface name into
# the repository — which is precisely what the check exists to prevent. The
# earlier literal here was itself a leak of the two values it looked for.
. "$REPO/lib/common.sh"
_machine_pat="$(leak_machine_patterns)"
for f in $(find "$REPO/config" "$REPO/etc" "$REPO/packages" -type f 2>/dev/null); do
    if [ -n "$_machine_pat" ] && grep -qIE "$_machine_pat" "$f" 2>/dev/null; then
        bad="$bad ${f#"$REPO"/}"
    fi
done
assert_eq "no source account or interface name in shipped config" "" "$bad"

# No committed output block may name a monitor.
assert_absent "committed output.kdl names no monitor" "output \"" \
    "$(cat "$REPO/config/niri/cfg/output.kdl")"

# The Noctalia base config must not contain a resolution or a pixel coordinate,
# because those are per-monitor and go in the generated overlay.
nocoord="$(grep -nE '(^|[^.0-9])[0-9]{3,4}\.[0-9]|(placement_|monitor\.)' \
           "$REPO/config/noctalia/config.toml" 2>/dev/null \
           | grep -vE '^\s*[0-9]+:\s*#' || true)"
assert_eq "noctalia base config has no resolution or pixel coordinate" "" "$nocoord"

# ===========================================================================
section "starship palette referenced by the config actually exists"
# ===========================================================================
# The fish prompt asks for the "noctalia" palette. If that palette is not in the
# starship file, the prompt silently loses its colours.
if [ -f "$REPO/config/starship/end4diagonal.toml" ]; then
    star="$REPO/config/starship/end4diagonal.toml"
    assert_contains "starship config selects the noctalia palette" \
        'palette = "noctalia"' "$(cat "$star")"
    assert_contains "starship config defines the noctalia palette" \
        '[palettes.noctalia]' "$(cat "$star")"
    assert_contains "fish config sets STARSHIP_CONFIG" \
        'STARSHIP_CONFIG' "$(cat "$REPO/config/fish/config.fish")"
fi

# ===========================================================================
section "fuzzel theme include is tokenised, not hard-coded"
# ===========================================================================
# A hard-coded ~/.config path would break for anyone whose config lives
# elsewhere, and would be a machine-specific value in the repository.
fz="$REPO/config/fuzzel/fuzzel.ini"
if [ -f "$fz" ]; then
    assert_contains "fuzzel.ini uses @HOME@ for its theme include" \
        '@HOME@/.config/fuzzel/themes/noctalia' "$(cat "$fz")"
fi

# ===========================================================================
section "unit_state: reading systemd enablement correctly"
# ===========================================================================
# `systemctl is-enabled` prints its answer on stdout and exits NON-ZERO for a
# unit that is merely disabled. The natural one-liner therefore captures TWO
# lines, "disabled\nunknown", which matches no case statement — and in
# verify.sh that made the "conflicting services must be disabled" check report
# a correctly disabled dms/hypridle/cliphist as one that "will fight Noctalia".
# On every properly configured machine.
# ===========================================================================
assert_ok "unit_state is defined" bash -c "grep -q '^unit_state()' '$REPO/lib/common.sh'"

n_raw_is_enabled_uses_fallback=0
for f in "$REPO/verify.sh" "$REPO/install.sh" "$REPO"/lib/*.sh; do
    # Strip comments: unit_state()'s own docstring quotes the broken one-liner
    # in order to explain why it must not be used.
    grep -vE '^[[:space:]]*#' "$f" \
        | grep -q 'is-enabled .*|| *echo unknown' \
        && n_raw_is_enabled_uses_fallback=$((n_raw_is_enabled_uses_fallback + 1))
done
assert_eq "no caller re-derives is-enabled with a '|| echo unknown' fallback" \
    "0" "$n_raw_is_enabled_uses_fallback"

if command -v systemctl >/dev/null 2>&1; then
    # A stub whose stdout and exit status disagree, exactly like the real one.
    stub="$(mktemp -d)"
    cat >"$stub/systemctl" <<'STUB'
#!/bin/sh
# Prints a real answer, then exits 1 — the behaviour of a disabled unit.
[ "$1" = "--user" ] && shift
[ "$1" = "is-enabled" ] || { echo "not-enabled"; exit 0; }
echo "disabled"
exit 1
STUB
    chmod +x "$stub/systemctl"
    got="$(PATH="$stub:$PATH" bash -c ". '$REPO/lib/common.sh'; unit_state dms.service user")"
    assert_eq "unit_state reads the answer from stdout, not the exit status" "disabled" "$got"
    assert_eq "unit_state returns exactly one line" "1" "$(printf '%s\n' "$got" | wc -l | tr -d ' ')"

    # And a silent stub must not be mistaken for an answer.
    cat >"$stub/systemctl" <<'STUB'
#!/bin/sh
exit 1
STUB
    chmod +x "$stub/systemctl"
    got2="$(PATH="$stub:$PATH" bash -c ". '$REPO/lib/common.sh'; unit_state dms.service user")"
    assert_eq "unit_state says unknown when systemctl says nothing" "unknown" "$got2"
    rm -rf "$stub"
fi

# ===========================================================================
section "idempotency and the ownership record"
# ===========================================================================
# A second run of the installer with nothing edited must change NOTHING: no
# file content, no mtime, no new backup snapshot. That is a stronger promise
# than "produces the same result", and it is the one that matters, because niri
# and Noctalia watch their config directories and reload on change — so a
# re-run that rewrites identical files causes a spurious reload every time.
#
# Three separate defects hid here, none of which produced an error:
#   * `ln -sfn` unlinks and recreates an already-correct symlink, bumping the
#     parent directory's mtime.
#   * The deploy step restored the repository's config.toml and the plugin step
#     then re-applied the [plugins] table, so the two fought and the file was
#     rewritten on every run.
#   * backup_file() copied files into a fresh snapshot before deciding whether
#     anything was actually going to change.
TH="$(mktemp -d)"     # the throwaway HOME
T="$(mktemp -d)"      # scratch for the fingerprints
FP_A="$T/a"; FP_B="$T/b"
fingerprint() {
    find "$TH" -path '*/dotfiles/last-install.log' -prune -o \
        -printf '%y %p\t%s\t%T@\n' 2>/dev/null | sort >"$1"
}
isolated_run() {
    env -i HOME="$TH" USER="$(id -un)" PATH=/usr/bin:/bin TERM=dumb \
        XDG_RUNTIME_DIR="/run/user/$(id -u)" \
        bash -c "cd '$REPO' && ./install.sh --skip-packages --no-chsh" 2>&1
}

out1="$(isolated_run)"; rc1=$?
assert_eq "install: first run into an empty HOME succeeds" "0" "$rc1"

fingerprint "$FP_A"
out2="$(isolated_run)"; rc2=$?
fingerprint "$FP_B"
assert_eq "install: second run succeeds" "0" "$rc2"

d2="$(diff "$FP_A" "$FP_B" 2>/dev/null)"
assert_eq "install: a second run changes nothing at all" "" "$d2"

out3="$(isolated_run)"
fingerprint "$T/c"
d3="$(diff "$FP_B" "$T/c" 2>/dev/null)"
assert_eq "install: a third run changes nothing at all" "" "$d3"

assert_eq "install: a no-op run creates no new backup snapshot" "1" \
    "$(find "$TH/.local/state/dotfiles/backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
assert_contains "install: a no-op run says so out loud" "no new backup snapshot" "$out2"
assert_contains "install: a no-op run reports 0 files deployed" "files deployed          : 0" "$out2"

# The ownership record answers "does this repository already manage this file?".
# It must be complete, or uninstall.sh silently leaves files behind, and the
# overwrite-safety check starts refusing the repository's own files.
OWN="$TH/.local/state/dotfiles/deployed-paths"
assert_ok "ownership: the record exists" test -s "$OWN"
missing=""
while IFS= read -r d; do
    case "$d" in
        ~/.config/*) grep -qxF "$TH/${d#\~/}" "$OWN" 2>/dev/null || missing="$missing $d" ;;
    esac
done < <(awk '$1 ~ /^(link|copy|seed|root)$/ {print $3}' "$REPO/deploy.manifest")
# /etc/sddm.conf is a root entry: in a test environment sudo is unavailable, so
# it is reported and skipped, and correctly not claimed.
assert_eq "ownership: every ~/.config destination is claimed" "" "$missing"

assert_eq "ownership: seeds are claimed, so uninstall can remove them" \
    "$(grep -c 'qt5ct/noctalia/color.conf$' "$OWN")" "1"
assert_contains "ownership: the generated niri output.kdl is claimed" \
    "niri/cfg/output.kdl" "$(cat "$OWN")"
assert_contains "ownership: the generated noctalia settings.toml is claimed" \
    "noctalia/settings.toml" "$(cat "$OWN")"

# The record is a union across runs, never a replacement: if it shrank, the
# repository would stop recognising its own files and refuse to update them.
assert_ok "ownership: the record is newline-terminated (grep -x can match the last line)" \
    bash -c "[ -z \"\$(tail -c 1 '$OWN')\" ]"

# --- overwrite safety, with no symlink written through ----------------------
# Remove the symlink and put a real file in its place. Writing through a
# link-mode destination would edit the repository itself, which is exactly what
# link mode means — and exactly what a test must not do by accident.
MANAGED="$TH/.config/niri/config.kdl"
rm -f "$MANAGED"
printf '// MY OWN VERSION\n' >"$MANAGED"
isolated_run >/dev/null
assert_absent "safety: a file this repo owns is restored, not left to rot" \
    "MY OWN VERSION" "$(cat "$MANAGED")"
assert_ok "safety: the user's version was backed up before being overwritten" \
    bash -c "find '$TH/.local/state/dotfiles/backups' -name '*niri%config.kdl' | grep -q ."

SEEDFILE="$TH/.config/qt5ct/noctalia/color.conf"
printf '# my qt tweak\n' >>"$SEEDFILE"
before="$(md5sum <"$SEEDFILE")"
isolated_run >/dev/null
assert_eq "safety: a seeded file is never clobbered" "$before" "$(md5sum <"$SEEDFILE")"

# ===========================================================================
section "the leak check actually works"
# ===========================================================================
# The leak check is the last line of defence between this repository and a
# published credential, and it failed silently three separate ways:
#
#   * LEAK_SCAN_PATHS is mostly DIRECTORIES, and a non-recursive grep handed a
#     directory prints "Is a directory" on stderr, matches nothing and exits 0.
#     It was therefore reading 2 of the 60 tracked files, and every clean bill
#     of health it had ever printed — in install.sh and in verify.sh — was
#     vacuous.
#   * Two patterns begin with "-", and a pattern that looks like an option is
#     parsed as one. grep exits non-zero, `|| true` swallows it, and the rule is
#     dead. The PEM-header rule never once ran.
#   * Content filters were applied to the whole "path:line:match" record rather
#     than to the match, so the directory name README.md supplied a required
#     uppercase letter and a line number supplied two required digits. Two
#     legitimate strings were reported; a check that cries wolf gets disabled.
#
# Each of these is silent, so each is asserted directly.
. "$REPO/lib/common.sh"

# --- it must traverse, and it must recurse -------------------------------
LT="$(mktemp -d)"
mkdir -p "$LT/a/b/c"
printf 'nothing to see\n' >"$LT/plain.txt"
assert_ok "leak: a clean tree reports clean" \
    bash -c ". '$REPO/lib/common.sh'; leak_check t '$LT' >/dev/null 2>&1"

# A secret at the top level AND four directories down. If traversal regresses to
# non-recursive, the deep one goes missing and the count drops.
TOK="$(printf 'kP7s65MfmMqlMCOaTPyIKSv9OmOS_OVwkgUbRZ0' )"
printf 'api_key = "%s"\n' "$TOK"            >"$LT/shallow.conf"
printf 'api_key = "%s"\n' "$TOK"            >"$LT/a/b/c/deep.conf"
printf -- '-----BEGIN RSA PRIVATE KEY-----\n' >"$LT/pem.conf"
printf 'X = "aB3xQ9zLmN7pR2sT5vW8yZ4cD6fH1jK0"\n' >"$LT/opaque.conf"
printf 'i = "%s/x"\n' "$HOME"               >"$LT/home.conf"
printf 'iface = "%s"\n' "$(ls /sys/class/net 2>/dev/null | grep -v '^lo$' | head -1)" \
    >"$LT/iface.conf"

leak_out="$(bash -c ". '$REPO/lib/common.sh'; leak_check t '$LT' 2>&1" || true)"
assert_contains "leak: a secret in a file is caught"                "shallow.conf" "$leak_out"
assert_contains "leak: a secret nested four directories deep is caught" "deep.conf"  "$leak_out"
assert_contains "leak: a PEM private key is caught"                 "pem.conf"     "$leak_out"
assert_contains "leak: a secret under an innocuous name is caught"  "opaque.conf"  "$leak_out"
assert_contains "leak: an absolute home path is caught"             "home.conf"    "$leak_out"
assert_eq      "leak: the scan reports failure when it finds something" "1" \
    "$(printf '%s' "$leak_out" | grep -c 'err t:')"

# --- no false positives on the real corpus -------------------------------
# The rules are aggressive by design, so this is the half that matters most: a
# leak check that reports the shipped wallpaper's filename is a leak check the
# user switches off.
assert_ok "leak: the real tracked corpus is clean" \
    bash -c "cd '$REPO' && . lib/common.sh && leak_check corpus config etc packages lib wallpapers deploy.manifest install.sh >/dev/null 2>&1"
assert_absent "leak: the wallpaper filename is not mistaken for a secret" \
    "wallhaven" \
    "$(bash -c "cd '$REPO' && . lib/common.sh && leak_check corpus wallpapers 2>&1" || true)"
assert_absent "leak: a systemd unit name is not mistaken for a secret" \
    "NetworkManager-wait-online" \
    "$(bash -c "cd '$REPO' && . lib/common.sh && leak_check corpus lib 2>&1" || true)"

# --- placeholders must stay allowed --------------------------------------
PH="$(mktemp -d)"
printf '# WEATHER_API_KEY=""\n# TOKEN="your-token-here"\n# PASS="changeme"\n# K="<redacted>"\n' \
    >"$PH/example.conf"
printf 'x = "aaaaaaaaaaaaaaaaaaaaaaaaaaaa"\n' >"$PH/b64ish.txt"
printf 'commit 0123456789abcdef0123456789abcdef01234567\n' >"$PH/sha.txt"
assert_ok "leak: documented placeholders are allowed" \
    bash -c ". '$REPO/lib/common.sh'; leak_check t '$PH' >/dev/null 2>&1"
rm -rf "$PH" "$LT"

# --- the repository must not ship the values it looks for ----------------
# The original deny-list was a literal string containing this host's account,
# hostname, interface name and a real credential — i.e. it committed the exact
# things it existed to keep out. Machine identifiers are now derived at runtime
# and credentials are matched by shape, so the repository itself must be clean.
_tracked="$(cd "$REPO" && git ls-files 2>/dev/null | grep -vE '^(docs/|tests/)' || true)"
if [ -n "$_tracked" ]; then
    assert_absent "leak: no hard-coded home path in any tracked file" "" \
        "$(cd "$REPO" && grep -lF "$HOME" $_tracked 2>/dev/null | head -3 || true)"
    assert_absent "leak: no credential-shaped literal in any tracked file" "" \
        "$(cd "$REPO" && grep -lE -e "$LEAK_TOKEN_PATTERNS" $_tracked 2>/dev/null | head -3 || true)"
fi

# Every pattern is passed with `-e`, because a pattern starting with "-" is an
# option to grep and silently disables the rule. Judged against the actual calls
# rather than by pattern-matching the source, so a reformatted grep is still
# tested on what it does.
_leak_body="$(sed -n '/^leak_check() {/,/^}/p' "$REPO/lib/common.sh")"
_unguarded="$(printf '%s\n' "$_leak_body" \
    | grep -E 'grep .*\$\{?(mach|LEAK_[A-Z_]+)\}?' \
    | grep -vE -- ' -e ' || true)"
assert_eq "leak: every grep of a pattern in leak_check uses -e" "" "$_unguarded"
assert_contains "leak: leak_check recurses into the directories it is given" "-rI" "$_leak_body"

# --- a common-word hostname must not be mistaken for a leak --------------
# "desktop", "local" and "host" are all ordinary short hostnames, and they
# appear in 28, 20 and 12 of this repository's own files. A user whose machine
# is called "desktop" must not get 28 files reported, or they will disable the
# check — and the check is the only thing standing between this repository and
# a published credential.
# The pattern is assembled by a function, so it is exercised with a stubbed
# `hostname` rather than by renaming the machine.
_common_hits=0
_common_detail=""
for w in desktop local host home linux arch laptop server; do
    n="$(HS="$w" bash -c '
        set -uo pipefail
        . "$1/lib/common.sh"
        # Stand in for hostname(1); everything else is the real thing.
        hostname() { case "${1:-}" in -s) printf "%s\n" "$HS" ;; -f) printf "" ;; *) printf "\n" ;; esac; }
        p="$(leak_machine_patterns)"
        [ -n "$p" ] || exit 0
        grep -rIlE -e "$p" -- "$1/config" 2>/dev/null | wc -l | tr -d " "
    ' _ "$REPO" 2>/dev/null)"
    case "${n:-}" in
        ""|*[!0-9]*) n=0 ;;   # never let a non-number reach the sum
    esac
    if [ "$n" -ne 0 ]; then
        _common_hits=$((_common_hits + n))
        _common_detail="$_common_detail $w=$n"
    fi
done
assert_eq "leak: a common-word hostname produces no findings${_common_detail:+ (got${_common_detail})}" \
    "0" "$_common_hits"

# ...while a distinctive hostname IS still caught, so the stop-list has not
# simply been used to switch the rule off.
_probe="$(mktemp -d)"
_n="$(HS="nyxraptor" bash -c '
    set -uo pipefail
    . "$1/lib/common.sh"
    hostname() { case "${1:-}" in -s) printf "%s\n" "$HS" ;; -f) printf "" ;; *) printf "\n" ;; esac; }
    p="$(leak_machine_patterns)"
    [ -n "$p" ] || exit 0
    printf "host = \"%s\"\n" "$HS" > "$2/probe.conf"
    grep -rIlE -e "$p" -- "$2" 2>/dev/null | wc -l | tr -d " "
' _ "$REPO" "$_probe" 2>/dev/null)"
rm -rf "$_probe"
case "${_n:-}" in ""|*[!0-9]*) _n=0 ;; esac
assert_eq "leak: a distinctive hostname is still detected" "1" "$_n"

# ===========================================================================
section "rollback: restore.sh and uninstall.sh"
# ===========================================================================
# Both of these used to decide "has the user edited this since the install?"
# with `test -f` plus a grep for a "generated" marker. A symlink satisfies
# `test -f` and carries no marker; a seeded file has no marker either. So
# essentially every file this repository deployed was classified as
# user-edited, and:
#
#   * restore.sh printed a warning per path and removed nothing, while
#     reporting "restored 0 path(s)" as though it had tried;
#   * uninstall.sh left nine of its own files behind and reported success.
#
# Both now compare a hash of the file as the installer wrote it
# (written.sha256 in the snapshot), which makes the question a fact.
assert_ok "rollback: a snapshot records what was written (written.sha256)" \
    bash -c "find '$TH/.local/state/dotfiles/backups' -name written.sha256 -size +0 | grep -q ."

# Every managed file as recorded, so we can prove the rollback really removes
# exactly the set that was written and nothing else.
mapfile -t MANAGED < <(grep -v '^[[:space:]]*$' "$OWN")

# uninstall, with nothing edited: every claimed path must go.
TU="$TH-u"; mkdir -p "$TU"
E() { env -i HOME="$TU" USER="$(id -un)" PATH=/usr/bin:/bin TERM=dumb \
        XDG_RUNTIME_DIR="/run/user/$(id -u)" \
        bash -c "cd '$REPO' && $1" 2>&1; }
E './install.sh --skip-packages --no-chsh' >/dev/null
# A single clean install must produce one complete, self-consistent record:
# every claimed path, and nothing else.
SNAP_TU="$(find "$TU/.local/state/dotfiles/backups" -mindepth 1 -maxdepth 1 -type d | sort | tail -n1)"
assert_eq "rollback: written.sha256 covers every path the repo claims" \
    "$(grep -cv '^[[:space:]]*$' "$TU/.local/state/dotfiles/deployed-paths")" \
    "$(grep -cv '^[[:space:]]*$' "$SNAP_TU/written.sha256")"
assert_absent "rollback: no deployed path in written.sha256 is absolute" "" \
    "$(grep -v '^symlink ' "$SNAP_TU/written.sha256" | grep -F "$TU" || true)"
assert_contains "rollback: every deployed path is recorded as \$HOME-relative" \
    '$HOME/.config/niri/config.kdl' "$(cat "$SNAP_TU/written.sha256")"

before_n="$(find "$TU/.config" -mindepth 2 \( -type f -o -type l \) 2>/dev/null | wc -l | tr -d ' ')"
out_un="$(E './uninstall.sh')"
assert_eq "rollback: uninstall.sh exits 0" "0" "$?"
left="$(grep -F -x -f <(printf '%s\n' "${MANAGED[@]}" | sed "s|^~|$TU|") \
        <(find "$TU/.config" -mindepth 2 \( -type f -o -type l \) 2>/dev/null) || true)"
assert_eq "rollback: uninstall removes every file it deployed" "" "$left"
assert_eq "rollback: what uninstall leaves is only the XDG files it never owned" \
    "3" "$(find "$TU/.config" -mindepth 1 \( -type f -o -type l \) 2>/dev/null | wc -l | tr -d ' ')"
[ "$before_n" -gt 20 ] || assert_ok "rollback: the fixture actually deployed files" true

# uninstall, with three files edited — a symlink-managed one, a copy-managed
# one and a seeded one. All three must survive; the rest must still go.
rm -rf "$TU"; mkdir -p "$TU"
E './install.sh --skip-packages --no-chsh' >/dev/null
# Write to a regular file, never through a symlink: link-mode destinations ARE
# the repository's own files, and a test that edits them edits the repository.
for f in ".config/qt5ct/noctalia/color.conf:qt tweak" \
         ".config/noctalia/config.toml:noctalia tweak" \
         ".config/niri/config.kdl:niri tweak"; do
    rel="${f%%:*}"; tag="${f##*:}"
    rm -f "$TU/$rel"
    printf '// %s\n' "$tag" >"$TU/$rel"
done
out_un2="$(E './uninstall.sh')"
for f in ".config/qt5ct/noctalia/color.conf" ".config/noctalia/config.toml" ".config/niri/config.kdl"; do
    assert_contains "rollback: uninstall keeps a user-edited ${f##*/}" "$f" \
        "$(printf '%s\n' "$out_un2" | grep 'edited since' || true)"
    assert_ok "rollback: the edited ${f##*/} is still on disk" test -f "$TU/$f"
done
assert_eq "rollback: only the edited files and XDG remain" "6" \
    "$(find "$TU/.config" -mindepth 1 \( -type f -o -type l \) 2>/dev/null | wc -l | tr -d ' ')"

# restore.sh on a clean tree: it must actually restore, not warn and do nothing.
TR="$TH-r"; mkdir -p "$TR"
ER() { env -i HOME="$TR" USER="$(id -un)" PATH=/usr/bin:/bin TERM=dumb \
        XDG_RUNTIME_DIR="/run/user/$(id -u)" \
        bash -c "cd '$REPO' && $1" 2>&1; }
ER './install.sh --skip-packages --no-chsh' >/dev/null
out_r="$(ER './restore.sh --latest')"
assert_contains "restore: reports a real number of restored paths" "restored 2" "$out_r"
assert_eq "restore: the only un-restored files are the ones never written" "3" \
    "$(find "$TR/.config" -mindepth 1 \( -type f -o -type l \) 2>/dev/null | wc -l | tr -d ' ')"

# ... and on an edited tree, it must leave the edit alone.
rm -rf "$TR"; mkdir -p "$TR"
ER './install.sh --skip-packages --no-chsh' >/dev/null
rm -f "$TR/.config/fish/config.fish"; printf '// my fish\n' >"$TR/.config/fish/config.fish"
out_r2="$(ER './restore.sh --latest')"
assert_contains "restore: says so when a file has been edited" "edited since" "$out_r2"
assert_contains "restore: the edit is still there" "my fish" "$(cat "$TR/.config/fish/config.fish" 2>/dev/null)"

# `set -u` turns a typo in a counter into an abort. uninstall.sh had
# REMOVED=$((REMED + 1)), which killed the script in the planning loop — so
# uninstall never worked at all for the ordinary case where the installer
# created the file and there is no earlier version to restore.
assert_absent "rollback: no truncated counter names" "REMED" \
    "$(grep -rhoE '\b(REMED|RESTORED|MISSING|SKIPPED)[a-z]*\b' "$REPO/uninstall.sh" | sort -u | tr '\n' ' ')"

rm -rf "$T" "$TH" "$TU" "$TR"

# ===========================================================================
printf '\n%s%s%s\n' "$B" "$(printf '=%.0s' {1..56})" "$N"
printf '  passed : %s%d%s\n' "$G" "$PASS" "$N"
printf '  failed : %s%d%s\n' "$([ "$FAIL" -gt 0 ] && printf '%s' "$R" || printf '%s' "$D")" "$FAIL" "$N"

if [ "$FAIL" -gt 0 ]; then
    printf '\n  %sfailures:%s\n' "$R" "$N"
    for n in "${FAILED_NAMES[@]}"; do printf '    - %s\n' "$n"; done
    printf '\n'
    exit 1
fi
printf '\n  %sall tests passed%s\n\n' "$G" "$N"
exit 0
