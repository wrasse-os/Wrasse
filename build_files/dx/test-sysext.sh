#!/usr/bin/bash
# Checks a finished /usr/share/wrasse/sysexts/wrasse-dx.raw against the running image's
# os-release. Run in the final Containerfile stage after the sysext is copied in.

echo "::group:: ===$(basename "$0")==="

set -euo pipefail

RAW="/usr/share/wrasse/sysexts/wrasse-dx.raw"
[[ -s "${RAW}" ]] || { echo "Missing ${RAW}" >&2; exit 1; }

# The final stage has no erofs tools; the build stage already ran fsck.erofs. Here we only
# check what the host can see without mounting: the file exists and carries the erofs magic
# (0xE0F5E1E2 little endian at offset 1024).
magic="$(od -An -tx1 -j1024 -N4 "${RAW}" | tr -d ' \n')"
if [[ "${magic}" != "e2e1f5e0" ]]; then
    echo "${RAW} is not an erofs image (magic ${magic})" >&2
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
