# Noctalia configuration

| File | Goes to | Mode |
|---|---|---|
| `config.toml` | `~/.config/noctalia/config.toml` | `copy` |
| *generated* | `~/.local/state/noctalia/settings.toml` | written by `lib/noctalia.sh` |

`config.toml` is the complete, self-contained description of the desktop. It
contains **no monitor name, no resolution, no pixel coordinate, no username
and no absolute path** outside of `@TOKEN@` placeholders. Everything that
describes the hardware attached right now is generated.

It is deployed as a **copy**, not a symlink, because Noctalia rewrites this file
when you change anything in its settings UI. A symlink would mean the UI writes
through the link and edits the repository.

**Full documentation: [`docs/NOCTALIA.md`](../../docs/NOCTALIA.md)** — sanitisation
log, plugin tiers, the generated overlay, and how to change any of it.
