#!/usr/bin/env bash
# Link the shared agent notes to ~/AGENTS.md so any coding agent that reads AGENTS.md
# (Claude Code does, when no CLAUDE.md applies) learns Wrasse's rules. Runs once per
# version: if the user deletes the link, it stays deleted. An existing file or link is
# never replaced.
set -euo pipefail

# shellcheck disable=SC1091
source /usr/lib/ublue/setup-services/libsetup.sh

AGENTS_SRC="${WRASSE_AGENTS_MD_SRC:-/usr/share/wrasse/AGENTS.md}"

[[ -f "${AGENTS_SRC}" ]] || exit 0

version-script wrasse-agents-md user 1 || exit 0

link="${HOME}/AGENTS.md"
if [[ -e "${link}" || -L "${link}" ]]; then
    exit 0
fi
ln -s "${AGENTS_SRC}" "${link}"
