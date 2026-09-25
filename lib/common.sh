#!/usr/bin/env bash
# lib/common.sh — logging, colours, dry-run gating, assertions.
# Sourced by install.sh / uninstall.sh / restore.sh / verify.sh.
# Not executable on its own.

# Guard against double-sourcing.
[ -n "${DOTFILES_COMMON_SH:-}" ] && return 0
DOTFILES_COMMON_SH=1

# ---------------------------------------------------------------------------
# State (populated by install.sh before sourcing, defaulted here for the
# auxiliary scripts so each can be run standalone).
# ---------------------------------------------------------------------------
: "${DOTFILES_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${DRY_RUN:=0}"
: "${FORCE:=0}"
: "${TARGET_USER:=${SUDO_USER:-${USER:-}}}"
: "${LOG_FILE:=}"
: "${LOG_INITIALISED:=0}"

# Where all installer-owned state lives.
: "${STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles}"
: "${BACKUP_ROOT:=$STATE_DIR/backups}"

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
    C_RED=$'\033[31m';  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'
else
    C_RESET=; C_BOLD=; C_DIM=; C_RED=; C_GREEN=; C_YELLOW=; C_BLUE=; C_CYAN=
fi

# Counters, reported by the summary.
LOG_FILE=""
LOG_IS_TEMP=0
STATS_PACKAGES=0
STATS_HARDWARE=0
STATS_DEPLOYED=0
STATS_GENERATED=0
STATS_SKIPPED=0
STATS_FAILED=0
STATS_WARNINGS=0

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
# Defined HERE, not in install.sh, because all five entry points (install,
# uninstall, restore, verify, regenerate) source this file and more than one of
# them needs these paths. Keeping them in the entry point meant a variable
# defined in exactly one place that the other four assumed existed — which is
# how `regenerate.sh` died on an unbound WALLPAPER_DIR.
#
# Each uses :- so ~/.config/dotfiles/local.conf, which is sourced later, wins.
# ---------------------------------------------------------------------------
TARGET_USER="${SUDO_USER:-${USER:-$(id -un)}}"
WALLPAPER_DIR="${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}"
ASSETS_DIR="${ASSETS_DIR:-$HOME/.local/share/dotfiles/assets}"
LOCAL_CONF="${LOCAL_CONF:-$HOME/.config/dotfiles/local.conf}"
export TARGET_USER WALLPAPER_DIR ASSETS_DIR LOCAL_CONF

# Source ~/.config/dotfiles/local.conf if it exists. READ ONLY — the installer
# never writes it, and it is the one file that is gitignored.
#
# Every entry point calls this, because WALLPAPER_DIR feeds the generated
# Noctalia overlay, and regenerate.sh has to honour the same override the
# installer did or the two would disagree about which wallpaper is active.
load_local_conf() {
    [ -f "$LOCAL_CONF" ] || return 0
    # shellcheck disable=SC1090
    if . "$LOCAL_CONF"; then
        return 0
    fi
    warn "could not read $LOCAL_CONF; continuing with defaults"
    return 1
}

_log_raw() {
    [ -n "$LOG_FILE" ] && printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >>"$LOG_FILE" 2>/dev/null
    return 0
}

_log_init() {
    [ "$LOG_INITIALISED" = 1 ] && return 0
    LOG_INITIALISED=1

    # A dry run must not touch the filesystem. Not even a log file — "it only
    # wrote a log" is how a dry-run guarantee quietly stops meaning anything,
    # and here it also truncated the log from the last real install. So the log
    # goes to a temp file instead, and is never cleaned up on the caller's
    # behalf: the summary says where it is.
    if [ "${DRY_RUN:-0}" = 1 ]; then
        LOG_FILE="$(mktemp "${TMPDIR:-/tmp}/dotfiles-dry-run.XXXXXX.log")" || LOG_FILE=""
        LOG_IS_TEMP=1
        return 0
    fi

    mkdir -p "$STATE_DIR" 2>/dev/null || true
    LOG_FILE="$STATE_DIR/last-install.log"
    : >"$LOG_FILE" 2>/dev/null || LOG_FILE=""
    return 0
}

