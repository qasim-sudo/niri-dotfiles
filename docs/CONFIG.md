# Configuration files

Every file this repository deploys, where it goes, and **why it is deployed
that way**. The deployment mode is not cosmetic — picking the wrong one causes
a real, confusing failure.

## Deployment modes

`deploy.manifest` drives `lib/deploy.sh`. One line per entry:

```
<mode>   <source, relative to the repo root>   <destination>
```

| Mode | What it does | Use it for |
|---|---|---|
| `link` | `ln -s` | static config the desktop never writes. Edit in the repo and the change is live immediately |
| `copy` | a real copy | anything a program **rewrites at runtime** |
| `seed` | copy only if the destination does not exist | theme files Noctalia generates on first run |
| `root` | `sudo install` | `/etc` files |

### Why `copy` and not `link` for Noctalia

Noctalia **rewrites `config.toml`** when you change anything in its settings UI.
If that file is a symlink into this repository, the UI writes *through* the link
and edits the repository. Your next `git status` is a mess, and the next
`./install.sh` overwrites what you just did. Same reasoning for the generated
runtime overlay, which is written fresh each install.

The same applies to any file that a program owns. The rule: **if a program can
write it, it is a copy.**

### Why `seed` for the theme files

`~/.config/kitty/themes/noctalia.conf`, `~/.config/fuzzel/themes/noctalia`,
`~/.config/qt5ct/noctalia/color.conf`, `~/.config/qt6ct/noctalia/color.conf` and
`~/.config/papirus-folders/keep` are all written by Noctalia's
`[theme.templates]` engine every time the wallpaper-derived palette changes.

Shipping a seed means the **very first login already looks themed** instead of
showing an unstyled terminal for thirty seconds while Noctalia starts and
computes the palette. After the first seed, the installer never touches them
again — that is the point of `seed`.

### Templating

A source file may contain these tokens; they are substituted at deploy time:

| Token | Becomes |
|---|---|
| `@HOME@` | your home directory |
| `@USER@` | your username |
| `@WALLPAPER_DIR@` | `~/Pictures/Wallpapers`, or whatever `local.conf` sets |
| `@ASSETS@` | `~/.local/share/dotfiles/assets` |
| `@DOTFILES@` | the absolute path of this repository |

**A file containing a token is always materialised as a real copy, never
symlinked**, because a symlink cannot carry per-machine content. This is
automatic — you do not have to choose a mode based on token presence.

No absolute path to any particular account appears in this repository. The
installer's final phase greps the whole tree for the source machine's username,
hostname and interface name and fails if it finds one.

---

## The manifest

### niri — `link`

`~/.config/niri/`

| Source | Destination |
|---|---|
| `config/niri/config.kdl` | `~/.config/niri/config.kdl` |
| `config/niri/noctalia.kdl` | `~/.config/niri/noctalia.kdl` |
| `config/niri/cfg/input.kdl` | `~/.config/niri/cfg/input.kdl` |
| `config/niri/cfg/layout.kdl` | `~/.config/niri/cfg/layout.kdl` |
| `config/niri/cfg/appearance.kdl` | `~/.config/niri/cfg/appearance.kdl` |
| `config/niri/cfg/animations.kdl` | `~/.config/niri/cfg/animations.kdl` |
| `config/niri/cfg/binds.kdl` | `~/.config/niri/cfg/binds.kdl` |
| `config/niri/cfg/environment.kdl` | `~/.config/niri/cfg/environment.kdl` |
| `config/niri/cfg/gestures.kdl` | `~/.config/niri/cfg/gestures.kdl` |
| *generated* | `~/.config/niri/cfg/output.kdl` — **not in the manifest** |
| `cfg/output.kdl` (placeholder) | committed, **not deployed** — see below |

`config.kdl` is the only entry point; it `include`s the eight files in `cfg/`
plus `noctalia.kdl`. Editing any of them is live immediately — niri watches its
config and reloads.

`cfg/output.kdl` is committed as a **comment-only placeholder** and is *not*
in the manifest. The placeholder is required: `config.kdl` includes it
unconditionally and niri has no optional include, so a missing file there is a
hard config error and a fresh clone would not start. The placeholder has no
`output` block, so niri auto-detects your displays. See below.

### Noctalia — `copy`

| Source | Destination |
|---|---|
| `config/noctalia/config.toml` | `~/.config/noctalia/config.toml` |
| *generated* | `~/.local/state/noctalia/settings.toml` |

### Terminal, shell, launcher — `link` + `seed`

| Source | Mode | Destination |
|---|---|---|
| `config/kitty/kitty.conf` | `link` | `~/.config/kitty/kitty.conf` |
| `config/kitty/themes/noctalia.conf` | `seed` | `~/.config/kitty/themes/noctalia.conf` |
| `config/kitty/current-theme.conf` | `seed` | `~/.config/kitty/current-theme.conf` |
| `config/fish/config.fish` | `link` | `~/.config/fish/config.fish` |
| `config/starship/end4diagonal.toml` | `link` | `~/.config/starship/end4diagonal.toml` |
| `config/fastfetch/config.jsonc` | `link` | `~/.config/fastfetch/config.jsonc` |
| `config/fuzzel/fuzzel.ini` | `link` | `~/.config/fuzzel/fuzzel.ini` |
| `config/fuzzel/themes/noctalia` | `seed` | `~/.config/fuzzel/themes/noctalia` |

