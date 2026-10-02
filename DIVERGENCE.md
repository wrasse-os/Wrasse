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
