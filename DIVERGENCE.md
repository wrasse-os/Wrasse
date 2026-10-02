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
