# Installing

```sh
git clone https://github.com/zaroutt/dotfiles
cd dotfiles
./install.sh --dry-run     # read this first
./install.sh
```

Then **log out and back in**.

`bash install.sh` works identically. `install.sh` must be run as your normal
user — it calls `sudo` itself and refuses to run as root.

---

## Before you start

- Arch Linux, `x86_64` or `aarch64`. The installer checks `/etc/os-release` and
  stops on anything else.
- `sudo` available.
- Network access.
- **A display manager already enabled**, if you want to be able to log back in.

The installer will *not* enable SDDM for you unless you pass `--enable-sddm`,
and even then it asks first. If you are on a fresh Arch with no display manager,
the desktop is installed but nothing brings you to it. Enable it deliberately:

```sh
sudo systemctl enable sddm
```

**Test that you can still log in before rebooting.** Open a second TTY
(<kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>F2</kbd>) and keep it there.

---

## The phases

Each prints a header, so `--dry-run` output reads as a table of contents.

### 0. Preflight

Checks: not root, `/etc/os-release` says Arch, architecture is supported. Then
loads `~/.config/dotfiles/local.conf` **last**, so your values override every
default.

### 1. Detect

Reads, and only ever reads:

| Source | What it determines |
|---|---|
| `/etc/os-release` | distribution |
| `lspci -nnk` | GPU vendor and kernel driver → the Vulkan package tier |
| `/proc/cpuinfo` | CPU vendor → the microcode tier |
| `/sys/class/dmi/id/chassis_type` | laptop or desktop; falls back to `/sys/class/power_supply` |
| `/proc/asound/cards` | SOF audio firmware |
| `ip route` / `nmcli` | default interface (for logging only) |
| `niri msg outputs` | connected displays, if a session is live |

**No PCI ID, CPU model name, monitor name, interface name or hostname is
hard-coded anywhere in this repository.** Everything is discovered.

An AUR helper is looked for but not required; if none exists, `yay` is cloned
and built.

### 2. Packages

`core.txt`, then `utilities.txt`, then whichever `hardware/*.txt` apply, then
`aur-required.txt`. Then `--with-extras` if you passed it, then
`EXTRA_PACKAGES` from `local.conf` if you set it.

Every pacman call uses `--needed`, so a re-run installs nothing. **No package is
ever removed.** If pacman reports a conflict the installer stops and prints the
manual command rather than resolving it for you.

### 3. Groups and login shell

Adds you to `video`, `input`, `audio`, `render`, `seat` and `wheel` if missing.
Never removes you from a group.

Then offers to set your login shell to `/usr/bin/fish`. Skipped with
`--no-chsh`.

**Group changes and the login shell need a new session.** That is the main
reason the installer tells you to log out and back in.

### 4. Directories and wallpaper

Creates `~/Pictures/Wallpapers`, `~/Pictures/Screenshots`, the assets directory
and `~/.config/dotfiles`. Copies the one shipped wallpaper in.

### 5. Deploy

Walks `deploy.manifest`. For each destination: check whether this repository
managed it before, back it up, write it, or leave it alone and report it.

### 6. Generate

- `~/.config/niri/cfg/output.kdl` from `niri msg outputs`
- `~/.local/state/noctalia/settings.toml` — per-display wallpaper assignment and
  login boxes
- `[plugins] enabled` in the Noctalia config, from
  `packages/plugins-core.txt`

### 7. XDG

Registers Thunar as the handler for 15 file-manager MIME types using
`xdg-mime default`, which is **additive**. Your existing associations survive.
`--force-mimeapps` replaces `~/.config/mimeapps.list` wholesale, after a backup
and a confirmation.

Then refreshes `update-desktop-database`, `update-mime-database` and
`xdg-user-dirs-update`.

### 8. SDDM

Installs `/etc/sddm.conf`, then patches
`/usr/share/sddm/themes/silent/metadata.desktop` so the greeter shows the **KEN**
variant. That file is pacman-owned, so **any theme upgrade reverts it** — the
patch is reapplied on every install and re-checked by `verify.sh`.

