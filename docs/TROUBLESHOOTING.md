# Troubleshooting

Start here:

```sh
./verify.sh            # every check, with the fix for each failure
./verify.sh --fix      # repair what is safely repairable
./verify.sh --quiet    # only problems
```

`verify.sh` is read-only unless you pass `--fix`. Every failure it prints is
followed by the exact command that fixes it.

The install log is at `~/.local/state/dotfiles/last-install.log`.

---

## Nothing appears after install

**You did not log out and back in.** Group memberships, the login shell and
user-unit state all need a new session. This is the most common cause.

```sh
echo $SHELL          # should be /usr/bin/fish
id -nG               # should include video, input, audio, render, seat, wheel
```

**No display manager is enabled.** The installer does not enable one unless you
pass `--enable-sddm`. On a fresh Arch with no DM, the desktop is installed and
nothing shows it to you:

```sh
sudo systemctl enable sddm
```

**Test you can still log in before rebooting.** Open <kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>F2</kbd>
for a TTY and keep it there. The classic Arch beginner failure is a config
error that makes the greeter unusable, discovered only after a reboot.

---

## No blur, no window animations, windows look flat

**The Vulkan driver is missing or wrong.** niri renders blur and the animation
shaders through the Vulkan renderer. With no matching ICD, it falls back to GL
with no blur and no error message.

```sh
lspci -nnk | grep -A3 'VGA\|3D controller'
vulkaninfo --summary 2>/dev/null | head -20
ls /usr/share/vulkan/icd.d/
```

If `icd.d/` is empty, the graphics tier was not installed. Check what detection
decided:

```sh
./install.sh --dry-run 2>&1 | grep -A5 'tier:'
```

`--nvidia` is required on an NVIDIA machine — the proprietary driver is never
installed automatically, because it is closed source.

---

## The greeter comes back in the wrong theme

**A `sddm-silent-theme` upgrade reverted `metadata.desktop`.** That file is
pacman-owned, and the KEN variant has to be selected by hand-patching it. This
is the most fragile part of the whole setup.

```sh
./verify.sh --fix
```

or:

```sh
sudo ~/dotfiles/install.sh --only=sddm
```

This is why the patch is applied on **every** install and re-checked by
`verify.sh`, rather than being a one-time setup step.

Check it by hand:

```sh
grep '^ConfigFile=' /usr/share/sddm/themes/silent/metadata.desktop
# must be:  ConfigFile=configs/ken.conf
```

---

## Notifications stopped appearing

**A second notification daemon is on the bus.** `dunst`, `dms` and `quickshell`
all claim `org.freedesktop.Notifications`. Two implementations on one bus means
neither reliably gets the message.

```sh
systemctl --user is-enabled dms.service dunst.service quickshell.service
./verify.sh            # checks all five conflicting units
./verify.sh --fix      # disables and masks them
```

Fix:

```sh
systemctl --user disable --now dunst.service
systemctl --user mask dunst.service
```

**Also check `dms` specifically.** If `dms-shell` is installed it ships its own
bar and launcher, which will fight Noctalia for the same layer-shell surfaces
and look like a Noctalia bug.

---

## Paste in Noctalia is broken or empty

**`cliphist.service` is enabled.** Noctalia implements the Wayland clipboard
protocol natively and keeps its own encrypted history. A second clipboard
watcher competing for the same Wayland selection breaks paste.

```sh
systemctl --user is-enabled cliphist.service     # must NOT be enabled
./verify.sh --fix
```

`verify.sh` and `install.sh` both assert this. If you enabled the service
yourself, that is on you — the installer deliberately does not re-disable it
unless you pass `--strict`.

---

## `niri.service` is wrong / I cannot log in graphically

**Do not enable or disable `niri.service`.** It is a **static** unit started by
SDDM through `niri-session`. Changing its enablement breaks the login session
completely.

```sh
systemctl is-enabled niri.service      # must be: static
```

If it is not:

```sh
sudo systemctl disable niri.service && sudo systemctl reset niri.service
```

`verify.sh` fails on this. If you are currently locked out, boot and pick
another session or land on a TTY, then run the above.

---

## External monitor not detected, or wrong resolution

`output.kdl`'s content is **generated per host**, never committed — see
[`docs/CONFIG.md`](CONFIG.md). It describes the displays attached when the
installer last ran. (A comment-only placeholder *is* committed, so niri can
always load the config; it just pins nothing.)

```sh
niri msg outputs                  # what niri currently sees
./regenerate.sh                   # rebuild it from that
```

