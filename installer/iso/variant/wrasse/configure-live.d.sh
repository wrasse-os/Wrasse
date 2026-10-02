#!/usr/bin/bash
# Wrasse hook for dakota-iso's live/src/configure-live.sh (it runs this last, from /tmp/src/wrasse/).
# Runs inside the live container build. Files next to this script come from installer/iso/variant/wrasse/
# plus two build outputs the workflow drops in: wrasse-gpu-detect (static musl binary) and images.json.tmpl
# (installer/gen-catalog.sh).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install -Dm755 "${here}/wrasse-gpu-detect" /usr/bin/wrasse-gpu-detect
install -Dm755 "${here}/wrasse-installer-config" /usr/libexec/wrasse-installer-config
install -Dm644 "${here}/images.json.tmpl" /usr/share/wrasse/installer/images.json.tmpl
install -Dm644 "${here}/wrasse-installer-config.service" /usr/lib/systemd/system/wrasse-installer-config.service
systemctl enable wrasse-installer-config.service

# configure-live.sh sets up an offline install: it writes the live-iso-mode flag and a recipe with
# local_imgref. The installer removes its image step in that mode, and the release line and GPU flavor
# are chosen in that step, so the Wrasse ISO is a network install: no flag, no embedded payload, and the
# plain recipe (with the image step) put back. fisherman pulls the chosen ghcr.io/wrasse-os image.
rm -f /etc/bootc-installer/live-iso-mode
install -Dm644 "${here}/recipe.json" /etc/bootc-installer/recipe.json

# configure-live.sh hardcodes Dakota's name and icon in the launchers.
for f in /etc/xdg/autostart/tuna-installer.desktop \
         /usr/share/applications/dakota-installer.desktop \
         /usr/share/applications/org.bootcinstaller.Installer.desktop; do
    [[ -f "${f}" ]] || continue
    sed -i -e 's/^Name=Dakota Installer/Name=Wrasse Installer/' \
           -e 's/^Comment=Install Dakota to your computer/Comment=Install Wrasse to your computer/' \
           -e 's/^Icon=dakota$/Icon=org.bootcinstaller.Installer/' "${f}"
done
