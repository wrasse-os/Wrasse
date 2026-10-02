# Divergence from upstream

Wrasse is a hard fork of [ublue-os/bluefin](https://github.com/ublue-os/bluefin). Fork point: tag `upstream-base` (`c9d08f4d`).
One short entry per change: what and why. Grouped by area. Detail on decisions and open items lives in `docs/SPEC.md`.

## Monorepo

- Vendored `projectbluefin/common` (`8a4c95eb`) `system_files/` into `system_files/shared/`. Wrasse owns these files; no `common`
  image dependency. Where a path existed in both, the Bluefin repo's own file won (the old overlay order). The
  `custom-command-list` submodule was not imported.
- Vendored `projectbluefin/branding` (`f5213ca6`) Bazaar artwork into `system_files/shared/etc/bazaar/` (placeholder).
- The Containerfile builds common's artifacts itself (`common-build` stage: umotd, uwelcome, ChairLift helper, game-device udev
  rules, wallpapers) with the same pins and checksums. Removed the `common` image from `Justfile`, `image-versions.yml` and Renovate.

## CI and release lines

- One `build.yml` replaces `build-images.yml`, `build-image-{stable,beta,latest-main}.yml` and `reusable-build.yml`. A `plan` job runs
  `.github/scripts/resolve-lines.sh matrix`; a line x flavor matrix (`fail-fast: false`) builds, rechunks, pushes, signs and attests each
  cell. A failed cell pushes nothing, so its tag keeps the last good image; a `Summary` job turns the run red. Triggers: push and
  pull request on `main`, weekly cron, manual dispatch with an optional line filter. Release/changelog job for `stable` only.
  Removed: dx axis, `beta` branch trigger, `stable-daily`, gts and lts.
- Fedora versions per line come from Bodhi (`current` = final, non-rawhide `pending` = branched) and the `releases/test/NN_Beta/`
  directory (beta). Why: Bluefin read a ublue manifest that does not exist for branched Fedora. `.github/build-matrix.json` holds the
  per-line akmods flavor, kernel pin and one `nvidia` boolean.
- Justfile: images `wrasse` and `wrasse-nvidia` under `ghcr.io/wrasse-os`, flavors `default` and `nvidia`, tags `reimagined`, `next`,
  `stable`. Removed: the `bluefin-dx` image and `IMAGE_FLAVOR`, `gts`/`stable-daily`, numeric Fedora tags, the `hwe` flavor, the
  CoreOS-manifest version lookup. `fedora_version` uses `FEDORA_VERSION` (CI) or the resolver. `just build` tolerates a repository
  with no tags.
