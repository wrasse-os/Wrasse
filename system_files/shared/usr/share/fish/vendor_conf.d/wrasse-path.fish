# Make ~/.local/bin win over /usr/bin, so the real Claude Code (installed there by
# Anthropic's native installer) is found before the lazy /usr/bin/claude stub.
# fish does not add ~/.local/bin to PATH on its own.
fish_add_path --move --prepend --path $HOME/.local/bin
