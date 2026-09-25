# Assets

This directory is the **source** for the assets directory on a live machine.

The installer creates `~/.local/share/dotfiles/assets` (override with
`ASSETS_DIR` in `~/.config/dotfiles/local.conf`), and Noctalia config files may
reference files in it with the `@ASSETS@` token.

It is intentionally empty.

Widget icons referenced by a `custom_image` key are the reason this exists —
when a Noctalia custom button uses a bitmap instead of a `glyph`, the path goes
here rather than into `~/Downloads`. The source configuration had three such
references, and all three pointed at files that no longer existed on the source
machine, so the `custom_image` keys were **removed rather than replaced**. The
widgets fall back to their `glyph`, which is what a missing image would have
produced anyway.

To use your own image:

1. Put it in `assets/`.
2. Set the `custom_image` key on the relevant widget in
   `config/noctalia/config.toml` to `@ASSETS@/your-file.png`.
3. Run `./install.sh --only=noctalia`.

Note the token, not a literal path: `@ASSETS@` is substituted at install time,
so the repository stays free of absolute paths to any particular account.
