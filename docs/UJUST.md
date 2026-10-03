# ujust reference

Recipes that exist in `system_files/shared/usr/share/ublue-os/just/` as of this tree (listed with `just --list` over those files).
`ujust` with no arguments lists what is installed on a running system. Recipe and link text now says Wrasse; there is no
forum or chat, links go to the repo. `00-entry.just` imports `flutter.just` optionally; that file does not exist here.

## Wrasse recipes (`60-custom.just`)

| Recipe | What it does |
|---|---|
| `ujust dx on\|off [purge]\|update\|status` | The developer sysext, downloaded on demand (it is not in the image). `on` downloads the `wrasse-dx.raw` that matches the booted image (about 1.4 GB, needs network, signature checked against `wrasse.pub`), enables `wrasse-dx-select.service` so only that file is linked into `/var/lib/extensions`, refreshes sysext, creates the users and tmpfiles, enables the Docker/Podman/libvirt sockets and adds you to `docker` and `libvirt`. `update` fetches the match for the booted and any staged image and re-merges; run it after an image update (DX stays off until then). `off` reverses `on` (`off purge` also deletes the downloads). Runs `/usr/libexec/wrasse-dx` through `pkexec`; see `docs/DX-SYSEXT.md`. |
| `ujust multiplexer zellij\|none\|status` | Sets or resets the custom command of your default Ptyxis profile so new tabs start Zellij (needs `brew install zellij`, done on first login). Nothing starts Zellij from fish or bash. |
| `ujust system-status` | Shows `bootc status` (booted, staged and rollback images) through `pkexec`; bootc needs root even to read. |
| `ujust rollback` | Shows `bootc status`, explains what changes, asks (gum, or `read` without gum) and runs `pkexec bootc rollback`; offers a restart with gum. DX follows the image: after the rollback it uses the sysext already downloaded for that image, else run `ujust dx update`; `/etc` reverts to the previous deployment's state, as bootc documents. |
| `ujust gradia-extension on\|off\|status` | Enables or disables the installed Gradia Capture GNOME Shell extension (off by default). |

## System

| Recipe | What it does |
|---|---|
| `update` (alias `upgrade`) | Updates the system, Flatpaks and Homebrew packages together. |
| `update-soft` | Runs `bootc upgrade --soft-reboot=auto --apply`: restarts userspace only when the new image has the same kernel, initrd and kernel arguments, otherwise a full reboot. Always restarts, and does not update Flatpaks or Homebrew. |
| `toggle-updates [enable\|disable\|cancel]` (alias `auto-update`) | Turns automatic updates on or off; with an argument it runs without the prompt. |
| `changelogs` | Shows the changelog (still upstream's; see Known stale below). |
| `bios`, `bios-info` | Reboot into the firmware setup; show BIOS info. |
| `logs-this-boot`, `logs-last-boot` | Journal of this or the previous boot. |
| `enroll-secure-boot-key` | Imports the ublue akmods key with `mokutil` (password `universalblue`). See `docs/INSTALL.md`. |
| `check-sb-key` | Prints Secure Boot state, enrolled MOKs and the kernel signature. |
| `toggle-tpm2` | Toggles LUKS auto-unlock through TPM2. |
| `benchmark` | One-minute system benchmark. |
| `check-idle-power-draw` | Measures idle power draw. |
| `check-local-overrides` | Lists local overrides of image files. |
| `device-info` | Gathers device info to a pastebin. |
| `clean-system` | Asks, then prunes Podman and Docker images and volumes, unused Flatpaks and brew leftovers. |
| `toggle-user-motd` | Compatibility shim for the welcome banner (state lives in `~/.config/uwelcome/disabled`). |
| `powerwash` | Factory reset with `bootc install reset --experimental`, after two confirmations. |
| `report [args]` | bonedigger: previewed, privacy-respecting bug report created with `gh`. |
| `install-system-flatpaks [confirm]`, `wrasse-apps` | Installs the default system Flatpaks (`wrasse-apps` is an alias for it). |
| `bazaar-preview <path>` | Previews a Bazaar curated config from a local checkout. |

## Developer and VM tooling (user space, separate from the DX sysext)

| Recipe | What it does |
|---|---|
| `toggle-devmode` (alias `devmode`) | Interactive Homebrew-based developer tool setup. Not the same as `ujust dx`. |
| `setup-vms`, `toggle-vms` | virt-manager Flatpak plus the QEMU extension; toggle it. |
| `setup-lima` | Sets up a Lima Ubuntu VM. |

## Apps

| Recipe | What it does |
|---|---|
| `install-jetbrains-toolbox` (alias `jetbrains-toolbox`) | Installs JetBrains Toolbox. |
| `install-opentabletdriver` | Installs OpenTabletDriver from a pinned release. |
| `install-asus` | Installs asusctl and ROG Control Center. |
| `cncf` | Installs CNCF tools from a curated Brewfile. |
| `install-ai-tools` | Installs Goose from a Brewfile and writes a read-only diagnostics MCP config if none exists. |
| `bluespeed` | Installs the opt-in local Bluespeed assistant stack from a Brewfile. |

## Known stale (not fixed here)

- `toggle-testing` only knows `stable`, `latest`, `lts` tags and switches to `testing`/`lts-testing`; Wrasse has no such tags, so it
  is wrong on Wrasse. To move between `reimagined`, `next` and `stable`, use `sudo bootc switch` (`docs/INSTALL.md`).
- `changelogs` reads GitHub releases of `wrasse-os/Wrasse` (via `ublue-image-repo`) and still looks for gts/lts tag names; what the
  testing channel becomes is a Phase 2 decision (`docs/SPEC.md`).

## Soft-reboot updates

`uupd` (the automatic updater) runs `bootc upgrade --quiet --progress-fd 3` and has no soft-reboot setting; its `--apply` does a
regular reboot. Do not rely on it for soft reboots; use `ujust update-soft` when you choose to restart. The bootc docs
(`bootc-upgrades(7)`, "Soft reboots") define `--soft-reboot=auto` as: prepare a soft reboot if the target deployment is capable,
otherwise leave it for a regular reboot; `--apply` triggers the restart. Limits:

- A new kernel or initrd (most Fedora kernel updates) cannot be soft-rebooted, so you get a normal reboot.
- A soft reboot restarts all userspace (session, services, containers), it only skips firmware and the kernel boot. Running
  processes still end.
- The kernel keeps running, so a kernel security fix is not active until a full reboot.

Checked against bootc 1.16.7 (Fedora 44). Fedora 45's bootc version was not checked.
