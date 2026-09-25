# Wallpapers

## What ships

Exactly one wallpaper, in `current/`:

    wallhaven-w5xokr_1920x1080.png

That is the wallpaper the source desktop was actually displaying (it comes from
Noctalia's `[wallpaper.last]` in the live runtime overlay), and it is what the
installed configuration points at. It is 3.0 MB.

No personal wallpaper collection is included, and none is required. The desktop
reads `[wallpaper.directory]` from `config/noctalia/config.toml`; drop any image
you like into `~/Pictures/Wallpapers` and Noctalia's wallpaper panel (`Mod+W`)
will find it.

## The optional fetch mechanism

`fetch.sh` is **not run by the installer** and is never required. It exists so
you can repopulate a wallpaper folder from Wallhaven without this repository
carrying the images.

    ./fetch.sh                      # fetch the defaults into wallpapers/favorites
    ./fetch.sh 1920x1080 landscape  # your own search
    ./fetch.sh --list               # show the configured presets

Requirements: `curl`. Optionally set `WALLHAVEN_API_KEY` in the environment to
raise the rate limit.

Fetched images land in `wallpapers/favorites/`, which is **gitignored**. Copy
anything you want to keep into `~/Pictures/Wallpapers` yourself.

## Why nothing else is committed

A wallpaper collection is personal, is measured in hundreds of megabytes, and
makes the repository unusable to clone. Committing the source machine's
collection also leaks personal taste and file names. The theme derives its
palette from whichever wallpaper is active
(`[theme] source = "wallpaper"`, `wallpaper_scheme = "m3-content"`), so any
image works — no specific file is baked into the colour scheme.
