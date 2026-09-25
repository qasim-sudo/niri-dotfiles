# Packages

Four tiers. The rule that keeps the list honest: **every entry in `core.txt` and
`aur-required.txt` exists because it is either a component of the desktop, or
the literal provider of a string that appears in a file this repository
deploys.** Nothing is in `core.txt` because an optional feature wanted it.

| Tier | File | Installed by default |
|---|---|---|
| 1 — core desktop | `packages/core.txt` | yes |
| 2 — desktop utilities | `packages/utilities.txt` | yes |
| 3 — hardware-conditional | `packages/hardware/*.txt` | yes, when the hardware is present |
| 3 — AUR required | `packages/aur-required.txt` | yes |
| — optional | `packages/optional.txt`, `aur-optional.txt` | only with `--with-extras` |
| 4 — excluded | `packages/excluded.txt` | **never** |

`pacman -S --needed` is used throughout, so a second run installs nothing. The
installer **never removes a package**. If pacman reports a conflict it stops and
prints the manual command.

---

## Tier 1 — core (`packages/core.txt`)

Without these the desktop does not come up.

### Wayland session

| Package | Reason |
|---|---|
| `niri` | the compositor |
| `xdg-desktop-portal` | the D-Bus portal broker every portal backend registers with |
| `xdg-desktop-portal-gnome` | the one backend: file chooser, screenshot, screencast, remote desktop, global shortcuts |
| `xwayland-satellite` | X11 apps (anything that is not a native Wayland client, including some Java and proprietary apps) |

Exactly **one** portal backend is installed. Two backends both claiming
`UseIn=niri` is ambiguous and produces intermittent failures in the file
chooser and screenshot dialogs.

### Audio

| Package | Reason |
|---|---|
| `pipewire` | the audio server |
| `wireplumber` | the session manager that names devices and routes them; provides `wpctl`, used by four keybindings |
| `pipewire-pulse` | the ALSA→Pulse shim, so anything still using PulseAudio works |
| `playerctl` | MPRIS control, used by five media keybindings |

### Network, Bluetooth, power

| Package | Reason |
|---|---|
| `networkmanager` | network management |
| `wpa_supplicant` | Wi-Fi, which NetworkManager drives |
| `bluez` | the `bluetooth` bar widget and the control-centre toggle |
| `power-profiles-daemon` | balances performance and battery on a laptop |

### Login manager

| Package | Reason |
|---|---|
| `sddm` | the greeter; starts `niri-session` |
| `qtvirtualkeyboard` | `InputMethod=qtvirtualkeyboard` in `etc/sddm.conf` — the on-screen keyboard for the greeter |
| `gnome-keyring` | the login keyring; without it nothing persists between sessions |

### Base

| Package | Reason |
|---|---|
| `linux` | the kernel |
| `linux-firmware` | device firmware; without it there is no Wi-Fi and no GPU |
| `base-devel` | the toolchain, and `makepkg`, which the AUR bootstrap needs |
| `git` | you already used it to clone this |
| `sudo` | the installer calls it; it refuses to run as root |

### Fonts and icons — each name is a literal string in a deployed file

| Package | Provides | Referenced by |
|---|---|---|
| `fontconfig` | `fc-match`, which `verify.sh` uses | — |
| `adwaita-fonts` | **Adwaita Sans** | `[shell] font_family` in `config/noctalia/config.toml` |
| `ttf-jetbrains-mono-nerd` | **JetBrainsMono Nerd Font Mono** | `font_family` in `config/kitty/kitty.conf`; every Nerd Font glyph on the bar and in the prompt |
| `noto-fonts` | fallback coverage | — |
| `noto-fonts-emoji` | `noto-color-emoji` | emoji in window titles and the clipboard panel |
| `papirus-icon-theme` | **Papirus-Dark** | `gtk-icon-theme-name` in both GTK settings files |

The Nerd Font variant is not optional. Every status glyph on the bar, in
`fuzzel` and in the shell prompt is a Private Use Area codepoint; a
non-Nerd JetBrains Mono renders them as tofu.

---

## Tier 2 — utilities (`packages/utilities.txt`)

Software the desktop *invokes*. Not needed to boot, but every entry is the
target of a shipped keybinding, a component of the file-manager experience, or
something the login shell calls directly.

### Shell stack

| Package | Reason |
|---|---|
| `fish` | the login shell; `Mod+T` and `Mod+Return` both open a terminal |
| `kitty` | the terminal those bindings open |
| `starship` | the prompt |
| `fastfetch` | the login banner, run by `config/fish/config.fish` |
| `fuzzel` | the `Mod+D` launcher |

