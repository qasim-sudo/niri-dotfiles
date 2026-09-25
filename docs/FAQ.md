# FAQ

## Why does it look plain right after installing?

Because the palette comes from the wallpaper, and Noctalia computes it on first
start. Give it a few seconds. If the bar is still unstyled, check that
Noctalia started at all:

```sh
journalctl --user --since '2 min ago' | grep -i noctalia
```

You can also force a specific palette without touching anything else — pick
`Tokyo-Night` and set `source = "builtin"` in
`~/dotfiles/config/noctalia/config.toml`, then re-run `./install.sh`.

## Why is the Accent colour in the lock screen different from the bar?

It shouldn't be. The lock screen reads the same palette. If it does not, the
cause is a monitor scale difference: the login box is positioned in each
display's own pixel space, which is computed at install time. Re-run
`./regenerate.sh` from inside your session after a display change.

## Can I use a different wallpaper?

Yes, any image. Drop it in `~/Pictures/Wallpapers` and press `Mod+W`. The theme
derives its palette from the active image
(`[theme] source = "wallpaper"`, `wallpaper_scheme = "m3-content"`), so nothing
is baked into the colour scheme.

To change what the desktop starts with, edit `[wallpaper.default]` and
`[wallpaper.last]` in `~/dotfiles/config/noctalia/config.toml`.

## Why is there only one wallpaper in the repository?

Because a wallpaper collection is personal and is measured in hundreds of
megabytes. The source repository had one, and its git history carried the
weight. This repository was initialised fresh rather than filtered, so the
history is not here either.

`wallpapers/fetch.sh` will populate a folder from Wallhaven if you want to
build a collection. It is never run by the installer, nothing depends on it, and
its output directory is gitignored.

## Why are `cliphist` and `wl-clipboard` not used?

Noctalia does not need them. It implements the Wayland clipboard protocol
natively, keeps its own encrypted history in
`~/.local/state/noctalia/clipboard/`, and drives
`zwp_virtual_keyboard_v1` directly rather than shelling out to `wtype`.

A second clipboard watcher on the same Wayland selection breaks paste in
Noctalia. The installer actively asserts that `cliphist.service` stays
disabled, for exactly that reason.

Both are in `packages/optional.txt` if you want them for a terminal workflow.

## Why do I have to log out and back in?

Three things need a new session:

- **group membership** — the kernel only reads a supplementary group set at
  login
- **the login shell** — read from `/etc/passwd` when the session starts
- **user unit state** — enable and mask changes take effect on the next session

`./install.sh` tells you this at the end. It is not boilerplate; each of those
is a real thing that will not work until you do.

## Can I install onto a machine that already has a desktop?

Yes. That is the case the deploy rules are built for.

A destination is only overwritten if it **already exists and this repository
managed it before**, or **does not exist**, or you passed `--force`. A
pre-existing file this repository has never touched is left alone and reported
in the summary as a skip. So your existing `~/.config/niri/config.kdl` is
backed up and skipped, not destroyed.

To take ownership anyway:

```sh
./install.sh --force
```

## Will it remove anything?

**No package is ever removed.** Not as a dependency, not as a conflict
resolution, not implicitly. If pacman reports a conflict, the installer stops
and prints the manual command.

`uninstall.sh` also removes no packages — many of them are shared with things
this repository has nothing to do with. If you want a package gone, use your
package manager.

## Why does it need sudo at all?

For `pacman`, `usermod`, `chsh`, and writing `/etc/sddm.conf` and the SDDM
theme metadata. It refuses to run **as** root, because running as root means
`$HOME` is `/root` and every config file would land in the wrong place.

## Does it touch my bootloader?

No. Not `grub`, not `efibootmgr`, not a partition, not an initramfs. Enabling
`linux` in `core.txt` puts the kernel package in place; regenerating the
bootloader is yours to trigger if you ever change kernels.

## What happens to `niri.service`?

Nothing. It is a **static** unit started by SDDM through `niri-session`.
Enabling or disabling it breaks the login session, so the installer never
touches it and `verify.sh` fails if it is anything other than `static`.

## Why is `output.kdl` almost empty in the repository?

Its **content** is not in the repository, and never will be. It contains output
connector names, modes, scale factors and positions. All four are properties of
the display attached right now, and wrong the moment you undock. Committing them
means committing a monitor name, a resolution and a layout.

What *is* committed is a **comment-only placeholder**, because `config.kdl` does
`include "cfg/output.kdl"` unconditionally and niri has no optional include — a
missing file there is a hard config error, so without the placeholder a fresh
clone would have a config that does not load. The placeholder has no `output`
block, so niri auto-detects and everything works.

Same reasoning for `~/.local/state/noctalia/settings.toml`: the table
`[wallpaper.monitors.eDP-1]` *is* a connector name, and the lock-screen
`cx = 960` is a resolution.

`./regenerate.sh` rebuilds both. With no niri session running it still writes
valid output — niri auto-detects, and the lock screen gets one
display-agnostic login box.

## Can I edit the config and have it stick?

Edit it **in the repository**, then re-run the installer:

```sh
vim ~/dotfiles/config/niri/cfg/binds.kdl
./install.sh --only=binds
```

