# Wrasse OS: notes for coding agents

This machine runs Wrasse, an image-based Fedora desktop (bootc, GNOME). This file is a read-only link to
`/usr/share/wrasse/AGENTS.md`; the user can delete the link.

- `/usr` is immutable. Do not edit it. System config goes in `/etc`, only with the user's consent.
- Never `sudo dnf install`, `rpm-ostree install` or `rpm -i`. Use `wrasse install <pkg>` (Flatpak for GUI apps, brew for CLI
  tools, distrobox with `--from <distro>` for anything that needs a mutable distro). Add `--json` for machine-readable output.
- The OS is managed with bootc, not rpm-ostree: `bootc status`, `bootc upgrade`, `bootc rollback` (root; ask first).
- `ujust` runs system recipes (`ujust --list`). `ujust dx status` shows whether the developer toolchain (Docker, libvirt, dev
  headers) is on; `ujust dx on` turns it on and needs the user's say-so.
- Nothing is pre-approved. Ask before installs, removals and anything that needs root.
- Agent processes run in `wrasse-agents.slice`, a memory-limited group; keep builds and tests modest. Run other agent or MCP
  server commands the same way with `wrasse-agent-run <cmd...>`.

Details, flags and exit codes: `/usr/share/wrasse/skills/wrasse/SKILL.md` (written for Claude Code, readable by any agent).
