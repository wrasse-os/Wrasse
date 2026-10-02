# Divergence from upstream

Wrasse is a hard fork of [ublue-os/bluefin](https://github.com/ublue-os/bluefin).
Fork point: tag `upstream-base` (`c9d08f4d`). One short entry per change: what and why.

## Monorepo

- **Vendored `projectbluefin/common` (`8a4c95eb`) `system_files/`** into `system_files/shared/`.
  Wrasse owns these files now; no more `common` image dependency. Where a path existed in both,
  the Bluefin repo's own file was kept, matching the old overlay order. The `custom-command-list`
  submodule was not imported (extension is being removed).
- **Vendored `projectbluefin/branding` (`f5213ca6`) bazaar artwork** into `system_files/shared/etc/bazaar/`.
  Placeholder until Wrasse artwork exists.
- **Containerfile builds common's artifacts itself** (`common-build` stage: umotd, uwelcome, ChairLift
  helper, game-device udev rules, wallpapers) instead of `COPY --from=ghcr.io/projectbluefin/common`.
  Same pins and checksum verification as upstream common; the `ctx` overlay order is unchanged.
- **Dropped the `common` image dependency** from `Justfile`, `image-versions.yml` and renovate config
  (build args, digest lookup, cosign verify). Nothing pulls `ghcr.io/projectbluefin/common` anymore.

## Desktop

- **Removed GNOME extensions** Dash to Dock, Logo Menu, Custom Command Menu, Search Light, GSConnect
  (incl. `nautilus-gsconnect`) and Gradia Capture: submodules, build steps, schema/dconf settings and
  the Logo-menu / custom-command-list dconf writes in the user-setup hooks. Wrasse targets vanilla GNOME.
  Enabled by default now: AppIndicator, Bazaar companion, Caffeine, Blur My Shell. Tiling Shell and QSAP
  were never in the tree. The build-tool `dnf` list in `build-gnome-extensions.sh` is unchanged (not yet
  verified which tools are now unused).
- `10-theming.sh`: moved the `SYS_ID` assignment above its first use (it was read before being set).

## Flatpaks

- **Removed default Flatpaks** Firefox, Thunderbird and DejaDup from `system-flatpaks.Brewfile`, plus the
  Firefox system-config hook (`privileged-setup.hooks.d/99-flatpaks.sh`, `firefox-config/`) that only
  served Firefox. Font Downloader was not in the list. Bazaar's curated "Browsers" section still lists Firefox
  as a store suggestion, not a default.
- **Added default Flatpaks** Chromium (replaces Firefox) and Clapper. Extension Manager, Flatseal and
  Mission Center were already defaults.
- **Vanilla GNOME layout**: dropped the Ubuntu-style window buttons (`button-layout`) and fixed 4 workspaces
  from the schema override, so GNOME defaults apply (dock was removed earlier). Favorite apps are now
  Chromium, Files, Bazaar, Ptyxis (no Firefox, Thunderbird, GNOME Software or VS Code).

## DX

- **Removed the DX image build path** (`build_files/shared/build-dx.sh`, the `IMAGE_FLAVOR=dx` branch in `build.sh`, the
  `IMAGE_FLAVOR` Containerfile arg, `build_files/dx/00-dx.sh` and `01-tests-dx.sh`, all of `system_files/dx/`). Why: DX is no
  longer an image (SPEC Phase 3); it is the `wrasse-dx.raw` sysext added in the next entry. The old Cockpit removal in the DX build
  went with it (Cockpit is already gone from the base image).
- **Dropped with the old DX, not carried into the sysext**: `80-vfio.conf` (a dracut file cannot live in a sysext, and it never
  applied because DX ran after the initramfs step), the Incus packages, units and tmpfiles, ROCm, `bluefin-dx-groups`
  (replaced by `ujust dx on` adding the user to groups), Docker Inc's `docker-ce` repo packages, and a few extras that the spec
  list does not name (android-tools, ydotool, wtype, p7zip, genisoimage, git-svn, git-subtree, qemu-user-*, osbuild-selinux).
  Re-adding one is a one-line edit to `PACKAGES` in `build_files/dx/build-sysext.sh`.

