# wrasse install

`wrasse` is a router, not a package manager. Each backend does its own work: Flatpak for GUI apps, Homebrew for CLI tools,
distrobox for anything that needs another distro, and `ujust dx` for the developer sysext. It lives in `cli/` and ships at
`/usr/bin/wrasse`. The image build has not been run yet, so the shipped binary is unconfirmed until CI.

```fish
wrasse install org.gnome.Loupe        # GUI app: Flatpak (user installation, flathub)
wrasse install ripgrep                # CLI tool: brew formula
wrasse install htop --from ubuntu     # distrobox container wrasse-ubuntu
wrasse install --dx                   # runs `ujust dx on`
wrasse remove ripgrep
wrasse list
wrasse search firefox
wrasse sync                           # reinstall what packages.toml lists and the machine lacks
```

Global flags: `--json` prints one JSON object on stdout (errors too, for agents); `--dry-run` shows what would run (lookups still
run). `wrasse remove` takes `--backend flatpak|brew|distrobox` or `--from <distro>` when a name is in several places, and
`--dx` runs `ujust dx off`.

## Choosing Flatpak or brew

`--kind gui` forces Flatpak and `--kind cli` forces brew. A name that exists in both is a policy question that is not decided yet
(`docs/SPEC.md`, pending decision 1): wrasse stops with a `policy_required` error unless you pass `--prefer flatpak|brew|ask` or put
`prefer = "flatpak"` (or `"brew"`, `"ask"`) in `~/.config/wrasse/config.toml`. Where Flathub lists two IDs that differ only by
case, wrasse reports the name as ambiguous and wants the exact ID.

Exit codes: 0 ok, 1 error or partial `sync` failure, 3 when a policy is required or `ask` has no terminal.

## Record

Every install and remove is written to `~/.config/wrasse/packages.toml` (`$WRASSE_CONFIG_DIR` or `$XDG_CONFIG_HOME/wrasse` override
the directory), with a `dx` flag and one `[[package]]` entry per package (`name`, `backend`, and `from` for distrobox).
Back that file up; `wrasse sync` on a new machine rebuilds the setup from it.

## Limits

- Flatpaks go to the user installation, so system-wide Flatpaks are not seen by `sync` or removed by `remove`.
- Brew casks are ignored (macOS only). Distrobox packages are not exported to the host menu.
- Real installs, `sync` and the DX toggle were only tested with a fake runner and `--dry-run`, not against the real backends.
- Distros for `--from`: fedora, ubuntu, debian, arch, alpine, opensuse, or a full image reference.
