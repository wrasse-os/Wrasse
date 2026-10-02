#!/usr/bin/env bash
# Resolve the Fedora version behind each Wrasse release line, and build the CI matrix.
#
#   resolve-lines.sh versions            JSON: stable/beta/branched and the three lines
#   resolve-lines.sh version <line>      Fedora major version for one line
#   resolve-lines.sh prerelease <line>   "1" if that version is not a final Fedora release yet, else "0"
#   resolve-lines.sh matrix [config]     JSON {"include": [...]} for GitHub Actions, one entry per image cell
#
# Lines: stable = newest final Fedora; next = newest Fedora beta, else stable;
# reimagined = branched (pre-beta or beta, never Rawhide), else next.
#
# Sources (checked against live data, not memory):
#   Bodhi releases API: state "current" = final; state "pending" with a non-rawhide branch = branched.
#   dl.fedoraproject.org/pub/fedora/linux/releases/test/NN_Beta/ exists while NN is in beta.
# Any lookup failure exits non-zero: no guessing, so the caller builds nothing.
set -euo pipefail

BODHI="${BODHI_URL:-https://bodhi.fedoraproject.org}"
TEST_DIR="${FEDORA_TEST_URL:-https://dl.fedoraproject.org/pub/fedora/linux/releases/test/}"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CONFIG="${SELF_DIR}/../build-matrix.json"

fetch() {
    curl --fail --silent --show-error --location --retry 3 --retry-delay 3 --max-time 60 "$1"
}

resolve() {
    local current pending stable branched beta listing

    current="$(fetch "${BODHI}/releases/?state=current&rows_per_page=100")"
    stable="$(jq -r '[.releases[] | select(.name | test("^F[0-9]+$")) | .version | tonumber] | max // empty' <<<"${current}")"
    if [[ -z "${stable}" ]]; then
        echo "resolve-lines: no current Fedora release found in Bodhi" >&2
        return 1
    fi

    pending="$(fetch "${BODHI}/releases/?state=pending&rows_per_page=100")"
    branched="$(jq -r '[.releases[] | select((.name | test("^F[0-9]+$")) and .branch != "rawhide") | .version | tonumber] | max // empty' <<<"${pending}")"

    listing="$(fetch "${TEST_DIR}")"
    beta="$(grep -oE 'href="[0-9]+_Beta/"' <<<"${listing}" | grep -oE '[0-9]+' | sort -n | tail -1 || true)"

    # A beta directory can outlive the final release for a short while; final wins.
    if [[ -n "${beta}" && "${beta}" -le "${stable}" ]]; then
        beta=""
    fi
    # Branched must be newer than the newest final release.
    if [[ -n "${branched}" && "${branched}" -le "${stable}" ]]; then
        branched=""
    fi

    jq -n \
        --argjson stable "${stable}" \
        --arg beta "${beta}" \
        --arg branched "${branched}" '
        def num: if . == "" then null else tonumber end;
        ($beta | num) as $b | ($branched | num) as $br |
        ($b // $stable) as $next |
        {
          stable: $stable,
          beta: $b,
          branched: $br,
          lines: { stable: $stable, next: $next, reimagined: ($br // $next) },
          prerelease: {
            stable: false,
            next: ($next > $stable),
            reimagined: (($br // $next) > $stable)
          }
        }'
}

cmd="${1:-}"
case "${cmd}" in
    versions)
        resolve
        ;;
    version)
        line="${2:?usage: resolve-lines.sh version <line>}"
        resolve | jq -er --arg l "${line}" '.lines[$l]'
        ;;
    prerelease)
        line="${2:?usage: resolve-lines.sh prerelease <line>}"
        resolve | jq -er --arg l "${line}" 'if .prerelease[$l] then "1" else "0" end'
        ;;
    matrix)
        config="${2:-${DEFAULT_CONFIG}}"
        resolved="$(resolve)"
        jq -c --argjson r "${resolved}" '
            [ .lines | to_entries[] | . as $e
              | (["default"] + (if $e.value.nvidia then ["nvidia"] else [] end))[] as $flavor
              | {
                  line: $e.key,
                  flavor: $flavor,
                  fedora_version: ($r.lines[$e.key] | tostring),
                  prerelease: (if $r.prerelease[$e.key] then "1" else "0" end),
                  akmods_flavor: $e.value.akmods_flavor,
                  kernel_pin: ($e.value.kernel_pin // "")
                }
            ] | {include: .}' "${config}"
        ;;
    *)
        echo "usage: resolve-lines.sh versions|version <line>|prerelease <line>|matrix [config]" >&2
        exit 2
        ;;
esac
