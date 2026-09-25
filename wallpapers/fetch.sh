#!/usr/bin/env bash
# wallpapers/fetch.sh — optional wallpaper fetcher.
#
# NOT part of the installation. The desktop does not need this script, and
# nothing in the repository runs it automatically. It exists so you can populate
# a wallpaper folder from Wallhaven without committing images to git.
#
#   ./fetch.sh                      fetch the default presets
#   ./fetch.sh 1920x1080 nature     fetch your own search
#   ./fetch.sh --list               show the presets
#   ./fetch.sh --out ~/Pictures/Wallpapers 1920x1080 nature
#
# Requires: curl.  Set WALLHAVEN_API_KEY in the environment for a higher rate
# limit. Output goes to --out (default: wallpapers/favorites, which is
# gitignored). Copy anything you want to keep into your Noctalia wallpaper
# directory by hand.

set -euo pipefail

OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/favorites"
RESOLUTION="1920x1080"
QUERY=""
PAGES=1
LIST=0

# The presets correspond to wallpaper aesthetics this theme pairs well with.
declare -a PRESET_NAMES=(nightcity nature architecture minimal abstract)
declare -a PRESET_QUERY=("night city neon" "forest fog nature" "modern architecture" "minimal dark gradient" "abstract dark")

usage() {
    sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --list)   LIST=1; shift ;;
        --out)    OUT_DIR="$2"; shift 2 ;;
        --pages)  PAGES="$2"; shift 2 ;;
        -h|--help) usage ;;
        -*) echo "unknown option: $1" >&2; exit 1 ;;
        *)
            if [ -z "$QUERY" ] && printf '%s' "$1" | grep -qE '^[0-9]+x[0-9]+$'; then
                RESOLUTION="$1"; shift
            elif [ -z "$QUERY" ]; then
                QUERY="$1"; shift
            else
                PAGES="$1"; shift
            fi
            ;;
    esac
done

if [ "$LIST" = 1 ]; then
    printf 'presets:\n'
    for i in "${!PRESET_NAMES[@]}"; do
        printf '  %-14s %s\n' "${PRESET_NAMES[$i]}" "${PRESET_QUERY[$i]}"
    done
    exit 0
fi

command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
mkdir -p "$OUT_DIR"

fetch_one() {
    local query="$1" tag="$2"
    local url
    if [ -n "${WALLHAVEN_API_KEY:-}" ]; then
        url="https://wallhaven.cc/api/v1/search?categories=100&purity=100&sorting=toplist&atleast=${RESOLUTION}&q=$(printf '%s' "$query" | sed 's/ /%20/g')&page=1"
    else
        url="https://wallhaven.cc/api/v1/search?categories=100&purity=100&sorting=toplist&atleast=${RESOLUTION}&q=$(printf '%s' "$query" | sed 's/ /%20/g')&page=1"
    fi

    echo "-> $tag"
    local json
    json="$(curl -fsSL --max-time 30 "$url")" || { echo "   request failed"; return 0; }

    # Requires jq for parsing. Without it, print the raw JSON and stop.
    command -v jq >/dev/null 2>&1 || { echo "   jq not installed; raw response follows"; echo "$json"; return 0; }

    local path
    while IFS= read -r path; do
        [ -z "$path" ] && continue
        local out="$OUT_DIR/${tag}-$(basename "$path")"
        [ -s "$out" ] && { echo "   have $(basename "$out")"; continue; }
        curl -fsSL --max-time 60 -o "$out" "$path" && echo "   saved $(basename "$out")"
    done < <(printf '%s' "$json" | jq -r '.data[]?.path' 2>/dev/null)
}

if [ -n "$QUERY" ]; then
    fetch_one "$QUERY" "custom"
else
    for i in "${!PRESET_NAMES[@]}"; do
        fetch_one "${PRESET_QUERY[$i]}" "${PRESET_NAMES[$i]}"
    done
fi

echo
echo "done. images are in: $OUT_DIR"
echo "that directory is gitignored. copy what you want into your Noctalia"
echo "wallpaper directory by hand."
