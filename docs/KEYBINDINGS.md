# Keybindings

**135 active bindings.** Every one targets niri itself, Noctalia, or a package
in `packages/utilities.txt` / `packages/core.txt`. There is no binding whose
target this repository does not install, and no binding was invented for a
program that is not here.

`Mod` is `Super` (the Windows/Command key) unless you remap it in
`config/niri/cfg/input.kdl`.

Press <kbd>Mod</kbd>+<kbd>Shift</kbd>+<kbd>/</kbd> for the hotkey overlay —
every binding is listed there with a description.

---

## Three bindings that were removed

The source configuration had 138. Three are not shipped, because they launched
software that is deliberately excluded from this desktop. They are kept in
`config/niri/cfg/binds.kdl` as **commented** lines with a note, so nothing is
lost and adding the software back is a one-line uncomment.

| Key | Launched | Why not shipped |
|---|---|---|
| `Mod+B` | `brave` | personal browser — out of scope |
| `Mod+C` | `code` | personal editor — out of scope |
| `Super+Alt+S` | `orca` | screen reader; an accessibility tool you may or may not want, so it is opt-in rather than assumed |

`Mod+Ctrl+C` is **unrelated** to the removed `Mod+C`. It is
`center-visible-columns`, a niri layout binding, and it is shipped.

To use Orca:

```sh
sudo pacman -S orca
```

then uncomment the `Super+Alt+S` block in `config/niri/cfg/binds.kdl`.

---

## Noctalia shell — 7

| Key | Action |
|---|---|
| `Mod+X` | Session / power menu |
| `Mod+Space` | Launcher |
| `Mod+W` | Wallpaper panel |
| `Mod+Shift+B` | Clipboard panel |
| `Mod+L` | Lock screen (Noctalia) |
| `Mod+Shift+S` | Region screenshot |
| `Mod+Print` | Fullscreen screenshot |

## Applications — 6

| Key | Action |
|---|---|
| `Mod+T` | Terminal (kitty) |
| `Mod+Return` | Terminal (kitty) |
| `Mod+D` | Run application (fuzzel) |
| `Mod+E` | File manager (thunar) |
| `Super+Alt+L` | Lock screen (swaylock) |
| `Mod+Shift+Slash` | Hotkey overlay |

Both lock bindings are shipped on purpose. `Mod+L` uses Noctalia's own lock, so
the login box matches the desktop. `Super+Alt+L` uses `swaylock`, which is
faster to start and has no dependencies on the shell being alive. Pick either.

## Hardware keys — 11

Volume, via `wpctl` (from wireplumber):

| Key | Action |
|---|---|
| `XF86AudioRaiseVolume` | +10%, capped at 100% |
| `XF86AudioLowerVolume` | −10% |
| `XF86AudioMute` | toggle sink mute |
| `XF86AudioMicMute` | toggle source mute |

Media, via `playerctl`:

| Key | Action |
|---|---|
| `XF86AudioPlay` / `XF86AudioPause` | play / pause |
| `XF86AudioStop` | stop |
| `XF86AudioPrev` | previous track |
| `XF86AudioNext` | next track |

Brightness, via `brightnessctl`:

| Key | Action |
|---|---|
| `XF86MonBrightnessUp` | +10% |
| `XF86MonBrightnessDown` | −10% |

These are no-ops on a machine with no backlight (a desktop). `brightnessctl` is
still installed — it is in `packages/utilities.txt` because the binding exists,
and a binding whose target is present but idle is better than a binding that
errors.

## Screenshots — 3

| Key | Action |
|---|---|
| `Print` | interactive screenshot |
| `Ctrl+Print` | whole screen |
| `Alt+Print` | active window |

These are niri's own, and they are distinct from `Mod+Shift+S` / `Mod+Print`,
which are Noctalia's and land in the same configured screenshot directory.

## Session — 3

| Key | Action |
|---|---|
| `Mod+Shift+E` | quit niri (return to the greeter) |
| `Ctrl+Alt+Delete` | quit niri |
| `Mod+Shift+P` | power off the monitors |

niri is a static unit started by SDDM, so "quit" means the greeter, not a
logout to a TTY. `Mod+X` is the graceful path (it offers suspend, restart and
power off through a confirmation dialog); these are the abrupt ones.

## Layout and focus — 12

| Key | Action |
|---|---|
| `Mod+O` | toggle the Overview |
| `Mod+Q` | close the focused window |
| `Mod+Up` / `Mod+K` | focus window up |
| `Mod+Down` / `Mod+J` | focus window down |
| `Mod+Left` / `Mod+H` | focus column left |
| `Mod+Right` | focus column right |
| `Mod+Home` | focus the first column |
| `Mod+Ctrl+Home` | move the column to first |
| `Mod+Ctrl+End` | move the column to last |

The vi-style `HJKL` aliases exist because arrow keys are four keys away on a
laptop and the arrows are already taken by window movement.

## Moving windows — 15

