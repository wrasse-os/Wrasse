# Wrasse: working rules

Wrasse is a hard fork of Universal Blue's Bluefin: a Fedora bootc desktop image, agent-first, opinionated, GNOME.
Repo: github.com/wrasse-os/Wrasse. Images publish to `ghcr.io/wrasse-os/wrasse` (always lowercase).
This is a monorepo: `projectbluefin/common` is vendored into `system_files/`. Read `docs/SPEC.md` for the phases and
their status. "Continue with the next phase" means: next `todo` phase in `docs/SPEC.md`.

## How we work

- Stop at the end of every phase. Report: commits made, anything skipped or uncertain, what needs real-hardware or CI
  verification by the user. Do not start the next phase without the user's go-ahead (unless the user said to run all phases).
- Verify against the actual repo and current upstream docs. Never assume Bluefin's layout, tool flags or file paths match
  descriptions. If reality conflicts with the spec, stop and say so (or mark the item `blocked` in `docs/SPEC.md`).
- Hard fork: edit Bluefin's scripts directly where changes logically belong. Delete code outright; never comment it out.
  Every change gets a short entry in `DIVERGENCE.md` (what + why).
- One concern per commit. Prefixes: `remove:`, `add:`, `brand:`, `memory:`, `shell:`, `ci:`, `dx:`, `agent:`, `cli:`,
  `installer:`, `docs:`. Commits end with the attribution trailer the harness specifies.
- Ask before: pushing, deleting remote branches, changing secrets or signing keys, anything heavy. Never run a full image
  build locally (the user's machine freezes under memory pressure). Linting, shellcheck, `just --list`, unit tests and
  syntax checks are fine.
- Shell commands for the user to run: fish syntax. Build scripts: bash. New CLI tooling: Rust. No OOP-heavy abstractions.
- Items under "Pending decisions" in `docs/SPEC.md`: stop and ask the user. Do not pick for them. When running without the
  user, mark the dependent work `blocked` and implement everything that does not depend on the decision.
- Do not rename Bluefin branding yet (`brand:` is deferred). Do not rename real ublue-os plumbing (akmods, brew, base
  images, COPRs, akmods signing keys).