### File manager — `Mod+E`, and the default file-manager experience

Only the pieces this desktop actually uses:

| Package | Reason |
|---|---|
| `thunar` | the file manager |
| `thunar-gvfs` | makes GVFS mounts work inside it — this is what makes `Mod+E` able to open a phone, a camera or a network share |
| `thunar-archive-plugin` | double-clicking a `.zip`/`.tar`/`.7z` opens Thunar Archive Manager rather than an unrelated app |
| `thunar-voluntary` | the "Open" and "Save" dialogs for other applications |
| `thunar-media-mimeinfo` | audio/video metadata in the properties pane |
| `thunar-ffmpeg-thumbnailer` | video thumbnails, which is why `ffmpeg` is here too |
| `gvfs` | the VFS layer the above two plug into |
| `gvfs-dudev` | removable devices, so a USB stick appears |
| `gvfs-mtp` | Android phones over MTP |
| `gvfs-smb` | SMB/CIFS shares |
| `gvfs-gphoto2` | cameras |
| `gvfs-fuse` | FUSE mounts |

### The rest

| Package | Reason |
|---|---|
| `swaylock` | the `Super+Alt+L` lock screen |
| `brightnessctl` | the two `XF86MonBrightness*` bindings |
| `ffmpeg` | the Noctalia `recorder` widget is in the shipped bar, and `noctalia/screen_recorder` is a **core** plugin. ffmpeg is also the ScreenCast portal's encoder backend |
| `xdg-utils` | provides `xdg-mime`, which `lib/xdg.sh` uses to register Thunar |
| `xdg-user-dirs` | provides `xdg-user-dirs-update`; keeps `~/Pictures`, `~/Downloads` etc. consistent |

---

## Tier 3 — hardware-conditional (`packages/hardware/`)

Selected per machine. `lib/detect.sh` reads `lspci -k`, `/proc/cpuinfo`,
`/sys/class/dmi/id/chassis_type` and `/proc/asound/cards`. No PCI ID, CPU model
name, monitor name or interface name is hard-coded anywhere in this repository.

### Graphics — exactly one is selected

`lib/hardware.sh` reads the first VGA/3D/Display controller from `lspci -nnk`
and matches on the kernel driver in use.

| File | Selected when | Contents |
|---|---|---|
| `intel-graphics.txt` | driver `i915` or `xe` | `vulkan-intel`, `libva-intel-driver`, `intel-media-driver` |
| `amd-graphics.txt` | driver `amdgpu` | `vulkan-radeon`, `libva-mesa-driver` |
| `nouveau-graphics.txt` | NVIDIA on the `nouveau` module | `vulkan-nouveau`, `libva-mesa-driver` |
| `nvidia-graphics.txt` | NVIDIA **and** `--nvidia` was given | `nvidia-dkms`, `nvidia-utils`, `libva-utils` |

**Why the Vulkan driver is not optional.** niri renders window animations and
blur through the Vulkan renderer. With no matching ICD, niri silently renders
with no blur and no shader animation, and there is no error message. This is the
single most common "the dotfiles installed fine but it looks wrong" cause.

**Why NVIDIA is not automatic.** The proprietary driver is closed source, so
installing it is a deliberate decision, not a detection result. Without
`--nvidia` you get a warning telling you the flag exists.

### CPU microcode

| File | Selected when | Contents |
|---|---|---|
| `intel-microcode.txt` | `vendor_id: GenuineIntel` | `intel-ucode` |
| `amd-microcode.txt` | `vendor_id: AuthenticAMD` | `amd-ucode` |

### Audio firmware

| File | Selected when | Contents |
|---|---|---|
| `sof-audio.txt` | SOF hardware: `/proc/asound/cards` names a `sof`/`snd_sof` device | `sof-firmware`, `alsa-firmware` |

Modern thin laptops route the internal microphone and speaker through a DSP
running SOF firmware. Without it PipeWire cannot open the codec at all — you
get a sink but no source, or neither.

### Laptop only

| File | Selected when | Contents |
|---|---|---|
| `laptop.txt` | DMI `chassis_type` is 8, 9, 10, 14, 30 or 31, **or** `/sys/class/power_supply` has a battery | `fprintd` |

---

## Tier 3 — AUR required (`packages/aur-required.txt`)

