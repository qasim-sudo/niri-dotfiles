# Noctalia — the desktop shell

Noctalia is the bar, the launcher, the wallpaper, the clipboard, the
notification daemon, the control centre, the lock screen and the settings app.
Everything visual in this desktop comes from it. niri provides the tiling and
the rendering; Noctalia provides everything drawn on top.

## The two config files

Noctalia reads a **base** config and merges a **runtime overlay** on top of it.
This repository ships both, for different reasons.

| File | Installed to | Mode | Contains |
|---|---|---|---|
| `config.toml` | `~/.config/noctalia/config.toml` | `copy` | the entire desktop: bar, panels, widgets, theme, plugins |
| *generated* | `~/.local/state/noctalia/settings.toml` | written by `lib/noctalia.sh` | only what depends on the displays attached right now |

**Why the overlay is generated rather than shipped.** Two parts of the config
describe hardware that is not the same on every machine:

- `[wallpaper.monitors.<output>]` — which display shows which wallpaper. The
  key is the connector name (`eDP-1`, `DP-1`, `HDMI-A-1`, …). Committing that
  key is committing a monitor name.
- `[lockscreen_widgets]` — one login box per display, with `cx`/`cy` pixel
  coordinates computed from that display's resolution and position. Committing
  `cx = 960` is committing a resolution.

So `config.toml` here contains **no output name, no resolution, and no pixel
coordinate anywhere**. The installer writes the overlay from `niri msg outputs`.
If no niri session is running it writes a single login box with no `output` key,
which Noctalia applies to whatever display is actually present.

**Why the base is `copy` and not `link`.** Noctalia rewrites `config.toml` when
you change something in its settings UI. A symlink there means the UI writes
*through* the link and edits the repository. Always a real copy.

**Why the overlay is `copy` and not `link`.** It is generated per host, so there
is nothing stable to symlink to.

## Sanitisation applied to the shipped config

The source configuration carried 11 validation warnings and a fair amount of
history. All of the following was removed, and `noctalia config validate` now
reports **zero warnings**:

### Seven dead buttons

`[bar.shortcuts]` existed only to host these, and none of them did anything —
they had no `type` key, so there was no command behind them:

```
kitty-opacity-opaque   kitty-opacity-transparent
niri-radius-0          niri-radius-10        niri-radius-20
niri-border-on         niri-border-off
```

The whole `[bar.shortcuts]` bar is gone, and so is the disabled `[bar.bar]`.
`[bar] order` is now `["waybar"]` — one bar.

No replacement scripts were written. The functionality those buttons implied
(opacity, corner radius, borders) is controlled in `config/niri/cfg/appearance.kdl`,
where it already was.

### Orphaned widget definitions

Any `[widget.*]` table not referenced by a bar group was removed. This includes
`custom_button_2/3/4/6/7`, `spacer_1/2/3/4/7/8/9`, `text_11/15`, the second
instances of every plugin widget (`notes_9/10/11`, `recorder_2/10/11`,
`wallhaven_3/4/5`, `widget_3/4`), and `[widget.taskbar]` (pinned to personal
apps) and `[widget.workspaces]`.

Several of those carried an invalid `scale` key, which was most of the 11
warnings.

### Machine-specific data

- `[desktop_widgets]` was deleted outright. It pinned one widget to
  `output="DP-1"` at 1920×1080 with a hard-coded centre point.
- All absolute paths became `@HOME@`, `@WALLPAPER_DIR@` or `@ASSETS@`.
- 16 `[[wallpaper.favorite]]` entries were pruned to the one that is actually in
  use. The favourites list is personal and would have shipped 16 filenames.

### Personal workflow removed

`[widget.widget_2]` was an instance of the `tadomika_ari/config-swap` plugin,
bound to `~/Config-Swap`. That plugin is not shipped and the widget is gone from
its bar group. It is **not** replaced — see `packages/plugins-optional.txt`.

### Theme templates trimmed

`[theme.templates]` was generating theme files for software this desktop does
not install. `community_ids` dropped `opencode`, `spicetify`, `neovim`, `zed`
and `brave`; `builtin_ids` dropped `ghostty` and `yazi`. What is left —
`gtk3`, `gtk4`, `kitty`, `qt`, `papirus-icons`, `fuzzel` — is exactly the set
of programs in `packages/`.

