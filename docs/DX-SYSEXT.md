# DX sysext builders

`wrasse-dx.raw` (docker, libvirt/QEMU, VS Code, perf tools, GNOME dev tools, waydroid) is built from the finished image and baked
into `/usr/share/wrasse/sysexts/`. `ujust dx on` links it into `/etc/extensions` and merges it. Two builders exist; the package list
for both is `build_files/dx/packages.txt`, and the overlay files are `build_files/dx/files/`.

| `DX_BUILDER` | What | Status |
|---|---|---|
| `script` (default) | `build_files/dx/build-sysext.sh` in Containerfile stage `dx-script`: `dnf5 download --resolve`, `rpm2cpio`, `mkfs.erofs -zlz4 --file-contexts` | Works in CI. Stable default cell: 1,414,643,712 bytes (about 1.4 GB). |
| `mkosi` | `build_files/dx/build-sysext-mkosi.sh` + `build_files/dx/mkosi/`: `Format=sysext`, `Overlay=yes`, `BaseTrees` = the image rootfs | Written, never run. Needs a CI run. |

## Switching

- CI: `gh workflow run build.yml -f dx_builder=mkosi -f only_line=stable` (builds both stable cells; `only_line` is optional). Scheduled,
  push and PR runs always use `script`; only `workflow_dispatch` can select `mkosi`.
- Local (not recommended; the build is heavy): `DX_BUILDER=mkosi sudo -E just build-ghcr ...` builds the image without a sysext, then
  `sudo build_files/dx/build-sysext-mkosi.sh localhost/<image>:<tag> out/` and
  `sudo podman build --build-arg BASE=localhost/<image>:<tag> -f build_files/dx/Containerfile.mkosi-layer --tag localhost/<image>:<tag> out/`.
- Anything other than `script` or `mkosi` makes `just build` fail.

## Why a CI step and not a Containerfile stage

mkosi builds a sysext by mounting the base tree as an overlayfs lower layer and running the package manager in its own sandbox
(user, mount and pid namespaces, loop devices and `systemd-repart` for the disk image). Inside `podman build` that needs privileges the
build does not have, so it cannot run in a Containerfile stage. On the runner it runs as root, against the finished image's rootfs
(`podman image mount`). With `DX_BUILDER=mkosi` the Containerfile stage `dx-mkosi` is empty, the CI step runs mkosi, and
`build_files/dx/Containerfile.mkosi-layer` adds the result as one last layer and retags the image, so rechunk, SBOM and push see the same
tag as before. Cells stay independent and fail closed: a failing mkosi step ends that cell before any push.

## How the mkosi build works (mkosi v26, verified against its docs and source)

- `Format=sysext` keeps only `/usr` and `/opt`; `Overlay=yes` with `--base-tree` makes the output only what is not in the base tree.
- `ID` and `VERSION_ID` of `extension-release.wrasse-dx` are copied by mkosi from the base tree's os-release, which is the match
  systemd-sysext checks. mkosi also writes `SYSEXT_SCOPE=initrd system portable`; `mkosi.extra/` adds `EXTENSION_RELOAD_MANAGER=1`.
  The `.raw` carries the file; `build-sysext-mkosi.sh` copies it out as `wrasse-dx.extension-release` for `test-sysext.sh`.
- `Output=wrasse-dx` names the file and the extension-release suffix. `CompressOutput=no` is required: mkosi compresses by default
  and systemd-sysext cannot attach a compressed image.
- The repart definition for sysext is erofs with a dm-verity partition, inside a GPT disk image (not a bare erofs file like the script's).
  `test-sysext.sh` accepts either. erofs compression is whatever `systemd-repart` picks (`Minimize=best`), not lz4.
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

1. Size: the job summary prints `wrasse-dx.raw` size and the builder; also the uncompressed size from the manifest (`out/wrasse-dx.manifest.json`).
2. Build time: summary line "mkosi + layer" against the `script` cell's stage time in the build log (tools tree download is the main cost).
3. Package set: `jq -r '.packages[].name'` on the manifest versus the files list from the script's `rpm2cpio` run; same payload under `/usr`?
4. SELinux labels: `docs/DX-SELINUX-CHECKLIST.md` on hardware; quick check, `systemd-dissect --mount wrasse-dx.raw /mnt && ls -Z /mnt/usr/bin/dockerd`
   should show `container_runtime_exec_t`-style types, not `unlabeled_t`.
5. `systemd-sysext` status: with the sysext linked, `systemd-sysext status` lists `wrasse-dx` merged (the check `ujust dx on` already does), then
   `systemd-sysext unmerge`, `refresh`; `ujust dx status`. Also `systemd-sysext list`: ID and VERSION_ID must match the host.
6. `bootc container lint` passes in the layer, and `ostree`/rechunk of the retagged image still works (check the layer count).