Regenerate after any monitor change: docking, undocking, changing resolution
or scale, or adding a second display.

If you have **no niri session running** (installing from a TTY), the generated
file has no `output` block and niri auto-detects. Log in and re-run
`./regenerate.sh` for explicit modes and positions.

To go back to niri's own detection entirely:

```sh
./regenerate.sh    # from a TTY, with no niri session: writes no output block
```

---

## The bar is missing, or a panel does not open

```sh
journalctl --user -u niri -n 100       # compositor errors
journalctl --user --since '5 min ago' | grep -i noctalia
noctalia config validate
```

**Check the bar order.** The shipped config has one bar:

```toml
[bar]
order = [ "waybar" ]
```

If you changed it in Noctalia's UI, the change lives in
`~/.config/noctalia/config.toml` and **will be overwritten on the next
install**. That is intended — the repository is the source of truth. Put the
change in `~/dotfiles/config/noctalia/config.toml` instead.

---

## A keybinding does nothing

```sh
./verify.sh            # reports any binding whose target is not installed
```

**The program is not installed.** `verify.sh` lists every command a binding
spawns that is not on `PATH` and gives you the `pacman` command.

**The program is installed but only as a dependency.** `verify.sh` warns about
this separately, because it is the subtler failure: something *is* present, so
nothing looks wrong, but an unrelated upgrade can remove it without notice. Fix
by making it explicit:

```sh
sudo pacman -S --needed kitty fuzzel playerctl brightnessctl
```

This matters on a machine where those packages arrived as dependencies of
software the desktop does not use. The source machine had exactly that problem.

**A Noctalia binding does nothing.** `noctalia msg …` is Noctalia's own IPC.
Check the plugin behind it is enabled:

```sh
noctalia config validate
grep -A20 '^\[plugins\]' ~/.config/noctalia/config.toml
```

---

## `noctalia config validate` reports warnings

The shipped config is clean. Warnings mean the file has drifted — most likely
because something edited `~/.config/noctalia/config.toml` outside the
repository.

```sh
noctalia config validate
git -C ~/dotfiles diff               # what actually changed
./install.sh --only=noctalia         # push the repo's version back
```

The commonest source of drift is Noctalia's own settings UI, which rewrites
`config.toml` in place. That is why it is deployed as a copy rather than a
symlink — but the repository still wins on the next install.

---

## Qt apps are unthemed, or use a light theme

```sh
grep -r 'QT_QPA' ~/.config/niri/cfg/environment.kdl
qtpaths6 --qt-version
ls ~/.config/qt6ct/noctalia/ ~/.config/qt5ct/noctalia/
```

`environment.kdl` sets `QT_QPA_PLATFORM=wayland` and
`QT_QPA_PLATFORMTHEME=gtk3`, so Qt apps should follow the GTK theme. If a Qt app
was running when the theme changed, restart it.

---

## Thunar is not the default file manager

```sh
xdg-mime query default inode/directory
```

Must be `thunar.desktop`. The installer uses additive `xdg-mime default` calls,
so something else may have claimed the type afterwards. Re-register:

```sh
./install.sh --only=xdg
```

or check `~/.config/mimeapps.list` for a `[Default Applications]` section with
`inode/directory=` pointing elsewhere.

**To make this repository own the whole file** — destructive, asks first, backs
up first:

```sh
./install.sh --force-mimeapps
```

---

## The install stopped partway through

It is safe to re-run. Every phase is idempotent.

```sh
./install.sh            # picks up where it left off
```

If a pacman transaction failed, nothing was removed and the installer printed
the manual command. Resolve the conflict, then re-run.

---

## I want to see what it changed

```sh
git -C ~/dotfiles diff                 # repository files
cat ~/.local/state/dotfiles/last-install.log
ls ~/.local/state/dotfiles/backups/
```

And to see what a run *would* do:

```sh
./install.sh --dry-run
```

`--dry-run` performs **zero** writes, including no backup snapshot.

---

## Roll it back

```sh
./restore.sh --list                  # what snapshots exist
./restore.sh --latest --dry-run      # what it would do
./restore.sh --latest                # do it
```

`restore.sh` checks every backed-up file against the `SHA256SUMS` manifest
before restoring, and warns you if the snapshot you picked is not the newest —
rolling back past a later install leaves a mixed state on purpose.

Full removal:

```sh
./uninstall.sh --dry-run
./uninstall.sh
```

---

## Getting help

If you are reporting a problem, these four commands give almost everything
needed:

```sh
./verify.sh
./install.sh --dry-run 2>&1 | tail -60
noctalia config validate
niri validate
```