info()  { printf '%s  ->%s %s\n' "$C_BLUE" "$C_RESET" "$*"; _log_raw "INFO  $*"; }
step()  { printf '\n%s==>%s %s%s%s\n' "$C_CYAN$C_BOLD" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"; _log_raw "STEP  $*"; }
ok()    { printf '%s  ok%s %s\n' "$C_GREEN" "$C_RESET" "$*"; _log_raw "OK    $*"; }
warn()  { printf '%swarn%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; _log_raw "WARN  $*"; STATS_WARNINGS=$((STATS_WARNINGS + 1)); }
err()   { printf '%s err%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; _log_raw "ERROR $*"; }
note()  { printf '%s     %s%s\n' "$C_DIM" "$*" "$C_RESET"; _log_raw "NOTE  $*"; }
dry()   { printf '%s   ~%s %s %s(dry-run)%s\n' "$C_DIM" "$C_RESET" "$*" "$C_DIM" "$C_RESET"; _log_raw "DRY   $*"; }
die()   { err "$*"; exit 1; }

# Interactive confirmation. Honours --force, and never blocks in a dry run.
confirm() {
    local prompt="$1" reply
    [ "$FORCE" = 1 ] && return 0
    if [ ! -t 0 ]; then
        warn "not a TTY; proceeding without confirmation: $prompt"
        return 0
    fi
    read -r -p "$prompt? [y/N] " reply
    case "$reply" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------------------
# Dry-run gate. Every mutating action in the installer funnels through `run`.
#   run <description> -- <command...>
# ---------------------------------------------------------------------------
run() {
    local desc="$1"; shift
    [ "$1" = "--" ] && shift
    if [ "$DRY_RUN" = 1 ]; then
        dry "$desc :: $(printf '%q ' "$@")"
        return 0
    fi
    _log_raw "RUN   $desc :: $*"
    "$@"
}

# Like run, but for commands that must not be logged with full arguments
# (nothing currently uses it; kept so password-bearing calls are never added by
# accident to a line that gets written to a log file).
run_quiet() { local d="$1"; shift; [ "$1" = "--" ] && shift; run "$d" -- "$@"; }

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------
require_cmd() {
    local missing=()
    for c in "$@"; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
    [ ${#missing[@]} -eq 0 ] || die "required command(s) not found: ${missing[*]}"
}

assert_not_root() {
    [ "$(id -u)" -eq 0 ] && die "do not run this installer as root. Run it as your normal user; it will call sudo where needed."
}

# Read a package list file, stripping comments and blanks.
read_list() {
    local f="$1"
    [ -f "$f" ] || return 0
    sed -e 's/#.*$//' -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' "$f" | grep -v '^$'
}

have_pkg() { pacman -Qq "$1" >/dev/null 2>&1; }

# True if the package is explicitly installed (not merely pulled in as a dep).
explicit_pkg() { pacman -Qqe 2>/dev/null | grep -qx -- "$1"; }

# ---------------------------------------------------------------------------
# unit_state <unit> [user|system]
#
# Prints the enablement state of a systemd unit, one word, on stdout.
# Prints "unknown" if it cannot be determined.
#
# This exists because the obvious one-liner is wrong, and being wrong about it
# is expensive:
#
#     systemctl --user is-enabled "$u" 2>/dev/null || echo unknown
#
# `is-enabled` prints its answer on stdout but exits NON-ZERO for a unit that is
# merely DISABLED. So the `||` branch also ran, and the captured value became
# the two-line string "disabled\nunknown" — which matches no case statement
# anywhere. In verify.sh that made the "conflicting services must be disabled"
# check report a correctly disabled dms/hypridle/cliphist as enabled and warn
# that it "will fight Noctalia", on every properly configured machine. In
# packages.sh the same value matched no arm at all, so the installer's own
# assertion silently printed nothing. In the niri.service check it made a
# genuinely disabled niri.service report as "not found".
#
# Never test the exit status of `is-enabled`; take the answer from stdout.
# ---------------------------------------------------------------------------
unit_state() {
    local u="$1" scope="${2:-user}"
    local st
    if [ "$scope" = user ]; then
        st="$(systemctl --user is-enabled "$u" 2>/dev/null)"
    else
        st="$(systemctl is-enabled "$u" 2>/dev/null)"
    fi
    # A unit name is a single token, so the first line is the whole answer.
    st="$(printf '%s' "$st" | head -n1 | tr -d '[:space:]')"
    printf '%s' "${st:-unknown}"
}

# ---------------------------------------------------------------------------
# write_if_changed <staged-file> <dest>
#
# Install <staged-file> as <dest>, but only if the content actually differs.
# Returns 0 if written, 1 if it was already identical (and the staged file is
# removed).
#
# Every write in this repository goes through here, because an installer that
# rewrites identical files is not idempotent in any way that matters:
#
#   * niri and Noctalia both watch their config directories and reload on
#     change, so re-running with no edits caused a spurious reload every time.
#   * mtime-based tooling — backup scripts, sync tools, dotfile managers,
#     `find -newer` — can no longer tell "changed" from "ran", so every run
#     looked like a change.
#   * It made the "what did this run do" summary a lie: files deployed said 2
#     on a run that changed nothing.
#
# The comparison is on content, so a genuine edit is still written.
# ---------------------------------------------------------------------------
write_if_changed() {
    local staged="$1" dest="$2"
    if [ -f "$dest" ] && cmp -s "$staged" "$dest"; then
        rm -f "$staged"
        return 1
    fi
    install -m 0644 "$staged" "$dest" || { rm -f "$staged"; return 2; }
    rm -f "$staged"
    return 0
}

# Print a compact summary table. In a dry run every number is a count of what
# WOULD happen, so the labels say so — a dry run reporting "packages installed:
# 11" is a lie that reads like a fact.
print_summary() {
    local lbl_pkgs="packages installed" \
          lbl_dep="files deployed" \
          lbl_gen="files generated" \
          lbl_skip="paths skipped"
    if [ "$DRY_RUN" = 1 ]; then
        lbl_pkgs="packages to install"
        lbl_dep="files to deploy"
        lbl_gen="files to generate"
        lbl_skip="paths to skip"
    fi

    step "Summary"
    printf '    %-24s: %s\n' "$lbl_pkgs" "$STATS_PACKAGES"
    printf '    %-24s: %s\n' "hardware tier added" "$STATS_HARDWARE"
    printf '    %-24s: %s\n' "$lbl_dep" "$STATS_DEPLOYED"
    printf '    %-24s: %s\n' "$lbl_gen" "$STATS_GENERATED"
    printf '    %-24s: %s\n' "$lbl_skip" "$STATS_SKIPPED"
    printf '    %-24s: %s\n' "warnings" "$STATS_WARNINGS"
    # Only shown when non-zero: a summary that always has a "failed" line reads
    # as though something is always broken, and people stop looking at it.
    if [ "$STATS_FAILED" -gt 0 ]; then
        printf '    %-24s: %s  %s(see the warnings above; the run continued)%s\n' \
               "failed but not fatal" "$STATS_FAILED" "$C_DIM" "$C_RESET"
    fi
    if [ -n "$LOG_FILE" ]; then
        if [ "$LOG_IS_TEMP" = 1 ]; then
            printf '    %-24s: %s\n' "log (temp)" "$LOG_FILE"
            printf '    %-24s  %snot a real run, so nothing under %s was touched%s\n' \
                   "" "$C_DIM" "$STATE_DIR" "$C_RESET"
        else
            printf '    %-24s: %s\n' "log" "$LOG_FILE"
        fi
    fi
    printf '\n'
}

banner() {
    printf '%s%s  %s dotfiles  %sv%s\n' \
        "$C_BOLD" "$C_CYAN" "${1:-arch}" "$C_RESET$C_DIM" "$(cat "$DOTFILES_ROOT/VERSION" 2>/dev/null || echo dev)"
    printf '%s  %s -> niri -> noctalia -> your desktop%s\n' "$C_DIM" "$(uname -m)" "$C_RESET"
    printf '\n'
}

# ===========================================================================
# Leak check
# ===========================================================================
# Two separate questions, deliberately answered by two separate mechanisms.
#
# 1. Is anything MACHINE-SPECIFIC about this host baked into a file that will
#    be deployed to some other host? Account name, home path, hostname,
#    interface name.
#
# 2. Is there a CREDENTIAL anywhere in a tracked file?
#
# The first was originally answered with a hard-coded deny-list of this
# machine's values. That has two flaws, and the second is severe:
#
#   * it commits the very identifiers it exists to keep out of the
#     repository — the account name, the hostname and the Wi-Fi interface
#     name were all in the repository, in the file whose job was to prevent
#     exactly that;
#
#   * it listed one real credential as a literal pattern, so committing the
#     repository would have published a live secret. A credential in git
#     history cannot be deleted, only rotated. (The credential in question was
#     a service password belonging to the author, not to this project; it has
#     been removed from this file and should be rotated.)
#
# So: machine identifiers are DERIVED AT RUNTIME, so nothing personal is
# committed and the check adapts to whoever runs it, and credentials are
# matched BY SHAPE rather than by value, so it catches secrets the author never
# knew existed.

# leak_machine_patterns
# Prints an ERE matching this host's identifiers. Derived, never literal.
leak_machine_patterns() {
    local pats=() u h i n

    # The home path itself. Catches any absolute home directory in a file that
    # is about to be deployed somewhere else. "/" is not an ERE metacharacter,
    # so escaping it only makes grep warn about a stray backslash.
    [ -n "${HOME:-}" ] && pats+=("$(printf '%s' "$HOME" | sed 's/[][\.*^$(){}?+|]/\\&/g')")

    # The account name, in the form it appears in a path.
    u="$(id -un 2>/dev/null || printf '%s' "${USER:-}")"
    [ -n "$u" ] && pats+=("/home/${u}([^A-Za-z0-9_-]|\$)")

    # The fully-qualified hostname. A dotted name is an identifier by
    # construction, so it is always worth looking for.
    h="$(hostname -f 2>/dev/null || true)"
    [ -n "$h" ] && pats+=("(^|[^A-Za-z0-9_-])${h}([^A-Za-z0-9_-]|\$)")

    # The SHORT hostname, but only when it looks like an identifier rather than
    # a word. This distinction is not cosmetic: "desktop", "local" and "host"
    # are all perfectly ordinary short hostnames, and they appear in 28, 20 and
    # 12 of this repository's own files respectively. Matching them as leaks
    # would fail verify.sh on a large share of real machines, with a message
    # about a hostname that has nothing to do with what was found. So a
    # four-character floor, and a stop-list of the generic words that show up in
    # desktop configuration. A host called "nyx" is still caught; a host called
    # "desktop" is not mistaken for a leak.
    h="$(hostname -s 2>/dev/null || true)"
    case "$h" in
        ''|?|??|???)
            # Too short to be evidence of anything.
            ;;
        *.*)
            pats+=("(^|[^A-Za-z0-9_-])${h}([^A-Za-z0-9_-]|\$)")
            ;;
        desktop|local|localhost|host|home|linux|arch|pc|laptop|server|client|\
        test|dev|prod|staging|user|users|main|admin|root|default|unknown|\
        workstation|system|node|box|machine|computer)
            ;;
        *)
            pats+=("(^|[^A-Za-z0-9_-])${h}([^A-Za-z0-9_-]|\$)")
            ;;
    esac

    # Network interface names, as a standalone word. Names under three
    # characters are skipped: "lo" and friends match ordinary English.
    for i in /sys/class/net/*; do
        [ -e "$i" ] || continue
        n="$(basename "$i")"
        [ "${#n}" -ge 3 ] || continue
        pats+=("(^|[^A-Za-z0-9_-])${n}([^A-Za-z0-9_-]|\$)")
    done

    local out='' p
    for p in "${pats[@]+"${pats[@]}"}"; do
        [ -n "$p" ] || continue
        out="${out:+$out|}$p"
    done
    printf '%s' "$out"
}

# Credential-shaped things, matched case-insensitively: a credential-ish name
# assigned a non-placeholder value. Placeholders are excluded so an .example
# file documenting the setting does not trip its own scanner.
LEAK_SECRET_PATTERNS='(pass(word|wd)?|secret|token|api[_-]?key|apikey|private[_-]?key|credential|bearer|auth)[[:space:]]*[:=][[:space:]]*.?[A-Za-z0-9/+_.=-]{8,}'

# Values that are obviously not secrets. Matched against the whole assignment.
LEAK_PLACEHOLDER_VALUES='(your|example|changeme|placeholder|redacted|dummy|todo|fixme|none|null|xxx|<[^>]*>|\.\.\.)'

# Credential and key material, matched case-SENSITIVELY by shape. These are
# unambiguous: no legitimate config value looks like a PEM header or a
# provider's key format.
LEAK_TOKEN_PATTERNS='-----BEGIN [A-Z ]*PRIVATE KEY-----|\b(sk|pk|rk)-[A-Za-z0-9_-]{20,}|\bgh[pousr]_[A-Za-z0-9]{20,}|\bAKIA[0-9A-Z]{16}\b|\bxox[baprs]-[A-Za-z0-9-]{10,}|\bAIza[0-9A-Za-z_-]{30,}'

# Long opaque runs, as a last resort. Catches a secret stored under a name that
# says nothing about it, which the keyword pass above cannot see.
#
# The character class excludes / . and : so paths and hostnames are not
# candidates, and the pipeline below additionally requires an uppercase letter,
# a lowercase letter and two digits, and rejects pure hex — which is what keeps
# git SHAs, colour codes and long English words out of the report. Without those
# filters this rule is pure noise, and a leak check that cries wolf gets
# switched off.
LEAK_OPAQUE_MIN=24

# Where a leak would actually matter: the tracked sources that get deployed,
# plus every shipped script, since a script that hard-codes this host's account
# or carries a credential is just as wrong as a config that does.
#
# NOT docs/ — the prose explains what was deliberately left out, and quoting an
# identifier in order to say "this is not here" is not a leak.
# NOT tests/ — the fixtures must contain plausible hardware names, or they are
# not testing anything.
LEAK_SCAN_PATHS=(config etc packages lib wallpapers deploy.manifest
                 install.sh uninstall.sh restore.sh verify.sh regenerate.sh)

# leak_check <label> <path...>
# Reports every hit. Returns 1 if any were found.
#
# Paths may be files OR directories, and the directories matter: LEAK_SCAN_PATHS
# is mostly directories, and a non-recursive grep given a directory prints
# "Is a directory" on stderr, matches nothing, and exits 0. That is not a
# failure — it is silence. So this function reported a clean bill of health
# while reading 2 of the 60 tracked files, and every "ok no account names,
# hostnames, interface names or credentials" it ever printed, in install.sh and
# in verify.sh, was vacuous. `grep -r` fixes the traversal; `-I` keeps it out of
# the binary wallpaper, where a plaintext match would be meaningless anyway.
#
# Every grep below passes its pattern with `-e`. Two of these patterns begin with
# a dash, and a pattern that looks like an option is parsed as one: grep exits
# with "unrecognized option", the non-zero status is swallowed by `|| true`, and
# the check reports nothing. That is how the PEM-header rule was silently dead.
leak_check() {
    local label="$1"; shift
    local p hits total=0
    local mach

    mach="$(leak_machine_patterns)"

    for p in "$@"; do
        [ -e "$p" ] || continue

        # Machine-specific values, case-sensitive, this host's own identifiers.
        hits=''
        [ -n "$mach" ] && hits="$(grep -rInE -e "$mach" -- "$p" 2>/dev/null || true)"

        # Credential-ish assignments, case-insensitive, minus placeholders.
        hits="$hits
$(grep -rInEi -e "$LEAK_SECRET_PATTERNS" -- "$p" 2>/dev/null \
    | grep -Eiv -e "$LEAK_PLACEHOLDER_VALUES" || true)"

        # Key material by shape, case-sensitive.
        hits="$hits
$(grep -rInE -e "$LEAK_TOKEN_PATTERNS" -- "$p" 2>/dev/null || true)"

        # Long opaque runs under any name at all.
        #
        # The filters below look at $NF — the MATCH — and not at the whole
        # "path:line:match" record, because that prefix is not part of the
        # candidate. Filtering the record instead flagged two perfectly
        # legitimate strings: the shipped wallpaper's filename
        # "wallhaven-w5xokr_1920x1080" was reported because the directory it
        # lives in is named README.md, which supplies the uppercase letter the
        # rule asks for; and the systemd unit "NetworkManager-wait-online" was
        # reported because its line number, 319, supplied the two digits. A
        # rule that reports those is a rule that gets switched off.
        hits="$hits
$(grep -rInEo -e "[A-Za-z0-9_-]{${LEAK_OPAQUE_MIN},}" -- "$p" 2>/dev/null \
    | awk -F: '{
          m = $NF
          if (m !~ /[A-Z]/)      next   # needs mixed case: rules out prose
          if (m !~ /[a-z]/)      next
          if (m !~ /[0-9].*[0-9]/) next  # needs entropy: rules out identifiers
          if (m ~  /^[0-9a-f]+$/) next  # rules out git SHAs and hex digests
          print
      }' || true)"

        hits="$(printf '%s\n' "$hits" | grep . || true)"
        if [ -n "$hits" ]; then
            printf '%s\n' "$hits" | sed "s|^|      |"
            total=$((total + $(printf '%s\n' "$hits" | grep -c .)))
        fi
    done

    if [ "$total" -gt 0 ]; then
        err "$label: $total machine-specific or secret value(s) found"
        note "the repository must not contain this host's account, home path,"
        note "hostname or interface names, nor any credential."
        note "Credentials belong in ~/.config/dotfiles/local.conf, which is"
        note "gitignored. A secret that reaches git history must be ROTATED."
        return 1
    fi
    ok "$label: no account names, hostnames, interface names or credentials"
    return 0
}

