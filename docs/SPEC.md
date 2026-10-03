# Wrasse spec

Hard fork of Universal Blue's Bluefin: Fedora bootc desktop image, agent-first, opinionated, GNOME.
Repo `github.com/wrasse-os/Wrasse` (detached from Bluefin's fork network). Images: `ghcr.io/wrasse-os/wrasse` (lowercase).
Working rules live in `/CLAUDE.md`. Change log lives in `/DIVERGENCE.md`.

## Phase status

| Phase | Title | Status |
|---|---|---|
| 0 | Recon + spec | done |
| 1 | Base image changes | done (except `brand:`, deferred by the user) |
| 2 | CI + release lines | partial: implemented, 2 items blocked (see "Phase 2 status notes") |
| 3 | DX as a sysext | partial: implemented (downloaded on demand, not baked in), not built or booted; needs a CI run (publish) and the SELinux checklist (see "Phase 3 status notes") |
| 4 | Terminal (Zellij, multiplexer) | done (not run on hardware; see "Phase 4 status notes") |
| 5 | Claude Code integration | partial: implemented and verified where possible, gating blocked on pending decision 2 (see "Phase 5 status notes") |
| 6 | `wrasse install` (Rust CLI) | partial: implemented and unit tested, Flatpak-vs-brew policy blocked on pending decision 1 (see "Phase 6 status notes") |
| 7 | Installer + ISO | partial: implemented, no ISO built or booted; needs a CI run and a VM/hardware install (see "Phase 7 status notes") |
| 8 | Docs | done (see "Phase 8 status notes"; some content is blocked on pending decisions) |
| 9 | composefs-native (bootc composefs backend, no ostree) | todo: direction decided 2026-10-03, research and staged plan in `docs/COMPOSEFS-NATIVE.md`; only Stage 0 (installer uses composefs + systemd-boot) is in the tree and it is unproven |

## Decisions made

- Default sleep inhibitor is **Caffeine** (Lidless does not exist yet; it is on the roadmap). Caffeine stays enabled.
- `brand:` (Bluefin to Wrasse renames) is **deferred** until the user says go.
- `projectbluefin/common` is vendored in-tree; there is no `common` image dependency anymore.

## Pending decisions (stop and ask the user)

1. `wrasse install`: when a package exists in both Flatpak and brew, auto-pick or ask the user?
   *blocked (Phase 6): `--prefer flatpak|brew|ask` and `prefer` in `~/.config/wrasse/config.toml` exist; with neither set, install stops with a `policy_required` error. To decide, bake a default into `classify::resolve` (`None => ...`) in `cli/src/classify.rs`.*
2. Claude Code integration in every image, or only after `ujust dx on`?
   *blocked (Phase 5): everything ships in every image today (stub, slice, skill, link hook, oomd). To gate, make the stub, the skill-link hook and the skill itself check `ujust dx status` / the sysext, and move the files into the sysext or a conditional; nothing else depends on it.*
3. Does `reimagined` get an nvidia flavor, given akmods often lag on branched Fedora?
   *blocked (Phase 2): `.github/build-matrix.json` has `"nvidia": true` for `reimagined` only as a placeholder matching the
   spec's "6 images"; flip that one boolean to change it. Not a decision.*
4. Is `reimagined` also the channel where new Wrasse features land first?
   *blocked (Phase 2): nothing in CI depends on it; no per-line feature gating was added.*

## Repo facts (verified in Phase 0)

- Fork point: local tag `upstream-base` (`c9d08f4d`). `upstream` remote = `ublue-os/bluefin`.
- Build: `Justfile` (`build`, `build-ghcr`, `rechunk`, `verify-container`, `fedora_version`, `image_name`, ...),
  `Containerfile` (stages `umotd-build`, `uwelcome-build`, `common-build`, `brew`, `ctx`, `base`), scripts in
  `build_files/{base,dx,shared}/` run in order from `build_files/shared/build.sh`.
- (Phase 0 fact, removed in Phase 3) `IMAGE_FLAVOR=dx` ran `build_files/shared/build-dx.sh` after the initramfs step.
- Streams today: `stable` (weekly cron, also `stable-daily`), `beta` (runs on push), `latest` (PR and manual). Workflows:
  `.github/workflows/build-image-{stable,beta,latest-main}.yml` calling `reusable-build.yml`; `build-images.yml` runs all.
  `Justfile` hard-codes the three tags and picks the akmods flavor by matching the tag text.
- Pins live in `image-versions.yml` (`brew`), verified with cosign in `just verify-container`.
- akmods are pulled in `build_files/base/03-install-kernel-akmods.sh` with `skopeo copy ghcr.io/ublue-os/akmods:<flavor>-<fedora>-<kernel>`
  (mutable tag, resolved inside the build). The kernel release is looked up by tag in `Justfile` `build`. This is the TOCTOU the spec fixes.
- Origin has no branches except `main`; it carries upstream's tags (`stable-*`, `gts-*`, `v*`). No ISO tooling exists in-tree.
- Upstream's `gts`/`lts` streams are not present in the workflows or the Justfile; only stale tags remain.

## Phase 0: recon + spec

Clone, add `upstream`, fetch, tag `upstream-base`. Map the repo (Justfile, build_files, system_files, workflows,
image-versions, ujust recipes, how variants build, how akmods are pulled and verified, how ISOs are made). Write this file,
`CLAUDE.md` and `DIVERGENCE.md`. List remote branches and recommend deletions (do not delete).
Branch recommendation: origin has only `main`; keep it. Stale upstream release tags (`stable-*`, `gts-*`, `latest-41.*`,
`v*`) are not branches; leave them unless the user wants them cleaned up. Do not push `upstream-base`.

## Phase 1: base image changes

Branding (`brand:`): rename Bluefin branding to Wrasse (os-release, image names, labels, ujust text, MOTD, CI image refs).
Do NOT rename real dependencies on ublue-os infrastructure (akmods, brew, base images, COPRs, akmods signing keys).
Show branding hits vs plumbing hits before changing anything. **Deferred.**

Done: vanilla GNOME layout; extensions (enabled: Bazaar companion, Caffeine, AppIndicator, Blur My Shell; removed: Dash to Dock,
Logo Menu, Custom Command Menu, Search Light, GSConnect, Gradia; QSAP and Tiling Shell were never present); default Flatpaks;
Cockpit removed; fish default login shell; bash bling and starship removed; `playerctl`; composefs dracut config;
memory stack (zram, DAMON, sysctls, MGLRU as separate droppable commits). Verify on real hardware or CI: that
`bootc-root-setup.service` lands in the initramfs (`lsinitrd`).

Keep: uupd, ujust, Homebrew, distrobox, codecs, Bazaar (GNOME Software stays removed).

## Phase 2: CI + release lines

One git branch: `main`. All channels are image tags from a build matrix, never git branches.

Release lines:
- `reimagined` = newest Fedora branched release (never Rawhide). With no branched release it follows the newest beta or stable.
- `next` = newest Fedora beta; once that version goes stable it stays on it until the next beta.
- `stable` = newest Fedora final.
- No LTS/GTS. Remove Bluefin's gts/lts streams entirely.

GPU flavors: default (Mesa) and nvidia (open driver only, Turing+). Image names: `wrasse` and `wrasse-nvidia`. 6 images total.

- Resolve each line's Fedora version automatically in CI. Base image: `quay.io/fedora-ostree-desktops/silverblue:<version>` for all lines
  (user decision, see the Phase 2 status notes); ublue's base images do not publish branched Fedora.
- akmods security: resolve each akmods image digest once, cosign-verify it, then pull by `@sha256:` everywhere. Never
  re-resolve mutable tags inside the build (fixes the TOCTOU issue reported against projectbluefin, issue #1264).
- Fail closed: if the akmods image for a kernel/Fedora combo does not exist, or verification fails, skip pushing that
  cell's tag so users stay on the last good image. Matrix cells are independent; one failure never blocks others.
- Signing: set up cosign for the wrasse-os org. Tell the user which secrets to create; never create them.
- Remove Bluefin's dx image builds from CI (DX becomes a sysext in Phase 3).
- Pending decision 3 and 4 affect this phase: do not decide them; make the matrix config-driven so either answer is a one-line change.

File map: `.github/workflows/*`, `Justfile` (tags, `fedora_version`, `image_name`, akmods flavor/verify), `image-versions.yml`,
`build_files/base/03-install-kernel-akmods.sh`, `Containerfile` (akmods ARGs), `.github/renovate.json5`, `.github/changelogs.py`.

### Phase 2 status notes (verified against live data on 2026-10-02)

Done: `build.yml` single matrix (reimagined/next/stable x default/nvidia, images `wrasse`, `wrasse-nvidia`); Fedora versions
resolved in CI by `.github/scripts/resolve-lines.sh` (Bodhi + `releases/test/NN_Beta/`); akmods and base image resolved to digests once,
cosign-verified, built `@sha256:`; cells fail closed and are independent; gts/lts/stable-daily/dx removed from CI, Justfile and
`changelogs.py`; secrets listed in `docs/CI-SECRETS.md`; overview in `docs/CI.md`. Resolver output on that date: stable 44, beta 45, branched 45,
so next = reimagined = 45.

**Finding: ublue base images do not publish branched Fedora.** `ghcr.io/ublue-os/silverblue-main` had only tags `43`, `44` while Fedora 45 was
branched and in beta. `quay.io/fedora/fedora-silverblue` has `44`, `45`, `46` (46 is Rawhide).

**Resolved (user decision, 2026-10-03): the base is Fedora's own Silverblue bootc image for every line, not `silverblue-main`.** First tried
`quay.io/fedora/fedora-silverblue:<version>`: tags `44`, `45` (`45.20261001.n.0`) and `46`/`rawhide`, labels `containers.bootc`, `ostree.linux`,
`org.opencontainers.image.version`, but no signature (no `.sig` tag, OCI referrers or lookaside) and stale dated tags, so it was replaced by
`quay.io/fedora-ostree-desktops/silverblue:<version>` (the one ublue-os/main uses). Checked 2026-10-03: `44` = `44.20261002.0`, `45` =
`45.20261002.0` (kernel `7.2.8-300.fc45`), `46` = `rawhide` = `46.20261002.0` (Rawhide; never used); dated tags `<fedora>.<date>.<n>`, with the
floating tag equal to the newest. Cosign signatures verify for 44 and 45 with Fedora's key, vendored in `.github/keys/`. No label says alpha, beta
or stable, so classification stays with `resolve-lines.sh` (Bodhi plus `releases/test/NN_Beta/`). `just build` resolves the floating tag to a digest
once, verifies it, checks `ostree.linux` contains `.fc<version>.` and the version label starts with `<version>.`, refuses a digest equal to the
`rawhide` tag, then builds `@sha256:`. A missing tag or failed verification fails the cell closed. What `silverblue-main` added is reproduced in
`build_files/base/01-fedora-base.sh` (see `DIVERGENCE.md`). Unverified without a CI build: that script, the kernel-install stubs, and whether
negativo17 stays complete for branched Fedora (it does not: its F45 ffmpeg stack is excluded, see `docs/CI.md`, "Pre-release codecs").

Other blocked or open items:
- `reimagined` nvidia and `reimagined` as the feature-first channel: pending decisions 3 and 4 (placeholder noted above).
- Signing: images are signed with `SIGNING_SECRET`; the in-image trust policy for `ghcr.io/wrasse-os` ships (`wrasse.pub`, `policy.json`,
  `registries.d`). Unverified until a signed image is pulled with `--enforce-container-sigpolicy`.
- On-device leftovers that still mention lts/gts/testing and the Bluefin repo (`ujust changelogs`, `ujust toggle-testing`, `ublue-image-repo`
  routing in `system_files/`) were not touched: they are runtime behavior tied to `brand:` and to what the `testing` channel becomes.
- Not verified without CI: the whole workflow end to end (actionlint passes with the pre-existing `ubuntu-26.04` label ignored),
  `just build` through the Containerfile (a dry run with `PODMAN=echo` produced correct build args for F44 and F45 and refused F46/F47), and Bodhi's state for a branched release
  after the final release day (the resolver treats `current` as final).

## Phase 3: DX as a sysext

DX is NOT an image. Build `wrasse-dx.raw` (systemd-sysext, erofs) in the same CI run as each image, with an
extension-release matching that image's os-release (ID + VERSION_ID).
Contents: Docker (engine, compose, buildx), Podman extras, libvirt/QEMU, VS Code, perf tools (bcc, bpftrace, sysstat, etc.),
GNOME/GTK dev headers (mutter-devel, gjs-devel, gtk4-devel, libadwaita-devel), waydroid. See github.com/fedora-sysexts/fedora.
~~Bake it into the image at `/usr/share/wrasse/sysexts/`~~ **Superseded (user decision, 2026-10-03): DX is downloaded on demand, not baked in.**
The measured `wrasse-dx.raw` is 1.4 GB; baking it in made every user download it on every image pull and bloated the live ISO.
CI publishes it as a cosign-signed OCI artifact `ghcr.io/wrasse-os/wrasse-dx:<IMAGE_ID>-<IMAGE_VERSION>` (aliases `-<line>`, `-f<fedora>`).
`ujust dx on`: download the artifact that matches the booted image (signature checked against `wrasse.pub`), cache it under
`/var/lib/wrasse/sysexts/`, enable `wrasse-dx-select.service` (links only the matching file into `/var/lib/extensions/` before
`systemd-sysext.service`), `systemd-sysext refresh`, `systemctl daemon-reload`, enable the needed units/sockets, add the user to required
groups. `ujust dx update` fetches the match after an image update. `ujust dx off` reverses all of it.
No systemd-sysupdate anywhere (the download is skopeo plus a selector unit, not sysupdate). bootc no longer delivers the sysext, but the
match is per image: rollback finds the old image's cached file, and an image update leaves DX off until `ujust dx update`.
Flag SELinux risks: Docker and libvirt must work with SELinux enforcing after merge. Write a test checklist for the user.
File map: `build_files/dx/*`, `build_files/shared/build-dx.sh`, `system_files/dx/**` (move what is still needed into the
sysext or shared files), `Containerfile`, new `ujust` recipe (vendored `system_files/shared/usr/share/ublue-os/just/`), CI.

### Phase 3 status notes

Done (written, nothing built or booted): `build_files/dx/build-dx.sh` builds `wrasse-dx.raw` plus `wrasse-dx.extension-release` from the finished
image (`Containerfile.dx` + `build-sysext.sh`, or mkosi) and `test-sysext.sh` asserts the extension-release ID and VERSION_ID equal the image's
os-release; `build.yml` publishes it after the image with `.github/scripts/publish-dx.sh` (oras, cosign, skopeo read-back); `ujust dx
on|off [purge]|update|status` in `60-custom.just` with the root helper `/usr/libexec/wrasse-dx`, `wrasse-dx-select` and `wrasse-dx-select.service`;
the old image path and `system_files/dx` are gone; `docs/DX-SELINUX-CHECKLIST.md` is the test list for you; the job summary prints the size.
No systemd-sysupdate anywhere. Flow and tags: `docs/DX-SYSEXT.md`.

**Decision record (2026-10-03):** DX on demand instead of baked in, because of the 1.4 GB. Consequences: the image and the live ISO shrink by that
much (nothing in `installer/` or `build-iso.yml` referenced the file); the first `dx on` and every `dx update` need network; an image update disables
DX until `dx update` (or `dx update` before the reboot, which also fetches the staged image's sysext); a DX build or publish failure in CI leaves the
image published and DX unavailable for that build, reported as a red cell, an error annotation and a summary; the package `wrasse-dx` must be made
public once (`docs/CI-SECRETS.md`). Kernel, FUSE and the rest of the image are unaffected.

Findings and choices (verified against github.com/fedora-sysexts/fedora and the Fedora repos on 2026-10-02):
- fedora-sysexts writes `ID="_any"` into extension-release because pinning `ID=fedora` breaks Universal Blue images (this image's ID is
  `bluefin`, becoming `wrasse` under `brand:`). The spec asks for ID + VERSION_ID matching, so the build copies the image's real
  `ID` and `VERSION_ID`; the brand rename needs no change here because the build reads os-release.
- Docker comes from Fedora (`moby-engine`, `docker-compose`, `docker-buildx`), not docker-ce, so no Docker Inc repo has to track
  branched Fedora. If you want docker-ce back, only `PACKAGES` and a repo file in `build-sysext.sh` change.
- Not in the spec list, so dropped: Incus/LXC, ROCm, android-tools, the vfio dracut file (cannot live in a sysext). See `DIVERGENCE.md`.
- Final size is unknown without a build. The first CI run prints it per cell in the job summary.
- (Obsolete after the on-demand decision: the bootc chunked-layer question no longer applies; the image has no sysext layer.)
- Open risks needing real hardware: sysext merge on composefs root, build-time SELinux labels (`mkfs.erofs --file-contexts`),
  `restorecon`-clean state after merge, Docker and libvirt under enforcing, waydroid kernel support (binder).
- `ujust devmode` (brew based dev tools) and `system-dx-flatpaks.Brewfile` were not touched; they are a separate user-space path.
- Pending decision 2 (Claude Code in every image or only after `ujust dx on`) is not decided here; Phase 5 owns it.

## Phase 4: terminal

Zellij as a default brew package, installed on first login (follow Bluefin's existing brew first-login mechanism,
`homebrew/preinstall.d/` and `usr/libexec/brew-preinstall`).
`ujust multiplexer zellij|none`: sets Ptyxis's profile custom command to launch zellij; `none` reverts it. Do NOT auto-start
zellij from fish config (it would hijack VS Code terminals and SSH). Verify the actual Ptyxis gsettings keys.

### Phase 4 status notes

- Zellij added to `preinstall.d/system-cli.Brewfile`; `brew-preinstall` needed no change.
- Reality differs from the spec's UUID assumption: the vendored dconf palette file pins profile
  `2871e8027773ae74d6c87a5f659bbc74`, but Ptyxis generates its own default profile UUID (`org.gnome.Ptyxis default-profile-uuid`).
  `ujust multiplexer` reads that key instead of hardcoding. The vendored palette entry may therefore never apply to real profiles;
  not touched here (outside Phase 4).
- Verified keys: `org.gnome.Ptyxis.Profile` `use-custom-command` (b) and `custom-command` (s), against ptyxis 50.1's installed schema.
- Needs real hardware: confirm Ptyxis honours the custom command for new tabs and that `none` restores the shell.

## Phase 5: Claude Code integration (Claude Code only, done properly)

- System skill at `/usr/share/wrasse/skills/wrasse/SKILL.md`, symlinked into `~/.claude/skills/` and `~/.agents/skills/` on
  first login (user tmpfiles or a systemd user oneshot). It teaches Wrasse's rules: read-only root, never `sudo dnf install`;
  use `wrasse install` (Phase 6), Flatpak for GUI apps, brew for CLIs, distrobox for anything needing a mutable distro, ujust
  for system tasks; `bootc status`/`bootc upgrade`, not rpm-ostree; where the memory tuning lives; how DX works. Check
  Anthropic's current docs for skill format.
- Lazy stub: `/usr/bin/claude` execs the real binary in `~/.local/bin` if present; otherwise it explains, asks for
  confirmation, and runs Anthropic's official native installer (get the current method from Anthropic's docs; do not
  hardcode from memory). Verify PATH order in fish and bash so the real binary wins after install.
- Agent memory slice: systemd user slice `wrasse-agents.slice` with `MemoryHigh` set and `ManagedOOMMemoryPressure=kill`, so
  systemd-oomd kills the agent instead of freezing the desktop. The stub launches Claude Code inside it
  (`systemd-run --user --scope --slice=wrasse-agents.slice`). Propose limits and explain the reasoning.
- Hard rule: agents launch in their normal permission modes. Nothing auto-approves by default. No default-agent keybinding
  (clashes with multiplexers). Lidless hooks, a usage panel, and crash-dump-to-agent are parked.
- Pending decision 2 (every image vs only after `ujust dx on`) is open: ship the files in the image but do not decide the gating; mark `blocked` what depends on it.

### Phase 5 status notes

Done (written; image not built or booted): skill `/usr/share/wrasse/skills/wrasse/SKILL.md` (uses `wrasse install`, `--json`, exit code 3 and
`policy_required`), user-setup hook `30-wrasse-agent-skill.sh` linking it into `~/.claude/skills/wrasse` and `~/.agents/skills/wrasse` once;
lazy `/usr/bin/claude` stub (exec `~/.local/bin/claude` in `wrasse-agents.slice`, else explain, ask `[y/N]`, run the official installer);
`wrasse-agents.slice` (+ `.d/20-oomd.conf`) with limits explained in `docs/AGENT-SLICE.md`; `systemd-oomd` enabled and tested in the build;
PATH snippets for bash and fish; build checks. Nothing auto-approves, no keybinding, no flags are passed to Claude Code.

Findings (verified on a Fedora 44 host and against code.claude.com/docs on 2026-10-03):
- Skill format: `~/.claude/skills/<name>/SKILL.md`, frontmatter fields all optional (`name`, `description`, ...), symlinked skill directories are
  followed. The docs do not mention `~/.agents/skills`; the link is kept because the spec asks for it.
- Official installer: `curl -fsSL https://claude.ai/install.sh | bash` (also `| bash -s stable|<version>`). Installs the launcher at
  `~/.local/bin/claude` (symlink into `~/.local/share/claude/versions/`), auto-updates in the background. Docs also list signed dnf/apt/apk
  repos, not usable on an immutable root. The stub downloads to a temp file first, then runs it.
- systemd: `MemoryHigh=` accepts a percentage of RAM. `systemd-oomd` ships in `systemd-udev` on F44 and Fedora's preset already enables it;
  the build now enables it explicitly. **Fedora's `user/slice.d/10-oomd-per-slice-defaults.conf` (80% pressure) overrides a limit set in the slice
  file itself**, so ours is in a `.d` drop-in. A dash in the slice name nests it under an implicit `wrasse.slice`.
- PATH: fish adds nothing for `~/.local/bin` by default; bash only through `/etc/skel/.bashrc` (new users). Hence the two `wrasse-path` files.
  zsh not touched.

Blocked: gating (pending decision 2), see above.

Needs real hardware or CI: image build with the new files (exec bits through `rsync -rvK`), the first-login hook on a real session, the installer end to end
(not run: it downloads and installs software), an actual oomd kill under memory pressure (test command in `docs/AGENT-SLICE.md`).

## Phase 6: `wrasse install` (Rust CLI)

A router, not a package manager. Each backend does its own real work.
- `wrasse install <pkg>`: GUI app -> Flatpak, CLI -> brew. `--from <distro>` -> distrobox. `wrasse install --dx` runs the DX toggle.
- `wrasse remove`, `wrasse list`, `wrasse search`.
- Every install/remove is recorded in `~/.config/wrasse/packages.toml`. `wrasse sync` rebuilds the user's setup on a fresh
  machine across all backends.
- `--json` output on every command for agents. Update the system skill so agents use `wrasse install`.
- Single static-ish binary, shipped in the image. Include tests.
- Pending decision 1 (Flatpak vs brew when both exist): do not pick; implement a policy flag with no default chosen by you, mark `blocked`.

### Phase 6 status notes

Done: `cli/` crate (`wrasse`, deps clap/serde/serde_json/toml, own `[workspace]`). Commands `install`, `remove`, `list`, `search`, `sync`,
`--json` and `--dry-run` on all; `install --dx` / `remove --dx` call `ujust dx on|off`; `install --from <distro>` uses distrobox
(container `wrasse-<distro>`; fedora, ubuntu, debian, arch, alpine, opensuse, or a full image ref). Manifest `~/.config/wrasse/packages.toml`
(honours `WRASSE_CONFIG_DIR`, `XDG_CONFIG_HOME`). Backends are plain functions over a `Runner` with real, dry-run and fake modes. 41 tests
(25 unit, 16 end to end with the fake runner), `cargo clippy --all-targets -D warnings` clean. Containerfile stage `wrasse-build`
(`rust:alpine` by digest, musl, `--locked`) copies the binary to `/usr/bin/wrasse`. Flag spellings were checked against the local
`flatpak`, `brew`, `distrobox` help output; read-only lookups and `--dry-run` were smoke-tested against the real tools.

Blocked: Flatpak-vs-brew policy (pending decision 1). No default is baked in; see the note under that decision.

Open or not verified:
- The image build was not run, so the musl static binary and the `/usr/bin/wrasse` path are unconfirmed until CI. A package in both
  Flatpak and brew was only exercised with the fake runner.
- Real installs, removals, `sync` and the DX toggle were not run against real backends (they change the machine).
- Flatpak installs go to the user installation (`--user`, with a user `flathub` remote added if missing), because the manifest is per user and
  needs no pkexec. Apps already installed system-wide are not seen by `sync` or removed by `wrasse remove`.
- Flathub currently lists some apps under two IDs that differ only by case (for example `org.mozilla.firefox` and `org.mozilla.Firefox`,
  `org.videolan.vlc` and `org.videolan.VLC`). wrasse reports that as ambiguous and asks for the exact ID rather than guessing.
- Brew casks are ignored (they are macOS only); only formulae are routed. Distrobox packages are not exported to the host menu.
- The system skill now exists (Phase 5) and teaches `wrasse install`, `--json`, exit code 3 and the `policy_required` error.
- Exit codes: 0 ok, 1 error or partial `sync` failure, 3 when a policy is required (or `ask` has no terminal).

## Phase 7: installer + ISO

Use `projectbluefin/bootc-installer` (Libadwaita fork of the Vanilla OS installer). Pin a specific version in the ISO
build; never pull latest. Configure it via its drop-in catalog/recipe directory (verify the current path; it was
`/etc/tuna-installer/` before the project moved).
Flow: autodetect the GPU (NVIDIA Turing+ -> preselect `wrasse-nvidia`; AMD/Intel/older NVIDIA -> `wrasse`, with an override),
then ask the release line (Reimagined / Next / Stable), then the usual disk/user steps.
Build live ISOs using Bluefin's existing ISO tooling, adapted (none exists in this repo: report what upstream uses, e.g.
`ublue-os/titanoboa`, and what you adapted). Report what changed.

### Phase 7 status notes (verified against live repos on 2026-10-03)

Done: `installer/gpu-detect` (Rust, 15 tests), `installer/gen-catalog.sh`, the `wrasse` ISO variant in `installer/iso/variant/wrasse/`,
pins in `installer/iso/pin.env`, and `.github/workflows/build-iso.yml` (`workflow_dispatch` only). Nothing was built. Detail in
`installer/README.md` and `DIVERGENCE.md`.

Findings where reality differs from this spec:
- **`projectbluefin/bootc-installer` is archived** (last push 2026-09-07). The live upstream is `tuna-os/bootc-installer` (same code, the
  README still says "hard fork of the Vanilla OS installer"). Pinned: `v2026.09.26-253d6938`, bundle sha256 recorded. Note the other
  rename: `/etc/tuna-installer/` is now `/etc/bootc-installer/` (verified in that repo's README and code: `images.json` catalog,
  `recipe.json` sys-recipe, `live-iso-mode` flag, `$XDG_CONFIG_HOME/bootc-installer/images.json`).
- **Bluefin's live ISO tooling is `projectbluefin/dakota-iso`**, not `ublue-os/titanoboa` (last push 2026-06-18, no installer, GRUB
  `iso.yaml` contract). dakota-iso retired its own bluefin variants (#228) but the scripts still handle them. Adapted, pinned to commit
  `9c123eea`.
- **The installer removes its image step in live-ISO mode**, and the image step is where "ask the release line" lives. So the flow in this
  spec (GPU preselect, then release line, then disk/user) only exists in a network-install ISO: no `live-iso-mode` flag, no `local_imgref`,
  no embedded payload. That is what was built. An offline ISO would have to embed one image and could not ask the line.
- **The installer's own NVIDIA logic is vendor-only and has no override** (`Systeminfo.has_nvidia_gpu`, any NVIDIA incl. Pascal; it also installs
  the `nvidia_imgref` and tracks the base). Not used. Wrasse's catalog is generated per detected flavor (`gen-catalog.sh <flavor>`): the image step lists only the release lines, with the
  detected flavor baked into each imgref, plus one "Use different graphics drivers" group for the other flavor. `wrasse-gpu-detect`
  chooses the flavor with Turing+ from NVIDIA's open-module device list.

