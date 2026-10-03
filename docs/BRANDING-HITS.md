# Branding hits (Bluefin to Wrasse)

Snapshot taken before any `brand:` change. Command:
`rg -i bluefin -g '!.git' -g '!DIVERGENCE.md' -g '!THEPATTERN.md'`, skipping `installer/`, `docs/INSTALL.md`,
`docs/SPEC.md` (another agent owns those; their hits are in the hand-off report, not here). 226 text lines plus 68 tracked
paths contain "bluefin". Every one is classified below. The "Result" column says what the `brand:` series did.

Categories: BRANDING (rename), PLUMBING (real dependency on ublue-os / projectbluefin infrastructure, keep),
TELEMETRY (reports to Bluefin servers, remove), ARTWORK (Bluefin imagery, never fabricate Wrasse art), UNCLEAR (maintainer decides).

## BRANDING (rename or reword)

| Where | What | Result |
| --- | --- | --- |
| `build_files/base/00-image-info.sh` | `IMAGE_PRETTY_NAME="Bluefin"`, `HOME_URL`, `DOCUMENTATION_URL`, `SUPPORT_URL`, `BUG_SUPPORT_URL` (ublue-os/bluefin), `CODE_NAME`, `CPE_NAME` (`universal-blue`), `DEFAULT_HOSTNAME` and `ID` (derived from the pretty name) | os-release commit |
| `Justfile` 215-225, 329-337 | `org.opencontainers.image.source/url/description`, `io.artifacthub.*` readme-url, keywords, maintainers | image/labels commit |
| `artifacthub-repo.yml` | Bluefin's Artifact Hub repository id and Jorge Castro as owner | deleted |
| `system_files/.../just/60-bonedigger.just`, `libexec/bonedigger-report` (brand strings, Discussions URL, issue repo) | "Bluefin Bug Report", "Bluefin Feature Request", ublue-os/bluefin/discussions | ujust/links commit |
| `libexec/ublue-image-repo`, `just/changelog.just` | maps image names to `projectbluefin/*` repos | points at `wrasse-os/Wrasse` |
| `just/system.just` 27, 179, 349, 360, 371 | `~/.config/bluefin` dev-mode marker, `bluefin-apps` recipe, Bazaar curation paths | file/recipe renames |
| `just/default.just` 2, `just/shared.just` 2-3 (comments), `just/00-entry.just` 6 (docs.projectbluefin.io link) | text and a link to Bluefin docs | reworded; link removed |
| `etc/uwelcome/config.json` | `issues.projectbluefin.io`, "Ask Bluefin" (`ask.projectbluefin.io`), `docs.projectbluefin.io` | links to wrasse-os/Wrasse; "Ask" removed |
| `usr/share/chairlift/config.yml` | comments, website/issues/chat links to projectbluefin.io | links to wrasse-os/Wrasse, chat removed |
| `usr/share/applications/documentation.desktop`, `discourse.desktop`, `system-update.desktop`, `bluefin-help.desktop`, `io.projectbluefin.chairlift.desktop` (Comment/Keywords) | "Bluefin documentation", "Bluefin Discussions", "Update Bluefin...", "Bluefin Help" | reworded; desktop-id of the vendored ChairLift app is PLUMBING |
| `build_files/base/05-override-install.sh` 13-16 | downloads Bluefin's offline docs PDF (`ublue-os/bluefin-docs`) | removed, `documentation.desktop` opens the repo docs |
| `etc/ublue-os/tags.json`, `etc/ublue-os/fastfetch.json` (logo dir), `etc/profile.d/91-bluefin-aliases.sh` | tag, logo directory, file name and header | tags changed; logo dir rename see ARTWORK |
| `etc/dconf/db/distro.d/01-bluefin-folders`, `02-bluefin-keybindings`, `03-bluefin-ptyxis-palette`, `locks/01-bluefin-locked-settings` | file names only | git mv |
| `usr/lib/systemd/system/uupd.service.d/10-bluefin.conf` | file name | git mv |
| `usr/share/pipewire/pipewire-pulse.conf.d/50-bluefin-bt-switch.conf` | file name | git mv |
| `usr/lib/systemd/user/bluefin-dynamic-wallpaper.{service,timer}`, `usr/libexec/bluefin-dynamic-wallpaper`, `user-setup.hooks.d/20-dynamic-wallpaper.sh`, `libexec/get-geoclue-latitude` 65 | unit, script and dconf-key names | git mv, references fixed |
| `usr/share/glib-2.0/schemas/zz0-bluefin-modifications.gschema.override`, `zz1-bluefin-extensions.gschema.override` | file names and `picture-uri` paths | git mv, paths follow the wallpaper directory |
| `build_files/base/05-override-install.sh` 20, 24-27, 39-40 | references to the schema override and the `faces/bluefin` directory | follow the renames |
| `usr/share/ublue-os/user-setup.hooks.d/25-damask-setup.sh` 25 | slideshow folder `backgrounds/bluefin` | follows the wallpaper directory |
| `usr/share/ublue-os/homebrew/system-flatpaks.Brewfile`, `system-dx-flatpaks.Brewfile`, `full-desktop.Brewfile`, `goose/config.yaml` | comments "for Bluefin" | reworded |
| `usr/libexec/brew-preinstall` 181, `bootc-update-stage` 11 | comments | reworded |
| `etc/security/pwquality.conf.d/10-pwquality.conf` 3 | comment "used by Bluefin and Utah" | reworded |
| `etc/bazaar/curated.yaml` 11-14 | "Bluefin Recommends" banner titles (en, id, pl) | "Wrasse Recommends" (en); translations dropped |
| `etc/bazaar/*-bluefin-{day,night}.jxl` and their `curated.yaml` URIs | banner file names | see ARTWORK |
| `Containerfile` 87-89, 164, 168 | stage/dir `/out/bluefin`, "bluefin image section" | renamed |
| `README.md`, `CONTRIBUTING.md`, `AGENTS.md`, `CLAUDE.md` 24, `docs/UJUST.md`, `.github/*` | prose, templates, links, CODEOWNERS, FUNDING | GitHub meta/README commit |
| `.github/changelogs.py` 32, 37, 70; `.github/ISSUE_TEMPLATE/config.yml`, `bug-report.yml`; `.github/pull_request_template.md` | "Bluefin Images" section title, ublue-os/bluefin commit links, ask/community/docs links | reworded, relinked |
| `usr/lib/systemd/system/flatpak-appstream-refresh.service` 3 | `Documentation=https://docs.projectbluefin.io` | relinked |
| `cli/` | no hits | |

