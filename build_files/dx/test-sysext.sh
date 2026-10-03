#!/usr/bin/bash
# Checks a built wrasse-dx.raw against the os-release of the image it was built from.
#   test-sysext.sh <out-dir> <image>     (as root; <image> is in root's podman storage)

echo "::group:: ===$(basename "$0")==="

set -euo pipefail

OUT_DIR="${1:?usage: test-sysext.sh <out-dir> <image>}"
IMAGE="${2:?usage: test-sysext.sh <out-dir> <image>}"

RAW="${OUT_DIR}/wrasse-dx.raw"
[[ -s "${RAW}" ]] || { echo "Missing ${RAW}" >&2; exit 1; }

# The script builder writes a bare erofs image (magic 0xE0F5E1E2 little endian at offset 1024);
# the mkosi builder writes a GPT disk image with an erofs partition ("EFI PART" at offset 512).
erofs_magic="$(od -An -tx1 -j1024 -N4 "${RAW}" | tr -d ' \n')"
gpt_magic="$(dd if="${RAW}" bs=1 skip=512 count=8 status=none)"
if [[ "${erofs_magic}" != "e2e1f5e0" && "${gpt_magic}" != "EFI PART" ]]; then
    echo "${RAW} is neither a bare erofs image nor a GPT disk image (erofs magic ${erofs_magic})" >&2
    exit 1
fi

REL="${OUT_DIR}/wrasse-dx.extension-release"
[[ -s "${REL}" ]] || { echo "Missing ${REL}" >&2; exit 1; }

# systemd-sysext refuses an extension whose ID or VERSION_ID differs from the host's.
host_release="$(podman run --rm --entrypoint cat "${IMAGE}" /usr/lib/os-release)"
for key in ID VERSION_ID; do
    host="$(sed -n "s/^${key}=//p" <<<"${host_release}" | tr -d '"')"
    ext="$(sed -n "s/^${key}=//p" "${REL}" | tr -d '"')"
    if [[ -z "${host}" || "${host}" != "${ext}" ]]; then
        echo "extension-release ${key}=${ext} does not match the image's os-release ${key}=${host}" >&2
        exit 1
    fi
done

# ujust dx on picks the artifact by these two values; the image must carry them.
for key in IMAGE_ID IMAGE_VERSION; do
    if ! grep -q "^${key}=\"[^\"]\+\"$" <<<"${host_release}"; then
        echo "the image's os-release has no ${key}" >&2
        exit 1
    fi
done

echo "::endgroup::"
