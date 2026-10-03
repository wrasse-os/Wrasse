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

lines_json() { jq -r '[.images[0].children[] | select(has("imgref")) | .imgref] | join(" ")' "$1"; }
escape_refs() { jq -r '[.images[0].children[] | select(has("children")) | .children[] | .imgref] | join(" ")' "$1"; }
r=ghcr.io/wrasse-os
matrix="${root}/.github/build-matrix.json"
mapfile -t lines < <(jq -r '.lines | keys_unsorted[]' "${matrix}")

# 1. The real matrix, both flavors: complete catalog, no placeholder, one top-level group, only the
# release lines as leaves in matrix order with the detected image, escape group with the other one.
for flavor in wrasse wrasse-nvidia; do
    "${gen}" "${flavor}" > "${work}/c-${flavor}.json"
    grep -q '@DEFAULT_IMAGE@' "${work}/c-${flavor}.json" && fail "placeholder left in ${flavor}"
    jq -e '.images | length == 1 and .[0].name == "Wrasse"' "${work}/c-${flavor}.json" >/dev/null || fail "${flavor}: not one Wrasse group"
    jq -e '.images[0] | .bootloader == "systemd" and .composefs == true and .needs_user_creation == true and .filesystem == "btrfs" and .filesystems == ["btrfs","xfs"]' "${work}/c-${flavor}.json" >/dev/null || fail "${flavor}: image defaults"
    jq -e '[.images[0].children[] | has("imgref")] | .[:-1] | all' "${work}/c-${flavor}.json" >/dev/null || fail "${flavor}: leaves must come first"
    jq -e '[.images[0].children[] | select(has("imgref"))] | length == '"${#lines[@]}" "${work}/c-${flavor}.json" >/dev/null || fail "${flavor}: leaf count"
    jq -e '[.images[0].children[] | select(has("children"))] | length == 1 and .[0].name == "Use different graphics drivers" and .[0].subtitle == "Only if the detected choice is wrong for your GPU"' "${work}/c-${flavor}.json" >/dev/null || fail "${flavor}: escape group"
    jq -e '.images[0].children[-1] | has("children")' "${work}/c-${flavor}.json" >/dev/null || fail "${flavor}: escape group not last"
    jq -e '[.. | objects | select(has("imgref")) | .imgref | select(. != ascii_downcase)] | length == 0' "${work}/c-${flavor}.json" >/dev/null || fail "uppercase imgref"
    jq -e '[.. | objects | select(has("imgref")) | .desc | length > 0] | all' "${work}/c-${flavor}.json" >/dev/null || fail "${flavor}: empty desc"
done
want_main="" want_other=""
for l in "${lines[@]}"; do want_main+="${r}/wrasse:${l} "; want_other+="${r}/wrasse-nvidia:${l} "; done
want_main="${want_main% }" want_other="${want_other% }"
[[ "$(lines_json "${work}/c-wrasse.json")" == "${want_main}" ]] || fail "wrasse leaves: $(lines_json "${work}/c-wrasse.json")"
[[ "$(escape_refs "${work}/c-wrasse.json")" == "${want_other}" ]] || fail "wrasse escape: $(escape_refs "${work}/c-wrasse.json")"
[[ "$(lines_json "${work}/c-wrasse-nvidia.json")" == "${want_other}" ]] || fail "nvidia leaves: $(lines_json "${work}/c-wrasse-nvidia.json")"
[[ "$(escape_refs "${work}/c-wrasse-nvidia.json")" == "${want_main}" ]] || fail "nvidia escape: $(escape_refs "${work}/c-wrasse-nvidia.json")"
jq -e '[.images[0].children[] | select(has("imgref")) | .desc] | all(contains("Mesa graphics"))' "${work}/c-wrasse.json" >/dev/null || fail "wrasse desc"
jq -e '[.images[0].children[] | select(has("imgref")) | .desc] | all(contains("NVIDIA graphics driver included"))' "${work}/c-wrasse-nvidia.json" >/dev/null || fail "nvidia desc"
jq -e '[.images[0].children[-1].children[] | .name] | all(endswith("(Mesa)"))' "${work}/c-wrasse-nvidia.json" >/dev/null || fail "escape names (Mesa)"
jq -e '[.images[0].children[-1].children[] | .name] | all(endswith("(NVIDIA)"))' "${work}/c-wrasse.json" >/dev/null || fail "escape names (NVIDIA)"
for flavor in wrasse wrasse-nvidia; do
    d="$(jq -r .default_image "${work}/c-${flavor}.json")"
    [[ "${d}" == "${r}/${flavor}:stable" ]] || fail "default_image ${d} for ${flavor}"
    jq -e --arg d "${d}" '[.images[0].children[] | select(has("imgref")) | .imgref] | index($d) != null' "${work}/c-${flavor}.json" >/dev/null || fail "default_image ${d} is not a top-level leaf"