| Key | Action |
|---|---|
| `Mod+Ctrl+Up` | move window up |
| `Mod+Ctrl+Down` | move window down |
| `Mod+Ctrl+Right` | move column right |
| `Mod+Ctrl+Left` | move column left |
| `Mod+Ctrl+H` | move column left |
| `Mod+Ctrl+J` | move column left |
| `Mod+Ctrl+K` | move window up |
| `Mod+Ctrl+L` | move column right |
| `Mod+Ctrl+Z` | move window down |
| `Mod+Shift+Up` | move window up |
| `Mod+Shift+Down` | move window down |
| `Mod+Shift+Left` | move column left |
| `Mod+Shift+Right` | move column right |
| `Mod+Shift+H` | focus the monitor to the left |
| `Mod+Shift+J` / `Mod+Shift+L` | focus the monitor below / above |

`Mod+Shift` is the "move" modifier; `Mod+Shift`+`H`/`J`/`L` are the three
monitor-direction focuses, because there is no reliable "monitor right of
this one" in a scrolling layout.

## Between monitors — 8

| Key | Action |
|---|---|
| `Mod+Shift+Ctrl+Up` | move column to the monitor above |
| `Mod+Shift+Ctrl+Down` | move column to the monitor below |
| `Mod+Shift+Ctrl+Right` | move column to the monitor right |
| `Mod+Shift+Ctrl+Left` | move column to the monitor left |
| `Mod+Shift+Ctrl+H` | move column to the monitor left |
| `Mod+Shift+Ctrl+J` | move column to the monitor below |
| `Mod+Shift+Ctrl+K` | move column to the monitor above |
| `Mod+Shift+Ctrl+L` | move column to the monitor right |

On a single-monitor machine these do nothing harmful. niri resolves "no such
monitor" as a no-op.

## Workspaces — movement, 16

| Key | Action |
|---|---|
| `Mod+Page_Down` / `Mod+U` | focus the workspace below |
| `Mod+Page_Up` / `Mod+I` | focus the workspace above |
| `Mod+Ctrl+Page_Down` / `Mod+Ctrl+U` | move the column to the workspace below |
| `Mod+Ctrl+Page_Up` / `Mod+Ctrl+I` | move the column to the workspace above |
| `Mod+Shift+Page_Down` / `Mod+Shift+U` | move the whole workspace down |
| `Mod+Shift+Page_Up` / `Mod+Shift+I` | move the whole workspace up |
| `Shift+WheelScrollDown` | focus the workspace below |
| `Shift+WheelScrollUp` | focus the workspace above |
| `Mod+Ctrl+WheelScrollDown` | move the column to the workspace below |
| `Mod+Ctrl+WheelScrollUp` | move the column to the workspace above |

Three modifiers, three different meanings, and they are worth spelling out
because it is the easiest thing to get wrong:

- **`Mod` + wheel** — move the *column* to another workspace.
- **`Mod+Shift` + wheel** — move the *workspace itself* in the strip.
- **plain `Shift` + wheel** — just *focus*, move nothing.

## Workspaces — direct, 27

`Mod+1`…`Mod+9` focus workspace 1–9. `Mod+Ctrl+1`…`9` and `Mod+Shift+1`…`9`
move the current column to workspace 1–9.

## Sizing — 13

| Key | Action |
|---|---|
| `Mod+BracketLeft` | consume or expel the window to the left |
| `Mod+BracketRight` | consume or expel the window to the right |
| `Mod+Comma` | consume the window into the column |
| `Mod+Period` | expel the window from the column |
| `Mod+R` | cycle the preset column width forward |
| `Mod+Shift+R` | cycle the preset column width back |
| `Mod+Ctrl+Shift+R` | cycle the preset window height |
| `Mod+Ctrl+R` | reset the window height |
| `Mod+Minus` | column −10% |
| `Mod+Shift+Minus` | height −10% |
| `Mod+Shift+Equal` | height +10% |
| `Mod+Ctrl+F` | expand the column to the available width |
| `Mod+Ctrl+C` | center the visible columns |

The preset widths are `0.5 0.6 0.7 0.8 0.9 1.0` proportions, set in
`config/niri/cfg/layout.kdl`.

## Window state — 6

| Key | Action |
|---|---|
| `Mod+F` / `Mod+Shift+F` | toggle fullscreen |
| `Mod+M` | maximize to the edges |
| `Mod+V` | toggle floating |
| `Mod+Shift+V` | switch focus between floating and tiled |
| `Mod+Shift+W` | toggle the column's tabbed display |

## Scroll — 8

| Key | Action |
|---|---|
| `Mod+WheelScrollRight` | focus the column right |
| `Mod+WheelScrollLeft` | focus the column left |
| `Mod+Ctrl+WheelScrollRight` | move the column right |
| `Mod+Ctrl+WheelScrollLeft` | move the column left |
| `Mod+Shift+WheelScrollDown` | focus the column right |
| `Mod+Shift+WheelScrollUp` | focus the column left |
| `Mod+Ctrl+Shift+WheelScrollDown` | move the column right |
| `Mod+Ctrl+Shift+WheelScrollUp` | move the column left |

The `Mod+Shift` + vertical-scroll pair makes a horizontal mouse wheel behave
like a horizontal one, for mice whose wheel is vertical-only.

---

## Changing a binding

Edit `config/niri/cfg/binds.kdl` **in the repository** — it is symlinked, so the
change is live immediately with no reinstall:

```sh
vim ~/dotfiles/config/niri/cfg/binds.kdl
niri msg action load-config-file    # or just use the key
```

Check it parses before you rely on it:

```sh
niri validate
```

`./verify.sh` re-checks that every command a binding spawns is actually
installed, so a binding cannot silently point at nothing.
