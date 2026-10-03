---
name: wrasse
description: Rules for working on Wrasse OS, an immutable Fedora bootc desktop. Use before installing software, changing system configuration, updating the OS, or diagnosing memory or performance problems on this machine. Covers wrasse install, Flatpak, brew, distrobox, ujust, bootc, and the DX toolchain.
---

# Wrasse OS

The short, agent-neutral version of these rules is `/usr/share/wrasse/AGENTS.md` (linked to `~/AGENTS.md`). This skill is the
Claude Code detail behind it.

Wrasse is an image-based Fedora desktop (bootc, GNOME). `/usr` is read-only and the image is the unit of update and
rollback. Work with that, not around it.

## Hard rules

- Never run `sudo dnf install`, `rpm-ostree install`, `rpm-ostree override`, or `rpm -i`. They do not apply here, and layering
  packages defeats rollback. If a task seems to need a system package, say so and propose one of the routes below.
- Never run `rpm-ostree upgrade`. Use `bootc` (see "Updates").
- Do not edit anything under `/usr`. It is read-only. System-wide config goes in `/etc`, and only with the user's consent.
- Do not run `sudo` or `pkexec` on your own initiative. Ask first and say what it will change.
- Nothing here is pre-approved. Ask for confirmation in the normal way before installs, removals and system changes.

## Installing software: use `wrasse install`

`wrasse install` is a router over Flatpak, brew and distrobox. It records every install in
`~/.config/wrasse/packages.toml`, so `wrasse sync` can rebuild the setup on a new machine. Prefer it over calling the
backends directly, so the record stays complete.

```
wrasse install <pkg>                  # GUI app -> Flatpak, CLI tool -> brew
wrasse install <pkg> --kind gui|cli   # skip classification
wrasse install <pkg> --from fedora    # inside a distrobox container (fedora, ubuntu, debian, arch, alpine, opensuse, or an image ref)
wrasse remove <pkg> [--backend flatpak|brew|distrobox] [--from <distro>]
wrasse list
wrasse search <query>
wrasse sync
wrasse install --dx                   # same as `ujust dx on`
```

- Add `--json` to any command for one machine-readable JSON object on stdout (errors too). Add `--dry-run` to see what
  would run without changing anything. Use `--dry-run` first when unsure.
- Exit codes: 0 ok, 1 error or partial `sync` failure, 3 means a decision is needed.
- Error code `policy_required` (exit 3): the name exists as both a Flatpak and a brew package and no preference is set.
  Do not pick for the user. Ask them which they want, then rerun with `--prefer flatpak` or `--prefer brew`, or `--kind gui`
  or `--kind cli`. `ask` needs a terminal; an agent usually has none, so it will fail with `needs_terminal`.
- `ambiguous` results (same app under two IDs differing in case) mean: ask for the exact ID.
- Flatpak installs are per user (`--user`, Flathub). Brew installs formulae only (no casks). Distrobox packages are not
  exported to the host menu.

Which backend is for what:

- GUI apps: Flatpak (via `wrasse install`; Bazaar is the app store).
- CLI tools and language toolchains: brew (Homebrew lives in `/home/linuxbrew/.linuxbrew`).
- Anything that needs a mutable distro (apt, dnf, pacman, a specific glibc, `.deb` or `.rpm` only software): distrobox,
  with `wrasse install <pkg> --from <distro>`, or `distrobox enter` for ad hoc work. Podman is available too.
- System tasks (toggles, setup, maintenance): `ujust`. Run `ujust --choose` or `ujust --list` to see the recipes.

## Updates and rollback

- Update the OS: `bootc upgrade` (needs root; ask first). It stages the next image; it applies on reboot. `uupd` also
  updates the OS, Flatpaks and brew on a timer.
- Inspect: `bootc status`. Roll back to the previous image: `bootc rollback`, then reboot.
- Do not use `rpm-ostree` for any of this.

## DX (developer toolchain)

Docker, Podman extras, libvirt/QEMU, VS Code, perf tools (bcc, bpftrace, sysstat), GNOME/GTK dev headers and waydroid are a
systemd-sysext, not part of the base image. It is downloaded on demand (about 1.4 GB, needs network) and is off by default.

- `ujust dx status`, `ujust dx on`, `ujust dx off`, `ujust dx update` (`on`, `off` and `update` need root through pkexec, and `on` adds the user to
  the docker and libvirt groups, which needs a re-login to take effect). After an OS update DX stays off until `ujust dx update`.
- If a task needs Docker, libvirt or the dev headers, check `ujust dx status` first and ask the user before turning it on.

## Terminal

Zellij is installed by default through brew. `ujust multiplexer zellij|none|status` makes Ptyxis start Zellij or a plain
shell. The login shell is fish. Do not start a multiplexer from shell config.

## Memory and performance

The memory stack is tuned for a desktop with zram and is set by files in the image, not by this machine's `/etc`:

- zram swap with lz4, recompressed to zstd when cold: `/usr/lib/systemd/zram-generator.conf.d/`, timer
  `wrasse-zram-recompress.timer`.
- Sysctls: `/usr/lib/sysctl.d/99-wrasse-*.conf` (high swappiness, page-cluster 0, raised watermark scale).
- DAMON_RECLAIM and MGLRU settings: `/usr/lib/tmpfiles.d/wrasse-damon-reclaim.conf`, `wrasse-mglru.conf`.
- Agents (including this one) run in `wrasse-agents.slice`, a user slice with a soft memory limit. If memory gets tight,
  systemd-oomd kills the agent's scope instead of letting the desktop freeze. If you were killed or a command vanished
  under memory pressure, that is why. Keep builds and test runs modest (`-j`, one at a time), and check the slice with
  `systemctl --user status wrasse-agents.slice` and `oomctl`.

Do not "fix" memory settings by editing `/usr`; tell the user what you found and let them decide.
