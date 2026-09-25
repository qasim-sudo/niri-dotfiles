# Scope

**This repository reproduces a desktop environment. It is not a personal
workstation.**

That distinction is the single most important thing about this project, and it
is enforced in three places: the package tiers, the keybindings, and the
repository's leak check.

## There is no `--with-apps` flag

There is no way to ask this installer for any of the software below, and adding
one would be a mistake. The reason is not squeamishness about which programs are
"acceptable" — it is that **every one of them would have to be represented in
the configuration**, and most of them would leak personal state into a
repository.

A browser ships a profile directory. An editor ships a plugin set, a keymap and
a recent-files list. A game launcher ships a library. A security tool ships
target lists. None of that belongs in a dotfiles repository that other people
clone, and stripping it out is more work than not shipping it.

The list in `packages/excluded.txt` is **documentation only**. Nothing in it is
ever installed, configured, symlinked, or made a dependency of anything that is.

---

## Excluded software

### Browsers
`brave-bin`, `brave`, `google-chrome`, `chromium`

### Editors and IDEs
`visual-studio-code-bin`, `vscodium-bin`, `vscodium-bin-marketplace`, `code`,
`vscodium`, `zed`, `neovim`, `nvim`, `emacs`, `kate`

### Music and audio players
`spotify`, `spicetify-cli`, `spicetify-marketplace-bin`, `spotify-player`,
`ncmpcpp`

### Productivity
`todoist-appimage`, `todoist`, `obsidian`

### Mobile and cross-platform development
`android-studio`, `flutter-bin`, `flutter`

### Gaming
`steam`, `lutris`, `wine`, `wine-staging`, `proton-qt`, `gamescope`,
`mangohud`, `vkbasalt-cli`, `heroic`, `bottles`

### University coursework
`packettracer`, `wireshark-qt`, `wireshark-cli`

### Security and offensive tooling
`nmap`, `masscan`, `lynis`, `john`, `aircrack-ng`, `metasploit`, `hydra`,
`burpsuite`, `zaproxy`

### AI and agent tooling
`opencode`, `aider`, `continue`

### Virtualisation and containers
`virtualbox`, `qemu-desktop`, `qemu-full`, `docker`, `docker-compose`, `podman`,
`libvirt`

**The `nightwatch75/todo` Noctalia plugin is not in this list.** It is a plain
in-shell task widget with no network calls and no dependency. It is a *core*
plugin. It is not the Todoist application.

---

## Personal state that is never shipped

The installer reads none of these, the repository contains none of them, and
`.gitignore` blocks them from being committed by accident.

### Application configuration
```
~/.config/{spicetify,opencode,nvim,zed,Code,VSCodium,BraveSoftware,
           Google,spotify,spotify-player,obsidian}/**
```

### Application state
```
~/.local/state/opencode/**
~/.local/share/opencode/**
~/.config/fish/fish_variables      # absolute paths + a browser path
```

### Noctalia runtime state
```
~/.local/state/noctalia/notification_history.json
~/.local/state/noctalia/clipboard/          # encrypted, but still personal
~/.local/state/noctalia/usage_counts.json
~/.local/state/noctalia/recently_used.json
~/.local/state/noctalia/state.toml
~/.local/state/noctalia/location.json
~/.local/state/noctalia/weather.json
~/.local/share/noctalia/*-theme/**          # generated, machine-specific
```

The shipped `[wallpaper.favorite]` list is pruned from 16 entries to the single
wallpaper actually in use. A favourites list is personal taste, and 16
filenames is a small amount of information about the person who made the repo.

### Credentials and keys
```
~/.ssh/  ~/.gnupg/  ~/.local/share/keyrings/**  ~/.pulse-cookie
~/.config/dotfiles/local.conf      # mode 600, gitignored
```

The source machine contained a stored API credential in a third-party tool's
config file. It is not in this repository, and it is not the installer's job to
touch it. **If a credential has ever been committed to a repository, rotating it
is the only fix** — removing the file from the working tree does not un-publish
it from any clone or fork.

### Documents and downloads
```
~/Documents/**  ~/Downloads/**
```

