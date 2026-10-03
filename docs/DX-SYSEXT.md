# DX sysext: built in CI, downloaded on demand

`wrasse-dx.raw` (docker, libvirt/QEMU, VS Code, perf tools, GNOME dev tools, waydroid) is **not in the image**. At 1.4 GB it would be
downloaded on every image pull and would bloat the live ISO, so (user decision, supersedes the original "bake it in" plan) CI builds it
from each finished image, publishes it as a signed OCI artifact, and `ujust dx on` downloads the one that matches the booted image.
`systemd-sysupdate` is not used anywhere.

## Flow

1. **CI** (`build.yml`, after the image is pushed, signed and attested): `build_files/dx/build-dx.sh` builds the sysext FROM the rechunked image
   (`Containerfile.dx` + `build-sysext.sh`, or mkosi), `test-sysext.sh` checks it against the image's os-release, then
   `.github/scripts/publish-dx.sh` runs `oras push` to `ghcr.io/wrasse-os/wrasse-dx` with `wrasse-dx.raw` and `wrasse-dx.extension-release`,
   signs the digest with `cosign sign --key` (same `SIGNING_SECRET` / `COSIGN_PASSWORD` as images and SBOMs) and fetches it back with skopeo
   through the policy the image ships.
2. **Tags** (all in the one repository `ghcr.io/wrasse-os/wrasse-dx`): exact `<IMAGE_ID>-<IMAGE_VERSION>` (for example
   `wrasse-stable-44.20261003`), plus moving aliases `<IMAGE_ID>-<line>` and `<IMAGE_ID>-f<fedora>`. `IMAGE_ID` and `IMAGE_VERSION` are written into
   `/usr/lib/os-release` by `build_files/base/00-image-info.sh`, so a booted image knows its own tag without network. The image id is in the tag
   because `IMAGE_VERSION` (`<line>-<fedora>.<date>[.<n>]`) is the same for `wrasse` and `wrasse-nvidia`. The manifest also carries the signed
   annotations `io.wrasse.dx.image-id` and `io.wrasse.dx.image-version`; the client refuses an artifact whose annotations do not name the booted image.
3. **`ujust dx on`** (`/usr/libexec/wrasse-dx`, via pkexec): `skopeo copy docker://ghcr.io/wrasse-os/wrasse-dx:<key> dir:...` under
   `/usr/share/wrasse/dx/policy.json`, which rejects everything except that repository signed by `/usr/lib/pki/containers/wrasse.pub`
   (`registries.d/wrasse-dx.yaml` makes skopeo read the signature attachment). cosign is not on the image (the RPM is excluded) and is not needed:
   skopeo is (bootc depends on it) and enforces the same sigstore policy as image pulls. The file is kept in
   `/var/lib/wrasse/sysexts/<IMAGE_ID>-<IMAGE_VERSION>/`.
4. **Selection**: `wrasse-dx-select.service` (vendored, enabled only while DX is on, skipped with `wrasse.safe=1`) runs before
   `systemd-sysext.service` and links only the file for the booted image into `/var/lib/extensions/wrasse-dx.raw`. No match, no link, nothing merges.
5. **After an image update**: the new image has a new `IMAGE_VERSION`, so DX is off after the reboot until `ujust dx update` fetches its match.
   `ujust dx update` also fetches the sysext of a staged (downloaded, not yet booted) image, so running it before the reboot keeps DX across it, and
   prunes cached files that are not for the booted, staged or rollback image. **Rollback** finds the older image's cached file again (if it was not pruned).
6. **`ujust dx off`** disables the units and the selector, removes the link and refreshes sysext; `ujust dx off purge` also deletes the cache.

Offline: the first `dx on` and each `dx update` need network and about 1.4 GB. Everything already merged keeps working offline; kernel, FUSE and
the rest of the image are unaffected because DX is only userspace under `/usr`.

## If CI could not publish DX

The image is pushed and signed before the DX steps run, so a failed DX build or publish never blocks or undoes an image: that cell turns red, the run
shows an error annotation and a "DX sysext UNAVAILABLE" job summary, and `ujust dx on` on that image build fails with "could not download" until the cell
is re-run (re-running rebuilds the image too, with a new `IMAGE_VERSION` point release when the date repeats). Pull requests build and check the sysext
but never publish.

## One-time setup

The package `wrasse-dx` is created private by the first push. Make it public like the images (see `docs/CI-SECRETS.md`), otherwise users get an
authorization error. The artifacts are never deleted automatically; old tags accumulate until someone prunes them.

Two builders exist; the package list for both is `build_files/dx/packages.txt`, and the overlay files are `build_files/dx/files/`.

| `DX_BUILDER` | What | Status |
|---|---|---|
| `script` (default) | `build_files/dx/build-sysext.sh` run by `Containerfile.dx` (`build-dx.sh`): `dnf5 download --resolve`, `rpm2cpio`, `mkfs.erofs -zlz4 --file-contexts` | Works in CI. Stable default cell: 1,414,643,712 bytes (about 1.4 GB). |
| `mkosi` | `build_files/dx/build-sysext-mkosi.sh` + `build_files/dx/mkosi/`: `Format=sysext`, `Overlay=yes`, `BaseTrees` = the image rootfs | Written, never run. Needs a CI run. |

