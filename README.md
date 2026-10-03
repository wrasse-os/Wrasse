# Wrasse

Wrasse is a hard fork of Universal Blue's [Bluefin](https://github.com/ublue-os/bluefin): an agent-first, opinionated
GNOME desktop built as a Fedora bootc image. Images are published to `ghcr.io/wrasse-os/wrasse` and
`ghcr.io/wrasse-os/wrasse-nvidia`. Source: `github.com/wrasse-os/Wrasse`.

> **Branding.** The rename from Bluefin to Wrasse (`brand:`) has not happened yet. The OS still identifies itself as
> Bluefin in os-release, MOTD, ujust text and some UI. Image names, release lines and the files named `wrasse-*` are already
> Wrasse. This README describes the tree as it is, not as it will be.

## What is different from Bluefin

- Vanilla GNOME layout. Enabled extensions: AppIndicator, Bazaar companion, Caffeine, Blur My Shell. Gradia Capture is installed
  but off (`ujust gradia-extension on`).
- fish is the default login shell for new users. No bash "bling", no starship. Zellij is installed from brew on first login and is
  opt-in as the Ptyxis shell (`ujust multiplexer zellij`).
- Developer tools are not an image. `ujust dx on` downloads the matching, signed `wrasse-dx.raw` systemd-sysext (Docker, libvirt/QEMU, VS Code, perf
  tools, GNOME/GTK dev headers, waydroid; about 1.4 GB, so it is not in the image or the ISO) and merges it.
- Memory tuning: zram with recompression, DAMON reclaim, MGLRU and VM sysctls.
- Claude Code integration: a system skill, a lazy `claude` stub that offers Anthropic's official installer, and a
  `wrasse-agents.slice` so systemd-oomd kills a runaway agent instead of freezing the desktop. See `docs/AGENT-SLICE.md`.
- `wrasse install`: one command that routes to Flatpak, brew or distrobox. See `docs/WRASSE-INSTALL.md`.
- Release lines instead of Bluefin's streams: `reimagined`, `next`, `stable`. See `docs/INSTALL.md`.
- Kept from Bluefin: uupd, ujust, Homebrew, distrobox, codecs, Bazaar.

## Install

See `docs/INSTALL.md` (GPU choice, release lines, rebase, Secure Boot with NVIDIA). A network-install ISO workflow exists
(`installer/README.md`) but is run by hand and has not been built or booted yet.

## Documentation

| File | Contents |
|---|---|
| `docs/INSTALL.md` | Images, GPU table, release lines, rebase, Secure Boot MOK enrollment |
| `docs/UJUST.md` | Reference of the `ujust` recipes in this tree |
| `docs/WRASSE-INSTALL.md` | The `wrasse` CLI |
| `docs/SPEC.md` | Phases, decisions, status, open items |
| `docs/CI.md`, `docs/CI-SECRETS.md` | Build matrix, fail-closed behavior, secrets to create |
| `docs/AGENT-SLICE.md` | Agent memory slice limits |
| `docs/DX-SELINUX-CHECKLIST.md` | Test list for the DX sysext |
| `installer/README.md` | Live ISO and GPU autodetect |
| `DIVERGENCE.md` | Every change from upstream Bluefin |
| `CLAUDE.md` | Working rules for agents and contributors |

## Status

Most of the work is implemented but not built or booted on hardware. Open and blocked items are tracked per phase in
`docs/SPEC.md`.

## License

Apache License 2.0, see [LICENSE](LICENSE). Wrasse builds on Fedora Linux, GNOME, Universal Blue and Bluefin; all keep their
own licenses and attributions.
