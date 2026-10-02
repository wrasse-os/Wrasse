# Installer and live ISO (Phase 7)

| Path | What |
|---|---|
| `gpu-detect/` | `wrasse-gpu-detect`: prints `wrasse-nvidia` for a Turing or newer NVIDIA GPU, else `wrasse`. `cargo test` runs its tests. |
| `gen-nvidia-ids.sh` | Regenerates `gpu-detect/src/nvidia_open_ids.rs` from NVIDIA's open-gpu-kernel-modules README (`./gen-nvidia-ids.sh <tag>`). |
| `gen-catalog.sh` | Prints the installer image catalog from `.github/build-matrix.json`. |
| `iso/pin.env` | Pinned bootc-installer release (+ bundle sha256) and pinned ISO tooling commit. |
| `iso/pin-installer.sh` | Patches the tooling's `install-flatpaks.sh` to use that pin. |
| `iso/variant/wrasse/` | The Wrasse variant dropped into the tooling's `live/src/`: recipe, boot-time catalog renderer, systemd unit, hook. |
| `tests/test-catalog.sh` | Tests for the catalog generator and renderer (needs `jq`). |

Build: Actions, "Build Live ISO" (`.github/workflows/build-iso.yml`), run by hand. Nothing builds an ISO locally or automatically.

## Flow

1. The ISO boots a live GNOME session (the live environment is `wrasse-nvidia` so every GPU can boot it).
2. `wrasse-installer-config.service` runs `wrasse-gpu-detect` and writes `/etc/bootc-installer/images.json` with
   `default_image` set to `ghcr.io/wrasse-os/<wrasse|wrasse-nvidia>:stable`.
3. The installer autostarts. Its image step shows two GPU groups (Mesa, NVIDIA), each with Reimagined / Next / Stable. The detected
   group is open with one line ticked; choosing any other leaf is the override.
4. Then the usual disk, encryption and user steps, and fisherman pulls `ghcr.io/wrasse-os/<image>:<line>`.

Override the autodetect before boot: edit the GRUB entry and add `wrasse.gpu=nvidia` or `wrasse.gpu=default`
(or `auto`). From the live session: put the same word in `/etc/wrasse/installer-gpu`, re-run
`sudo /usr/libexec/wrasse-installer-config`, and restart the installer.

## Changes from upstream tooling

See the "Phase 7" section of `DIVERGENCE.md`.
