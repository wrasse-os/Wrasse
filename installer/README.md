# Installer and live ISO (Phase 7)

| Path | What |
|---|---|
| `gpu-detect/` | `wrasse-gpu-detect`: prints `wrasse-nvidia` for a Turing or newer NVIDIA GPU, else `wrasse`. `cargo test` runs its tests. |
| `gen-nvidia-ids.sh` | Regenerates `gpu-detect/src/nvidia_open_ids.rs` from NVIDIA's open-gpu-kernel-modules README (`./gen-nvidia-ids.sh <tag>`). |
| `gen-catalog.sh` | `gen-catalog.sh <wrasse\|wrasse-nvidia>` prints the complete installer image catalog for that detected flavor from `.github/build-matrix.json`. |
| `iso/pin.env` | Pinned bootc-installer release (+ bundle sha256) and pinned ISO tooling commit. |
| `iso/pin-installer.sh` | Patches the tooling's `install-flatpaks.sh` to use that pin. |
| `iso/variant/wrasse/` | The Wrasse variant dropped into the tooling's `live/src/`: recipe, boot-time catalog renderer, systemd unit, hook. |
| `iso/variant/wrasse/wrasse-installer-preflight` | RAM minimum check run before the installer starts. |
| `iso/variant/wrasse/branding.json` | Installer branding file: welcome and confirm text, including the download note. |
| `tests/test-catalog.sh` | Tests for the catalog generator, renderer, recipe and branding (needs `jq`). |
| `tests/test-preflight.sh` | Tests for the RAM preflight. |

Build: Actions, "Build Live ISO" (`.github/workflows/build-iso.yml`), run by hand. Nothing builds an ISO locally or automatically.

## Requirements

| | Minimum | Enforced by |
|---|---|---|
| RAM | 8 GB | `wrasse-installer-preflight`: refuses to start the installer when `MemTotal` is below 7,000,000 kB (an "8 GB" machine reports about 7.0 to 7.7 GiB after firmware and iGPU reservations). A dialog says how much was found. |
| Disk | 25 GB | the installer's `min_disk_size` in `recipe.json` |
| Network | working internet | the `conn_check` step; the image (about 5 GB compressed, 4.4 to 5.0 GB) is downloaded during the install |

To install on less than 8 GB anyway (unsupported, the live session may kill the installer), add `wrasse.ignore_ram=1` to the kernel
command line: press `e` on the boot menu entry, add it at the end of the `linux` line, boot with `Ctrl+x`.

## Flow

0. Both installer launchers (`/etc/xdg/autostart/tuna-installer.desktop` and the application entry) run
   `/usr/libexec/wrasse-installer-preflight` first; it checks RAM and then execs the original command.
1. The ISO boots a live GNOME session (the live environment is `wrasse-nvidia` so every GPU can boot it).
2. `wrasse-installer-config.service` runs `wrasse-gpu-detect` and installs the matching pre-generated catalog
   (`/usr/share/wrasse/installer/images.<wrasse|wrasse-nvidia>.json`) as `/etc/bootc-installer/images.json`.
3. The installer autostarts. Its welcome page states the requirements, then the `conn-check` step probes `ghcr.io:443` (then `8.8.8.8:53`)
   and moves on by itself when one answers; with no connection it shows "No Internet Connection!" and a Recheck button, and there is no way
   forward. The installer's Wi-Fi picker is not available from a recipe, so connect from the live GNOME system menu (top right), then Recheck.
   Before the installer opens, `wrasse-installer-preflight` waits up to 8 seconds for a default route; if there is none it shows a message listing the options (Ethernet cable, phone USB tethering, Wi-Fi from the system menu) and still starts the installer, whose check page stays the gate. Any connection type counts; a machine with no way online cannot install.
   Its image step lists only the release lines (Reimagined / Next / Stable), each already pointing at the
   detected graphics variant (the description says which); `stable` is preselected. A last group, "Use different graphics drivers",
   holds the same lines for the other variant and is the override. It is absent when the other variant exists for no line. A line
   without an NVIDIA image falls back to `wrasse` (Mesa) on NVIDIA hardware and says so.
4. Then the usual disk, encryption and user steps, then the confirm page (chosen image, disk, the erase warning, and the note that the
   image is downloaded, about 5 GB; text from `iso/variant/wrasse/branding.json`), and fisherman pulls `ghcr.io/wrasse-os/<image>:<line>`.

Override the autodetect before boot: edit the GRUB entry and add `wrasse.gpu=nvidia` or `wrasse.gpu=default`
(or `auto`). From the live session: put the same word in `/etc/wrasse/installer-gpu`, re-run
`sudo /usr/libexec/wrasse-installer-config`, and restart the installer.

## Changes from upstream tooling

See the "Phase 7" section of `DIVERGENCE.md`.
