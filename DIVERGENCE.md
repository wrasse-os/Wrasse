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

- **Removed Cockpit** (all `cockpit-*` packages) from the DX build. Only edit made to DX build logic.

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
