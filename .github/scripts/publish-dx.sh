#!/usr/bin/env bash
# Publishes the DX sysext as a cosign-signed OCI artifact and proves a booted image could fetch it.
#
#   publish-dx.sh <dir> <repo> <image-id> <image-version> <line> <fedora-version>
#
# <dir> holds wrasse-dx.raw and wrasse-dx.extension-release (build_files/dx/build-dx.sh output).
# <repo> is the artifact repository, ghcr.io/wrasse-os/wrasse-dx. <image-id> and <image-version> are
# IMAGE_ID and IMAGE_VERSION from the built image's /usr/lib/os-release, the two values a booted image
# can read offline. Tags: <image-id>-<image-version> (exact, what `ujust dx on` fetches),
# <image-id>-<line> and <image-id>-f<fedora-version> (moving aliases, for humans).
# Needs oras (logged in), cosign and skopeo; COSIGN_PRIVATE_KEY / COSIGN_PASSWORD in the environment.
# Run from the repository root: it checks the artifact with the policy the image ships.

set -euo pipefail

dir="${1:?usage: publish-dx.sh <dir> <repo> <image-id> <image-version> <line> <fedora-version>}"
repo="${2:?}"
image_id="${3:?}"
image_version="${4:?}"
line="${5:?}"
fedora="${6:?}"

tag_re='^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$'
tag="${image_id}-${image_version}"
for t in "${tag}" "${image_id}-${line}" "${image_id}-f${fedora}"; do
    [[ "${t}" =~ ${tag_re} ]] || { echo "::error::'${t}' is not a valid OCI tag" >&2; exit 1; }
done
[[ -s "${dir}/wrasse-dx.raw" && -s "${dir}/wrasse-dx.extension-release" ]] || {
    echo "::error::${dir} lacks wrasse-dx.raw or wrasse-dx.extension-release" >&2
    exit 1
}

# The annotations are covered by the signature; ujust dx on refuses an artifact whose annotations
# do not name the booted image, so a validly signed artifact cannot be replayed under another tag.
(
    cd "${dir}"
    oras push --no-tty \
        --artifact-type application/vnd.wrasse.dx.sysext.v1 \
        --annotation "org.opencontainers.image.source=https://github.com/${GITHUB_REPOSITORY:-wrasse-os/Wrasse}" \
        --annotation "org.opencontainers.image.description=Wrasse DX sysext for ${tag}" \
        --annotation "io.wrasse.dx.image-id=${image_id}" \
        --annotation "io.wrasse.dx.image-version=${image_version}" \
        "${repo}:${tag}" \
        wrasse-dx.raw:application/vnd.wrasse.dx.sysext.raw.v1 \
        wrasse-dx.extension-release:text/plain
)

digest="$(oras resolve "${repo}:${tag}")"
[[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "::error::unexpected digest '${digest}'" >&2; exit 1; }

cosign sign -y --key env://COSIGN_PRIVATE_KEY "${repo}@${digest}"
oras tag "${repo}@${digest}" "${image_id}-${line}" "${image_id}-f${fedora}"

# Fetch it back the way the image does: skopeo with the shipped policy (signature required) and
# check the signed annotations and the blob digest.
policy_dir="system_files/shared/usr/share/wrasse/dx"
check="$(mktemp -d)"
trap 'rm -rf "${check}"' EXIT
# The shipped policy names the key at its on-image path (/usr/lib/pki/containers/wrasse.pub), which does not exist
# on the runner: point the same policy at the repository's copy of the key (identical to the image's).
jq --arg key "$(pwd)/cosign.pub" '(.. | objects | select(has("keyPath")) | .keyPath) = $key' "${policy_dir}/policy.json" > "${check}/policy.json"
skopeo --policy "${check}/policy.json" --registries.d "${policy_dir}/registries.d" \
    copy --retry-times 3 "docker://${repo}:${tag}" "dir:${check}/art"
[[ "$(jq -r '.annotations["io.wrasse.dx.image-version"]' "${check}/art/manifest.json")" == "${image_version}" ]]
raw_blob="$(jq -r '.layers[] | select(.annotations["org.opencontainers.image.title"] == "wrasse-dx.raw") | .digest' "${check}/art/manifest.json")"
cmp "${check}/art/${raw_blob#sha256:}" "${dir}/wrasse-dx.raw"

{
    echo "### DX sysext published: ${image_id} ${image_version}"
    echo ""
    echo "- \`${repo}:${tag}\` (\`${digest}\`), aliases \`${image_id}-${line}\`, \`${image_id}-f${fedora}\`"
    echo "- signed with the Wrasse key and fetched back through the image's trust policy"
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