done

# 2. nvidia=false on one line: with the nvidia flavor that line falls back to wrasse and says so,
# and it leaves the escape group of the wrasse flavor.
jq '.lines.reimagined.nvidia = false' "${matrix}" > "${work}/m.json"
"${gen}" wrasse-nvidia "${work}/m.json" > "${work}/f.json"
jq -e '.images[0].children[] | select(.name == "Reimagined") | .imgref == "'"${r}"'/wrasse:reimagined" and (.desc | contains("No NVIDIA image"))' "${work}/f.json" >/dev/null || fail "nvidia=false fallback"
jq -e '[.images[0].children[] | select(has("imgref") and .name != "Reimagined") | .imgref | contains("wrasse-nvidia")] | all' "${work}/f.json" >/dev/null || fail "other lines lost nvidia"
"${gen}" wrasse "${work}/m.json" | jq -e '[.images[0].children[-1].children[].imgref] | index("'"${r}"'/wrasse-nvidia:reimagined") == null and length == 2' >/dev/null || fail "escape group kept an nvidia=false line"

# 3. No NVIDIA line at all: wrasse flavor has no escape group; nvidia flavor falls back for every line.
jq '.lines |= map_values(.nvidia = false)' "${matrix}" > "${work}/m.json"
"${gen}" wrasse "${work}/m.json" | jq -e '[.images[0].children[] | has("children")] | any | not' >/dev/null || fail "empty escape group kept"
"${gen}" wrasse "${work}/m.json" | jq -e '[.. | objects | select(has("imgref")) | .imgref | contains("nvidia")] | any | not' >/dev/null || fail "nvidia ref without nvidia lines"
"${gen}" wrasse-nvidia "${work}/m.json" > "${work}/f.json"
jq -e '.default_image == "'"${r}"'/wrasse:stable" and ([.. | objects | select(has("imgref")) | .imgref | contains("nvidia")] | any | not)' "${work}/f.json" >/dev/null || fail "nvidia flavor without nvidia lines"

# 4. Bad flavor argument fails.
"${gen}" bogus >/dev/null 2>&1 && fail "bogus flavor accepted"
"${gen}" >/dev/null 2>&1 && fail "missing flavor accepted"

# 5. Render with a stub detector: the catalog of the detected flavor lands in the output.
# A failing detector and garbage output both fall back to wrasse.
mkdir -p "${work}/bin" "${work}/cat"
cp "${work}/c-wrasse.json" "${work}/cat/images.wrasse.json"
cp "${work}/c-wrasse-nvidia.json" "${work}/cat/images.wrasse-nvidia.json"
render_with() { # <detector script body> <out file>
    printf '#!/usr/bin/bash\n%s\n' "$1" > "${work}/bin/wrasse-gpu-detect"
    chmod +x "${work}/bin/wrasse-gpu-detect"
    PATH="${work}/bin:${PATH}" WRASSE_INSTALLER_CATALOG_DIR="${work}/cat" WRASSE_INSTALLER_CATALOG="$2" "${render}" >/dev/null 2>&1
}
for flavor in wrasse wrasse-nvidia; do
    render_with "echo ${flavor}" "${work}/out-${flavor}.json"
    cmp -s "${work}/out-${flavor}.json" "${work}/c-${flavor}.json" || fail "rendered catalog is not the ${flavor} one"
done
render_with 'exit 1' "${work}/out-fail.json"
cmp -s "${work}/out-fail.json" "${work}/c-wrasse.json" || fail "failing detector"
render_with 'echo "a|b"' "${work}/out-bad.json"
cmp -s "${work}/out-bad.json" "${work}/c-wrasse.json" || fail "garbage detector output"

# 6. The recipe is valid JSON, has the installer's required keys, and keeps the image step.
jq -e 'has("log_file") and has("distro_name") and has("distro_logo") and (.steps | has("image") and has("disk"))' "${root}/installer/iso/variant/wrasse/recipe.json" >/dev/null || fail "recipe.json"

echo "ok"