## Switching

- CI: `gh workflow run build.yml -f dx_builder=mkosi -f only_line=stable` (builds both stable cells; `only_line` is optional). Scheduled,
  push and PR runs always use `script`; only `workflow_dispatch` can select `mkosi`.
- Local (not recommended; the build is heavy): build the image, then `sudo DX_BUILDER=mkosi build_files/dx/build-dx.sh localhost/<image>:<tag> out/`
  (default builder: omit `DX_BUILDER`). Anything other than `script` or `mkosi` makes `build-dx.sh` fail.

## Why mkosi runs in a CI step and not inside `podman build`

mkosi builds a sysext by mounting the base tree as an overlayfs lower layer and running the package manager in its own sandbox
(user, mount and pid namespaces, loop devices and `systemd-repart` for the disk image). Inside `podman build` that needs privileges the
build does not have. On the runner it runs as root, against the finished image's rootfs (`podman image mount`). Both builders now run in
the same place, `build-dx.sh`, after the image exists; neither changes the image.

## How the mkosi build works (mkosi v26, verified against its docs and source)

- `Format=sysext` keeps only `/usr` and `/opt`; `Overlay=yes` with `--base-tree` makes the output only what is not in the base tree.
- `ID` and `VERSION_ID` of `extension-release.wrasse-dx` are copied by mkosi from the base tree's os-release, which is the match
  systemd-sysext checks. mkosi also writes `SYSEXT_SCOPE=initrd system portable`; `mkosi.extra/` adds `EXTENSION_RELOAD_MANAGER=1`.
  The `.raw` carries the file; `build-sysext-mkosi.sh` copies it out as `wrasse-dx.extension-release` for `test-sysext.sh`.
- `Output=wrasse-dx` names the file and the extension-release suffix. `CompressOutput=no` is required: mkosi compresses by default
  and systemd-sysext cannot attach a compressed image.
- The repart definition for sysext is erofs with a dm-verity partition, inside a GPT disk image (not a bare erofs file like the script's).
  `test-sysext.sh` accepts either (the artifact is the file as built; the runtime only needs systemd-sysext to attach it). erofs compression is whatever `systemd-repart` picks (`Minimize=best`), not lz4.
- `Release` is passed as the image's `VERSION_ID`. The VS Code repo is `mkosi.sandbox/etc/yum.repos.d/vscode.repo`. The package list is
  generated into `mkosi.conf.d/10-packages.conf` from `packages.txt` at build time.
- mkosi runs from a Fedora tools tree (`ToolsTree=default`, `ToolsTreeDistribution=fedora`), so the Ubuntu runner only needs Python and
  systemd-container. mkosi is pinned by commit (tag `v26`, the version `dnf5 repoquery mkosi` shows on Fedora 44). Tag `v27.1` exists too.

## Differences to check

- The script moves `/etc` to `/usr/etc` and drops `/var`, `/run`, `/boot`; mkosi's sysext drops everything outside `/usr` and `/opt`, so
  package defaults in `/etc` are not carried over. Check whether any DX package needs them (docker, libvirt, waydroid).
- `ARCHITECTURE=` is not in mkosi's extension-release.
- SELinux: the script labels with `mkfs.erofs --file-contexts` from the image's policy. mkosi uses `SELinuxRelabel=auto` (setfiles when a
  policy is in the tree). Whether labels survive into the erofs partition is not verified.
- F45 (pre-release): mkosi pulls from the Fedora 45 repos, while the image was built from the Silverblue compose. A newer package in the repo than
  in the image can pull library updates into the sysext.

## What to compare after a CI run with `dx_builder=mkosi`

Baseline for `script` on stable default: 1,414,643,712 bytes.

1. Size: the `Build DX sysext` job summary prints `wrasse-dx.raw` size and the builder; also the uncompressed size from the manifest (`out/wrasse-dx.manifest.json`).
2. Build time: the "builder, N s" line of the `Build DX sysext` summary, mkosi against the `script` cell (tools tree download is the main cost).
3. Package set: `jq -r '.packages[].name'` on the manifest versus the files list from the script's `rpm2cpio` run; same payload under `/usr`?
4. SELinux labels: `docs/DX-SELINUX-CHECKLIST.md` on hardware; quick check, `systemd-dissect --mount wrasse-dx.raw /mnt && ls -Z /mnt/usr/bin/dockerd`
   should show `container_runtime_exec_t`-style types, not `unlabeled_t`.
5. `systemd-sysext` status: with the sysext linked, `systemd-sysext status` lists `wrasse-dx` merged (the check `ujust dx on` already does), then
   `systemd-sysext unmerge`, `refresh`; `ujust dx status`. Also `systemd-sysext list`: ID and VERSION_ID must match the host.
6. Publishing and `ujust dx on` work with the mkosi file exactly as with the script's (the artifact carries no builder-specific metadata).
