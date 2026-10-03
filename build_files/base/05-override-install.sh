#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# We do not need anything here at all
rm -rf /usr/src
rm -rf /usr/share/doc
# Remove kernel-devel from rpmdb because all package files are removed from /usr/src
rpm --erase --nodeps kernel-devel

# Bibata Modern Classic cursor theme (black with a white outline, the Linux Mint default; GPL-3.0).
# Pinned release asset with its sha256; one cursor theme in light and dark mode on purpose.
BIBATA_VERSION="v2.0.7"
BIBATA_SHA256="7d3495864e5bbef02f5e77de760b2905903b63c71495a78ef6306d19a3b556d8"
ghcurl "https://github.com/ful1e5/Bibata_Cursor/releases/download/${BIBATA_VERSION}/Bibata-Modern-Classic.tar.xz" --retry 3 -o /tmp/bibata.tar.xz
echo "${BIBATA_SHA256}  /tmp/bibata.tar.xz" | sha256sum -c -
tar -xJf /tmp/bibata.tar.xz -C /usr/share/icons
rm -f /tmp/bibata.tar.xz

# Automatic wallpaper changing by month
HARDCODED_RPM_MONTH="12"
sed -i "/picture-uri/ s/${HARDCODED_RPM_MONTH}/$(date +%m)/" "/usr/share/glib-2.0/schemas/zz0-wrasse-modifications.gschema.override"
rm /usr/share/glib-2.0/schemas/gschemas.compiled
glib-compile-schemas /usr/share/glib-2.0/schemas

# Required for wrasse faces to work without conflicting with a ton of packages
rm -f /usr/share/pixmaps/faces/* || echo "Expected directory deletion to fail"
mv /usr/share/pixmaps/faces/wrasse/* /usr/share/pixmaps/faces
rm -rf /usr/share/pixmaps/faces/wrasse

# Remove desktop entries
if [[ -f /usr/share/applications/gnome-system-monitor.desktop ]]; then
    sed -i 's@\[Desktop Entry\]@\[Desktop Entry\]\nHidden=true@g' /usr/share/applications/gnome-system-monitor.desktop
fi
if [[ -f /usr/share/applications/org.gnome.SystemMonitor.desktop ]]; then
    sed -i 's@\[Desktop Entry\]@\[Desktop Entry\]\nHidden=true@g' /usr/share/applications/org.gnome.SystemMonitor.desktop
fi

# Add Mutter experimental-features
if [[ "${IMAGE_NAME}" =~ nvidia ]]; then
    sed -i "/experimental-features/ s/\]/, 'kms-modifiers'&/" /usr/share/glib-2.0/schemas/zz0-wrasse-modifications.gschema.override
    echo "Compiling gschema to include wrasse setting overrides"
    glib-compile-schemas /usr/share/glib-2.0/schemas
fi

echo "::endgroup::"
