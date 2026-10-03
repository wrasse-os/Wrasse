# Composefs-native Wrasse (Phase 9): feasibility and migration plan

Written 2026-10-03. Research only: nothing in this document is implemented except the two installer/package commits listed under "Stage 0".
Status and tracking: `docs/SPEC.md`, Phase 9. Change log: `DIVERGENCE.md`.

Direction (maintainer decision, 2026-10-03): Wrasse becomes **composefs-native**. bootc's composefs backend replaces ostree: no
`ostree-prepare-root`, no ostree repo or deployments, no `rpm-ostree`.

Confidence tags: **[V]** verified against source or docs I read today, **[I]** inference from verified facts, **[U]** unverified, needs the experiment.

## 0. Verdict

Feasible, with a working precedent, but **experimental upstream and not shippable to the stable line yet**. Be blunt about three things:

1. **"No ostree at all" is not literally achievable.** The `bootc` binary itself links `libostree-1.so.1` and `libcomposefs.so.1` (`ldd /usr/bin/bootc` on this
   Fedora 44 host, bootc 1.16.7) **[V]**. What goes away is the ostree *repository, deployments, `ostree-prepare-root`, `rpm-ostree`, `ostree-finalize-staged`*;
   the library stays as a dependency of bootc.
2. **There is no in-place migration from ostree to composefs.** The composefs doc lists "In place transitions: first factory reset from ostree to composefs, next copying
   /etc and /var" as future work **[V]**. `bootc install reset` only operates on ostree stateroots **[V]**. Every existing Wrasse/Bluefin install must be reinstalled.