`fuzzel.ini` contains `@HOME@`, so it is deployed as a real copy despite being
marked `link`. `lib/deploy.sh` handles that automatically.

**`fish_variables` is never deployed.** It is machine-generated state that
records absolute paths and, on the source machine, a browser path. fish
regenerates it.

**Kitty's `dank-*.conf` files are not deployed.** They were DMS leftovers from a
shell this desktop does not use.

### Widget theming — `link` + `seed`

| Source | Mode | Destination |
|---|---|---|
| `config/gtk-3.0/settings.ini` | `link` | `~/.config/gtk-3.0/settings.ini` |
| `config/gtk-4.0/settings.ini` | `link` | `~/.config/gtk-4.0/settings.ini` |
| `config/qt5ct/noctalia/color.conf` | `seed` | `~/.config/qt5ct/noctalia/color.conf` |
| `config/qt6ct/noctalia/color.conf` | `seed` | `~/.config/qt6ct/noctalia/color.conf` |
| `config/papirus-folders/keep` | `seed` | `~/.config/papirus-folders/keep` |

The GTK settings are four lines each: prefer dark, `adw-gtk3-dark`,
`Papirus-Dark`, `Bibata-Modern-Classic`. **No `font-name` key** — the UI font
is Noctalia's `[shell] font_family = "Adwaita Sans"`, which is the only reason
`adwaita-fonts` is a core package.

`environment.kdl` sets `QT_QPA_PLATFORM=wayland` and
`QT_QPA_PLATFORMTHEME=gtk3`, so Qt apps follow Wayland and borrow the GTK theme
rather than shipping their own.

### XDG — `link`

| Source | Mode | Destination |
|---|---|---|
| `config/xdg/portals.conf` | `link` | `~/.config/xdg-portal/portals.conf` |

**`mimeapps.list` is NOT in the manifest.** Thunar is registered by
`lib/xdg.sh` with `xdg-mime default`, which is additive. See
[`docs/FAQ.md`](FAQ.md) and the header of `lib/xdg.sh`. If you *want* the
repository to own the whole file, `--force-mimeapps` replaces it from
`config/xdg/mimeapps.list` after backing it up and asking.

### `/etc` — `root`

| Source | Destination |
|---|---|
| `etc/sddm.conf` | `/etc/sddm.conf` |

### Secrets

| Source | Mode | Destination |
|---|---|---|
| `config/dotfiles/local.conf.example` | `seed` | `~/.config/dotfiles/local.conf.example` |

`local.conf` itself is **read, never written**, and gitignored. Only the
`.example` is tracked.

---

## The two generated files

These are the only files that cannot be in the repository, because their
content is a property of the hardware attached right now.

### `~/.config/niri/cfg/output.kdl`

Contains output connector names, modes, scale factors and positions. Committing
it means committing a monitor name like `DP-1`, a resolution, and a layout — so
**the content is generated per host, not committed.** What is committed is a
comment-only placeholder, for the `include` reason above.

Written by `lib/hardware.sh` from `niri msg outputs`, with this header:

```
// GENERATED by the dotfiles installer. DO NOT EDIT, DO NOT COMMIT.
```

That marker is what `verify.sh` and `uninstall.sh` use to tell a generated file
from a file you edited by hand.

If no niri session is running, the file is written with no `output` block at
all, so niri auto-detects using its own EDID logic — exactly like the
placeholder, so installing from a TTY is safe. Rebuild it with
`./regenerate.sh` from inside your session after a monitor change.

### `~/.local/state/noctalia/settings.toml`

The Noctalia runtime overlay, containing:

- `[wallpaper.monitors.<output>]` — the table name **is** the connector name
- `[lockscreen_widgets]` — one login box per display, with `cx`/`cy` in that
  display's own pixel space

Written by `lib/noctalia.sh`. With no live session it writes one login box with
no `output` key, which Noctalia applies to whatever display is present.

The shipped `config/noctalia/config.toml` therefore contains **no output name, no
resolution and no pixel coordinate**. See
[`docs/NOCTALIA.md`](NOCTALIA.md) for the full rationale.

---

## Deployment safety

For every non-`seed` destination, in this order:

1. **Has this repository managed it before?** Checked against `deployed.json` in
   the newest snapshot under `~/.local/state/dotfiles/backups/`.
2. If yes, or if the destination does not exist, or if `--force` was given:
   back it up, then write.
3. If no — the file pre-existed and this repository has never touched it:
   **leave it alone**, warn, and count it in the summary.

That third case is what makes the installer safe on an already-configured
machine. Your `~/.config/niri/config.kdl` is not destroyed by a first run; the
installer tells you it skipped it and tells you the flag to override it.

## Selective deploys

```sh
./install.sh --only=binds          # only entries matching "binds"
./install.sh --skip=noctalia       # everything except Noctalia
```

The substring matches the source and destination paths. Both flags are useful
when iterating on one file. `lib/sddm.sh` is also documented as
`./install.sh --only=sddm` for re-applying the theme patch — run
`./verify.sh --fix` instead, which is the supported path.
