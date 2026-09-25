# fish login-shell configuration.
#
# Installed to ~/.config/fish/config.fish
#
# This is the ONLY file the repository ships for fish. In particular
# fish_variables is never deployed: it is machine-generated state that records
# absolute paths and, on the source machine, a browser path.

# ---------------------------------------------------------------------------
# Greeting
# ---------------------------------------------------------------------------
# The default fish greeting prints the hostname and motd. Suppress it; the
# login banner below does the job.
function fish_greeting
    # intentionally empty
end

# ---------------------------------------------------------------------------
# Prompt
# ---------------------------------------------------------------------------
set -gx STARSHIP_CONFIG "$HOME/.config/starship/end4diagonal.toml"

if type -q starship
    starship init fish | source
end

# ---------------------------------------------------------------------------
# Login banner
# ---------------------------------------------------------------------------
if type -q fastfetch
    fastfetch
end

# ---------------------------------------------------------------------------
# PATH
# ---------------------------------------------------------------------------
fish_add_path "$HOME/.local/bin"