3. **Secure Boot is the hard part, not the backend.** Fedora 44 ships only `systemd-boot-unsigned` (checked with `dnf repoquery` today, 259.x); a Fedora-signed
   systemd-boot and Fedora-signed UKIs do not exist (travier/fedora-atomic-desktops-sealed issues #5, #6, both open) **[V]**. Wrasse has to sign
   systemd-boot and the UKIs with its own key and every user must enroll that key as a MOK, on top of the ublue akmods key that NVIDIA needs.

A close precedent exists: `travier/fedora-atomic-desktops-sealed` builds sealed Fedora Silverblue/Kinoite (UKI + systemd-boot + composefs + fs-verity) **from the
official Fedora ostree Silverblue image**, which is exactly Wrasse's base. It is explicitly "work in progress, unofficial development images for testing" **[V]**.

## 1. What "composefs-native" means in bootc today

Sources: `docs/src/experimental-composefs.md` and `bootloaders.md` at tag `v1.16.13` (read from a clone), `bootc.dev/bootc/experimental-composefs.html`,
the bootc source (`crates/lib/src/{install.rs,ukify.rs,bootc_composefs/*,install/baseline.rs}`), and `--help` of the local bootc 1.16.7.

| Question | Answer | Conf. |
|---|---|---|
| Status | **Experimental**: the doc page says "Experimental features are subject to change or removal" and "on-disk formats are subject to change". Not stable in 1.16.x. | V |
| Version in Fedora | bootc 1.16.13 is stable in F44 and F46 (Bodhi, today). The composefs doc names bootc 1.14.1 as the minimum for the Fedora sealed images. | V |
| Backend selection | `bootc install ... --composefs-backend` (explicit, "not as heavily tested"), **or** automatic when the image has a UKI, **or** automatic when it ships `/usr/lib/composefs/setup-root-conf.toml` (may be empty) and no ostree `prepare-root.conf`. An image that ships both is installed with ostree. | V |
| Install flags (local `bootc install to-filesystem --help`, 1.16.7) | `--composefs-backend`, `--bootloader grub\|grub-cc\|systemd\|none`, `--allow-missing-verity`, `--uki-addon <name>` (repeatable). `--bootloader none` is rejected with composefs. | V |
| Bootloader | UKI + **systemd-boot** is the supported sealed configuration (image must NOT contain `bootupd`). Traditional `vmlinuz`/`initramfs.img` composefs installs (never sealed) may use bootupd/GRUB or systemd-boot. If `bootupd` is absent from the image, systemd-boot is the default. systemd-boot is composefs-only. | V |
| Boot entries | bootc writes standard BLS entries for both UKI and vmlinuz installs (Type 1 for kernel+initrd; UKI is a Type 2 style file under `ESP/EFI/Linux/bootc/`). Code also has GRUB+UKI paths (`user.cfg`), but docs only bless systemd-boot for sealed builds. | V (docs), I (details) |
| ESP | A single ESP. `install to-disk` creates **1024 MiB** for composefs (`CFS_EFIPN_SIZE_MB`) versus 512 MiB for ostree, because UKIs and addons live there. travier's disk configs use 2 GiB. | V |
| Root filesystem | fs-verity needed unless `--allow-missing-verity`. bootc treats **ext4 and btrfs** as verity-capable and **xfs as not** (`Filesystem::supports_fsverity`). | V |
| Kernel | Needs EROFS, overlayfs and fs-verity. The bootc dracut module installs `erofs overlay`. Stock Fedora kernels work in travier's images. The ublue akmods kernels are Fedora/CoreOS-stable kernel RPMs; confirm `CONFIG_FS_VERITY`, `CONFIG_EROFS_FS` on the pinned kernel in the VM. | V / U |
| Initramfs | bootc's dracut module `bootc` (`bootc-root-setup.service`, runs `/usr/lib/bootc/initramfs-setup setup-root`, only when `composefs` is on the cmdline). Wrasse already ships `60-bootc-composefs.conf` (`add_dracutmodules+=" bootc "`). Fedora ships modules `50ostree` and `51bootc` side by side. Rebuild the initramfs whenever bootc changes ("an old initramfs with a newer bootc is not supported"). | V |
| Sealed vs unsealed | **Sealed** = fs-verity enforced + root digest embedded in a UKI that Secure Boot authenticates. A BLS entry or unsigned UKI still checks fs-verity at mount but nothing authenticates the digest. Sealed UKI works with Secure Boot off (fs-verity still enforced), but any local root code can replace the UKI. | V |
| Digest kargs | `composefs.digest=v1-sha512-12:<hex>` (V1 EROFS) followed by bare `composefs=<hex>` (V2 fallback). Releases through 1.16.13 write a V1 digest in the bare form, releases after 1.16.13 write V2 there: pin one bootc version per image and regenerate initramfs before the UKI. | V |
| Building the UKI | `bootc container split-kernel-and-rootfs` then `bootc container ukify --rootfs R --kernel-dir /kernel/<kver> [--allow-missing-verity] [--erofs-version v1\|v2] -- <ukify args>`; ukify args (signing) go after `--`. It reads `/usr/lib/bootc/kargs.d` and bakes it into the cmdline. Both subcommands exist in the local 1.16.7. `bootc container compute-composefs-digest` is the hidden lower-level primitive. | V |
| `kargs.d` | Honored **at UKI build time only** (baked into the signed cmdline). `bootc install --karg` is rejected for UKI installs ("Cannot use externally specified kernel arguments with UKI"). Runtime `bootc`/`rpm-ostree kargs` edits cannot apply to a sealed UKI. | V |
| UKI addons | `.addon.efi` files in `ESP/loader/addons/` (global) or `<uki>.efi.extra.d/` (per UKI), signed and verified by Secure Boot, appended to the cmdline. bootc installs them only at `install --uki-addon`, **not on upgrade** (source TODO); managing them is an open request. | V |
| Storage | `/composefs` (objects keyed by SHA-512 fs-verity digest, images, streams), `/state/deploy/<id>/{etc,var,*.origin}`. No `/ostree/repo`; a stub `/ostree` holds one compat symlink. | V |
| `/etc` | Per-deployment writable copy, bind-mounted; `bootc` merges on staging (`get_etc_diff`, `bootc-finalize-staged.service`). `setup-root-conf.toml` can set `etc.mount` to `none`, `bind` (default), `overlay`, `transient`. | V |
| `/var` | One shared `/state/os/default/var` bind-mounted into each deployment (as with ostree). `/opt` as symlink to `/var/opt` (Containerfile already does this) is compatible. | V / I |
| `bootc status` / `upgrade` / `switch` / `rollback` | Implemented for composefs (`bootc_composefs/{status,update,switch,rollback}.rs`). `status --format json` has a `composefs` object per boot entry (with `verity`) next to the usual `image` object. | V |
| Soft reboot | Present but **differs**: "both modes fail if systemd lacks soft-reboot support; if the target is not capable, `auto` leaves it staged without rebooting" (bootc-upgrades). Needs a runtime test. | V |
| Boot counting / auto-rollback | **None for composefs**: "the composefs backend does not configure boot entry counting, this is likely to be added in the future" and there is no `-boot-complete` service. Failed boots do not roll back by themselves. | V |
| Boot failure detection | `journalctl -u bootc-finalize-staged.service -b -1`; if `bootc-root-setup.service` fails the system will not boot (emergency or hang). | V |
| Known issues listed upstream | Upgrades tested only from bootc 1.16.0 UKI installs, and that test "doesn't yet run in CI"; recovery from corrupt state and GC with V1+V2 entries untested; how container signature enforcement carries from install into the installed system "is not settled yet". | V |
| Marker file | Native composefs boots do **not** write `/run/ostree-booted` (bootc `generator.rs` comments). Anything gated on that file silently does nothing. | V |

## 2. Precedents, and what Dakota is not

- **travier/fedora-atomic-desktops-sealed** (pushed 2026-08-19 **[V]**): `Containerfile`, `scripts/prepare-rootfs.sh`, `uki.sh`, `repart.d/`. Starts `FROM` the official
  Fedora Atomic Desktop image and, in `prepare-rootfs.sh`: `dnf remove rpm-ostree rpm-ostree-libs gnome-software-rpm-ostree`; `rpm -e bootupd` and `rm -rf /usr/lib/bootupd /usr/lib/ostree-boot`;
  removes all `grub2-*` packages; installs `systemd-boot-unsigned` plus a signed build from a non-production key (Rawhide koji); writes `/usr/lib/bootc/install/{80-rootfs,90-install}.toml`
  (btrfs, `bootloader = "systemd"`) and `/usr/lib/dracut/dracut.conf.d/20-bootc-base.conf` (`DRACUT_NO_XATTR=1`, `add_dracutmodules+=" bootc "`). The kernel and initramfs are removed from the
  rootfs, the rootfs is rechunked with **chunkah** (`--prune /ostree --prune /sysroot/ostree`) so that the composefs digest is stable, the initramfs is rebuilt in a separate stage, and `uki.sh` runs
  `bootc container compute-composefs-digest` then `ukify build ... --signtool sbsign`. They use the manual ukify path and note the `bootc container ukify` wrapper was not yet usable for an externally built
  initramfs; the current doc describes the `split-kernel-and-rootfs` + `--kernel-dir` flow, which exists in bootc 1.16.7 here, so retest it. **[V]**
- Their open issues are Wrasse's open issues: shim does not trust their sd-boot (#5) or UKIs (#6), no Anaconda (#20), large UKI with long boot (#23), updates and GC of UKI/repo untested (#4),
  "bootc update results in composefs digest error" (#41, custom Kinoite build), no GUI update manager support for bootc (#11). **[V]**
- Disk images: image-builder or bcvk produce them; "blueprint customizations are generally disabled for sealed container images" **[V]**.
- **Dakota (projectbluefin/dakota) is not a template for Wrasse's image.** It is "Bluefin built on GNOME OS, assembled entirely from source" with BuildStream (`elements/`, `project.conf`),
  and it builds bootc from source (`elements/gnomeos-deps/bootc.bst`, currently pinned to v1.16.14) **[V]**. It proves the *installer* path (below) and an ostree-free image,
  but it has no Fedora packaging, dnf, akmods or rpm-ostree to remove. Wrasse's route is Fedora-derived (travier), not Dakota's.

## 3. Wrasse today (verified in this repo, 2026-10-03)

- Base: `quay.io/fedora-ostree-desktops/silverblue:<fedora>` (Containerfile `BASE_IMAGE`), cosign-verified, built by digest. No `/usr/lib/ostree` dir ships from `system_files`; ostree files come from the base.
- `build_files/base/19-initramfs.sh`: `dracut --no-hostonly --reproducible --add ostree -f /lib/modules/$kver/initramfs.img`, plus `60-bootc-composefs.conf` adds `bootc`. **Both modules are in the initramfs today.**
- `03-install-kernel-akmods.sh`: erases the Fedora kernel, installs the akmods kernel RPMs with the `05-rpmostree.install` and `50-dracut.install` kernel-install hooks stubbed, writes `kargs.d/00-nvidia.toml`.
- **Stage 0 already landed on `main` while this research ran**: `01955a3f add: systemd-boot-unsigned` and `98eda7d3 installer: install new systems with composefs and systemd-boot` (variant files `composefs=true`, `bootloader=systemd`,
  recipe `composeFsBackend`). Consequence: **new ISO installs already use `bootc install --composefs-backend --bootloader systemd` with a non-UKI, ostree-built image.** That is the "unsealed BLS composefs" mode
  (fs-verity enforced where the filesystem supports it, nothing authenticated, no Secure Boot chain). It is allowed by bootc but is the "not as heavily tested" path, and `DIVERGENCE.md` already says it is unproven.
  Until a VM install passes, treat every new ISO install as experimental.

## 4. File-by-file: what breaks or changes

| Area / file | Today | Needed for composefs-native | Conf. |
|---|---|---|---|
| `Containerfile` base | `quay.io/fedora-ostree-desktops/silverblue` | **Can be kept as the input.** travier does exactly this and removes the ostree pieces in-image. `bootc container lint` already runs; add `--fatal-warnings` once clean. Final stages change: split kernel, UKI stage (separate tools image with `systemd-ukify`, `sbsigntools`, `bootc`), signing secrets via `--mount=type=secret` (`secureboot_key`, `secureboot_crt`). `/opt -> /var/opt` stays. | V |
| `ostree` dracut module (`19-initramfs.sh`) | `--add ostree` | Drop `--add ostree`, add `--add bootc` (or rely on `60-bootc-composefs.conf`). `bootc-root-setup.service` has `After=ostree-prepare-root.service` (soft, harmless when absent). Initramfs is produced for `--kver`, then **removed from `/usr/lib/modules/<kver>/`** (split) and embedded in the UKI. `--no-hostonly` makes it big: UKI size is a boot-time issue (travier #23); consider per-GPU initramfs like travier. | V / I |
| Kernel install hooks (`03-*.sh`) | stubs `05-rpmostree.install`, `50-dracut.install` | Keep the stubs (needed in a container build either way). With rpm-ostree removed the `05-rpmostree.install` file disappears (script already guards on existence). Add a check that exactly one dir exists in `/usr/lib/modules` (bootc invariant). | I |
| `rpm-ostree` references | `build_files/shared/build.sh` does `rpm-ostree install dnf5 dnf5-plugins` first; `04-packages.sh` installs `gnome-software-rpm-ostree`; `17-cleanup.sh` enables `rpm-ostree-countme.service`, disables `rpm-ostreed-automatic.timer`; `20-tests.sh` lists both; `clean-stage.sh` keeps `/var/cache/rpm-ostree`; `etc/rpm-ostreed.conf`; `projectbluefin-countme.service`; `default.just` (`rpm-ostree cleanup -bm`); `update.just` (rpm-ostree layered check and `rpm-ostreed-automatic.timer`); `Containerfile` cache mount `/var/cache/rpm-ostree`; `AGENTS.md`/SKILL.md text. | Remove `rpm-ostree` (the dnf5 bootstrap line must use `dnf` from the base, check `dnf5` presence first), remove its units/timers/conf/tests, delete the layered-package checks in `update.just`/`default.just`. Keep `dnf5` as the build tool. | V (grep), I |
| `/usr/lib/ostree`, `ostree-boot`, `bootupd` | from base | `rm -rf /usr/lib/ostree-boot /usr/lib/bootupd`, `rpm -e bootupd`; ship `/usr/lib/composefs/setup-root-conf.toml` (optional with UKI). Remove GRUB packages as travier does (`01-fedora-base.sh` currently installs **`grub2-tools-extra`**, remove it). | V |
| `ostree.linux` label | set by Justfile/changelog, read by `resolve`/verification | Not needed by the composefs backend. Keep as plain metadata (CI, `changelogs.py` and base verification read it). | I |
| `ostree-image-signed:docker://...` (`00-image-info.sh` IMAGE_REF) | ostree-style transport prefix | Consumers: `ublue-image-info.sh`, `system.just` ujust (strips the prefix). Check the composefs `bootc status` image string format; keep prefix only if a consumer needs it. | U |
| `rechunker-group-fix.service` | `ConditionPathExists=/run/ostree-booted` | **Never runs on a composefs-native boot** (no marker). Its job is `/etc/gshadow` for the legacy rechunker; with chunkah and bootc's `bootc-sysusers-shadow-sync.service` it is probably obsolete, but test before deleting. | V |
| `projectbluefin-countme.service`, `dconf-update.service`, `ublue-system-setup.service`, `10-framework.sh`, `bonedigger-report`, `chairlift` config | mention `ostree`/`rpm-ostree` | Audit each `ConditionPathExists=/run/ostree-booted`, `rpm-ostree` call or `/sysroot/ostree` path. Fedora units gated on the marker: `fedora-atomic-desktop-mandb-update`, `fedora-atomic-desktop-appstream-cache-refresh`, `dnf-makecache.*` (disabled on ostree). On composefs-native `dnf-makecache.timer` would **run**; mask it. | V (host unit scan), I |
| Rechunk (`Justfile` `rechunk` recipe: legacy-rechunk image, `cache_ostree` volume, `REPO=/var/ostree/repo`) | ostree tree + `rpm-ostree compose` style | Replace with `quay.io/coreos/chunkah` (`--prune /ostree --prune /sysroot/ostree`, many layers), run **before** computing the digest, and never mutate the rootfs afterwards. Also resolves ublue's legacy-rechunk dependency. | V (travier), U (fit) |
| `ujust rollback`, `system-status`, `update-soft`, `wrasse status/rollback` | `bootc status`, `bootc rollback`, `bootc upgrade --soft-reboot=auto --apply`; jq paths `.status.{booted,staged,rollback}.image.{image.image,version,imageDigest}` and `.status.rollbackQueued` | Same verbs exist for composefs. The image object stays under `.image`, so the CLI mapping is expected to work **[I]**; composefs entries add `.composefs.verity`. Verify `rollbackQueued` and a null `rollback` exist, and update-soft's fallback behaviour (leaves staged, no reboot; recipe text says "both end with a restart"). Add UKI-aware text: rollback restores `/etc` of the older deployment; **no automatic rollback on failed boot** (no counting). | I / U |
| `bootc-update-stage`, polkit, sudoers `001-bootc` | plain `bootc upgrade` | Comment mentions `ostree-finalize-staged`; composefs uses `bootc-finalize-staged.service`. Text-only change. | V |
| uupd | calls `bootc upgrade --quiet --progress-fd 3`; reads `bootc status --format=json` (`booted/staged .image.timestamp`); `uupd wait` polls `/sysroot/ostree/lock` | Works on the same JSON fields if the composefs status keeps `image.timestamp` **[I]**. `wait` returns at once (lock file missing), harmless. uupd falls back to `rpm-ostree` only if `bootc` is missing. Test one real update. | I (read uupd source) |
| `system_files` sysext flow (`wrasse-dx*`, `/var/lib/extensions`) | links file into `/var/lib/extensions`, `systemd-sysext merge` | `/var` and `/usr` overlay logic are unchanged under composefs. Same untested overlay-over-composefs question as today. **New problem for sealed systems:** an unsigned sysext in user-writable `/var` lets root change `/usr` content without touching the signed root digest. Decide whether sealed Wrasse requires a signed (dm-verity + signature) sysext. | I |
| Safe mode (`wrasse.safe=1`) | edit the kernel line at the GRUB menu | **Does not work with a sealed UKI.** See section 5.3. | V |
| Brew, Flatpak, distrobox paths (`/home/linuxbrew`, `/var/lib/flatpak`) | on `/var` | Unaffected. | I |
| Signature policy (`policy.json`, `registries.d`, `wrasse.pub`, `ujust toggle-testing`, `changelogs.py`) | `bootc switch --enforce-container-sigpolicy ghcr.io/wrasse-os/...` | bootc says carry-over of signature enforcement from install into the system is **not settled** for composefs. Keep the policy files, re-test `switch --enforce-container-sigpolicy` and a pull of an unsigned tag (must fail) on a composefs install. | V / U |
| `ujust enroll-secure-boot-key`, `docs/INSTALL.md` | enrolls the ublue akmods key only | Must enroll **two** certs (see 5.1) or be replaced by one Wrasse flow; docs rewrite. | I |
| CI (`build.yml`, `Justfile build`) | one cell per line x flavor, rechunk, cosign sign image, DX publish | New steps per cell: split kernel, UKI build and sign, publish. Needs the Secure Boot signing key as a new secret (user action: see `docs/CI-SECRETS.md`, do not create it myself). Fail the cell if `bootc container lint` or UKI build fails. The two image tags in the same cell must reference the UKI of that exact digest. | I |
| Installer / ISO | Stage 0 already composefs + systemd-boot | See 5.4. | V |
| VM testing (virt-manager) | ostree/GRUB qcow2 | UEFI firmware, no Secure Boot first; 2 GiB ESP or the installer's 1 GiB; see section 8. | V |

## 5. Deep dives

### 5.1 NVIDIA, akmods and Secure Boot

Facts: the NVIDIA open modules and v4l2loopback (and ZFS on the `coreos` flavor) are prebuilt by `ublue-os/akmods` and signed with the ublue key; the kernel RPMs are Fedora-built, i.e. signed by Fedora's key for the stock
firmware path **[V]** (docs: `docs/INSTALL.md`, `03-install-kernel-akmods.sh`). With a UKI, **the kernel inside the UKI is no longer what shim verifies**: shim verifies the UKI PE binary (our signature),
and the kernel's own Fedora signature is irrelevant **[I]**. Module signing is a separate layer: the kernel checks module signatures against its keyrings (built-in, `.platform`, and the machine/MOK keyring) **[I, same as today]**.

Chain Wrasse has to run on a Secure Boot machine:

1. Firmware db (Microsoft) trusts Fedora's shim (`shim-x64` 16.1 is in the F44 repos).
2. Shim loads `systemd-boot` (**we sign it** with the Wrasse key, because Fedora ships only `systemd-boot-unsigned`; Fedora issue releng#10765 is the signing request) and then the UKI (**our signature**). Both require the Wrasse cert in the **MOK** (or db).
3. NVIDIA modules need the **ublue** cert in MOK as today.

So users enroll two certificates, unless we eliminate one. Options, cheapest first:
- (a) Two MOK imports in one `mokutil` step. Works; documentation burden; two secrets to protect. **[I]**
- (b) Re-sign the ublue-built modules with the Wrasse key during the image build. Fewer enrollments, but it changes provenance, and whether a second signature replaces the first cleanly is **[U]**. Not recommended initially.
- (c) Build our own akmods. Out of scope; it is the real ublue plumbing the project rules say not to rename.
Recommended: (a) for the first signed release. Not verified: SBAT handling of an own-signed `systemd-boot-unsigned` build and of ukify's default `.sbat` under Fedora's shim **[U]**; test on real hardware.

### 5.2 Sealed vs unsealed for Wrasse

- Sealed (UKI, signed, verity enforced) is the point of composefs-native for Secure Boot users, but it **freezes the kernel command line** and makes `kargs.d` a build-time-only input; `rpm-ostree kargs`, `bootc install --karg`, hand-edited kernel lines and image-builder customizations stop working **[V]**.
- Unsealed composefs (what Stage 0 gives): fs-verity at mount, BLS entries, editable cmdline, no Secure Boot trust. Good enough to prove the backend; not what the maintainer's goal is long-term.
- Wrasse can build **both from one rootfs**: ship the UKI for Secure Boot machines and keep working BLS entries where Secure Boot is off. bootc selects the mode from whether a UKI is present, so this is two image lines, not one image **[I]**. Treat "sealed + Secure Boot" as the final product and the BLS mode only as a bridge.

### 5.3 Safe mode (`wrasse.safe=1`) cannot work as written

systemd-stub, verbatim: "If UEFI SecureBoot is enabled and the `.cmdline` section is present in the executed image, any attempts to override the kernel command line by passing one as invocation parameters
to the EFI binary are ignored." bootc's UKI always has a `.cmdline` section (it carries the composefs digest) **[V]**. So with Secure Boot on, the GRUB-style "press e, append `wrasse.safe=1`" idea is dead.
(GRUB is also gone from composefs/UKI installs.) With Secure Boot off the stub does accept an edited cmdline, so the VM works for testing.

Alternatives, ranked by how well they fit:

1. **Multi-profile UKI**: one UKI with a base profile plus profile `@0` (normal) and `@1` (`wrasse.safe=1`), appearing as a separate systemd-boot menu entry; the profile is selected by the UKI's own first cmdline word `@N`.
   `ukify` has `--profile=PATH` and `--join-profile=PATH` for this (systemd main man page). Open: does systemd-boot 259 list profiles as menu entries, does bootc accept and garbage-collect a multi-profile file, and does `bootc container ukify` pass these options through after `--` **[U]**. Best candidate; needs experiment E3.
2. **Second, separately signed UKI** (safe variant) installed beside the main one in the ESP. bootc owns that directory and may delete unknown files **[U]**.
3. **Signed global UKI addon** (`ESP/loader/addons/*.addon.efi`) carrying `wrasse.safe=1`: always applies, cannot be chosen at boot, and bootc does not manage it. Only useful as a persistent switch. **[V]**
4. **Drop the kernel argument**: make safe mode a runtime flag. `ujust dx off` is already the persistent answer; for an unbootable system the only boot-time lever left is the previous deployment entry. Caveat: rollback does **not** disable DX because DX is selected per image and a cached sysext may exist for the old image too. A pre-boot flag (for example an ESP file read in the initramfs) would need an initramfs hook; not recommended.
5. Boot the sysext-free rollback entry plus a rescue image: no new code, poor UX.

### 5.4 Installer: composefs-native installs are supported, with conditions

- `projectbluefin/dakota-iso` (pinned `9c123eea`, read in `/tmp/dk`) has a first-class composefs path: variant file `composefs` (`true`/`false`) and `bootloader` (`systemd`/`grub`). `live/src/configure-live.sh` writes `recipe.json` with `composeFsBackend`, and for composefs sets `image` and `local_imgref` to `containers-storage:<ref>`; for ostree variants it leaves `image` empty (bootcDirect). `grub` is normalised to `grub2` because fisherman's recipe validator needs `grub2` or `systemd`. `scripts/plain-install-qemu.sh` ("fisherman plain (no-encryption) composefs install") and `scripts/iso-sd-boot.sh` exercise it, and Dakota's own ISO is composefs + systemd-boot. **[V]**
- Fisherman (`tuna-os/fisherman`, the engine behind `tuna-os/bootc-installer`, read on main today; **the exact version inside the pinned installer bundle was not checked [U]**), in `internal/install/bootc.go`:
  `bootc install to-filesystem --composefs-backend --source-imgref oci:<exported path> [--bootloader systemd] [--target-imgref ...] --skip-finalize`; composefs **always** exports the image to an OCI layout under `/var/tmp` first ("Composefs always requires OCI layout for raw blobs"); `internal/install/systemdboot.go` copies `systemd-bootx64.efi` (preferring `.signed`) into the ESP when bootc's `--graceful` run did not. **[V]**
- **Disk-backed scratch is required**: the OCI export and the pull both go through `/var/tmp`. Dakota's QEMU script mounts a separate disk over `/var/tmp` ("/var/tmp is now disk-backed on /dev/vdb"); per the maintainer's notes fisherman bind-mounts `/var/fisherman-tmp` over `/var/tmp` (not independently re-read by me). Wrasse images are 4.4-5.0 GB compressed with 71 layers, so
  the live session needs several tens of GB of real disk, not a RAM-backed tmpfs. **[V for the mechanism, I for sizing]**
- The Wrasse live ISO is a network-install ISO (no `live-iso-mode`, no embedded payload; `installer/README.md`), so the image is pulled during installation. The live ISO ESP is systemd-boot **unsigned**, so booting the ISO needs Secure Boot off. **[V]**
- Not possible yet: **Anaconda** support (travier #20), **image-builder customizations** on sealed images, and a signed-boot ISO. Installing a sealed image on a Secure Boot machine is a two-step flow today: install, then enroll the Wrasse MOK on first boot (travier's README documents shim copy + `mokutil --import` by hand, because bootupd cannot manage shim + systemd-boot yet). **[V]**
- Stage 0 changed the variant files and catalog only; the image behind them is still ostree-built, so install success is **[U]** until a VM run.

### 5.5 Flatpak, brew, update stack

No dependency on ostree: Flatpak and Homebrew live in `/var` and `/home`; `ujust update` and uupd drive them separately. ChairLift/Bazaar do not call ostree directly in the paths I grepped. GNOME Software is already removed. **[I]**

## 6. Risks and blockers, ranked

| # | Risk | Severity | Why |
|---|---|---|---|
| 1 | Experimental backend; on-disk formats may change | blocker for `stable` | Doc banner; upgrades tested only from 1.16.0 UKI installs and not in CI; GC with V1/V2 entries untested. A bad bootc bump could strand users. |
| 2 | No ostree to composefs migration | blocker for existing users | Doc lists it as future work. Every install must be redone; `/home` and Flatpak data need a backup/restore story. |
| 3 | Secure Boot chain does not exist upstream | blocker for sealed on SB machines | No Fedora-signed systemd-boot or UKI (F44 has `systemd-boot-unsigned` only); users must enroll Wrasse MOK plus ublue MOK; key custody and rotation are ours. |
| 4 | No boot counting or auto-rollback | high | A bad UKI means manual rescue; the doc says "likely to be added". |
| 5 | Safe mode and runtime kargs impossible on sealed UKI | high (feature loss) | systemd-stub ignores cmdline overrides under SB. |
| 6 | Installer path unproven for Wrasse | high | Stage 0 flipped it; needs disk-backed scratch and a VM run; pinned installer/fisherman versions unchecked. |
| 7 | UKI size and boot time (`--no-hostonly` initramfs, nvidia) | medium | travier #23; ESP 1 GiB default holds only a few UKIs; per-GPU initramfs likely. |
| 8 | Sysext on a sealed system | medium | `/var`-resident unsigned sysext defeats the integrity story. |
| 9 | Signature policy carry-over | medium | Upstream says not settled; Wrasse relies on `policy.json`. |
| 10 | Residual ostree-gated units (`/run/ostree-booted`) | medium | Silent no-ops and `dnf-makecache` running; fixed by an audit. |
| 11 | bootc version drift (V1/V2 digest format, initramfs must match) | medium | Pin bootc per image; regenerate initramfs before UKI. |
| 12 | Soft-reboot behaviour differs | low | `update-soft` text and fallback. |
| 13 | CI cost: more steps, a signing key | low/medium | Needs user-created secret; never created by me. |

**Not possible yet** (cited above): in-place ostree-to-composefs migration; a Fedora-signed boot chain; boot counting; managing UKI addons through bootc; Anaconda install of sealed images; runtime kargs on UKI; image-builder customizations for sealed images; the "no ostree library" ideal (bootc links libostree).

## 7. Staging plan

Never touch `stable` until a stage says so. Every stage ends with a stop (CLAUDE.md rule). Each is one concern per commit.

- **Stage 0 (done, unproven): unsealed composefs install of the current image.** Commits `01955a3f`, `98eda7d3`. Prove with E1 below. If E1 fails, `git revert` of the one-word variant change returns to ostree installs.
- **Stage 1: image line `wrasse:composefs` (experimental tag, never `stable`).** Switch to a composefs-clean image in a *separate* CI cell/tag so the stable lines are untouched.
  Files: `Containerfile` (final stages), `build_files/base/19-initramfs.sh` (`--add bootc`, no `ostree`), new `build_files/base/18-composefs.sh` (remove rpm-ostree, bootupd, grub; install `fsverity-utils`; write `usr/lib/bootc/install/{80-rootfs,90-install}.toml`), `03-install-kernel-akmods.sh` (no change needed; verify), `build_files/shared/build.sh` (bootstrap dnf5 without rpm-ostree),
  `04-packages.sh`, `17-cleanup.sh`, `20-tests.sh`, `clean-stage.sh`, `system_files/shared/etc/rpm-ostreed.conf` (delete), `.github/build-matrix.json` (add experimental line `composefs`, fixed to one Fedora version), `.github/workflows/build.yml`. Still **unsealed** (no UKI). Gate: image boots in the VM, `bootc status` reports composefs, `rpm-ostree` absent.
- **Stage 2: `ujust`/CLI/uupd audit for composefs** (`60-custom.just`, `update.just`, `default.just`, `cli/src/app.rs` text only, `bootc-update-stage` comment, `rechunker-group-fix.service`, countme service). Gate: `ujust rollback`, `system-status`, `update-soft`, `wrasse status/rollback`, one uupd run.
- **Stage 3: UKI in the VM, Secure Boot off.** Add split kernel + `bootc container ukify` (unsigned) stage; use a btrfs or ext4 root so `--allow-missing-verity` is not needed. Gate: boots, digest enforced (E2 negative test), upgrade A to B and rollback.
- **Stage 4: signing.** Wrasse key pair created by the maintainer (never by an agent), secret in CI (`docs/CI-SECRETS.md` addition), sign systemd-boot and UKI, MOK enrollment doc, test in a VM with OVMF Secure Boot firmware and custom vars, then on real hardware, then the NVIDIA module path. Gate: Secure Boot on, UKI loads, NVIDIA modules load.
- **Stage 5: installer and ISO.** Disk-backed `/var/tmp` guarantee in the live image (`configure-live.d.sh`), size checks, ESP size (use 2 GiB via repart if the installer cannot), pinned fisherman version recorded in `installer/iso/pin.env`. Gate: full VM install from the ISO, reboot, `bootc upgrade`.
- **Stage 6: safe mode replacement** (profile UKI, E3) and the sysext-on-sealed decision. `docs/SAFE-MODE.md` rewritten.
- **Stage 7: promotion.** `next`, then `reimagined`, then `stable`, one line at a time, only after upstream drops the "experimental" banner or the maintainer accepts the risk in writing. Existing users: documented reinstall path with backup (`wrasse sync` already rebuilds user package setups).

## 8. First experiment and VM verification checklist (fish)

**E1 (the recommended first experiment, no image rebuild): install the current published or locally pulled Wrasse image with the composefs backend in the existing virt-manager VM, UEFI, Secure Boot off.**
It answers the single biggest unknown: does bootc accept the ostree-built Wrasse image in composefs mode, and does it boot and update. No code change; Stage 0's installer variant already requests exactly this.

VM setup: UEFI firmware without Secure Boot (virt-manager: Overview, Firmware "UEFI x86_64: /usr/share/edk2/ovmf/OVMF_CODE.fd"; a `*.secboot.*` file means Secure Boot on); disk at least 60 GB virtio; 8 GB RAM; add a second 40 GB disk for the installer scratch (`/var/tmp`).

Install (from any Fedora live or the Wrasse ISO shell; adapt the image tag):

```fish
sudo podman pull ghcr.io/wrasse-os/wrasse:stable
sudo podman run --rm --privileged --pid=host --ipc=host --security-opt label=type:unconfined_t \
  -v /var/lib/containers:/var/lib/containers -v /dev:/dev -v /var/tmp:/var/tmp \
  ghcr.io/wrasse-os/wrasse:stable \
  bootc install to-disk --composefs-backend --bootloader systemd --filesystem btrfs /dev/vda
```

(`to-disk` creates a 1 GiB ESP for composefs. If the ISO path is used instead, answer the installer's disk step and let it install. Pull needs several tens of GB on the disk-backed `/var/tmp`.)

Checks after first boot (each is a pass or fail):

```fish
bootc --version
sudo bootc status                                  # expect a composefs entry; note booted image and digest
sudo bootc status --format json | jq '.status.booted | {image: .image.image.image, composefs: .composefs}'
cat /proc/cmdline | tr ' ' '\n' | grep -E '^composefs'   # expect composefs= or composefs.digest=
test -e /run/ostree-booted; and echo "ostree marker present"; or echo "no ostree marker (expected)"
mount | grep -E ' on / | /sysroot|/etc |/var '           # composefs overlay root, bind /etc, /var
ls /composefs /state/deploy
ls /sysroot/ostree 2>&1                                  # expect missing or a stub only
sudo ls /boot/loader/entries /boot/EFI/Linux 2>&1
findmnt /boot; lsblk -f
systemctl --failed
systemctl status bootc-root-setup.service --no-pager 2>&1 | head -5   # initrd unit; look in journal
journalctl -b -u bootc-finalize-staged.service --no-pager 2>&1 | head
set obj (sudo find /composefs/objects -type f | head -1); sudo fsverity measure $obj   # verity enabled on one object
rpm -q rpm-ostree bootupd ostree 2>&1                    # what is still installed (rpm-ostree will be until Stage 1)
lsinitrd /boot/initramfs* 2>/dev/null | grep -i -E 'bootc|ostree-prepare'   # if a BLS initrd is on /boot
```

Update, rollback, the wrapper commands (each on the composefs install):

```fish
sudo bootc upgrade --check
sudo bootc upgrade; and sudo bootc status          # staged entry appears
systemctl reboot                                    # then: bootc status shows booted = new
ujust system-status
wrasse status --json | jq .
ujust rollback                                      # answer y; check Rollback entry flips after reboot
ujust update-soft                                   # expect a message, not a reboot, if not soft-reboot capable
sudo uupd --dry-run 2>&1 | tail                     # confirm bootc is the driver, no rpm-ostree fallback
ujust dx status; ujust dx on                        # sysext merge on the composefs root, then: systemd-sysext status
```

Negative checks:

```fish
sudo bootc switch --enforce-container-sigpolicy ghcr.io/wrasse-os/wrasse:stable   # signature enforcement works
sudo bootc upgrade --apply --soft-reboot=required                                # report exact behaviour
```

**E2 (Stage 3): sealed UKI, still Secure Boot off.** Build a UKI with `bootc container ukify` (unsigned), install, then prove fs-verity enforcement by flipping one byte in a file of the composefs repo on a *copy* of the disk and confirming the boot stops (do not do this on a disk you care about).
**E3 (Stage 6): safe mode via a multi-profile UKI.** Build with `ukify --profile` / `--join-profile`, check systemd-boot shows two entries, and check that `bootc upgrade` and GC keep or remove the second profile as expected.

## 9. Open questions (stop and ask the maintainer)

1. Which Secure Boot trust model: Wrasse MOK plus ublue MOK (recommended), or a single key via re-signing modules? Who holds the Wrasse private key, and where does CI get it? (I will not create or store it.)
2. May existing Bluefin-derived installs be abandoned (no migration), with a documented reinstall path?
3. Is an experimental `composefs` image line acceptable on `ghcr.io/wrasse-os`, given Stage 0 already points the ISO at composefs?
4. Which kernel-argument and safe-mode UX is acceptable once the cmdline is sealed: profile UKI, or drop the boot-time safe mode?
5. Sealed requires a signed sysext story for DX; is DX allowed to be unavailable on sealed images at first?

## 10. Sources

- bootc docs at tag v1.16.13: `docs/src/{experimental-composefs,bootloaders,initramfs,boot-failure-detection,upgrades,relationships,filesystem-sysroot,experimental-install-reset}.md`, `docs/src/man/bootc-setup-root-conf.5.md`; https://bootc.dev/bootc/experimental-composefs.html
- bootc source v1.16.13: `crates/lib/src/{install.rs,install/baseline.rs,install/config.rs,ukify.rs,generator.rs,store/mod.rs,bootc_composefs/*}`, `crates/initramfs/{dracut/module-setup.sh,bootc-root-setup.service}`
- Local: bootc 1.16.7 `bootc container ukify --help`, `bootc install to-filesystem --help`, `ldd /usr/bin/bootc`; `dnf repoquery` for F44 (`systemd-boot-unsigned` only, `systemd-ukify`, `sbsigntools`, `shim-x64 16.1`, `bootupd 0.3.x`); Bodhi `bootc-1.16.13-1.fc44`
- systemd `man/systemd-stub.xml`, `man/ukify.xml`, `man/systemd-boot.xml` (main branch)
- https://tim.siosm.fr/blog/2026/04/28/sealed-atomic-desktops-test-images/ and https://github.com/travier/fedora-atomic-desktops-sealed (README, Containerfile, `scripts/`, issues #4 #5 #6 #20 #23 #41)
- https://github.com/projectbluefin/dakota-iso (pin `9c123eea`: `live/src/configure-live.sh`, `scripts/plain-install-qemu.sh`, `scripts/iso-sd-boot.sh`, `live/Containerfile`), https://github.com/projectbluefin/dakota (BuildStream, `elements/gnomeos-deps/bootc.bst`), https://github.com/tuna-os/fisherman (`internal/install/{bootc.go,systemdboot.go}`)
- https://github.com/ublue-os/uupd (`drv/system/system.go`, `cmd/wait.go`)
