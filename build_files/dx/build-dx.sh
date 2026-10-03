#!/usr/bin/bash
# Builds the DX sysext as a standalone artifact from a finished image and checks it.
#
# Usage (as root, from the repository root, image in root's podman storage):
#   build-dx.sh <image> <out-dir>
# <out-dir> receives wrasse-dx.raw and wrasse-dx.extension-release. DX_BUILDER selects the builder:
# "script" (default, Containerfile.dx + build-sysext.sh) or "mkosi" (build-sysext-mkosi.sh).
# The image itself never contains the sysext; CI publishes the artifact separately (docs/DX-SYSEXT.md).

set -euo pipefail

IMAGE="${1:?usage: build-dx.sh <image> <out-dir>}"
OUT_DIR="$(realpath -m "${2:?usage: build-dx.sh <image> <out-dir>}")"
HERE="$(dirname "$(realpath "$0")")"
BUILDER="${DX_BUILDER:-script}"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Must run as root (the image is in root's podman storage)" >&2
    exit 1
fi

case "${BUILDER}" in
    script)
        build_tag="localhost/wrasse-dx-build:$$"
        cid=""
        cleanup() {
            [[ -z "${cid}" ]] || podman rm -f "${cid}" >/dev/null 2>&1 || true
            podman rmi -f "${build_tag}" >/dev/null 2>&1 || true
        }
        trap cleanup EXIT
        podman build --build-arg "BASE=${IMAGE}" -f "${HERE}/Containerfile.dx" --tag "${build_tag}" "${HERE}/../.."
        cid="$(podman create "${build_tag}" /bin/true)"
        rm -rf "${OUT_DIR}"
        mkdir -p "${OUT_DIR}"
        podman cp "${cid}:/out/." "${OUT_DIR}/"
        ;;
    mkosi)
        "${HERE}/build-sysext-mkosi.sh" "${IMAGE}" "${OUT_DIR}"
        ;;
    *)
        echo "DX_BUILDER must be script or mkosi, got '${BUILDER}'" >&2
        exit 1
        ;;
esac

"${HERE}/test-sysext.sh" "${OUT_DIR}" "${IMAGE}"
ls -l "${OUT_DIR}"