Four packages. No official repository provides them, and each supplies a literal
string that appears in a file this repository deploys.

| Package | Provides | Referenced by |
|---|---|---|
| `adw-gtk-theme-git` | `/usr/share/themes/adw-gtk3-dark` | `gtk-theme-name` in **both** `config/gtk-3.0/settings.ini` and `config/gtk-4.0/settings.ini` |
| `bibata-cursor-theme-bin` | the `Bibata-Modern-Classic` cursor | `XCURSOR_THEME` in `config/niri/cfg/environment.kdl` **and** `CursorTheme` in `etc/sddm.conf` |
| `sddm-silent-theme` | `/usr/share/sddm/themes/silent` | `Current=silent` in `etc/sddm.conf` |
| `papirus-folders` | the Papirus folder-colour overlay | the `keep` file Noctalia's `papirus-icons` template writes |

The installer bootstraps an AUR helper if you have none: it uses `yay`, `paru`
or `pikaur` if present, otherwise it clones and builds `yay` with `makepkg`.
There is no assumption that any AUR helper exists.

---

## Optional (`--with-extras`)

Nothing here is required by the shipped configuration.

### Noctalia plugin dependencies

See [`docs/NOCTALIA.md`](NOCTALIA.md) for why each plugin is optional.

| Package | Plugin |
|---|---|
| `hyprpicker` | `oldirtty/color_picker` |
| `imagemagick` | `jinliu/imagemagick-clock` |
| `smartmontools` | `gustav0ar/drive-health` |
| `mpv` | `noctalia/mpvpaper` |

### Clipboard tooling

`cliphist` and `wl-clipboard` are here for a **terminal** clipboard workflow.

**Noctalia does not use them.** It implements the Wayland clipboard protocol
natively and keeps its own encrypted history in
`~/.local/state/noctalia/clipboard/`, and it drives
`zwp_virtual_keyboard_v1` directly rather than shelling out to `wtype`.
Installing the package is harmless — but the installer **asserts that
`cliphist.service` stays disabled**, because a second clipboard watcher
competing for the same Wayland selection breaks paste in Noctalia.

### Audio extras

`pwvucontrol`, `libpulse`, `pipewire-alsa`, `pipewire-jack`, `gst-libav`,
`gst-plugin-pipewire` — a mixer GUI and legacy ALSA/JACK/codec bridges.

### Desktop extras

`uwsm`, `xdg-desktop-portal-gtk`, `inter-font`, `noto-fonts-cjk`,
`gnu-free-fonts`, `bluez-utils`, `pacman-contrib`, `firewalld`.

`inter-font` is listed but **inactive**: no shipped file sets a GTK `font-name`,
because the UI font comes from Noctalia's `[shell] font_family`. To use it, add
`font-name=Inter 10` to a GTK settings file and re-run the installer.

`uwsm` is not required either — `niri.service` is a static unit started by
`niri-session`, and nothing in the session references `uwsm`.

### AUR optional

`mpvpaper` and `shelly` (both Noctalia plugins), plus `ttf-space-grotesk`,
`otf-space-grotesk`, `ttf-readex-pro`, `ttf-rubik-vf`, `ttf-twemoji` and
`ttf-material-symbols-variable-git`.

---

## Tier 4 — excluded (`packages/excluded.txt`)

**Documentation only. Never installed, configured, or depended upon.** See
[`docs/SCOPE.md`](SCOPE.md).

---

## Services the installer asserts must be **disabled**

| Unit | Why it must be off |
|---|---|
| `dms.service` | a second shell; fights Noctalia for the bar, the launcher and the notification daemon |
| `dunst.service` | a second `org.freedesktop.Notifications` implementation on the same bus — the classic "notifications stopped appearing" cause |
| `quickshell.service` | the engine behind `dms`; same conflict |
| `hypridle.service` | a second idle/DPMS handler; fights Noctalia's own |
| `cliphist.service` | a second clipboard watcher on the same Wayland selection |

By default these produce a **warning** with the command to run. With `--strict`
they are disabled and masked automatically.

## Services the installer will **never** touch

`niri.service` is a **static** unit. SDDM starts it through `niri-session`.
Enabling or disabling it breaks the login session completely. `verify.sh` fails
if it is anything other than `static`.

## Installing extra packages

Add them to `~/.config/dotfiles/local.conf`:

```sh
EXTRA_PACKAGES=(some-package another-package)
```

Nothing in this repository is removed, ever. If you want a package gone, use
your package manager.
