#!/usr/bin/bash
# Tests for installer/gen-catalog.sh and wrasse-installer-config. Needs jq. No root, no hardware.
# Usage: installer/tests/test-catalog.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
gen="${root}/installer/gen-catalog.sh"
render="${root}/installer/iso/variant/wrasse/wrasse-installer-config"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
leaves() { jq -r '[.. | objects | select(has("imgref")) | .imgref] | .[]' "$1"; }

# 1. The real matrix: all six images, in the spec's naming, ready for the placeholder.
"${gen}" > "${work}/tmpl.json"
[[ "$(jq -r .default_image "${work}/tmpl.json")" == "@DEFAULT_IMAGE@" ]] || fail "placeholder missing"
mapfile -t got < <(leaves "${work}/tmpl.json" | sort)
want=$(jq -r '.lines | to_entries[] | .key as $l | ("wrasse", (if .value.nvidia then "wrasse-nvidia" else empty end)) | "ghcr.io/wrasse-os/\(.):\($l)"' "${root}/.github/build-matrix.json" | sort)
[[ "${got[*]}" == "$(echo "${want}" | tr '\n' ' ' | sed 's/ $//')" ]] || fail "leaves ${got[*]} != matrix ${want}"
for ref in "${got[@]}"; do [[ "${ref}" == "${ref,,}" ]] || fail "uppercase in ${ref}"; done
jq -e '.images[0] | .bootloader == "systemd" and .composefs == true and .needs_user_creation == true' "${work}/tmpl.json" >/dev/null || fail "image defaults"

# 2. A line with nvidia=false gets no NVIDIA leaf.
jq '.lines.reimagined.nvidia = false' "${root}/.github/build-matrix.json" > "${work}/m.json"
"${gen}" "${work}/m.json" | jq -e '[.. | objects | select(has("imgref")) | .imgref] | index("ghcr.io/wrasse-os/wrasse-nvidia:reimagined") == null and index("ghcr.io/wrasse-os/wrasse:reimagined") != null' >/dev/null || fail "nvidia=false not honored"

# 3. No NVIDIA line at all drops the NVIDIA group.
jq '.lines |= map_values(.nvidia = false)' "${root}/.github/build-matrix.json" > "${work}/m.json"
"${gen}" "${work}/m.json" | jq -e '[.. | objects | select(has("imgref")) | .imgref | select(contains("nvidia"))] | length == 0' >/dev/null || fail "empty nvidia group kept"

# 4. Render with a stub detector for each flavor: default_image is a real leaf of the right image.
mkdir -p "${work}/bin"
for flavor in wrasse wrasse-nvidia; do
    printf '#!/usr/bin/bash\necho %s\n' "${flavor}" > "${work}/bin/wrasse-gpu-detect"
    chmod +x "${work}/bin/wrasse-gpu-detect"
    PATH="${work}/bin:${PATH}" WRASSE_INSTALLER_TEMPLATE="${work}/tmpl.json" WRASSE_INSTALLER_CATALOG="${work}/out-${flavor}.json" "${render}" >/dev/null
    d="$(jq -r .default_image "${work}/out-${flavor}.json")"
    [[ "${d}" == "ghcr.io/wrasse-os/${flavor}:stable" ]] || fail "default_image ${d} for ${flavor}"
    leaves "${work}/out-${flavor}.json" | grep -qxF "${d}" || fail "default_image ${d} is not a catalog leaf"
done

# 5. A failing detector falls back to wrasse; garbage output does too.
printf '#!/usr/bin/bash\nexit 1\n' > "${work}/bin/wrasse-gpu-detect"
PATH="${work}/bin:${PATH}" WRASSE_INSTALLER_TEMPLATE="${work}/tmpl.json" WRASSE_INSTALLER_CATALOG="${work}/out-fail.json" "${render}" >/dev/null
[[ "$(jq -r .default_image "${work}/out-fail.json")" == "ghcr.io/wrasse-os/wrasse:stable" ]] || fail "failing detector"
printf '#!/usr/bin/bash\necho "a|b"\n' > "${work}/bin/wrasse-gpu-detect"
PATH="${work}/bin:${PATH}" WRASSE_INSTALLER_TEMPLATE="${work}/tmpl.json" WRASSE_INSTALLER_CATALOG="${work}/out-bad.json" "${render}" >/dev/null 2>&1
[[ "$(jq -r .default_image "${work}/out-bad.json")" == "ghcr.io/wrasse-os/wrasse:stable" ]] || fail "garbage detector output"

# 6. The recipe is valid JSON, has the installer's required keys, and keeps the image step.
jq -e 'has("log_file") and has("distro_name") and has("distro_logo") and (.steps | has("image") and has("disk"))' "${root}/installer/iso/variant/wrasse/recipe.json" >/dev/null || fail "recipe.json"

echo "ok"