`--enable-sddm` enables the service, with a confirmation.

### 9. Services

Enables `NetworkManager`, `NetworkManager-wait-online`, `bluetooth` and
`power-profiles-daemon`. Never touches `niri.service`, which is static and
started by SDDM through `niri-session`.

### 10. Conflicting services

Asserts that `dms`, `dunst`, `quickshell`, `hypridle` and `cliphist` user units
are disabled. **Warning by default**; `--strict` disables and masks them.

A second notification daemon or clipboard watcher on the same bus is the single
most common cause of "notifications stopped appearing" in this setup, which is
why this is an explicit step rather than a hope.

### 11. Verify

Runs the same checks as `verify.sh`, and exits non-zero if any fail. See
`./verify.sh` for the list.

---

## Flags

```
MODES
    --dry-run           Print every action, change nothing. Start here.
    --backup-only       Take a snapshot of everything that would change, then stop.
    --force             Answer yes to every confirmation and overwrite files
                        this repository has not managed before.

SCOPE
    --with-extras       Also install packages/optional.txt and aur-optional.txt.
    --with-noctalia-plugins
                        Also enable the optional Noctalia plugins. Implies
                        --with-extras for their dependencies.
    --with-wallpapers   Copy wallpapers/current/ into your wallpaper directory.

SELECTIVE
    --only=SUBSTR       Only deploy manifest entries matching SUBSTR.
    --skip=SUBSTR       Skip manifest entries matching SUBSTR.
    --no-chsh           Do not change the login shell.
    --force-mimeapps    REPLACE ~/.config/mimeapps.list instead of adding to it.
                        Backs up the old file first. Asks for confirmation.

HARDWARE
    --nvidia            Install the proprietary NVIDIA driver. Without this an
                        NVIDIA machine gets a warning and no driver from here.

SYSTEM
    --enable-sddm       Enable sddm as the display manager.
    --strict            Mask conflicting user units instead of warning.
    --user=NAME         Operate on NAME's home.
    --repo=DIR          Use DIR as the repository root.
```

### Useful combinations

```sh
# look before you leap
./install.sh --dry-run

# just the keybindings, while iterating
./install.sh --only=binds

# everything except Noctalia (e.g. debugging a portal problem)
./install.sh --skip=noctalia

# snapshot without installing, then review
./install.sh --backup-only
./restore.sh --list
```

---

## Re-running

**The installer is idempotent.** A second run installs no packages, changes no
files that already match, and reports zero changes.

Two cases are *not* no-ops, by design:

- A **theme upgrade** reverted `metadata.desktop` → it is re-patched.
- `dms`/`dunst`/etc. were enabled by something else → you get warned again.

Pull new changes and re-run:

```sh
cd ~/dotfiles && git pull
./install.sh
```

Static config is symlinked, so `git pull` updates your live niri, kitty, fish,
starship, fastfetch and fuzzel configuration immediately with no reinstall at
all. Files Noctalia rewrites need the re-run.

---

## Machine-local settings

```sh
cp ~/dotfiles/config/dotfiles/local.conf.example ~/.config/dotfiles/local.conf
chmod 600 ~/.config/dotfiles/local.conf
```

That file is gitignored, is read but never written, and is sourced after the
installer's defaults, so anything you set there wins. It is the only place a
secret or a machine-specific value belongs.

---

## Undoing

```sh
./uninstall.sh --dry-run    # see the plan
./uninstall.sh              # do it
```

`uninstall.sh` restores your previous files from the newest snapshot and removes
only what the installer created. It does **not** remove packages, change systemd
units, or touch the bootloader. If you used `--enable-sddm`:

```sh
sudo systemctl disable sddm
```

Backups are kept — they are the only way back. Delete
`~/.local/state/dotfiles/backups/` by hand when you are satisfied.

For a single bad run rather than a full removal:

```sh
./restore.sh --list
./restore.sh --latest
```
