# dotfiles

A reproducible **Arch Linux → Niri → Noctalia** desktop environment.

```sh
git clone https://github.com/zaroutt/dotfiles
cd dotfiles
./install.sh
```

That is the whole interface. The installer works on a fresh Arch install and on
an already-configured one, and it does not destroy configuration it does not
own.

---

## What this is

A tiled Wayland desktop with:

- **niri** — scrolling tiling compositor, custom GLSL window animations, blur
- **Noctalia** — bar, launcher, wallpaper, clipboard, notifications, control
  centre, lock screen, settings
- **Kitty** + **Fish** + **Starship** + **Fastfetch** — the shell stack
- **Fuzzel** — `Mod+D` launcher
- **Thunar** — `Mod+E` file manager, with the archive, volume and media-preview
  plugins
- **SilentSDDM (KEN)** — Wayland login screen
- **PipeWire / WirePlumber**, NetworkManager, bluez, power-profiles-daemon

135 keybindings, 22px gaps, 20px window corners, 0.85 opacity, two-pass blur,
a capsule bar, and a colour palette derived from whichever wallpaper is active.

## What this is not

**This is a desktop environment, not a workstation.** Browsers, editors and
IDEs, terminal-based music players, mobile and cross-platform SDKs, games and
emulators, packet analysers, security tooling, AI agents and virtualisation
stacks are all **out of scope and never installed**. There is no `--with-apps`
flag and there never will be one. See [`docs/SCOPE.md`](docs/SCOPE.md) for the
itemised list and the reasoning.

No personal state is shipped either: no browser or IDE profiles, no SDKs, no
SSH keys, no credentials, no clipboard or notification history, no saved
networks, no personal documents. The single wallpaper in this repository is the
one the theme needs; your own collection stays on your machine.

## Requirements

- Arch Linux, `x86_64` or `aarch64`
- A Wayland-capable GPU with a Vulkan driver (the installer picks the right
  `vulkan-*` package for your card)
- `sudo` available
- Internet access on first run

Nothing else. `base-devel` and `git` are installed by the installer itself if
missing — except `git`, which you need to clone this repository.

## Install

```sh
git clone https://github.com/zaroutt/dotfiles
cd dotfiles
./install.sh --dry-run     # see every action, change nothing
./install.sh               # do it
```

`bash install.sh` works identically.

Then **log out and back in**. Group memberships, the login shell and
user-unit state all need a fresh session.

### Options

```
MODES
    --dry-run           Print every action, change nothing. Start here.
    --backup-only       Take a snapshot of everything that would change, then stop.
    --force             Answer yes to every confirmation.

SCOPE
    --with-extras       Also install packages/optional.txt and aur-optional.txt.
    --with-noctalia-plugins
                        Also enable the optional Noctalia plugins.
    --with-wallpapers   Copy wallpapers/current/ into your wallpaper directory.

SELECTIVE
    --only=SUBSTR       Only deploy manifest entries matching SUBSTR.
    --skip=SUBSTR       Skip manifest entries matching SUBSTR.
    --no-chsh           Do not change the login shell.
    --force-mimeapps    REPLACE ~/.config/mimeapps.list instead of adding to it.

HARDWARE
    --nvidia            Install the proprietary NVIDIA driver. Without this, an
                        NVIDIA machine gets a warning and no driver from here.

SYSTEM
    --enable-sddm       Enable sddm as the display manager.
    --strict            Mask (not merely warn about) conflicting user units.
    --user=NAME         Operate on NAME's home.
```

## Safety

The installer's contract:

| It does | It does not |
|---|---|
| back up every path **before** changing it | ever run as root |
| ask before anything destructive | ever remove a package |
| refuse to overwrite a file it has not managed | ever touch grub, efibootmgr, or partitions |
| stay idempotent — a second run changes nothing | ever enable or disable `niri.service` |
| log everything to a file | ever ship or read a secret |
| support `--dry-run` on every phase | ever overwrite `mimeapps.list` by default |

Backups land in `~/.local/state/dotfiles/backups/<timestamp>/`, with a
`SHA256SUMS` manifest and a `deployed.json` listing every path the run owned.

```sh
./restore.sh --list          # what snapshots exist
./restore.sh --latest        # roll back the last install
./restore.sh 20260926-014512 # roll back a specific one
./uninstall.sh --dry-run     # see what removing it all would do
./uninstall.sh               # do it
```

`uninstall.sh` restores your previous files and removes only what the installer
created. It does **not** remove packages or change systemd units — those are
shared with things this repository has nothing to do with.

## Two files are generated per host, not committed

- `~/.config/niri/cfg/output.kdl` — monitor names, modes, scale, positions
- `~/.local/state/noctalia/settings.toml` — per-display wallpaper assignment and
  per-display lock-screen login boxes

All four values are properties of the display plugged in right now. Commit them
and you have hard-coded a monitor name, a resolution and a pixel coordinate that
are wrong on every other machine. Run `./regenerate.sh` after a monitor change.

With no niri session running, `regenerate.sh` still writes valid output: niri
auto-detects the displays and the lock screen gets one display-agnostic login
box.

## Testing

```sh
./tests/run.sh
```

130 assertions, no root, no packages installed, and it does not touch your
`~/.config` — the deploy tests run the real installer against a throwaway
`HOME` under `$TMPDIR` and then throw it away. It exits non-zero on the first
failure it can report and prints the name of every failed assertion at the end.

