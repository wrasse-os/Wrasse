#!/usr/bin/bash
# Checks a finished /usr/share/wrasse/sysexts/wrasse-dx.raw against the running image's
# os-release. Run in the final Containerfile stage after the sysext is copied in.

echo "::group:: ===$(basename "$0")==="

set -euo pipefail

# Nothing to check while the sysext is still to be layered in (DX_BUILDER=mkosi stage `final`).
if [[ "${DX_BUILDER:-script}" == "mkosi" && ! -e /usr/share/wrasse/sysexts/wrasse-dx.raw ]]; then
    echo "DX sysext comes from the mkosi layer; skipping"
    echo "::endgroup::"
    exit 0
fi

RAW="/usr/share/wrasse/sysexts/wrasse-dx.raw"
[[ -s "${RAW}" ]] || { echo "Missing ${RAW}" >&2; exit 1; }

# The final stage has no erofs tools; the build stage already ran fsck.erofs. Here we only
# check what the host can see without mounting. The script builder writes a bare erofs
# image (magic 0xE0F5E1E2 little endian at offset 1024); the mkosi builder writes a GPT
# disk image with an erofs partition ("EFI PART" at offset 512).
erofs_magic="$(od -An -tx1 -j1024 -N4 "${RAW}" | tr -d ' \n')"
gpt_magic="$(dd if="${RAW}" bs=1 skip=512 count=8 status=none)"
if [[ "${erofs_magic}" != "e2e1f5e0" && "${gpt_magic}" != "EFI PART" ]]; then
    echo "${RAW} is neither a bare erofs image nor a GPT disk image (erofs magic ${erofs_magic})" >&2
    exit 1
fi

REL="/usr/share/wrasse/sysexts/wrasse-dx.extension-release"
[[ -s "${REL}" ]] || { echo "Missing ${REL}" >&2; exit 1; }

# systemd-sysext refuses an extension whose ID or VERSION_ID differs from the host's.
for key in ID VERSION_ID; do
    host="$(. /usr/lib/os-release && printf '%s' "${!key}")"
    ext="$(sed -n "s/^${key}=//p" "${REL}" | tr -d '"')"
    if [[ "${host}" != "${ext}" ]]; then
        echo "extension-release ${key}=${ext} does not match os-release ${key}=${host}" >&2
        exit 1
    fi
done

echo "::endgroup::"
