#!/usr/bin/env bash
# Link the system Wrasse skill into the user's agent skill directories.
# ~/.claude/skills is where Claude Code reads personal skills (symlinked skill
# directories are followed). ~/.agents/skills is the shared location other
# agent tools read. Runs once per version: if the user deletes a link, it stays
# deleted. An existing real directory or other link at the target is never replaced.
set -euo pipefail

# shellcheck disable=SC1091
source /usr/lib/ublue/setup-services/libsetup.sh

SKILL_SRC="${WRASSE_SKILL_SRC:-/usr/share/wrasse/skills/wrasse}"

[[ -f "${SKILL_SRC}/SKILL.md" ]] || exit 0

version-script wrasse-agent-skill user 1 || exit 0

for dir in "${HOME}/.claude/skills" "${HOME}/.agents/skills"; do
    link="${dir}/wrasse"
    if [[ -e "${link}" || -L "${link}" ]]; then
        continue
    fi
    mkdir -p "${dir}"
    ln -s "${SKILL_SRC}" "${link}"
done
