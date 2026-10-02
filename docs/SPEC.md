# Wrasse spec

Hard fork of Universal Blue's Bluefin: Fedora bootc desktop image, agent-first, opinionated, GNOME.
Repo `github.com/wrasse-os/Wrasse` (detached from Bluefin's fork network). Images: `ghcr.io/wrasse-os/wrasse` (lowercase).
Working rules live in `/CLAUDE.md`. Change log lives in `/DIVERGENCE.md`.

## Phase status

| Phase | Title | Status |
|---|---|---|
| 0 | Recon + spec | in progress |
| 1 | Base image changes | done (except `brand:`, deferred by the user) |
| 2 | CI + release lines | partial: implemented, 3 items blocked (see "Phase 2 status notes") |
| 3 | DX as a sysext | todo |
| 4 | Terminal (Zellij, multiplexer) | todo |
| 5 | Claude Code integration | todo |
| 6 | `wrasse install` (Rust CLI) | todo |
| 7 | Installer + ISO | todo |
| 8 | Docs | todo |

## Decisions made

- Default sleep inhibitor is **Caffeine** (Lidless does not exist yet; it is on the roadmap). Caffeine stays enabled.
- `brand:` (Bluefin to Wrasse renames) is **deferred** until the user says go.
- `projectbluefin/common` is vendored in-tree; there is no `common` image dependency anymore.

## Pending decisions (stop and ask the user)

1. `wrasse install`: when a package exists in both Flatpak and brew, auto-pick or ask the user?
2. Claude Code integration in every image, or only after `ujust dx on`?
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
- `IMAGE_FLAVOR=dx` runs `build_files/shared/build-dx.sh` after the initramfs step. Flavors in CI: `main`, `nvidia-open`.
- Streams today: `stable` (weekly cron, also `stable-daily`), `beta` (runs on push), `latest` (PR and manual). Workflows:
  `.github/workflows/build-image-{stable,beta,latest-main}.yml` calling `reusable-build.yml`; `build-images.yml` runs all.
  `Justfile` hard-codes the three tags and picks the akmods flavor by matching the tag text.
- Pins live in `image-versions.yml` (base `silverblue-main-43/44`, `brew`), verified with cosign in `just verify-container`.
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

- Resolve each line's Fedora version automatically in CI. Check whether ublue's base images publish tags during branched; if
  they do not, report options (e.g. building `reimagined` FROM `quay.io/fedora/fedora-silverblue`) instead of guessing.
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

**Finding: ublue base images do not publish branched Fedora.** `ghcr.io/ublue-os/silverblue-main` has only tags `43`, `44` (and `latest`) while
Fedora 45 is branched and in beta; `ghcr.io/ublue-os/base-main` only `latest`, `gts`, `43`, `44`. `ghcr.io/ublue-os/akmods` and
`akmods-nvidia-open` do publish `main-45-*` (kernel 7.2.8-300.fc45). `quay.io/fedora/fedora-silverblue` has `44`, `45`, `46`
(46 is Rawhide), so a branched base exists upstream. Consequence: today the `reimagined` and `next` cells (both F45) fail closed at
"base image does not exist" and keep their last tag; `stable` (F44) builds. Options (user decides, not made):
1. Wait for ublue to publish `silverblue-main:45` (it will likely appear at or after the final release). Nothing to change.
2. Build `reimagined`/`next` `FROM quay.io/fedora/fedora-silverblue:<ver>` while ublue has no base, losing whatever
   `silverblue-main` adds (ublue repo/policy/service tweaks), which would have to be reproduced in `build_files`.
3. Keep both lines on the newest version ublue publishes until then (breaks the "newest branched" rule).
Status: `blocked` on this choice. The resolver and matrix need no change for any of them; only the base image reference in
`just build` (and a per-line base setting in `.github/build-matrix.json` if option 2) would.

Other blocked or open items:
- `reimagined` nvidia and `reimagined` as the feature-first channel: pending decisions 3 and 4 (placeholder noted above).
- Signing: images are signed with `SIGNING_SECRET`, but the in-image trust policy only covers `ghcr.io/ublue-os` (`policy.json`,
  `registries.d`, `ublue-os.pub`), and `/cosign.pub` is still Bluefin's. Needs the user's key; steps in `docs/CI-SECRETS.md`.
- On-device leftovers that still mention lts/gts/testing and the Bluefin repo (`ujust changelogs`, `ujust toggle-testing`, `ublue-image-repo`
  routing in `system_files/`) were not touched: they are runtime behavior tied to `brand:` and to what the `testing` channel becomes.
- Not verified without CI: the whole workflow end to end (actionlint passes with the pre-existing `ubuntu-26.04` label ignored),
  `just build` through the Containerfile (a dry run with `PODMAN=echo` produced correct build args), and Bodhi's state for a branched release
  after the final release day (the resolver treats `current` as final).

## Phase 3: DX as a sysext

DX is NOT an image. Build `wrasse-dx.raw` (systemd-sysext, erofs) in the same CI run as each image, with an
extension-release matching that image's os-release (ID + VERSION_ID).
Contents: Docker (engine, compose, buildx), Podman extras, libvirt/QEMU, VS Code, perf tools (bcc, bpftrace, sysstat, etc.),
GNOME/GTK dev headers (mutter-devel, gjs-devel, gtk4-devel, libadwaita-devel), waydroid. See github.com/fedora-sysexts/fedora.
Bake it into the image at `/usr/share/wrasse/sysexts/` (NOT an auto-load path), in its own late Containerfile layer so
bootc's chunked pulls only redownload it when DX changes. Report the final size.
`ujust dx on`: symlink into `/etc/extensions/`, `systemd-sysext refresh`, `systemctl daemon-reload`, enable the needed
units/sockets, add the user to required groups. `ujust dx off` reverses all of it.
No systemd-sysupdate anywhere. bootc delivers the sysext with the image, so rollback rolls it back too.
Flag SELinux risks: Docker and libvirt must work with SELinux enforcing after merge. Write a test checklist for the user.
File map: `build_files/dx/*`, `build_files/shared/build-dx.sh`, `system_files/dx/**` (move what is still needed into the
sysext or shared files), `Containerfile`, new `ujust` recipe (vendored `system_files/shared/usr/share/ublue-os/just/`), CI.

## Phase 4: terminal

Zellij as a default brew package, installed on first login (follow Bluefin's existing brew first-login mechanism,
`homebrew/preinstall.d/` and `usr/libexec/brew-preinstall`).
`ujust multiplexer zellij|none`: sets Ptyxis's profile custom command to launch zellij; `none` reverts it. Do NOT auto-start
zellij from fish config (it would hijack VS Code terminals and SSH). Verify the actual Ptyxis gsettings keys.

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

## Phase 6: `wrasse install` (Rust CLI)

A router, not a package manager. Each backend does its own real work.
- `wrasse install <pkg>`: GUI app -> Flatpak, CLI -> brew. `--from <distro>` -> distrobox. `wrasse install --dx` runs the DX toggle.
- `wrasse remove`, `wrasse list`, `wrasse search`.
- Every install/remove is recorded in `~/.config/wrasse/packages.toml`. `wrasse sync` rebuilds the user's setup on a fresh
  machine across all backends.
- `--json` output on every command for agents. Update the system skill so agents use `wrasse install`.
- Single static-ish binary, shipped in the image. Include tests.
- Pending decision 1 (Flatpak vs brew when both exist): do not pick; implement a policy flag with no default chosen by you, mark `blocked`.

## Phase 7: installer + ISO

Use `projectbluefin/bootc-installer` (Libadwaita fork of the Vanilla OS installer). Pin a specific version in the ISO
build; never pull latest. Configure it via its drop-in catalog/recipe directory (verify the current path; it was
`/etc/tuna-installer/` before the project moved).
Flow: autodetect the GPU (NVIDIA Turing+ -> preselect `wrasse-nvidia`; AMD/Intel/older NVIDIA -> `wrasse`, with an override),
then ask the release line (Reimagined / Next / Stable), then the usual disk/user steps.
Build live ISOs using Bluefin's existing ISO tooling, adapted (none exists in this repo: report what upstream uses, e.g.
`ublue-os/titanoboa`, and what you adapted). Report what changed.

## Phase 8: docs

README, install guide (GPU table, Secure Boot MOK enrollment for NVIDIA with the ublue key, release line explanation),
ujust reference, `wrasse install` docs, and `DIVERGENCE.md` cleanup.