It is not a unit-test suite. It is a check of the claims this repository makes
about itself, and each of those claims had a real bug behind it at some point,
so each one is now an assertion:

| Section | What it pins down |
| --- | --- |
| `shell scripts parse` | every script is syntactically valid |
| `no niri msg outputs parser outside lib/detect.sh` | one parser per external format |
| `niri msg outputs parsing`, `output_field column mapping` | both the current and the legacy output layouts, and the `awk` field indices behind them |
| `deploy pipeline (in a throwaway HOME)` | every manifest entry is accounted for, and `--dry-run` writes nothing at all |
| `idempotency and the ownership record` | a second and third run change **nothing**: no content, no mtime, no new snapshot; the record is complete, newline-terminated, and a union across runs; a file this repo owns is restored, a seed is never clobbered |
| `rollback: restore.sh and uninstall.sh` | both remove what was written and keep what you edited |
| `unit_state: reading systemd enablement correctly` | reads enablement from stdout, never from the exit status |
| `every referenced command is provided by a package we install` | no keybinding spawns something this repo does not install |
| `config syntax` | `niri validate`, Noctalia (0 warnings), kitty, fish, fastfetch, starship, fuzzel, GTK 3/4, Qt 5/6 |
| `config contains no machine-specific values` | no source account, hostname, interface name, resolution or credential anywhere |
| `repository hygiene`, `excluded software is never a dependency` | nothing excluded is installed or depended on, and the tier files are well-formed |

Two rules the tests exist to protect, because breaking either is silent:

- **Never write through a link-mode destination.** Those paths *are* the
  repository's files. A test that appends to `~/.config/niri/config.kdl` in a
  throwaway `HOME` is editing the repository, and will happily commit the
  result. Replace the symlink with a real file instead.
- **One parser per external format.** `niri msg outputs` is read in exactly one
  place, `lib/detect.sh`; `output_field` and `output_geometry` are the only
  sanctioned readers. A second ad-hoc `grep` in another file is how a config
  starts disagreeing with itself.

`config/niri/cfg/output.kdl` is committed as a comment-only placeholder on
purpose. It is never deployed — the installer generates it for the host it is
running on — so a fresh clone still validates, and no monitor name is ever
committed.

## Repository layout

```
install.sh              the installer
uninstall.sh            undo it
restore.sh              roll back to a snapshot
verify.sh               check the desktop against the shipped config
regenerate.sh           rebuild the per-host files
deploy.manifest         which file goes where, and how
tests/run.sh            the assertions described above

lib/
  common.sh             logging, colours, the dry-run gate, assertions
  detect.sh             OS, arch, GPU, CPU, laptop, backlight, SOF, outputs
  hardware.sh           hardware tier resolution, output.kdl generator
  packages.sh           pacman/AUR transactions, groups, service assertions
  backup.sh             the timestamped snapshot engine
  deploy.sh             manifest-driven deployment, @TOKEN@ templating
  xdg.sh                safe Thunar MIME registration
  noctalia.sh           Noctalia overlay + plugin list generation
  sddm.sh               SilentSDDM KEN theme patch

packages/
  core.txt              TIER 1 — required for the desktop to function
  utilities.txt         TIER 2 — software the desktop invokes
  optional.txt          not installed by default
  aur-required.txt      TIER 3 — AUR, required
  aur-optional.txt      AUR, not installed by default
  hardware/*.txt        TIER 3 — selected per machine
  excluded.txt          TIER 4 — documentation only, never installed
  plugins-core.txt      Noctalia plugins enabled by default
  plugins-optional.txt  the rest

config/                 deployed to ~/.config
etc/                    deployed to /etc
wallpapers/             one wallpaper + an optional fetcher
docs/                   the long-form documentation
```

## Documentation

| Document | What it covers |
|---|---|
| [`docs/INSTALL.md`](docs/INSTALL.md) | every flag, every phase, what to do when it stops |
| [`docs/PACKAGES.md`](docs/PACKAGES.md) | all four tiers, with the reason for each package |
| [`docs/KEYBINDINGS.md`](docs/KEYBINDINGS.md) | all 135 bindings, and the three that were removed |
| [`docs/CONFIG.md`](docs/CONFIG.md) | every deployed file, its mode, and why |
| [`docs/NOCTALIA.md`](docs/NOCTALIA.md) | sanitisation, plugin tiers, the generated overlay |
| [`docs/SCOPE.md`](docs/SCOPE.md) | exactly what is excluded, and why |
| [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) | every known failure mode |
| [`docs/FAQ.md`](docs/FAQ.md) | the questions that come up |

## Customising

Edit the config **in the repository**, then re-run `./install.sh`:

```sh
vim ~/dotfiles/config/niri/cfg/binds.kdl
./install.sh --only=binds
```

Static config is symlinked, so an edit is live immediately — no reinstall. Files
Noctalia rewrites (`config.toml`, the theme files) are real copies, so re-run
the installer to push a change.

Machine-specific values belong in `~/.config/dotfiles/local.conf` (mode 600,
gitignored). Copy `config/dotfiles/local.conf.example` to get started.

## Screenshots

`docs/screenshots/` holds the desktop as shipped. If it is empty in your clone,
that is expected — they are added with `git lfs` or replaced by a link in this
section; either way nothing about the desktop depends on them.

## Licence

MIT. See [`LICENSE`](LICENSE).

The configuration is yours to change. If you fork it, the one thing worth
keeping is the discipline: no machine-specific values in the repository, and no
binding pointing at something the repository does not install.