- akmods are pulled by digest (`just resolve-akmods`, `03-install-kernel-akmods.sh`, Containerfile): each akmods image
  (`akmods`, `akmods-nvidia-open`, `akmods-zfs` for coreos) is resolved once, cosign-verified, passed as `AKMODS_*_DIGEST` build
  args and copied by `@sha256:`. No tag is re-resolved inside the build (the TOCTOU in projectbluefin issue #1264). A missing image or
  failed verification fails that cell before any push.
- The base image is resolved by digest at build time (`silverblue-main:<fedora>`, cosign-verified); the `silverblue-main-NN` pins are
  gone from `image-versions.yml` so Fedora rollovers do not stall on hand-edited pins. If ublue has no base for that version
  (branched Fedora), the cell fails closed.
- `FEDORA_PRERELEASE` build arg replaces `UBLUE_IMAGE_TAG == beta` in `03-install-kernel-akmods.sh` and `validate-repos.sh`.
- `clean.yml` lists only the two Wrasse images. `changelogs.py`: registry `ghcr.io/wrasse-os/`, no dx section. Renovate: dropped the
  `silverblue-main` digest rule.
- `.github/workflows/build-iso.yml` (manual only): see Installer.
- Docs: `docs/CI.md`, `docs/CI-SECRETS.md`; the CI size report for the DX sysext is a step in `build.yml`.

## Desktop and apps

- Removed GNOME extensions Dash to Dock, Logo Menu, Custom Command Menu, Search Light, GSConnect (incl. `nautilus-gsconnect`) and
  Gradia Capture (submodules, build steps, schemas, dconf and user-setup writes). Enabled by default: AppIndicator, Bazaar
  companion, Caffeine, Blur My Shell. Gradia Capture was later re-added as installed but not enabled; `ujust gradia-extension
  on|off|status` toggles it. Why: vanilla GNOME, nothing forced on the user.
- Vanilla GNOME layout: dropped the Ubuntu-style `button-layout` and fixed 4 workspaces. Favorites: Chromium, Files, Bazaar, Ptyxis.
- Default Flatpaks: removed Firefox, Thunderbird, DejaDup, Connections, Simple Scan, Snapshot, Characters, File Roller and the Firefox
  system-config hook; added Chromium, Clapper, Warehouse; Gradia Flatpak kept. Pinta moved to Bazaar's curated list.
- Added `playerctl`. `10-theming.sh`: moved the `SYS_ID` assignment above its first use.

## Terminal

- Removed all bash bling (`ublue-os/bling/*`, `ublue-bling`, `ujust bluefin-cli`, its Brewfile, the uwelcome `term_bling` entry);
  fastfetch theming kept. Removed starship everywhere. Why: vanilla shells.
- fish is the default login shell for new users (`SHELL=` in `/etc/default/useradd`, asserted at build). The fish prompt shows
  `<full directory>> `.
- Zellij is in `preinstall.d/system-cli.Brewfile`; nothing starts it automatically (it would hijack VS Code terminals and SSH).
  `ujust multiplexer zellij|none|status` sets or resets the Ptyxis profile's custom command on the profile named by
  `org.gnome.Ptyxis default-profile-uuid`, not the UUID hardcoded in the vendored dconf file.
- `~/.local/bin` precedes `/usr/bin` in bash (`/etc/profile.d/wrasse-path.sh`) and fish (`vendor_conf.d/wrasse-path.fish`).

## Memory and system

- composefs: `60-bootc-composefs.conf` adds the dracut `bootc` module. Not verified: `bootc-root-setup.service` in the built
  initramfs (check with `lsinitrd`).
- Memory stack (ported from `luohoa97/Bluefin-developers`, `wrasse` prefix): zram-generator drop-in (lz4, `zstd(level=3)`
  recompression), `wrasse-zram-recompress` service and timer (priority=1, requires `/sys/block/zram0/idle`), DAMON_RECLAIM
  tmpfiles, `vm.watermark_scale_factor = 125`, `vm.page-cluster = 0`, `vm.swappiness = 180`, MGLRU `min_ttl_ms = 1000`. Separate
  files so each can be dropped.

## DX sysext

- Removed the DX image path (`build-dx.sh`, `IMAGE_FLAVOR`, `build_files/dx/00-dx.sh`, `01-tests-dx.sh`, `system_files/dx/`). DX is a
  sysext now.
- `wrasse-dx.raw` (`build_files/dx/build-sysext.sh`, Containerfile stages `dx-build` and `final`): erofs (lz4), built `FROM base` so
  only missing RPMs are fetched; same method as github.com/fedora-sysexts/fedora. Differences: `ID=` is the image's real `ID`
  (not `_any`) and is asserted by `test-sysext.sh`; SELinux labels via `mkfs.erofs --file-contexts` (no privileged container in a
  plain build), verified on a real boot by `docs/DX-SELINUX-CHECKLIST.md`.
- Packages: Docker from Fedora (`moby-engine`, `docker-compose`, `docker-buildx`), Podman extras, libvirt/QEMU/swtpm/virt-manager,
  VS Code (Microsoft repo, enabled only in `dx-build`), bcc, bpftrace, sysstat, GNOME/GTK `-devel`, waydroid. Dropped: Incus,
  ROCm, `80-vfio.conf` (a dracut file cannot live in a sysext; it never applied because DX ran after the initramfs), `bluefin-dx-groups`,
  docker-ce, and extras the spec does not name (android-tools, ydotool, wtype, p7zip, genisoimage, git-svn, git-subtree,
  qemu-user-*, osbuild-selinux). Re-adding one is an edit to `PACKAGES`.
- Baked at `/usr/share/wrasse/sysexts/` as the last layer, with a plain-text `wrasse-dx.extension-release`. systemd does not scan that
  path, so DX is off until `ujust dx on`. No systemd-sysupdate; bootc delivers it, so rollback rolls it back.
- Moved from `system_files/dx` into the sysext: docker `ip_forward` sysctl, `iptable_nat` modules-load, libvirt log tmpfiles and
  relabel unit (`wrasse-dx-libvirt-relabel.service`), VS Code first-login hook (settings from `/usr/share/wrasse/dx/`).
- `ujust dx on|off|status` with the root helper `/usr/libexec/wrasse-dx` (via `pkexec`): link into `/etc/extensions/`,
  `systemd-sysext refresh`, `daemon-reload`, sysusers, tmpfiles, sysctl and modules-load, enable the sockets, add the invoking user
  (from `PKEXEC_UID`) to `docker` and `libvirt`; `off` reverses it and keeps `/var/lib/docker` and `/var/lib/libvirt`. `ujust
  devmode` (Homebrew path) is untouched.
- CI step "Report DX sysext size" writes size and extension-release to the job summary (size is unknown without a build).

## Claude Code integration

- System skill `/usr/share/wrasse/skills/wrasse/SKILL.md` and user-setup hook `30-wrasse-agent-skill.sh`, which links it into
  `~/.claude/skills/wrasse` and `~/.agents/skills/wrasse` once per user (a deleted link stays deleted; existing files are never
  replaced). Frontmatter is only `name` and `description`; nothing is pre-approved. The docs confirm `~/.claude/skills`; they do
  not mention `~/.agents/skills`, which is kept because the spec asks for it.
- Lazy `/usr/bin/claude` stub: execs `~/.local/bin/claude` if present (guarded by `readlink -f`) inside `systemd-run --user --scope
  --slice=wrasse-agents.slice` (`WRASSE_AGENT_NO_SLICE=1` skips it); otherwise explains, asks `[y/N]` on a terminal and runs the
  official installer (`https://claude.ai/install.sh`, downloaded to a temp file first). No flags are added, so permission modes are
  untouched. Gating on pending decision 2 is not done.
- `wrasse-agents.slice`: `MemoryHigh=60%`, `ManagedOOMMemoryPressure=kill`; pressure limit and duration are in
  `wrasse-agents.slice.d/20-oomd.conf` because Fedora's `user/slice.d/10-oomd-per-slice-defaults.conf` overrides values set in the
  slice file. `systemd-oomd.service` enabled explicitly in `17-cleanup.sh`. See `docs/AGENT-SLICE.md`.
- Build checks in `20-tests.sh`: files exist, `systemd-analyze --user verify` of the slice, oomd enabled.

## wrasse CLI

- `cli/` (own crate; clap, serde, serde_json, toml): a router over Flatpak (`--user`, flathub), brew (formulae), distrobox (`--from`)
  and `ujust dx`. `install`, `remove`, `list`, `search`, `sync`, `--json`, `--dry-run`; records to `~/.config/wrasse/packages.toml`.
  Backends are functions over one `Runner` (real, dry-run, fake) so tests never touch the real tools.
- No Flatpak-vs-brew default: a name in both stops with `policy_required` unless `--prefer`, `config.toml` `prefer`, or `--kind`
  settles it (pending decision 1).
- Containerfile stage `wrasse-build` (`rust:alpine` by digest, musl, `--locked`) ships `/usr/bin/wrasse` via `common-build`'s
  `/out/shared`. Not built locally.

## Installer and ISO

- `installer/gpu-detect/` (`wrasse-gpu-detect`, Rust): reads `/sys/bus/pci/devices`, prints `wrasse-nvidia` for a Turing or newer NVIDIA
  GPU (NVIDIA's open-module device list via `gen-nvidia-ids.sh`), else `wrasse`. Override: `--override`, `$WRASSE_GPU`,
  `wrasse.gpu=` on the kernel command line, `/etc/wrasse/installer-gpu`. Why: the installer's own check is vendor-only and has no
  override.
- `installer/gen-catalog.sh` builds `/etc/bootc-installer/images.json` from `build-matrix.json` (two GPU groups, three lines each; a
  line with `"nvidia": false` loses its NVIDIA leaf). `installer/iso/variant/wrasse/` runs `wrasse-gpu-detect` at live boot and sets
  `default_image`. The ISO is a network install because the installer drops its image step (where the release line is asked) in
  live-ISO mode.
- `build-iso.yml` adapts `projectbluefin/dakota-iso` (what Bluefin's ISOs use now, not `ublue-os/titanoboa`), pinned to commit
  `9c123eea`, with `tuna-os/bootc-installer` `v2026.09.26-253d6938` pinned by bundle sha256 (`installer/iso/pin.env`,
  `pin-installer.sh` patches the upstream `releases/latest` lookup). `wrasse-gpu-detect` is built static in the workflow. No payload,
  R2 upload, schedule or boot test. The ISO label stays `DAKOTA_LIVE` (hardcoded upstream).

## Docs

- Rewrote `README.md` for Wrasse (Bluefin branding is noted as unrenamed); added `docs/INSTALL.md`, `docs/UJUST.md`,
  `docs/WRASSE-INSTALL.md`; cut `AGENTS.md` down to a pointer to `CLAUDE.md` and `docs/SPEC.md`; regrouped this file by area.