niri, kitty, fish, starship, fastfetch, fuzzel and the GTK settings are
**symlinked**, so editing the repo file is already live — no reinstall needed at
all.

Files Noctalia owns — `config.toml`, the theme files — are **real copies**.
Noctalia rewrites `config.toml` from its settings UI, and a symlink there would
mean the UI writes through the link and edits the repository. So if you change
something in the Noctalia UI, the next `./install.sh` overwrites it. That is
intended: the repository is the source of truth. Put the change in
`~/dotfiles/config/noctalia/config.toml`.

`git -C ~/dotfiles diff` always shows what the installer pushed.

## What are the `@HOME@` placeholders?

Substituted at deploy time. `@HOME@`, `@USER@`, `@WALLPAPER_DIR@`, `@ASSETS@`,
`@DOTFILES@`.

A file containing one is always deployed as a real copy, never symlinked,
because a symlink cannot carry per-machine content. `install.sh` greps the whole
repository for the source machine's username, hostname and interface name and
fails if it finds one.

## Where do I put a secret?

`~/.config/dotfiles/local.conf`, mode 600, gitignored:

```sh
cp ~/dotfiles/config/dotfiles/local.conf.example ~/.config/dotfiles/local.conf
chmod 600 ~/.config/dotfiles/local.conf
```

It is read, never written, and sourced after the installer's defaults so your
values win. Weather provider keys go there, not in the tracked Noctalia config.

## Why is the Noctalia weather widget present but invisible?

The `weather` widget is defined, and its bar group (`g3`) is
`enabled = false`, which is how it was in the source configuration. To show it:
set `enabled = true` on `g3` in
`~/dotfiles/config/noctalia/config.toml`, then `./install.sh --only=noctalia`.

No credential is committed. Put your provider key in `local.conf`. Read
`~/.local/state/noctalia/weather.json` after Noctalia has run once to see which
provider it selected.

## The bar has "four dead buttons" missing — what were they?

Seven, actually, in a `[bar.shortcuts]` bar: kitty opacity on/off, niri corner
radius 0/10/20, and niri border on/off. None had a `type` key, so there was no
command behind them. Both that bar and a disabled `[bar.bar]` are gone, and
`[bar] order` is now `["waybar"]`.

The functionality they implied — opacity, corner radius, borders — is
controlled in `config/niri/cfg/appearance.kdl`, where it already was. No
replacement scripts were written. The full list is in
[`docs/NOCTALIA.md`](NOCTALIA.md).

## Three keybindings are missing

`Mod+B` (a personal browser), `Mod+C` (a personal editor) and `Super+Alt+S`
(the Orca screen reader). They are kept as commented lines in
`config/niri/cfg/binds.kdl` with a note explaining what each needs. Install the
software, uncomment, done.

`Mod+Ctrl+C` is a different binding — it is `center-visible-columns`, and it is
shipped.

## Why aren't the disabled bar groups removed too?

Because they are valid, working configuration you might want to switch on, and
they produce no validation warnings. Enabling one is a one-word change.

The one exception was `text_2`, which `g3` referenced but which was itself a
malformed widget with no `type` key. It was removed and `g3` now lists just
`weather`.

## Is the SDDM setup fragile?

Yes, and it is worth knowing why.

`/usr/share/sddm/themes/silent/metadata.desktop` is a **pacman-owned** file, and
selecting the KEN variant means hand-patching it. Any upgrade of
`sddm-silent-theme` reverts that patch silently.

So the installer reapplies the patch on **every** run and `verify.sh`
re-checks it. If the greeter ever comes back in the wrong theme:

```sh
./verify.sh --fix
```

This is the largest single reproducibility risk in the project and the reason
the check exists at all.

## What happens if I unplug a monitor?

`output.kdl` is stale — it describes the layout at install time. niri keeps
working (it falls back to auto-detection for a monitor it has no block for),
but positions may be wrong. `./regenerate.sh` fixes it.

## `verify.sh` warns that a package is "only a dependency of something else"

It means the program is installed but not **explicitly** installed — it arrived
as somebody else's dependency. This is subtler than it looks, because nothing
appears broken until an unrelated upgrade removes it and a keybinding silently
stops working.

Several packages the desktop needs were in exactly this state on the source
machine, pulled in by software the desktop does not use. This repository lists
all of them explicitly, and `verify.sh` keeps warning if you ever drop back to
implicit.

```sh
sudo pacman -S --needed kitty fuzzel playerctl brightnessctl
```

## How do I add software of my own?

```sh
sudo pacman -S your-package
vim ~/dotfiles/config/niri/cfg/binds.kdl     # add the binding
./install.sh --only=binds
```

Or pin it so every future install keeps it, in
`~/.config/dotfiles/local.conf`:

```sh
EXTRA_PACKAGES=(your-package)
```

Nothing is ever removed, so uninstalling something is your package manager's
job, not this repository's.

## Is there an option to install apps?

No, and there will not be one. See [`docs/SCOPE.md`](SCOPE.md) for the full
reasoning — it is not a matter of taste. A browser ships a profile, an editor
ships plugins and a recent-files list, and stripping that out is more work than
not shipping it.
