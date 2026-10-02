# Install

Images (lowercase, on GitHub Container Registry):

| Image | For |
|---|---|
| `ghcr.io/wrasse-os/wrasse` | Mesa: AMD, Intel, and NVIDIA GPUs older than Turing (Nouveau) |
| `ghcr.io/wrasse-os/wrasse-nvidia` | NVIDIA Turing or newer, with the NVIDIA open kernel driver |

Whether the images are published yet depends on CI and the signing setup (see `docs/SPEC.md`, Phase 2 notes).

## GPU table

| GPU | Image |
|---|---|
| NVIDIA Turing or newer (GTX 16xx, RTX 20xx and later) | `wrasse-nvidia` |
| NVIDIA Pascal (GTX 10xx) and older | `wrasse` (the open driver does not support these) |
| AMD | `wrasse` |
| Intel | `wrasse` |

"Turing or newer" is the device list of NVIDIA's open kernel modules; the installer's autodetect (`wrasse-gpu-detect`) uses that
list. Only the open driver is shipped; there is no proprietary-module image.

## Release lines

One git branch, several image tags. Each line is built for both images.

| Tag | Fedora | Meaning |
|---|---|---|
| `stable` | newest final release | Default. |
| `next` | newest Fedora beta | Stays on its last version after that goes final, until the next beta. |
| `reimagined` | newest branched Fedora (never Rawhide) | With no branched release it follows `next`. |

There is no LTS or GTS line. Versions are resolved by CI (`docs/CI.md`). Images are built from Fedora's own
`quay.io/fedora-ostree-desktops/silverblue:<version>` (cosign-verified), so beta and branched lines build as soon as Fedora publishes the tag. One open
decision remains: whether `reimagined` has an NVIDIA image.

## Rebase an existing bootc system

```fish
sudo bootc switch ghcr.io/wrasse-os/wrasse:stable
systemctl reboot
```

Use `wrasse-nvidia` and/or another line in the same way. `bootc status` shows the booted and staged images; `sudo bootc rollback`
returns to the previous one. The in-image signature policy still only covers `ghcr.io/ublue-os` and `/cosign.pub` is still
Bluefin's, so do not rely on signature enforcement for Wrasse images yet.

## Live ISO

`installer/README.md` describes a network-install ISO that autodetects the GPU and asks the release line. It is built by hand in
Actions ("Build Live ISO") and has not been run. The live ISO tooling boots through systemd-boot, so Secure Boot likely has to be
off to boot the ISO; turn it on again afterwards and follow the next section.

## Secure Boot with NVIDIA

The `wrasse-nvidia` kernel modules are signed with the Universal Blue akmods key, not a Microsoft or Fedora key, so with Secure
Boot on you must enroll that key as a Machine Owner Key (MOK) once. Wrasse still uses the ublue key; a Wrasse key does not exist.

On the installed system:

```fish
ujust enroll-secure-boot-key
systemctl reboot
```

What the recipe does (read from `default.just`): `mokutil --timeout -1`, then `mokutil --import /etc/pki/akmods/certs/akmods-ublue.der`
with the password `universalblue`. At the next boot the blue MokManager screen appears (QWERTY keyboard): choose **Enroll MOK**,
**Continue**, **Yes**, enter `universalblue`, then reboot. Check afterwards with `ujust check-sb-key` (or `mokutil --sb-state`).

To enroll before installing or rebasing, download the key from the akmods repository and import it by hand:

```fish
curl -LO https://github.com/ublue-os/akmods/raw/main/certs/public_key.der
sudo mokutil --timeout -1
sudo mokutil --import public_key.der
```

Notes, verified 2026-10-03 against `github.com/ublue-os/akmods`:
- `certs/` holds two public keys, `public_key.der` (subject "ublue kernel", kernel signing) and `public_key_2.der` (subject "ublue
  akmods"); upstream enabled dual signing in 2024. The upstream README and Bluefin docs only name `public_key.der`, and the recipe
  imports `/etc/pki/akmods/certs/akmods-ublue.der` from the installed image. Which of the two that file equals was not verified
  here. If modules still fail to load with Secure Boot on after enrolling `public_key.der`, enroll `public_key_2.der` too, or use the
  recipe on the installed system.
- `universalblue` is a public throwaway password for the one-time enrollment screen, not a secret.
- The `wrasse` (Mesa) image has no out-of-tree GPU modules, but other akmods in the image (for example v4l2loopback) are signed with
  the same key.
- Not tested on hardware: the whole enrollment flow on a Wrasse image.