The source configuration referenced two files under `~/Downloads/` as widget
icons. Both no longer existed on the source machine, so the `custom_image` keys
pointing at them were removed rather than replaced with a path to a file
nobody has. Noctalia falls back to each widget's `glyph`.

### Network state
```
~/.config/NetworkManager/system-connections/**    # saved Wi-Fi passwords
```

The installer manages `NetworkManager` as a service but never reads or writes
your saved connections.

---

## Dead references found during the audit

Documented rather than shipped, because shipping them would mean shipping a
reference to something that does not exist.

| Reference | Why it is not shipped |
|---|---|
| `~/Downloads/pixilart-drawing.png` | the file does not exist on the source machine |
| `~/Downloads/457d9d41cc81f410cc5d88f0c503ab53.png` | same |
| a `zen` window rule | the application is not installed |
| `DP-1` / `WL-1` output blocks | a specific monitor setup; the content of `output.kdl` is generated instead |
| `/usr/share/wayland-sessions/nothing.desktop` | an unowned file left by a different compositor, pointing at a binary that does not exist |
| 16 `[[wallpaper.favorite]]` entries | personal collection |
| `theme.custom_palette = "wallhaven-6lylmw-fs"` | a palette derived from a wallpaper that is not shipped; also unused, since the palette comes from the active wallpaper |
| `theme.templates` entries for `opencode`, `spicetify`, `neovim`, `zed`, `brave`, `ghostty`, `yazi` | Noctalia was generating theme files for software this desktop does not install |

## Unused software on the source machine

These were installed but unreferenced by the live configuration. They are
documented, not shipped, because including them would only add coupling:

`dms-shell`, `quickshell`, `dunst`, `rofi`, `wofi`, `wlogout`,
`illogical-impulse-*` (15 packages), `hypridle`, `matugen`, `breeze-plus`,
`qogir-icon-theme`, `qml-niri-git`, `alacritty`, `foot`, `ghostty`, `yazi`,
`btop`, `micro`, `nano`, `vim`, `lldb`, `less`, `bind`, `traceroute`, `inxi`,
`direnv`, `python-{numpy,opencv,pip}`, `frameworkintegration`.

### A consequence worth knowing

Several packages the desktop *does* depend on — kitty, fuzzel, playerctl,
brightnessctl, starship, eza, ripgrep, cliphist, wl-clipboard, matugen, fish —
were present on the source machine **only as dependencies of those unused
`illogical-impulse-*` packages**, never explicitly installed.

That is a latent breakage: an unrelated upgrade that drops one of those
dependencies silently removes a program a keybinding needs. So this repository
lists all of them explicitly in `packages/utilities.txt`, and `verify.sh` warns
when a keybinding target is present but not *explicitly* installed.

---

## Wallpapers

Exactly one wallpaper ships: `wallpapers/current/wallhaven-w5xokr_1920x1080.png`,
3.0 MB. That is the wallpaper the source desktop was actually displaying.

The source repository also contained a collection weighing several hundred
megabytes. **It is not in this repository**, and its history is not in this
repository's git history either — the project was initialised fresh rather than
filtered. A wallpaper collection is personal, is impractical to clone, and the
theme does not need it: `source = "wallpaper"` means the palette is computed
from whichever image is active, so any image works.

`wallpapers/fetch.sh` exists so you can populate a folder from Wallhaven
without committing images. It is **never run by the installer** and nothing
depends on it. Its output directory is gitignored.

## What the installer actively refuses to do

- run as root
- remove a package
- touch `grub`, `efibootmgr`, or any partition
- enable or disable `niri.service`
- overwrite `~/.config/mimeapps.list` without `--force-mimeapps` plus a
  confirmation
- overwrite any file it has not previously managed, without `--force`
- write a secret, or read one other than `local.conf`
- install from `packages/excluded.txt`

## Adding something back

Everything is a plain directory and plain text. Install the software, then add
your own binding:

```sh
sudo pacman -S your-package
vim ~/dotfiles/config/niri/cfg/binds.kdl    # add the binding
./install.sh --only=binds
```

That is the whole point of keeping the config symlinked.