`[theme] custom_palette` was removed: it named a palette derived from a
wallpaper that is not shipped. It was unused anyway, because
`source = "wallpaper"` means the palette is computed from the active image.

### Disabled bar groups are kept

Groups `g1`, `g3`, `g5` and `g7` are `enabled = false` and so are not drawn.
They were **kept**, along with the widgets they reference, because they are
valid configuration you may want to switch on. Enabling one is a one-word
change. They generate no validation warnings.

The exception is `text_2`, which was referenced by `g3` but was itself a
malformed widget with no `type` key. It was removed and `g3` now lists just
`weather`.

## Plugin tiers

A plugin is **core** only if a widget it provides sits in a live bar group, or
it backs a shipped keybinding. Everything else is optional. This keeps the core
package list honest: no optional plugin's dependency is in `packages/core.txt`.

**Core (6, no extra packages):**

| Plugin | Why it is core |
|---|---|
| `noctalia/screen_recorder` | the `recorder` widget is in bar group `g4` |
| `noctalia/notes` | the `notes` widget is in bar group `g4` |
| `noctalia/wallhaven` | the `wallhaven` widget is in `g4`; backs the `Mod+W` panel |
| `noctalia/timer` | backs the `Mod+X` session panel |
| `noctalia/translator` | part of the launcher panel |
| `nightwatch75/todo` | in-shell task widget (**not** the Todoist app) |

`ffmpeg` is a utility rather than a plugin dependency for the same reason: the
recorder widget is on the live bar, so its encoder backend is required.

**Optional** (`--with-noctalia-plugins`, whose packages also need
`--with-extras`): `oldirtty/color_picker`, `jinliu/imagemagick-clock`,
`gustav0ar/drive-health`, `thepunkoff/pomodoro`, `noctalia/mpvpaper`,
`joshuaslate/shelly`. `color_picker`'s `widget` instance is re-added to group
`g4` by the installer when this flag is used.

**Never shipped:** `tadomika_ari/config-swap` (personal) and
`nzlov/daily-wallpaper` (disabled on the source machine).

`[plugins] enabled` is written by the installer from
`packages/plugins-core.txt`, so editing that list by hand will not survive a
re-run. The list in `config.toml` below it is the default and is a harmless
placeholder.

## What is deliberately absent

**`cliphist` is not used.** Noctalia implements the Wayland clipboard protocol
natively and keeps its own encrypted history in
`~/.local/state/noctalia/clipboard/`. It also uses
`zwp_virtual_keyboard_v1` directly for the virtual keyboard, so `wtype` is not
needed either. The installer actively asserts that `cliphist.service` stays
**disabled** — a second clipboard watcher on the same selection fights Noctalia
and breaks paste.

Both are listed in `packages/optional.txt` if you want them for a terminal
workflow, and the assertion in `lib/packages.sh` is what stops the service from
being enabled behind your back.

**`gammastep` is not used.** `[nightlight] enabled = true` is Noctalia's own
built-in blue-light filter. No external gamma daemon is involved.

**`uwsm` is not used.** `niri.service` is a static unit started by
`niri-session` through SDDM. There is no `uwsm` reference anywhere in the
session.

**`inter-font` is not used.** The shipped GTK settings have no `font-name` key,
and the UI font in force is Noctalia's `[shell] font_family = "Adwaita Sans"` —
which is the only reason `adwaita-fonts` is a core package.

## Changing it

Prefer editing `config.toml` **in the repository**, then re-run `./install.sh`.
It is deployed as a copy, so your edit is backed up before it is overwritten.

If you change something in the Noctalia settings UI instead, the change lands in
`~/.config/noctalia/config.toml` and will be **overwritten on the next
install**. That is the intended behaviour — the repository is the source of
truth. If you want a setting to persist across installs, put it in
`config/noctalia/config.toml` in the repo, or add it from `local.conf`.

To see what the installer changed: `git -C ~/dotfiles diff`.

## Validate it yourself

```sh
noctalia config validate
```

The shipped config returns `✓ Config is valid` with no warnings. If yours does
not, `lib/noctalia.sh` printed the warnings during install — re-run
`./verify.sh` to see them again.