## Shell

- **fish is the default login shell for new users** (`SHELL=` in `/etc/default/useradd`, set in
  `04-packages.sh` and asserted). Bash stays installed; root's shell is unchanged.

## Packages and system

- **Added `playerctl`** to the base package list.
- **composefs support**: `60-bootc-composefs.conf` adds the dracut `bootc` module. `19-initramfs.sh` already runs
  dracut after all base packages are installed and dracut reads `dracut.conf.d/` on its own, so no separate
  dracut run was added. Not yet verified: that `bootc-root-setup.service` lands in the built initramfs (needs a
  build; check with `lsinitrd`). Note: DX's `80-vfio.conf` is never applied because DX runs after 19 (upstream bug).

## Memory stack

Ported from `luohoa97/Bluefin-developers` (`files/system/`), files renamed with a `wrasse` prefix.

- **Base**: zram-generator drop-in (lz4 primary, `zstd(level=3)` recompression), `wrasse-zram-recompress`
  service and timer (timer enabled in `17-cleanup.sh`), DAMON_RECLAIM tmpfiles config, and
  `vm.watermark_scale_factor = 125`. Why: start background reclaim into zram before allocations stall.
- **zram recompress `priority=1`**: write `priority=1` so recompression uses the zstd slot explicitly.
- **zram recompress service condition**: also require `/sys/block/zram0/idle`, so it skips on kernels without idle marking.
- **`vm.page-cluster = 0`** (own file): no swap readahead on zram.
- **`vm.swappiness = 180`** (own file): favor swapping to zram over dropping file cache. No other swappiness setting exists in this repo or the vendored common; the base image was not checked.
- **MGLRU `min_ttl_ms = 1000`** (own tmpfiles file): keep the working set from thrashing.

## Terminal

- **Removed all bash "bling"**: `ublue-os/bling/*`, `ublue-bling`, the `ujust bluefin-cli` recipe and its
  `cli.Brewfile`, the uwelcome `term_bling` entry, and the `bluefin-cli` copy in `18-workarounds.sh`.
  Why: Wrasse ships vanilla shells; users bring their own prompt and tools. Fastfetch theming
  (`ublue-bling-fastfetch`) is kept.
- **Removed starship** everywhere: binary download, bash profile.d hook, fish and zsh init, brew preinstall entry.
- **fish prompt** replaced Bluefin's user@host/container prompt with `<full directory>> `.

- **Debloated default Flatpaks**: removed Connections, Simple Scan, Snapshot, Characters and File Roller. Kept core GNOME
  utilities, DistroShelf, Ignition, Impression, Contacts, Calendar, Maps, Weather, Showtime, Refine and the Wrasse set
  (Chromium, Clapper, Extension Manager, Flatseal, Mission Center, Bazaar). Video mime defaults stay on Showtime. Loupe stays; Warehouse was added. The Gradia Flatpak stays a default (only its shell extension was removed).
  Pinta is no longer a default; it is listed in Bazaar's curated "Office & Productivity" section instead.

## CI + release lines

- **Fedora version resolver** (`.github/scripts/resolve-lines.sh`) and **matrix config** (`.github/build-matrix.json`): resolves the
  Fedora version for each release line from Bodhi (`current` = final, `pending` non-rawhide = branched) and the `releases/test/NN_Beta/`
  directory on dl.fedoraproject.org (beta). Why: the spec wants versions resolved automatically, and Bluefin's version lookup read
  a ublue base-image manifest that does not exist for branched Fedora. The config holds the per-line akmods flavor, kernel pin and
  the `nvidia` switch (one boolean per line) that decides whether a line gets an nvidia image.

## Gradia extension (opt-in)

- **Gradia Capture GNOME extension is installed but not enabled.** Re-added the submodule and build step; it is not in
  the default `enabled-extensions`. `ujust gradia-extension on|off|status` toggles it per user (`60-custom.just`).
  Why: users who do not want their GNOME Shell modified are not forced into it.