## PLUMBING (real dependencies, kept)

| Where | What |
| --- | --- |
| `Containerfile` 10, 17 | `projectbluefin/umotd` and `projectbluefin/uwelcome` source repos, pinned by commit (they build the MOTD tools) |
| `Containerfile` 31 | `ghcr.io/ublue-os/bluefin-wallpapers-gnome` image (source of the wallpapers; the image name is upstream's) |
| `Containerfile` 57-60, 71-84 | `projectbluefin/chairlift` release download and cosign identity; `io.projectbluefin.chairlift.*` policy and gschema files from that release |
| `usr/share/polkit-1/actions/io.projectbluefin.chairlift.bootc.policy` | polkit action ids and `exec.path` for the ChairLift app, whose app id is `io.projectbluefin.chairlift` (`vendor` text is branding and is reworded) |
| `usr/share/applications/io.projectbluefin.chairlift.desktop`, `icons/hicolor/*/apps/io.projectbluefin.chairlift*.svg` | app id of the vendored ChairLift flatpak/cask; renaming breaks the app. The symbolic icon is also Bluefin's raptor mark (ARTWORK) |
| `libexec/bootc-update-stage` 3-5 | names the ChairLift polkit action id |
| `usr/share/ublue-os/homebrew/artwork.Brewfile` | casks `ublue-os/tap/bluefin-wallpapers` and `-extra` (optional extra wallpapers from the upstream tap) |
| `usr/share/ublue-os/just/shared.just` 16-17, 42, 53, 64 | `ghcr.io/projectbluefin/contribute` image, Hive hub endpoint, `ublue-os`-style verification of `ghcr.io/projectbluefin/*` (the `ujust contribute` recipe consumes upstream infrastructure) |
| `usr/share/ublue-os/just/apps.just` 18, 59 | `projectbluefin/common#1170` issue references in comments |
| `libexec/bonedigger-report` comments (98-163, 270, 567, 618) | upstream issue references in comments |
| `usr/lib/systemd/system/rechunker-group-fix.service` 10-24 | upstream issue links in comments |
| `docs/CI-SECRETS.md` 32-33, `docs/COMPOSEFS-NATIVE.md` | historical references to upstream issues and file names |
| `Justfile`, `build_files` (ublue-os/brew, legacy-rechunk, akmods, COPRs, `ublue-os-*` packages), `/usr/share/ublue-os/*` paths, `ublue-*` scripts, `etc/containers/registries.d/ublue-os.yaml`, `usr/lib/pki/containers/ublue-os*.pub` | do not contain "bluefin"; listed because the rule says keep them |
| `.github/workflows/*` `ublue-os/remove-unwanted-software` | third-party Action |
| `DIVERGENCE.md`, `AGENTS.md` 3-10, `README.md` fork note, `CLAUDE.md` 3-14 | upstream attribution (kept on purpose) |

## TELEMETRY / EXTERNAL SERVICE

| Where | What | Result |
| --- | --- | --- |
| `usr/libexec/projectbluefin-countme`, `usr/lib/systemd/system/projectbluefin-countme.{service,timer}`, `system-preset/03-projectbluefin-countme.preset`, `timers.target.wants/projectbluefin-countme.timer` | daily "active system" ping (image name, flavor, tag) to `countme.projectbluefin.io`. Gated to `dakota*` and `utah*` image names so it does nothing for `wrasse`, but the code and an enabled timer still ship | removed in a separate `remove:` commit |
| `build_files/base/00-image-info.sh` 66 | at build time downloads `ublue-os/countme` badge JSON (Bluefin weekly user count) for `fastfetch` | removed; `fastfetch.jsonc` line showing it removed with it |
| `build_files/base/17-cleanup.sh` 15, `20-tests.sh` 152 (`rpm-ostree-countme`) | Fedora's own countme, not Bluefin's. Reports to Fedora mirrors | not changed; UNCLEAR whether to disable (maintainer) |

## ARTWORK (Bluefin imagery; no Wrasse replacement exists)

Nothing here was redrawn or fabricated. Files are renamed only where the rename is safe. The pixels stay Bluefin's until real
Wrasse art exists.

| Where | What | Result |
| --- | --- | --- |
| `usr/share/ublue-os/bluefin-logos/{bluefin,chicken,dolly,karl}.png`, `sixels/*`, `symbols/*` | Bluefin dolphin mark and mascots used by `fastfetch` (`etc/ublue-os/fastfetch.json`) | directory renamed to `wrasse-logos` (`git mv`); `bluefin.png/sixels/symbols` renamed `wrasse.*`; imagery still Bluefin. Needs a Wrasse logo |
| `usr/share/pixmaps/faces/bluefin/*.jpg` | stock user avatars (generic photos: bicycle, cat, ...) | directory renamed `faces/wrasse`; the build flattens it to `faces/` anyway |
| `usr/share/backgrounds/bluefin/bluefin-hidamari.webm` | live wallpaper video | directory and file renamed |
| `etc/bazaar/NN-bluefin-{day,night}.jxl` (16 files) | Bazaar store banners | renamed `NN-wrasse-...`, `curated.yaml` follows; imagery still Bluefin. Needs Wrasse banners |
| Wallpapers from `ghcr.io/ublue-os/bluefin-wallpapers-gnome` | `06-bluefin.xml` etc. extracted by the Containerfile | Containerfile now installs them under `backgrounds/wrasse` and rewrites the names inside the XML. Not verified by a build (CI) |
| `usr/share/icons/hicolor/symbolic/apps/io.projectbluefin.chairlift-symbolic.svg` | Bluefin raptor mark (vendored ChairLift icon) | unchanged (app id plumbing) |
| `ublue-docs`, `ublue-discourse`, `ublue-logo-symbolic` icons | Universal Blue marks used by `documentation.desktop`, `discourse.desktop`, `ublue-logo-symbolic.svg` | unchanged, name has no "bluefin"; listed because they are still UB art |

## UNCLEAR (not changed, maintainer decides)

- `CODE_NAME` for os-release: Bluefin used "Deinonychus". Set to a placeholder `Cheilinus` (wrasse genus); pick a real one.
- `.github/CODEOWNERS` lists upstream maintainers (`@castrojo @p5 @m2Giles @tulilirockz`). Needs the Wrasse maintainers' GitHub handles.
- `Justfile` artifacthub `maintainers` label names castrojo. Removed rather than replaced; add the real maintainer if wanted.
- `io.artifacthub.package.logo-url` points at the Universal Blue org avatar. Removed; needs a Wrasse logo URL.
- `rpm-ostree-countme` (Fedora's own telemetry) is still enabled.
- Existing DX sysexts built against `ID=bluefin` will not merge on an image with `ID=wrasse` (see risks in the commit log).
- `README`/`docs` forum links: Wrasse has no forum or chat, so those links were removed rather than replaced.
