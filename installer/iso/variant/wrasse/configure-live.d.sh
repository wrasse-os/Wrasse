#!/usr/bin/bash
# Wrasse hook for dakota-iso's live/src/configure-live.sh (it runs this last, from /tmp/src/wrasse/).
# Runs inside the live container build. Files next to this script come from installer/iso/variant/wrasse/
# plus build outputs the workflow drops in: wrasse-gpu-detect (static musl binary) and images.wrasse.json /
# images.wrasse-nvidia.json (installer/gen-catalog.sh, one catalog per detected graphics flavor).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install -Dm755 "${here}/wrasse-gpu-detect" /usr/bin/wrasse-gpu-detect
install -Dm755 "${here}/wrasse-installer-config" /usr/libexec/wrasse-installer-config
install -Dm644 "${here}/images.wrasse.json" /usr/share/wrasse/installer/images.wrasse.json
install -Dm644 "${here}/images.wrasse-nvidia.json" /usr/share/wrasse/installer/images.wrasse-nvidia.json
install -Dm644 "${here}/wrasse-installer-config.service" /usr/lib/systemd/system/wrasse-installer-config.service
systemctl enable wrasse-installer-config.service

# configure-live.sh sets up an offline install: it writes the live-iso-mode flag and a recipe with
# local_imgref. The installer removes its image step in that mode, and the release line and GPU flavor
# are chosen in that step, so the Wrasse ISO is a network install: no flag, no embedded payload, and the
# plain recipe (with the image step) put back. fisherman pulls the chosen ghcr.io/wrasse-os image.
rm -f /etc/bootc-installer/live-iso-mode
install -Dm644 "${here}/recipe.json" /etc/bootc-installer/recipe.json

# configure-live.sh hardcodes Dakota's name and icon in the launchers. The installer is the generic
# bootc installer, so name the launcher after what it does and drop the Dakota-named duplicate.
rm -f /usr/share/applications/dakota-installer.desktop
for f in /etc/xdg/autostart/tuna-installer.desktop \
         /usr/share/applications/org.bootcinstaller.Installer.desktop; do
    [[ -f "${f}" ]] || continue
    sed -i -e 's/^Name=Dakota Installer/Name=Install Wrasse/' \
           -e 's/^Comment=Install Dakota to your computer/Comment=Install Wrasse to your computer/' \
           -e 's/^Icon=dakota$/Icon=org.bootcinstaller.Installer/' "${f}"
    if grep -qi 'dakota' "${f}"; then
        echo "leftover Dakota branding in ${f}" >&2
        exit 1
    fi
done

# The tooling pins `dakota-installer.desktop` in the dock (now removed above), but the running installer window's app id is
# org.bootcinstaller.Installer, which GNOME matches to org.bootcinstaller.Installer.desktop. Two different
# desktop ids meant two installer icons (one pinned, one running). Pin the id the window really uses, and
# use Wrasse's own live favorites instead of Firefox and Console.
dconf_file=/etc/dconf/db/distro.d/50-live-iso
grep -q '^favorite-apps=' "${dconf_file}"
sed -i "s|^favorite-apps=.*|favorite-apps=['org.bootcinstaller.Installer.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Ptyxis.desktop']|" "${dconf_file}"
dconf update
