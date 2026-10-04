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
- A `Require signing key before any push` step fails a non-PR run before the push when `SIGNING_SECRET` is empty, so no unsigned image
  can reach GHCR (the cosign step runs after the push).
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
- The base image is `quay.io/fedora-ostree-desktops/silverblue:<fedora>` (Fedora's own bootc Silverblue, user decision), for every line.
  `base_image` and `base_image_key` in `.github/build-matrix.json` are the one place to change it. `just build` resolves the floating
  tag to a digest once (it equals the newest dated `<fedora>.<date>.<n>` tag), cosign-verifies that digest with Fedora's key
  (`.github/keys/quay.io-fedora-ostree-desktops.pub`, from gitlab.com/fedora/ostree/ci-test, same key as in the quay signature
  bundle) and builds `@sha256:`. It then inspects the digest and refuses a base whose `ostree.linux`/version label is not the requested
  release or whose digest equals the `rawhide` tag (Rawhide is tag `46` today). A missing tag or failed verification fails that cell
  closed. The `silverblue-main-NN` pins and the ublue cosign check of the base are gone. (`quay.io/fedora/fedora-silverblue` was
  tried first; it has no signature.)
- `build_files/base/01-fedora-base.sh` (run before the kernel swap) reproduces what ublue-os/main added on top of Fedora and the
  image still depends on: negativo17 `fedora-multimedia` at priority 90 with the mesa/libva/intel overrides (versionlocked),
  main's `packages.json` package set (ffmpeg, codecs, distrobox, ptyxis, fzf, htop, nvtop, udev rule packages, ...),
  `oversteer-udev` from the ublue-os/packages COPR, removal of `fedora-flathub-remote`, `fedora-third-party` and
  `totem-video-thumbnailer`, `/etc/flatpak/remotes.d/flathub.flatpakrepo`, the linuxbrew `sudo` secure_path, the pinned CoreOS
  sulogin generator, plus `copr.vendor.conf`, the 5-day coredump tmpfiles rule and zstd dracut compression in `system_files/`.
  `build.sh` no longer runs `dnf remove ublue-os-*` (plain Fedora does not have them) and installs dnf5 if the base lacks it.
  Why: the base is no longer `silverblue-main`. Not reproduced: `ublue-os-just/-luks/-udev-rules/-signing/-update-services` (this
  repo carries its own copies), `fedora-repos-archive`, the on-device `cosign` RPM (excluded in `04-packages.sh`), the
  `rm /usr/bin/chsh`, the staging COPR.
- The akmods image is now fetched and extracted in `01-fedora-base.sh` (moved out of `03-install-kernel-akmods.sh`, same digest-only rule), which
  installs `ublue-os-akmods-addons` from it, as ublue-os/main did. That RPM provides `/etc/yum.repos.d/_copr_ublue-os-akmods.repo`,
  `negativo17-fedora-multimedia.repo` (the file names `03`, `17-cleanup.sh` and `validate-repos.sh` use) and the `akmods-ublue.der` Secure Boot
  key. Plain Fedora has none of them (first CI run failed in `03` on the missing akmods repo file); the negativo17 repo is no longer added by URL.
- `03-install-kernel-akmods.sh` stubs kernel-install's `05-rpmostree.install` and `50-dracut.install` while the akmods kernel RPMs install,
  as ublue-os/main does on a plain Fedora base; `19-initramfs.sh` still builds the initramfs. Why: unverified without a build, but main hit
  the failure with the same procedure.
- `FEDORA_PRERELEASE` build arg replaces `UBLUE_IMAGE_TAG == beta` in `03-install-kernel-akmods.sh` and `validate-repos.sh`.
- `changelogs.py` writes no output and exits 0 when the line has no published image; `generate-release.yml` then skips the release instead of failing.
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
- `installer/gen-catalog.sh <wrasse|wrasse-nvidia>` builds the complete `/etc/bootc-installer/images.json` for one detected flavor from
  `build-matrix.json`: only the release lines as leaves (NVIDIA is a hardware variant, not a line), the detected flavor in each imgref,
  and one "Use different graphics drivers" group with the other flavor (omitted if none exists). A line with `"nvidia": false` falls
  back to the wrasse image on NVIDIA hardware. build-iso.yml generates both catalogs; `installer/iso/variant/wrasse/` runs
  `wrasse-gpu-detect` at live boot and installs the matching one. Kept inside one "Wrasse" group because the installer's top level
  only accepts groups (`ListBox.add_row` on a top-level leaf does not exist). The ISO is a network install because the installer drops its image step (where the release line is asked) in
  live-ISO mode.
- `build-iso.yml` adapts `projectbluefin/dakota-iso` (what Bluefin's ISOs use now, not `ublue-os/titanoboa`), pinned to commit
  `9c123eea`, with `tuna-os/bootc-installer` `v2026.09.26-253d6938` pinned by bundle sha256 (`installer/iso/pin.env`,
  `pin-installer.sh` patches the upstream `releases/latest` lookup). `wrasse-gpu-detect` is built static in the workflow. No payload,
  R2 upload, schedule or boot test. The ISO label stays `DAKOTA_LIVE` (hardcoded upstream).

## Docs

- Rewrote `README.md` for Wrasse (Bluefin branding is noted as unrenamed); added `docs/INSTALL.md`, `docs/UJUST.md`,
  `docs/WRASSE-INSTALL.md`; cut `AGENTS.md` down to a pointer to `CLAUDE.md` and `docs/SPEC.md`; regrouped this file by area.

- **Signing key**: generated a new cosign key pair for the wrasse-os org; `/cosign.pub` is now Wrasse's public key (was Bluefin's). The private key and password live only in the repo secrets `SIGNING_SECRET` / `COSIGN_PASSWORD` and a local 0600 backup outside the repo. Round-trip sign/verify was tested. The in-image trust policy (`policy.json`, `registries.d`) still needs this key; see docs/CI-SECRETS.md.

- **20-tests.sh**: check `wrasse-agents.slice` with greps instead of `systemd-analyze --user verify`, which cannot run without a user manager in a container build (broke every CI cell).

- **Pre-release ffmpeg (`01-fedora-base.sh`)**: when `FEDORA_PRERELEASE=1`, the negativo17 ffmpeg stack (`ffmpeg`, `ffmpeg-libs`, `libavcodec`, `libavformat`, `libavutil`, `libavfilter`, `libavdevice`, `libswscale`, `libswresample`, `libpostproc` and their `-devel`) is added to `fedora-multimedia.excludepkgs`, and `ffmpeg-free` is installed instead of `ffmpeg`, `ffmpeg-libs` and `libavcodec`. Why: negativo17's fedora-45 `libavformat` requires `libxml2.so.16`, which Fedora 45 (fedora and updates-testing) does not provide (only `libxml2.so.2`), and its `libavcodec` obsoletes `libavcodec-free`, so the `dnf5 install` failed in all four F45 cells. Everything else from negativo17 (mesa, libva, libheif, intel media stack, `libfdk-aac`, `pipewire-libs-extra`, the overrides and their versionlock) still resolves on F45 and is unchanged. Cost: Fedora's `ffmpeg-free` is built without the H.264, HEVC, VC-1 and VVC decoders and without x264/x265 encoders, so those codecs are missing from the ffmpeg CLI and libraries on pre-release images. Temporary: delete the `NEGATIVO17_FFMPEG_STACK` block once negativo17's `libavformat` installs on the pre-release. Stable (F44) is unchanged.

- **DX sysext build**: pass `--arch` once per architecture to `dnf5 download`; the comma-separated form is rejected ("Unsupported architecture noarch,x86_64"), which failed every stable cell.
- **gnome-rounded-blur on pre-release Fedora**: skipped when the COPR has no build (ublue-os/packages builds it for Fedora 44 only today), instead of failing the image. Rounded blur corners are cosmetic.

- **Build pull retries**: `podman build --retry 5 --retry-delay 15s` after a quay.io CDN blob dropped mid-pull (unexpected EOF) failed the next/nvidia cell. The cell passed on re-run; the retry is hardening.

- **Rollback and status UX**: added `ujust rollback` and `ujust system-status` (`60-custom.just`) and `wrasse status` / `wrasse rollback` (`cli/`), thin wrappers over `bootc status` and `bootc rollback` through `pkexec` (bootc needs root). Why: a rollback path that is one command, shows what will change and states the DX sysext and `/etc` consequences, instead of expecting users to know bootc.

- **Sysext safe mode**: `systemd-sysext.service.d/10-wrasse-safe-mode.conf` skips the unit when `wrasse.safe=1` is on the kernel command line; `docs/SAFE-MODE.md` says how to add it once at GRUB. Why: a broken DX sysext must not strand a user; a one-shot kernel argument is the smallest mechanism and leaves `ujust dx off` as the persistent fix.

- **Claude Code sandbox default**: `bubblewrap` and `socat` added to the base packages (the Linux dependencies listed in code.claude.com/docs/en/sandboxing), and `/etc/claude-code/managed-settings.d/10-wrasse-sandbox.json` sets `sandbox.enabled: true` and `sandbox.autoAllowBashIfSandboxed: false`. Why: the sandbox only restricts what Bash commands can reach; `autoAllowBashIfSandboxed` defaults to `true` upstream and would approve sandboxed commands without a prompt, which breaks the rule that nothing auto-approves, so it is pinned to `false`. Not set: `failIfUnavailable` (could stop Claude Code starting where user namespaces are blocked) and `allowUnsandboxedCommands` (setting `false` makes the sandbox admin-required). Caveat: managed settings rank above user and project settings, so users cannot switch these two keys from `~/.claude/settings.json`; the supported way out is a root-owned later drop-in (for example `/etc/claude-code/managed-settings.d/90-local.json`) or deleting the Wrasse one. Other sandbox keys (paths, domains) still merge from user and project scopes.

- **`wrasse-agent-run`**: new `/usr/bin/wrasse-agent-run <cmd...>` runs any agent or MCP server command in a scope under `wrasse-agents.slice` with `MemoryMax=75%` (override: `WRASSE_AGENT_MEMORY_MAX`); the lazy `claude` stub now calls it instead of carrying its own `systemd-run` logic. Why: MCP servers and other agents had no way into the slice, and a per-scope hard cap is a backstop above the slice's `MemoryHigh=60%` and the oomd trigger. `docs/AGENT-SLICE.md` updated.

- **System AGENTS.md**: `/usr/share/wrasse/AGENTS.md` (short, agent-neutral: immutable `/usr`, `wrasse install`, bootc, `ujust dx`, never `sudo dnf install`) plus user-setup hook `31-wrasse-agents-md.sh` that symlinks it to `~/AGENTS.md` once, only if absent. Chosen over `/etc/skel/AGENTS.md` because skel reaches new users only (not the existing one) and copies a real file into every home; a link into `/usr` stays current with the image and the user can delete it. A separate hook id keeps the skill hook's once-only state untouched. `SKILL.md` points to the shared file instead of repeating it.

- **Enforced signature policy for `ghcr.io/wrasse-os`**: `policy.json` gets a `sigstoreSigned` entry for `docker://ghcr.io/wrasse-os` (key `/usr/lib/pki/containers/wrasse.pub`, a copy of `/cosign.pub`, `signedIdentity: matchRepository`) and `registries.d/wrasse-os.yaml` sets `use-sigstore-attachments: true`; the ublue entries are untouched. Why: before this, Wrasse images fell through to `insecureAcceptAnything`, so `bootc switch --enforce-container-sigpolicy` verified nothing. Deliberately key-based (what CI signs with) and without `subjectRegExp`/keyless identities, which broke every pull in Bluefin's closed projectbluefin/common#1194. `20-tests.sh` checks the entry statically. `wrasse.pub` must be updated together with `/cosign.pub` on key rotation. `image-info.json` already carries `ostree-image-signed:docker://ghcr.io/wrasse-os/<name>` (IMAGE_VENDOR is set from `repo_organization`), and `ujust toggle-testing` already passes `--enforce-container-sigpolicy`, so no recipe change.

- **`ujust update-soft`** (`60-custom.just`): runs `pkexec bootc upgrade --soft-reboot=auto --apply`, documented in `docs/UJUST.md` with its limits. Why: uupd (`drv/system/system.go`) hard-codes `bootc upgrade --quiet --progress-fd 3` and its `--apply` is a regular reboot, with no soft-reboot setting, and forking uupd is out of scope. A kernel or initrd change forces a full reboot (bootc falls back under `auto`).

- **tuned as the power daemon**: `tuned` and `tuned-ppd` added to the Fedora packages, `power-profiles-daemon` removed first in `04-packages.sh`, `tuned.service` enabled in `17-cleanup.sh`, static checks in `20-tests.sh`. Why: the user wants tuned. Checked with `dnf5 repoquery` on F44 (tuned/tuned-ppd 2.27.0, F45 2.28.0): `tuned-ppd` ships `net.hadess.PowerProfiles` D-Bus/polkit files (GNOME's power profile menu keeps working) and `Conflicts: ppd-service`, which `power-profiles-daemon` 0.30 also provides; it only obsoletes ppd < 0.23-2, so the removal is explicit. Nothing in the F44 repo requires power-profiles-daemon except cosmic-settings (not shipped). `tuned-ppd.service` is D-Bus activated, so only `tuned.service` is enabled. The Fedora change page (TunedReplacesPower-profiles-daemon, targeted F41) is marked rejected, so Silverblue still ships power-profiles-daemon; no ppd assumptions exist in `system_files` (searched `power-profiles`, `powerprofilesctl`, `power-saver`).

- **oomd defaults drop-in**: `/usr/lib/systemd/oomd.conf.d/20-wrasse.conf` pins `SwapUsedLimit=90%`, `DefaultMemoryPressureLimit=60%`, `DefaultMemoryPressureDurationSec=20s` (keys from oomd.conf(5), verified on F44 systemd 259), explained in new `docs/MEMORY.md`; static check in `20-tests.sh`. Why: values were implicit (Fedora's `10-oomd-defaults.conf` sets only the 20 s), so they could drift from the zram/MGLRU tuning. `systemd-oomd.service` was already enabled in `17-cleanup.sh`.

- **Bazaar "Agents and Developer Tools" section**: appended to `system_files/shared/etc/bazaar/curated.yaml` in the existing section schema (title/subtitle/appids list), English strings only. App IDs each returned HTTP 200 from `flathub.org/api/v2/appstream/<id>`: OpenCode, Alpaca, LM Studio, Newelle, Zed, GitButler, BoxBuddy, Bruno. Why: surface agent and developer tools in the store. Not listed because not on Flathub: Ghostty (`com.mitchellh.ghostty` 404) and no Claude desktop client exists there.

- **ISO workflow**: run shellcheck at warning level; info-level SC1091 ("not following pin.env") failed the first ISO run.

- **DX sysext package list in `packages.txt`**: `build_files/dx/packages.txt` is now the one list of DX packages, read by `build-sysext.sh` (previously an inline array). Why: the mkosi builder (added next) must install exactly the same packages; one file avoids two lists drifting. No change to what the script builds.

- **mkosi DX sysext builder (alternative)**: `build_files/dx/build-sysext-mkosi.sh`, `build_files/dx/mkosi/` and `build_files/dx/Containerfile.mkosi-layer` build `wrasse-dx.raw` with mkosi (`Format=sysext`, `Overlay=yes`, base tree = the finished image) from the shared `packages.txt` and `files/`; `test-sysext.sh` accepts a GPT image as well as bare erofs and skips while a mkosi sysext is yet to be layered in. Why: the user asked to try mkosi; it is an alternative, the script stays the default until CI proves it. Not run anywhere yet.

- **`DX_BUILDER` switch**: Containerfile stage `dx-build` is now selected by `ARG DX_BUILDER` (`script` = old `dx-script` stage, `mkosi` = empty `dx-mkosi` stage); `just build` passes it from the environment, default `script`, and rejects other values. Why: the mkosi sysext is built outside `podman build` and layered in afterwards. The default path builds the same stage as before.

- **CI `dx_builder` input**: `build.yml` gets a `workflow_dispatch` input `dx_builder` (script or mkosi, default script) that sets `DX_BUILDER`; for mkosi, steps install a pinned mkosi, build the sysext from the built image, layer it in and retag, and the size report names the builder. Why: compare the two builders in CI without changing scheduled, push or PR builds.

- **`docs/DX-SYSEXT.md`**: documents both DX sysext builders, how to switch, the 1.4 GB baseline and what to compare. Why: record the mkosi trial design and its checklist.

- **DX sysext is no longer in the image** (user decision, supersedes SPEC Phase 3 "bake in"): the Containerfile's `dx-script`, `dx-mkosi`, `dx-build` and `final` stages, the `DX_BUILDER` build arg and `/usr/share/wrasse/sysexts/` are gone, so the image (and the live ISO built from it) no longer carries the 1.4 GB `wrasse-dx.raw`. The sysext is built as a separate artifact FROM the finished image by `build_files/dx/build-dx.sh` (`Containerfile.dx` for the script builder, `build-sysext-mkosi.sh` for mkosi; `DX_BUILDER` is now an environment variable of that script), and `test-sysext.sh` checks the output directory against the image's os-release (and that os-release has `IMAGE_ID` and `IMAGE_VERSION`). `Containerfile.mkosi-layer` is deleted. Why: every user downloaded 1.4 GB on every image pull for a feature most do not turn on. Building from the finished image (not a second `--target` of the main Containerfile) guarantees the sysext is built against exactly the pushed content and never rebuilds the base on a cache miss.

- **CI builds and publishes the DX sysext separately** (`build.yml`, `.github/scripts/publish-dx.sh`): after the image is pushed, signed and attested, each cell builds `wrasse-dx.raw` from the rechunked image with `build_files/dx/build-dx.sh` (mkosi still selectable through the `dx_builder` dispatch input), then `oras push`es it with `wrasse-dx.extension-release` to `ghcr.io/wrasse-os/wrasse-dx` as `<image-id>-<IMAGE_VERSION>` (exact) plus `<image-id>-<line>` and `<image-id>-f<fedora>` aliases, signs the digest with the same `SIGNING_SECRET`/`COSIGN_PASSWORD` key as the images, and fetches it back with skopeo through the image's own DX trust policy. The manifest carries signed `io.wrasse.dx.image-id`/`image-version` annotations. Why separate and last: a failed DX build or publish must not block or undo the image; it turns that cell red, adds an error annotation and a "DX sysext UNAVAILABLE" summary, and DX stays unavailable for that image build until the cell is re-run. The image id is part of the tag because `IMAGE_VERSION` is the same for `wrasse` and `wrasse-nvidia`. Pull requests build and check the sysext but never publish.

- **`ujust dx` downloads the sysext on demand** (`wrasse-dx`, new `wrasse-dx-select`, `wrasse-dx-select.service`, `/usr/share/wrasse/dx/`, `60-custom.just`): `dx on` and the new `dx update` fetch `ghcr.io/wrasse-os/wrasse-dx:<IMAGE_ID>-<IMAGE_VERSION>` (both read from the booted `/usr/lib/os-release`, so offline) with `skopeo copy` under a dedicated policy that rejects everything except that repository signed by `/usr/lib/pki/containers/wrasse.pub`, refuse an artifact whose signed annotations do not name the booted image, and keep it in `/var/lib/wrasse/sysexts/<IMAGE_ID>-<IMAGE_VERSION>/`. `wrasse-dx-select.service` (enabled only while DX is on, skipped with `wrasse.safe=1`) runs before `systemd-sysext.service` and links only that file into `/var/lib/extensions`; with no match nothing merges, so an image update turns DX off until `ujust dx update`, and a rollback finds the old file again. `dx update` also fetches the staged image's sysext and prunes cache entries other than booted, staged and rollback; `dx off purge` deletes the cache. Daemon-reload, socket enabling and groups are unchanged. Why skopeo and not cosign or oras: skopeo is on the image (a dependency of bootc) while the cosign RPM is excluded, and it enforces the same sigstore policy mechanism as image pulls; an OCI artifact (custom layer media types, empty config) copies through skopeo to a `dir:`. Why the key includes the image id: `IMAGE_VERSION` is identical for `wrasse` and `wrasse-nvidia`. `20-tests.sh` gets static checks (policy, units, skopeo, jq, no `/usr/share/wrasse/sysexts`).

- **Docs for DX on demand**: `docs/DX-SYSEXT.md` (flow, tags, failure semantics, one-time package visibility), `SAFE-MODE.md`, `DX-SELINUX-CHECKLIST.md` (new download, selector, update and offline checks), `INSTALL.md`, `UJUST.md`, `WRASSE-INSTALL.md`, `CI.md`, `CI-SECRETS.md`, `SPEC.md` Phase 3 (decision recorded; "bake in" marked superseded), `README.md` and the agent skill text. Why: the DX sysext is no longer in the image, so every statement that it ships with or rolls back with the image was wrong.

- **`wrasse rollback` note**: the confirmation text said the DX sysext "is part of the image and rolls back with it"; it now says DX follows the image and uses the sysext downloaded for it, else `ujust dx update`. `wrasse install --dx` is unchanged (it still runs `ujust dx on`, which now downloads first). Why: the old sentence became false.

- **Dark mode by default**: `color-scheme='prefer-dark'` in the schema override. Night Light stays at the GNOME default (off); the maintainer's own setting is also off.

- **Live ISO dock**: pin `org.bootcinstaller.Installer.desktop` (the id the running window matches) instead of `dakota-installer.desktop`, which showed two installer icons; live favorites are now Installer, Files, Ptyxis.

- **Installer launcher naming**: the live ISO launcher is "Install Wrasse" (generic bootc installer); the Dakota-named launcher is removed and the build fails if Dakota branding is left in the installer launchers. The `DAKOTA_LIVE` volume label is hardcoded upstream and unchanged.
- **systemd-boot-unsigned in the image**: bootc's composefs backend installs systemd-boot from the image, so new installs can use it.
- **New installs use composefs**: the live installer recipe and catalog now use `composeFsBackend` with `systemd-boot` instead of GRUB. Existing ostree installs are untouched and have no migration. NOT yet proven: the current images are still built from an ostree base, so a VM install must confirm bootc accepts them; revert is one word in `installer/iso/variant/wrasse/{composefs,bootloader}`.
- **Direction decided: composefs-native (Phase 9, research only)**: the maintainer chose bootc's composefs backend without ostree (`docs/COMPOSEFS-NATIVE.md`, `docs/SPEC.md` Phase 9). Why: drop the ostree stack and head toward sealed, Secure Boot verified images. NOT implemented: the image is still built from the ostree Silverblue base with `--add ostree` in `19-initramfs.sh`, `rpm-ostree` is still installed and referenced, there is no UKI, no signing key, no boot-menu safe mode replacement (`wrasse.safe=1` cannot work on a sealed UKI), and no migration for existing ostree installs. Only the installer variant (composefs + systemd-boot, an earlier entry above) points that way, and it is unproven.

- **`docs/BRANDING-HITS.md`**: every remaining case-insensitive "bluefin" hit (outside `installer/`, `docs/INSTALL.md`, `docs/SPEC.md`) classified as BRANDING, PLUMBING, TELEMETRY, ARTWORK or UNCLEAR, with what the `brand:` commits did about each. Why: the maintainer asked for branding vs plumbing hits to be shown before anything is renamed.

- **Bluefin telemetry removed** (`projectbluefin-countme` script, service, timer, preset and timers.target.wants link; build-time download of the `ublue-os/countme` Bluefin user-count badge and its fastfetch "Murder Chickens" line): the daily ping went to `countme.projectbluefin.io` (it only fired for `dakota*`/`utah*` image names, so it never ran for Wrasse, but the code and an enabled timer shipped). Why: Wrasse must not phone home to Bluefin. Fedora's own `rpm-ostree-countme` is untouched.

- **os-release branding** (`build_files/base/00-image-info.sh`): `NAME`/`PRETTY_NAME` Wrasse, `ID=wrasse` and `DEFAULT_HOSTNAME=wrasse` (both derived from the pretty name), `CPE_NAME=cpe:/o:wrasse-os:wrasse`, `HOME_URL`, `DOCUMENTATION_URL` (docs in the repo), `SUPPORT_URL` and `BUG_REPORT_URL` point at `github.com/wrasse-os/Wrasse`, `VERSION_CODENAME` is the placeholder `Cheilinus` (Bluefin used `Deinonychus`; maintainer picks the real one). Why: the OS still identified itself as Bluefin. `ID` changes from `bluefin`: the DX sysext is built against the image's own `ID`, so a sysext built for an older image will not merge on a new one (it is rebuilt per image build anyway).

- **Image labels** (`Justfile`, both label blocks): `org.opencontainers.image.source`/`url` and `io.artifacthub.package.readme-url` point at `wrasse-os/Wrasse`, keywords are `bootc,fedora,gnome,wrasse`, description is Wrasse's one-liner; the Universal Blue org avatar `logo-url` and the `castrojo` `maintainers` labels are removed (no Wrasse logo or maintainer entry exists yet). `artifacthub-repo.yml` is deleted: it held Bluefin's Artifact Hub repository id and Jorge Castro as owner. Why: the images still advertised Bluefin as their source and owner.

- **File and directory renames** (`git mv`, every reference fixed): dconf `distro.d/{01-wrasse-folders,02-wrasse-keybindings,03-wrasse-ptyxis-palette,locks/01-wrasse-locked-settings}`, `profile.d/91-wrasse-aliases.sh`, `uupd.service.d/10-wrasse.conf`, `50-wrasse-bt-switch.conf`, `wrasse-help.desktop`, schema overrides `zz0-wrasse-modifications` and `zz1-wrasse-extensions` (and `05-override-install.sh`, which edits the first), the dynamic wallpaper (`wrasse-dynamic-wallpaper` script, user service and timer, its hook, the GeoClue `DesktopId` in `get-geoclue-latitude`), `backgrounds/wrasse` (`picture-uri` in the schema override, the Damask slideshow folder, the dynamic wallpaper script, `wrasse-hidamari.webm`), `pixmaps/faces/wrasse`, `ublue-os/wrasse-logos` (with `wrasse.png`, `sixels/wrasse`, `symbols/wrasse`; fastfetch `logo-directory`), `etc/ublue-os/tags.json`. The Containerfile stages the upstream wallpaper image as `/out/wallpapers` and now installs it under `backgrounds/wrasse`, renaming every `*bluefin*` file and rewriting the paths and names inside the XML (not verified by a build). Why: no file name should say Bluefin. The images inside those files are still Bluefin artwork (see `docs/BRANDING-HITS.md`); the vendored ChairLift ids (`io.projectbluefin.chairlift*`), `ublue-os` paths and the upstream wallpaper image name are real plumbing and stay.

- **Bazaar curation** (`etc/bazaar/curated.yaml`): section title "Wrasse Recommends" (en, id, pl); the 16 banner images are renamed `NN-wrasse-{day,night}.jxl` and the YAML points at them. The pixels are still Bluefin banners (no Wrasse banner art exists; see `docs/BRANDING-HITS.md`). Why: the store front page said Bluefin.

- **ujust, MOTD and links**: `uwelcome` links are `issues` and `docs` on `github.com/wrasse-os/Wrasse` ("Ask Bluefin" removed: no Wrasse forum exists); ChairLift `help_resources_group` website/issues point at the repo and the `chat` link is removed; `ujust` entry banner prints the repo `docs/UJUST.md` URL instead of Bluefin docs; bug-report brand is "Wrasse Bug Report", feature requests and "no issue created" help go to `wrasse-os/Wrasse` issues (Discussions link removed); `ublue-image-repo` now resolves every `wrasse*` image (and the fallback, also used by `ujust changelogs`) to `wrasse-os/Wrasse` instead of mapping to `projectbluefin/{bluefin,bluefin-lts,dakota,common}`; devmode marker is `~/.config/wrasse/devmode` (a Bluefin-era marker is not migrated); `bluefin-apps` recipe is `wrasse-apps`; `bazaar-preview` reads the repo layout `system_files/shared/etc/bazaar` (it pointed at upstream `common`/`bluefin-branding` paths that do not exist here); comments and the `flatpak-appstream-refresh` Documentation= link say Wrasse; `docs/UJUST.md` updated. Why: the on-device text and links sent users to Bluefin infrastructure.

- **Desktop entries**: `documentation.desktop` opens `docs/` in the repo (it opened an offline Bluefin PDF; the build step that downloaded `ublue-os/bluefin-docs` `bluefin.pdf` into `/usr/share/doc/bluefin` is removed from `05-override-install.sh`); `discourse.desktop` is now "Report an Issue" opening the repo issue tracker (translated names dropped: they said Community/Discussions); `system-update.desktop` and the vendored ChairLift entry (Comment, Keywords) say Wrasse; the ChairLift polkit policy `vendor`/`vendor_url` say Wrasse (action ids stay `io.projectbluefin.chairlift.*`, the vendored app id). Why: the launchers showed Bluefin text and links to Bluefin Discussions. The `ublue-docs`/`ublue-discourse` icons are Universal Blue art and are still used.

- **README and GitHub meta**: README branding note replaced by a short "forked from Bluefin" attribution (the Apache-2.0 LICENSE and the upstream mention in the License section are kept); `CONTRIBUTING.md` points at `CLAUDE.md`, `docs/SPEC.md` and the repo issues instead of `docs.projectbluefin.io` and `projectbluefin/common`; issue template `config.yml` drops the Bluefin "Ask", community and `projectbluefin/common` links (no Wrasse forum or chat exists) and links the repo docs; `bug-report.yml` says Wrasse and drops the link to a Bluefin Discussions thread; the PR template points at `CONTRIBUTING.md`; `changelogs.py` titles the section "Wrasse Images" and links commits and docs to `wrasse-os/Wrasse`; `.github/FUNDING.yml` (upstream maintainers' sponsor links) is deleted; `CLAUDE.md` no longer says branding is deferred. `.github/CODEOWNERS` still lists upstream maintainers and needs the real Wrasse handles (maintainer decision). Why: the repo front page and templates still presented Bluefin.

- **`ujust contribute` removed** (`shared.just`, `docs/UJUST.md`): it ran Bluefin's `ghcr.io/projectbluefin/contribute` worker, connected it to Bluefin's hosted Hive hub (`hosted-projectbluefin-knuckle-*.hive.hivecommons.dev`) and handed it the user's GitHub token. Why: Wrasse must not connect to Bluefin services; the recipe only made sense for Bluefin contributors and was user-initiated, never automatic.

- **`docs/BRANDING-HITS.md` outcome section**: remaining hits, artwork still needing Wrasse versions, and the extra `ujust contribute` removal. Why: keep the classification honest after the renames.

- **fastfetch logo**: Wrasse ASCII logo (`/usr/share/wrasse/fastfetch/logo.txt`, original placeholder art) instead of the distro-ID fallback logo. The OS line already reads the Wrasse `os-release`.

- **Cursor theme**: Bibata Modern Classic (as Linux Mint), pinned v2.0.7 release asset verified by sha256, set as the default `cursor-theme` in light and dark mode. One consistent theme on purpose: GNOME has no per-color-scheme cursor setting and a switcher would not update Flatpak/Qt/Xwayland apps live. Bibata is GPL-3.0.

- **Installer minimum disk size**: `min_disk_size` is 25 GB (installer default is 50 GB) in the Wrasse recipe. The installed image is about 11-14 GB and a second deployment needs room, so 25 GB is a sensible floor; 50 GB blocked small test VMs.

- **Installer RAM minimum**: new `installer/iso/variant/wrasse/wrasse-installer-preflight` (installed as `/usr/libexec/wrasse-installer-preflight`), and `configure-live.d.sh` rewrites `Exec=` in both launchers (`/etc/xdg/autostart/tuna-installer.desktop`, `/usr/share/applications/org.bootcinstaller.Installer.desktop`) to run it first; it execs the original command unchanged. It reads `MemTotal` and, below 7,000,000 kB, shows a zenity error (amount found, 8 GB required, how to add the `wrasse.ignore_ram=1` kernel argument that skips the check) and does not start the installer. Why: a 4 GB VM test had the live session's OOM handling kill the installer, and bootc-installer v2026.09.26 has no RAM check. 7,000,000 kB (6.68 GiB) because an "8 GB" machine reports about 7.0 to 7.7 GiB of MemTotal after firmware and iGPU reservations, while 6 GB (~5.7 GiB) and 4 GB (~3.8 GiB) machines stay below. `installer/tests/test-preflight.sh` covers it; `build-iso.yml` lints and runs it.

- **Installer connectivity check**: `recipe.json` gets a `conn_check` step (template `conn-check`) directly after `welcome`. The Wrasse ISO is a network install (4.4 to 5.0 GB from ghcr.io/wrasse-os), so an install with no connectivity must not get as far as the image step. The template tries `ghcr.io:443`, then `8.8.8.8:53`, advances by itself when either answers, and otherwise shows "No Internet Connection!" with a Recheck button and no way forward. It must stay at index 1: its back-button workaround compares against that position. The installer's Wi-Fi picker (`defaults/network.py`) exists in v2026.09.26 but is not registered in `utils/builder.py`, so it cannot be used from a recipe; connecting is done from the live GNOME system menu. `installer/tests/test-catalog.sh` checks the order and template name.

- **Installer download wording**: the installer has a confirm page (always shown, last step before the disk is written) whose title, body and button come from a branding file's `copy` keys, so `installer/iso/variant/wrasse/branding.json` (installed to `/etc/bootc-installer/branding.json` by `configure-live.d.sh`) sets `confirm_body` to say the image is downloaded from ghcr.io/wrasse-os, about 5 GB, and `welcome_install_subtitle` to list the 8 GB RAM and download requirements. It also carries `name`, `id` and the welcome title and subtitle, because with a branding file that names the product the installer ignores the recipe's `welcome_*`. `gen-catalog.sh` ends every image description with "Network install: downloads about 5 GB." Why static text: the installer has no size field, the images are 4.4 to 5.0 GB compressed, and a size read with skopeo at ISO build time would go stale before the install. The confirm page already lists the chosen image and the disk-erase warning.

- **Docs for installer requirements**: `docs/INSTALL.md` and `installer/README.md` state the minimums (8 GB RAM, 25 GB disk, network and the ~5 GB download), the `wrasse.ignore_ram=1` escape hatch and the connection check. Why: the RAM check and the connectivity step are new and the 25 GB disk floor was undocumented.

- **No-network message**: the live installer wrapper waits up to 8 s for a default route and, if none, shows how to get online (Ethernet, phone USB tethering, Wi-Fi from the system menu) before starting the installer. The installer's own connection check stays the gate; Wi-Fi is not required.

- **DX publish read-back**: point the shipped DX trust policy at the repo copy of the Wrasse public key on the runner (the on-image path does not exist there). The artifact itself was already pushed and signed; only the read-back failed.

- **Live ISO Flatpaks**: the installer copies the live system's Flatpaks to the target, and the ISO tooling's shared list is Bluefin's (Firefox-era set incl. DejaDup, File Roller, Characters). The Wrasse variant now supplies its own list, generated at ISO build time from the image's `system-flatpaks.Brewfile`, and the build fails if removed apps come back.

- **os-release PRETTY_NAME is just "Wrasse"** (no version suffix): GNOME Shell's welcome dialog after first sign-in reads "Welcome to %s" from PRETTY_NAME, so it now says "Welcome to Wrasse". The version stays in VERSION / VERSION_ID / IMAGE_VERSION; fastfetch shows `{name} {version-id}`.

- **DX sysext extraction**: `cpio -idmu` (overwrite) when unpacking RPMs. On Fedora 45 two packages ship the same man pages; cpio refused with "newer or same age version exists", the pipe closed early and the build died with SIGPIPE (exit 141) in one cell.
- **Preflight shellcheck**: silence SC2120 on the optional-argument helpers; the newer shellcheck on the runner flagged them and failed the ISO workflow before building anything.