Blocked or left open (not decided here):
- *blocked (pending decision 3):* a `wrasse-nvidia:reimagined` image is offered only because `build-matrix.json` says `"nvidia": true`
  for `reimagined`; flip that boolean and that line falls back to `wrasse` on NVIDIA hardware and drops out of the escape group (tested). No other change.
- *blocked (pending decision 4):* the preselected line is hardcoded to `stable` in `installer/gen-catalog.sh` (`default_image`). This is a
  default, not the decision; change it there if `reimagined` should be the feature-first default.
- *blocked (Phase 2 signing and base images):* the ISO needs `ghcr.io/wrasse-os/wrasse-nvidia:<tag>` to exist and be pullable; the signing key is not set up and no wrasse image has been built from the Fedora base yet. The in-image `policy.json` covers only
  `ghcr.io/ublue-os`, which matters for installing from `ghcr.io/wrasse-os` (the installer/fisherman path was not checked for signature policy).
- Unverified (needs a CI run, then a VM with UEFI and a real NVIDIA machine): that dakota-iso's `build-live-squashfs.sh` works without
  `--oci-image`; that `systemctl enable` and the unit's `ConditionPathExists=/run/initramfs/live` hold in the live container; that the image
  step opens with the detected group expanded; that fisherman network-installs a Fedora ostree image with `grub2`/`btrfs`/`composefs: false` (copied
  from the Bluefin catalog entry, not confirmed against Wrasse's image); Secure Boot (the live ESP the tooling builds is systemd-boot, so
  Secure Boot likely must be off to boot the ISO, as for dakota-iso's Utah builds; MOK enrollment is Phase 8 docs).
- The ISO volume label stays `DAKOTA_LIVE` (hardcoded upstream).

## Phase 8: docs

README, install guide (GPU table, Secure Boot MOK enrollment for NVIDIA with the ublue key, release line explanation),
ujust reference, `wrasse install` docs, and `DIVERGENCE.md` cleanup.

### Phase 8 status notes

Done: `README.md` rewritten (Bluefin branding stated as unrenamed), `docs/INSTALL.md`, `docs/UJUST.md`, `docs/WRASSE-INSTALL.md`, `AGENTS.md`
reduced to a pointer, `DIVERGENCE.md` regrouped by area.

Findings:
- Secure Boot: the `ujust enroll-secure-boot-key` recipe imports `/etc/pki/akmods/certs/akmods-ublue.der` with password `universalblue`.
  `ublue-os/akmods` `certs/` has two keys (`public_key.der` "ublue kernel", `public_key_2.der` "ublue akmods"; dual signing since 2024); upstream docs
  name only `public_key.der`. Which one the on-device file equals was not verified. Not tested on hardware.
- `ujust toggle-testing` is stale for Wrasse (knows only stable/latest/lts tags). Documented in `docs/UJUST.md`, not changed (outside Phase 8).

*blocked (pending decision 1):* `docs/WRASSE-INSTALL.md` documents the `policy_required` behaviour; update it when a default is chosen.
*blocked (pending decision 2):* docs say Claude Code ships in every image; update if gated behind `ujust dx on`.
*blocked (pending decisions 3 and 4):* `docs/INSTALL.md` says the `reimagined` NVIDIA image and its status as the feature-first line are open.
*blocked (`brand:`):* README, INSTALL and UJUST keep Bluefin names where unrenamed and must be revisited when `brand:` runs.

## Phase 9: composefs-native

Direction (maintainer decision, 2026-10-03): adopt bootc's composefs backend and drop ostree (no `ostree-prepare-root`, no ostree repo or deployments, no `rpm-ostree`).
Full feasibility assessment, file-by-file impact, ranked risks, staged plan and a VM checklist: **`docs/COMPOSEFS-NATIVE.md`**. Status: `todo`.

Summary of the findings (all sourced in that document):
- The composefs backend is **experimental** in bootc 1.16.x (1.16.13 is in Fedora 44); a working precedent builds sealed Silverblue from the official ostree Silverblue image (`travier/fedora-atomic-desktops-sealed`).
- No ostree to composefs migration exists; every install must be redone. `bootc` itself still links libostree.
- No Fedora-signed systemd-boot or UKI exists (F44 ships `systemd-boot-unsigned`); Wrasse must sign both and users must enroll a Wrasse MOK in addition to the ublue akmods key.
- A sealed UKI freezes the kernel command line: `wrasse.safe=1` at the boot menu cannot work with Secure Boot on (systemd-stub ignores cmdline overrides). Replacement candidates in section 5.3.
- No boot counting for composefs.

Stages (each stops for the user): 0 installer uses composefs + systemd-boot (landed, unproven) / 1 experimental `composefs` image line, unsealed / 2 ujust, CLI, uupd audit / 3 UKI in a VM, Secure Boot off / 4 signing and MOK / 5 installer and ISO scratch disk / 6 safe-mode replacement and sysext on sealed / 7 promote line by line.

*blocked (pending decisions, to ask the user; see section 9 of the doc):* Secure Boot trust model and key custody; abandoning existing installs (no migration); an experimental `composefs` image line on `ghcr.io/wrasse-os`; safe-mode UX; DX on sealed images.
First experiment (no rebuild): composefs install of the current image in the virt-manager VM, UEFI, Secure Boot off (doc section 8, E1).
