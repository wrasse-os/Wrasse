#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# Wrasse builds FROM plain Fedora Silverblue (quay.io/fedora/fedora-silverblue), not ghcr.io/ublue-os/silverblue-main.
# This script reproduces only what ublue-os/main (build_files/install.sh, packages.sh, post-install.sh and its
# sys_files) put on top of Fedora AND that survives into this repo's final image. Things the ublue-os-* RPMs
# shipped (ujust, policy.json and registries.d, update services, udev rules, luks helpers) are not here: this repo
# already carries its own copies in system_files/ and used to `dnf remove` the RPMs.
# Runs after the system_files rsync and before the kernel swap (03-install-kernel-akmods.sh).

# shellcheck source=build_files/shared/copr-helpers.sh
source /ctx/build_files/shared/copr-helpers.sh

# Replaces: main install.sh `mkdir -p /var/roothome`. Root's home on ostree systems.
mkdir -p /var/roothome

# Needed by 03-install-kernel-akmods.sh, which writes the nvidia kargs here. Not taken from main: plain Fedora
# images are not guaranteed to ship the directory, and the earlier silverblue-main base may have provided it.
mkdir -p /usr/lib/bootc/kargs.d

# Replaces: main install.sh "use negativo17 for 3rd party packages with higher priority than default".
# Provides the ffmpeg, fdk-aac, libva and Intel media stack and the less crippled mesa. 17-cleanup.sh and
# validate-repos.sh disable the repo again before the image is committed.
if ! dnf5 repolist --all | grep -q fedora-multimedia; then
    dnf5 config-manager addrepo --from-repofile="https://negativo17.org/repos/fedora-multimedia.repo"
fi
dnf5 config-manager setopt fedora-multimedia.enabled=1
dnf5 config-manager setopt fedora-multimedia.priority=90

# Replaces: main install.sh OVERRIDES. Swap mesa and the media libraries to the negativo17 builds and hold them
# so the later `dnf install` calls in 04-packages.sh cannot move them back. clean-stage.sh clears the versionlock.
# mesa-va-drivers is not listed: it is a Provides of mesa-dri-drivers in Fedora 44/45.
OVERRIDES=(
    intel-gmmlib
    intel-mediasdk
    intel-vpl-gpu-rt
    libheif
    libva
    libva-intel-media-driver
    mesa-dri-drivers
    mesa-filesystem
    mesa-libEGL
    mesa-libGL
    mesa-libgbm
    mesa-vulkan-drivers
)
dnf5 distro-sync --skip-unavailable -y --repo='fedora-multimedia' "${OVERRIDES[@]}"
dnf5 versionlock add "${OVERRIDES[@]}"

# Replaces: main packages.json ("all" and "silverblue" include lists), minus what 04-packages.sh already installs.
# heif-pixbuf-loader and fdk-aac are not listed: in Fedora 44/45 gdk-pixbuf2 and libfdk-aac provide them.
BASE_PACKAGES=(
    alsa-firmware
    apr
    apr-util
    distrobox
    ffmpeg
    ffmpeg-libs
    ffmpegthumbnailer
    flatpak-spawn
    fuse
    fzf
    google-noto-sans-balinese-fonts
    google-noto-sans-cjk-fonts
    google-noto-sans-javanese-fonts
    google-noto-sans-sundanese-fonts
    grub2-tools-extra
    gvfs-nfs
    htop
    ibus-unikey
    intel-vaapi-driver
    libavcodec
    libcamera
    libcamera-gstreamer
    libcamera-ipa
    libcamera-tools
    libfdk-aac
    libimobiledevice-utils
    libva-utils
    lshw
    net-tools
    nvme-cli
    nvtop
    openrgb-udev-rules
    openssl
    pam-u2f
    pam_yubico
    pamu2fcfg
    pipewire-libs-extra
    pipewire-plugin-libcamera
    ptyxis
    smartmontools
    solaar-udev
    squashfs-tools
    symlinks
    tcpdump
    traceroute
    vim
    xhost
    xorg-x11-xauth
    yubikey-manager
    zstd
)
dnf5 -y install "${BASE_PACKAGES[@]}"

# oversteer-udev exists only in the ublue-os/packages COPR (verified for Fedora 44 and 45), so it is installed
# alone with the COPR enabled just for that call.
copr_install_isolated "ublue-os/packages" "oversteer-udev"

# Replaces: main packages.json "exclude" and install.sh. Plain Fedora Silverblue ships the Fedora Flatpak remote
# package and the third-party repo prompt; ublue removed them, and Wrasse ships Flathub only.
# Guarded: dnf5 errors on packages that are not installed.
for pkg in fedora-flathub-remote fedora-third-party totem-video-thumbnailer; do
    if rpm -q "${pkg}" >/dev/null 2>&1; then
        dnf5 -y remove "${pkg}"
    fi
done

# Replaces: main install.sh flathub.flatpakrepo download. flatpak reads remotes.d on first use of the system
# installation. flatpak-add-fedora-repos.service (the Fedora one) is removed by clean-stage.sh.
mkdir -p /etc/flatpak/remotes.d
curl --fail --silent --show-error --location --retry 3 -o /etc/flatpak/remotes.d/flathub.flatpakrepo \
    https://dl.flathub.org/repo/flathub.flatpakrepo

# Replaces: main post-install.sh. Let `sudo` find Homebrew.
sed -Ei 's|secure_path = (.*)|secure_path = \1:/home/linuxbrew/.linuxbrew/bin|' /etc/sudoers
grep -q 'secure_path = .*linuxbrew' /etc/sudoers

# Replaces: main install.sh (ublue-os/main issue #653). CoreOS' generator forces sulogin for emergency and rescue
# boot. Pinned to a commit of coreos/fedora-coreos-config and checked against its sha256.
SULOGIN_GEN=/usr/lib/systemd/system-generators/coreos-sulogin-force-generator
curl --fail --silent --show-error --location --retry 3 -o "${SULOGIN_GEN}" \
    https://raw.githubusercontent.com/coreos/fedora-coreos-config/971127c59bd7fba75b4b3ed93b7752548a7f5436/overlay.d/05core/usr/lib/systemd/system-generators/coreos-sulogin-force-generator
echo "eb9222214c4647f1ed430f379dca13c3ba945a6aa7950ce6b2d5be3e0a337da1  ${SULOGIN_GEN}" | sha256sum -c -
chmod 0755 "${SULOGIN_GEN}"

echo "::endgroup::"
