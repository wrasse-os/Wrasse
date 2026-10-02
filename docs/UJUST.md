# ujust reference

Recipes that exist in `system_files/shared/usr/share/ublue-os/just/` as of this tree (listed with `just --list` over those files).
`ujust` with no arguments lists what is installed on a running system. Recipe text still says Bluefin in places (`brand:` is
deferred). `00-entry.just` imports `flutter.just` optionally; that file does not exist here.

## Wrasse recipes (`60-custom.just`)

| Recipe | What it does |
|---|---|
| `ujust dx on\|off\|status` | Turns the `wrasse-dx.raw` sysext on or off. `on` links it into `/etc/extensions/`, refreshes sysext, creates the users and tmpfiles, enables the Docker/Podman/libvirt sockets and adds you to `docker` and `libvirt`; `off` reverses it. Runs `/usr/libexec/wrasse-dx` through `pkexec`. |
| `ujust multiplexer zellij\|none\|status` | Sets or resets the custom command of your default Ptyxis profile so new tabs start Zellij (needs `brew install zellij`, done on first login). Nothing starts Zellij from fish or bash. |
| `ujust gradia-extension on\|off\|status` | Enables or disables the installed Gradia Capture GNOME Shell extension (off by default). |

## System

| Recipe | What it does |
|---|---|
| `update` (alias `upgrade`) | Updates the system, Flatpaks and Homebrew packages together. |
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
| `contribute` | Runs the Hive contributor worker in an isolated Podman container. |
| `install-system-flatpaks [confirm]`, `bluefin-apps` | Installs the default system Flatpaks (`bluefin-apps` is an alias for it). |
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
- `changelogs`, `update` text and recipe headings still point to Bluefin resources. These belong to `brand:` and to deciding what
  the testing channel becomes (`docs/SPEC.md`, Phase 2).