- **akmods are pulled by digest** (`just resolve-akmods`, `03-install-kernel-akmods.sh`, `Containerfile`): the kernel is read once from
  the rolling `akmods:<flavor>-<fedora>` tag (or the kernel pin), each akmods image (`akmods`, `akmods-nvidia-open`, and
  `akmods-zfs` for coreos flavors) is resolved to a digest once, cosign-verified by digest, and passed in as `AKMODS_DIGEST`,
  `AKMODS_NVIDIA_DIGEST`, `AKMODS_ZFS_DIGEST` build args. The install script now requires them and copies `@sha256:`, so no tag is
  re-resolved inside the build (the TOCTOU in projectbluefin issue #1264). A missing image or failed verification exits non-zero,
  which fails that matrix cell before anything is pushed.
- **Release lines and image names in the Justfile**: images are `wrasse` / `wrasse-nvidia` under `ghcr.io/wrasse-os` (`repo_organization`
  is now `wrasse-os`; flavors are `default` and `nvidia`); tags are the lines `reimagined`, `next`, `stable`. Removed: the `bluefin-dx`
  image and its `IMAGE_FLAVOR=dx` build arg, the `gts` and `stable-daily` tags, the numeric Fedora-version tags (they collide between
  lines), the `hwe` akmods flavor, and the CoreOS-manifest/ublue-base-main version lookup. `fedora_version` now takes `FEDORA_VERSION`
  (set by CI) or runs `resolve-lines.sh`; the akmods flavor and kernel pin come from `.github/build-matrix.json`.
- **Base image resolved by digest at build time** (Justfile `build`, `image-versions.yml`): the `silverblue-main-NN` entries are gone;
  `just build` reads `silverblue-main:<fedora>` once, cosign-verifies the digest and builds `FROM ...@sha256:`. Why: with the Fedora
  version resolved per line automatically, a hand-maintained per-version pin would stall every Fedora rollover. If ublue has not
  published the base for that Fedora version (true for branched Fedora, see `docs/SPEC.md`), the cell fails closed.
- **`FEDORA_PRERELEASE` build arg** replaces the `UBLUE_IMAGE_TAG == beta` checks in `03-install-kernel-akmods.sh` and
  `validate-repos.sh`: updates-testing and the rpmfusion/mesa workarounds apply when the Fedora version is not final yet.
- **`just build` tolerates a repository with no tags** (`skopeo list-tags` failing on first push).
- **Workflows**: `build-images.yml`, `build-image-{stable,beta,latest-main}.yml` and `reusable-build.yml` are replaced by one
  `build.yml`. A `plan` job runs `resolve-lines.sh matrix`; a `build` matrix (line x flavor, `fail-fast: false`) builds, rechunks,
  pushes, signs and attests each cell independently. A failed cell pushes nothing (its tag keeps the last good image) and a final
  `Summary` job only turns the run red. Triggers: push and pull request on `main`, weekly cron (Tuesday), manual dispatch with an
  optional single-line filter. The release/changelog job runs for `stable` only. Removed: the `-dx` matrix axis, the `beta` branch
  trigger, the `stable-daily` cadence. `COSIGN_PASSWORD` is passed to cosign alongside `SIGNING_SECRET` (see `docs/CI-SECRETS.md`).
- **`clean.yml`** only lists `wrasse` and `wrasse-nvidia`. **`changelogs.py`**: registry `ghcr.io/wrasse-os/`, images `wrasse` and
  `wrasse-nvidia`, no dx section or dx packages, no `stable-daily` special case. **Renovate**: dropped the `silverblue-main` digest
  rule (that image is resolved at build time now).
- **Docs**: added `docs/CI.md` (lines, config, resolution, fail-closed) and `docs/CI-SECRETS.md` (secrets and one-time setup the user
  must do); `AGENTS.md` build/workflow/pinning sections rewritten for the new layout.

## DX sysext (Phase 3)

- **`wrasse-dx.raw` build** (`build_files/dx/build-sysext.sh`, Containerfile stages `dx-build` and `final`): a systemd-sysext in
  erofs (lz4), built `FROM base` so `dnf5 download --resolve` fetches only what the image lacks and the extension-release comes from
  the image's own `/usr/lib/os-release`. Same method as github.com/fedora-sysexts/fedora (`sysext.just`): download RPMs, extract with
  `rpm2cpio | cpio`, `/etc` to `/usr/etc`, `usr/sbin` into `usr/bin`, drop `/var` `/run` `/boot`, then `mkfs.erofs`.
  Two deliberate differences: (1) `ID=` is the image's real `ID`, not fedora-sysexts' `ID=_any` (spec asks for ID + VERSION_ID to
  match, and the build asserts it; `_any` was only needed for images whose ID they do not know); (2) SELinux labels come from
  `mkfs.erofs --file-contexts` against the image's `file_contexts`, because `setfiles` needs a privileged container and a plain
  `podman build` RUN has none. The `.raw` is not labelled by a running kernel, so the checklist verifies labels on a real boot.
- **Packages**: Docker from Fedora (`moby-engine`, `docker-compose`, `docker-buildx`, which pulls `docker-cli` and `containerd`) rather
  than docker-ce, so no third-party repo has to follow branched Fedora; Podman extras; libvirt/QEMU/swtpm/virt-manager; VS Code (Microsoft
  repo, enabled only inside the `dx-build` stage, never in the shipped image); bcc, bpftrace, sysstat and friends; GNOME/GTK `-devel`
  packages; waydroid. Full list in `PACKAGES`.
- **Baked at `/usr/share/wrasse/sysexts/`** in the last Containerfile layer (`final`), next to a plain-text
  `wrasse-dx.extension-release` that `test-sysext.sh` compares with os-release at build time. systemd does not scan that path, so DX
  stays off until `ujust dx on`. No systemd-sysupdate: bootc delivers the file, so rollback rolls DX back too.
- **Files moved from `system_files/dx` into the sysext** (`build_files/dx/files/usr`): the docker `ip_forward` sysctl, the
  `iptable_nat` modules-load entry (was written to `/etc/modules-load.d` by `build-dx.sh`), the libvirt `/var/log/libvirt` tmpfiles
  entry and relabel unit (renamed `wrasse-dx-libvirt-relabel.service`), and the VS Code first-login hook (reads its settings from
  `/usr/share/wrasse/dx/vscode-settings.json` instead of `/etc/skel`, which a sysext cannot provide).
- **`Containerfile`**: `base` now ends the stage chain `base` to `dx-build` to `final`; the default build target is `final`.
- **`ujust dx on|off|status`** (`60-custom.just`, helper `/usr/libexec/wrasse-dx`, run through `pkexec`): `on` links the baked
  `.raw` into `/etc/extensions/`, runs `systemd-sysext refresh`, `daemon-reload`, `systemd-sysusers` (creates the `docker`, `libvirt`
  and `qemu` accounts from the sysext's sysusers.d files), `systemd-tmpfiles --create`, restarts sysctl and modules-load, enables the
  Docker, Podman and libvirt sockets, and adds the invoking user to `docker` and `libvirt`. `off` reverses all of it and leaves
  `/var/lib/docker` and `/var/lib/libvirt` alone. The user comes from `PKEXEC_UID`, not from an argument. The existing
  `ujust devmode` (Homebrew based dev tools) is untouched.
- **CI reports the DX sysext size** (`build.yml`, step "Report DX sysext size"): reads `wrasse-dx.raw` out of the built image and writes
  its size and extension-release to the job summary for every cell. Size cannot be known without a build, so the spec's "report the
  final size" is answered by the first CI run.
- **`docs/DX-SELINUX-CHECKLIST.md`**: bring-up and SELinux test list for the DX sysext (labels, Docker, libvirt/QEMU, VS Code, perf,
  waydroid, reboot, update and rollback, off). Written because none of it could be run without a build.

## Phase 4: terminal

- **Zellij in the default brew set** (`homebrew/preinstall.d/system-cli.Brewfile`): added `brew "zellij"`. `brew-preinstall` is
  content-addressed on the Brewfile hash, so existing users get it on the next login after the update and it enters the managed
  set. No change to `brew-preinstall` itself. Nothing in fish or bash config starts Zellij (it would hijack VS Code terminals and SSH).
- **`ujust multiplexer zellij|none|status`** (`60-custom.just`): sets or resets `use-custom-command` and `custom-command` on the
  Ptyxis profile (schema `org.gnome.Ptyxis.Profile`, relocatable at `/org/gnome/Ptyxis/Profiles/<uuid>/`; keys checked against the
  installed ptyxis 50.1 schema). The profile is the one named by `org.gnome.Ptyxis default-profile-uuid`, not the hardcoded UUID in
  the vendored dconf palette file, because Ptyxis generates its own UUID at first launch (this machine's is not
  `2871e802...`). `none` uses `gsettings reset`, so it returns to the schema default rather than writing a value. Zellij is
  launched by absolute brew path since a GUI-launched Ptyxis may not have brew on PATH.

## Phase 6: wrasse install

- **`cli/`: the `wrasse` Rust CLI** (own crate, no workspace; deps clap, serde, serde_json, toml). A router over
  Flatpak (`--user`, flathub), brew (formulae only), distrobox (`--from <distro>`, container `wrasse-<distro>`)
  and `ujust dx on|off` (`--dx`). `install`, `remove`, `list`, `search`, `sync`, `--json` and `--dry-run` on all.
  Every install/remove is recorded in `~/.config/wrasse/packages.toml`; `sync` replays it. Backends are plain
  functions over one `Runner` (real, dry-run or fake) so tests never touch the real tools. Why: spec Phase 6;
  wrasse never reimplements a package manager.
- **Flatpak-vs-brew policy has no default.** If a name exists in both, `wrasse install` stops with a
  `policy_required` error unless `--prefer flatpak|brew|ask`, `prefer = ...` in `~/.config/wrasse/config.toml`, or
  `--kind gui|cli` settles it. Why: pending decision 1 is the user's; see `docs/SPEC.md`.
- **Containerfile builds the `wrasse` CLI** (`wrasse-build` stage, `rust:alpine` pinned by digest, `cargo build
  --release --locked`, musl so the binary is static) and copies it to `/usr/bin/wrasse` through `common-build`'s
  `/out/shared`, like umotd. Why: ship the CLI in the image. Nothing was built locally.

## Phase 5: Claude Code integration

- **System skill `/usr/share/wrasse/skills/wrasse/SKILL.md`** and user-setup hook `30-wrasse-agent-skill.sh`, which symlinks
  it into `~/.claude/skills/wrasse` and `~/.agents/skills/wrasse` once per user (`version-script`, so a deleted link stays
  deleted; an existing file or directory is never replaced). Teaches the read-only root, `wrasse install` (with `--json`, exit
  code 3 and the `policy_required` error), Flatpak/brew/distrobox/ujust routing, `bootc` instead of rpm-ostree, DX, memory
  tuning locations. Frontmatter is only `name` and `description` and sets no `allowed-tools`, so nothing is pre-approved.
  Why: spec Phase 5. Docs (code.claude.com/docs/en/skills) confirm `~/.claude/skills/<name>/SKILL.md` and that symlinked
  skill directories are followed; they do not mention `~/.agents/skills`, which is kept only because the spec asks for it
  (other agent tools read it).

- **Lazy `/usr/bin/claude` stub.** If `~/.local/bin/claude` exists it is exec'd (never itself, guarded by `readlink -f`),
  inside `systemd-run --user --scope --slice=wrasse-agents.slice`; without a user manager it runs unwrapped and says so
  (`WRASSE_AGENT_NO_SLICE=1` also skips the slice). Otherwise it explains, needs a terminal, asks `[y/N]`, downloads
  `https://claude.ai/install.sh` to a temp file and runs it (the method documented at code.claude.com/docs/en/setup;
  no root needed, installs to `~/.local/bin` and `~/.local/share/claude`, then auto-updates itself), then launches. No flags
  are added to Claude Code, so permission modes are untouched. Why: Claude Code is not baked into the image, so it can
  update itself. Gating on pending decision 2 is not done; see `docs/SPEC.md`.

- **`wrasse-agents.slice`** (user slice, `/usr/lib/systemd/user/`): `MemoryHigh=60%`, `ManagedOOMMemoryPressure=kill`;
  pressure limit 50% and duration 20 s in `wrasse-agents.slice.d/20-oomd.conf` because Fedora's
  `user/slice.d/10-oomd-per-slice-defaults.conf` (80%) overrides a value set in the slice file itself (verified with
  `oomctl`). `systemd-oomd.service` is enabled explicitly in `17-cleanup.sh` (Fedora's preset already enables it). Why: spec
  Phase 5, the agent should be killed before the desktop freezes. Numbers and reasoning in `docs/AGENT-SLICE.md`.

- **PATH so `~/.local/bin` wins over `/usr/bin`** (so the real Claude Code beats the stub): `/etc/profile.d/wrasse-path.sh`
  (bash/sh; prepends unless `~/.local/bin` is already ahead of `/usr/bin`) and `fish/vendor_conf.d/wrasse-path.fish`
  (`fish_add_path --move --prepend --path`). Verified in a clean environment: fish 4.6 adds nothing on its own, bash only gets it
  from `/etc/skel/.bashrc` (new users only). The stub still finds the real binary by absolute path, so this is belt and braces
  and also keeps `claude doctor`'s PATH check quiet. zsh not touched.

- **Build checks for the Claude Code integration** in `20-tests.sh`: files exist, `systemd-analyze --user verify` of the
  slice, `systemd-oomd.service` in the enabled-units list. Why: a missing stub or a disabled oomd would silently break Phase 5.

## Phase 7: installer + ISO

- **`installer/gpu-detect/` (`wrasse-gpu-detect`, Rust, std only).** Reads `/sys/bus/pci/devices` (display classes only, so NVIDIA's
  HDMI audio function is ignored) and prints `wrasse-nvidia` for a Turing or newer NVIDIA GPU, else `wrasse`. "Turing or newer" is
  NVIDIA's own supported-device table for the open kernel modules (`NVIDIA/open-gpu-kernel-modules` README, tag 615.71.09), turned
  into a sorted ID list by `installer/gen-nvidia-ids.sh` (294 device IDs); Pascal and older are absent. Override precedence:
  `--override`, `$WRASSE_GPU`, `wrasse.gpu=nvidia|default|auto` on the kernel command line, `/etc/wrasse/installer-gpu`; an invalid
  value is reported and skipped. Why: the installer's own detection (`Systeminfo.has_nvidia_gpu`) is vendor-only (any NVIDIA, Pascal
  included, which the open driver cannot drive) and has no override. 15 tests, no hardware needed.

- **Installer catalog and live-ISO variant (`installer/gen-catalog.sh`, `installer/iso/variant/wrasse/`, `installer/tests/`).**
  `gen-catalog.sh` builds the bootc-installer image catalog (`/etc/bootc-installer/images.json`) from `.github/build-matrix.json`:
  a Wrasse group with two GPU groups (`wrasse`, `wrasse-nvidia`), each listing Reimagined / Next / Stable as
  `ghcr.io/wrasse-os/<image>:<line>`; a line with `"nvidia": false` loses its NVIDIA leaf, so the pending nvidia decision stays a
  one-line change. At live boot `wrasse-installer-config.service` runs `wrasse-gpu-detect` and fills `default_image`
  (`:stable` of the detected flavor), which makes the installer open with that GPU group expanded and a leaf ticked; picking the
  other group is the override (so is `wrasse.gpu=` on the kernel command line). Why this shape: in the installer, the image step is
  where the release line is asked, and it is removed whenever live-ISO mode is on (`/etc/bootc-installer/live-iso-mode`, or a
  `local_imgref`); so the Wrasse ISO is a network install, with no flag file, no embedded payload and a recipe that keeps the `image`
  step. `configure-live.d.sh` is the hook dakota-iso's `configure-live.sh` runs last; it installs the above, deletes the flag and
  `local_imgref` recipe that script writes, and renames Dakota's launchers. `installer/tests/test-catalog.sh` covers the generator
  and renderer (jq only).
