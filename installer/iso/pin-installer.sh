#!/usr/bin/bash
# Patch dakota-iso's live/src/install-flatpaks.sh so it installs the pinned bootc-installer release
# (installer/iso/pin.env) and checks the bundle's sha256, instead of following releases/latest.
# Fails if the lines it expects are not there, so a changed upstream script is noticed, not silently skipped.
#
# Usage: installer/iso/pin-installer.sh <path to install-flatpaks.sh>
set -euo pipefail

script="${1:?usage: pin-installer.sh <install-flatpaks.sh>}"
# shellcheck source=pin.env
source "$(dirname "${BASH_SOURCE[0]}")/pin.env"

grep -qxF "INSTALLER_REPO=\"${INSTALLER_REPO}\"" "${script}" \
    || { echo "error: ${script} does not download from ${INSTALLER_REPO}; check pin.env against upstream" >&2; exit 1; }
# shellcheck disable=SC2016  # the ${...} must reach the grep literally
grep -q '^PRIMARY_URL="https://github.com/${INSTALLER_REPO}/releases/latest/download/${FLATPAK_FILENAME}"$' "${script}" \
    || { echo "error: PRIMARY_URL line not found in ${script}" >&2; exit 1; }
grep -qF -- '-o /tmp/tuna-installer.flatpak' "${script}" \
    || { echo "error: bundle download line not found in ${script}" >&2; exit 1; }

# Pin the release tag.
sed -i "s|^PRIMARY_URL=.*|PRIMARY_URL=\"https://github.com/\${INSTALLER_REPO}/releases/download/${INSTALLER_TAG}/\${FLATPAK_FILENAME}\"|" "${script}"
# Verify the stable bundle right after the download (the Devel bundle is never used: INSTALLER_CHANNEL=stable).
sed -i "/-o \/tmp\/tuna-installer.flatpak/a echo \"${INSTALLER_FLATPAK_SHA256}  /tmp/tuna-installer.flatpak\" | sha256sum -c -" "${script}"

grep -q "releases/download/${INSTALLER_TAG}/" "${script}" \
    || { echo "error: tag pin did not apply to ${script}" >&2; exit 1; }
grep -q "${INSTALLER_FLATPAK_SHA256}" "${script}" \
    || { echo "error: sha256 check did not apply to ${script}" >&2; exit 1; }
echo "pinned bootc-installer ${INSTALLER_REPO} ${INSTALLER_TAG} in ${script}"
