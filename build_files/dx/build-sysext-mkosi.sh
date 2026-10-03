#!/usr/bin/bash
# Builds wrasse-dx.raw with mkosi (Format=sysext, Overlay=yes) from a finished image.
# Alternative to build-sysext.sh; selected by DX_BUILDER=mkosi through build-dx.sh (docs/DX-SYSEXT.md).
#
# Usage (as root, on a host with mkosi installed and podman):
#   build-sysext-mkosi.sh <image> <out-dir>
# <image> is the finished image (its rootfs is the mkosi base tree, so only files the image
# does not ship land in the sysext). <out-dir> receives wrasse-dx.raw, wrasse-dx.extension-release and
# wrasse-dx.manifest.json.
#
# mkosi writes ID and VERSION_ID of usr/lib/extension-release.d/extension-release.wrasse-dx
# from the base tree's os-release, which is what systemd-sysext matches against the host.

set -euo pipefail

IMAGE="${1:?usage: build-sysext-mkosi.sh <image> <out-dir>}"
OUT_DIR="$(realpath -m "${2:?usage: build-sysext-mkosi.sh <image> <out-dir>}")"
HERE="$(dirname "$(realpath "$0")")"
SYSEXT_NAME="wrasse-dx"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Must run as root (mkosi overlay builds need it)" >&2
    exit 1
fi

work="$(mktemp -d)"
mounted=0
cleanup() {
    if [[ "${mounted}" -eq 1 ]]; then
        podman image unmount "${IMAGE}" >/dev/null || true
    fi
    rm -rf "${work}"
}
trap cleanup EXIT

rootfs="$(podman image mount "${IMAGE}")"
mounted=1

# shellcheck disable=SC1091,SC2153
version_id="$(. "${rootfs}/usr/lib/os-release" && printf '%s' "${VERSION_ID}")"
if [[ ! "${version_id}" =~ ^[0-9]+$ ]]; then
    echo "Unexpected VERSION_ID '${version_id}' in the image's os-release" >&2
    exit 1
fi

# Config tree in a scratch dir: the checked-in mkosi/ plus a package list generated from packages.txt.
# ExtraTrees=../files in mkosi.conf is relative to the config dir, so files/ sits beside conf/.
conf="${work}/conf"
cp -a "${HERE}/mkosi" "${conf}"
cp -a "${HERE}/files" "${work}/files"
mkdir -p "${conf}/mkosi.conf.d"
{
    echo "[Content]"
    echo "Packages="
    sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' -e 's/^/    /' "${HERE}/packages.txt"
} > "${conf}/mkosi.conf.d/10-packages.conf"

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"

mkosi --directory "${conf}" \
    --base-tree "${rootfs}" \
    --release "${version_id}" \
    --output-directory "${OUT_DIR}" \
    --force build

raw="${OUT_DIR}/${SYSEXT_NAME}.raw"
[[ -s "${raw}" ]] || { echo "mkosi did not produce ${raw}" >&2; ls -la "${OUT_DIR}" >&2; exit 1; }

# Plain-text copy of extension-release, published next to the .raw and read by test-sysext.sh.
systemd-dissect --copy-from "${raw}" \
    "/usr/lib/extension-release.d/extension-release.${SYSEXT_NAME}" \
    "${OUT_DIR}/${SYSEXT_NAME}.extension-release"
cat "${OUT_DIR}/${SYSEXT_NAME}.extension-release"

# Same sanity list as build-sysext.sh: what ujust dx on relies on must be in the payload.
listing="$(systemd-dissect --list "${raw}")"
for path in \
    usr/bin/dockerd usr/bin/docker usr/bin/virsh usr/bin/code usr/bin/bpftrace usr/bin/waydroid \
    usr/lib/systemd/system/docker.socket usr/lib/systemd/system/virtqemud.socket \
    usr/lib/systemd/system/virtnetworkd.socket usr/lib/systemd/system/wrasse-dx-libvirt-relabel.service \
    usr/lib/sysusers.d/moby-engine.conf; do
    grep -Eq "^/?${path}\$" <<<"${listing}" || { echo "Missing from sysext: ${path}" >&2; exit 1; }
done

stat -c "${SYSEXT_NAME}.raw: %s bytes" "${raw}"
