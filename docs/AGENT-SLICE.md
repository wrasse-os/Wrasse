# Agent memory slice

Coding agents (Claude Code and the build, test and language-server processes it spawns) can allocate memory faster than a
desktop session can tolerate. Without a boundary, the kernel stalls the whole machine in reclaim and the user sees a frozen
screen. `wrasse-agents.slice` is that boundary: the agent slows down first, and if that is not enough, `systemd-oomd`
kills the agent instead of the desktop.

Files (all in the image, no per-user setup):

- `/usr/lib/systemd/user/wrasse-agents.slice`: `MemoryHigh=60%`, `ManagedOOMMemoryPressure=kill`.
- `/usr/lib/systemd/user/wrasse-agents.slice.d/20-oomd.conf`: `ManagedOOMMemoryPressureLimit=50%`,
  `ManagedOOMMemoryPressureDurationSec=20s`.
- `/usr/bin/claude` (the lazy stub) starts the real binary with
  `systemd-run --user --scope --slice=wrasse-agents.slice`. `WRASSE_AGENT_NO_SLICE=1` skips the slice.
- `systemd-oomd.service` is enabled in the image build (`17-cleanup.sh`) and checked in `20-tests.sh`.

## Proposed limits and why

| Setting | Value | Reasoning |
|---|---|---|
| `MemoryHigh` | `60%` of RAM | The desktop (GNOME Shell, a browser, Flatpak apps) needs roughly a third of RAM to stay responsive. Leaving 40% means the agent can use a lot (a big build, several test workers) but not everything. Above this the kernel throttles the slice and reclaims from it aggressively (into zram first), which slows the agent rather than the desktop. It is a soft limit: nothing is killed by it. |
| `MemoryMax` | not set | A hard cap makes the kernel OOM-kill inside the cgroup with no warning and no chance to relieve pressure first. `MemoryHigh` plus oomd gives a gentler, earlier response. Revisit if a runaway process ever outruns oomd (see below). |
| `ManagedOOMMemoryPressure` | `kill` | Makes the slice a candidate for `systemd-oomd`. oomd kills the descendant cgroup (the agent's scope) with the most reclaim activity, with SIGKILL, so the whole agent and its children go together. |
| `ManagedOOMMemoryPressureLimit` | `50%` | Pressure is the share of a 10 s window in which tasks in the slice were stalled on memory. A throttled agent (above `MemoryHigh`) shows up as pressure, so this is "throttled for half the time". oomd's default is 60%, and Fedora's `systemd-oomd-defaults` sets 80% on every user slice. 50% makes the agent the first thing to go. |
| `ManagedOOMMemoryPressureDurationSec` | `20s` | Must hold for 20 s before the kill (oomd default 30 s). Long enough to ride out a short compile spike, short enough that a real runaway is stopped before the desktop starves. The minimum allowed is 1 s. |

Percentages are supported by `MemoryHigh=` (relative to installed RAM; `systemd.resource-control(5)`), so the same files fit a
4 GB laptop (about 2.4 GB) and a 64 GB workstation (about 38 GB). `ManagedOOMMemoryPressureDurationSec=` needs systemd 257 or
newer; Fedora 43 and later ship 258 or newer.

Swap: with zram the system seldom reaches 100% swap before it stalls, so the pressure signal is the right trigger. The slice
does not set `ManagedOOMSwap`.

## Verified on a Fedora 44 host (systemd 259)

- `systemd-run --user --scope --slice=wrasse-agents.slice -- ...` lands the process in
  `user@UID.service/wrasse.slice/wrasse-agents.slice/run-*.scope`. A dash in a slice name means nesting, so systemd creates
  an implicit parent `wrasse.slice`. Fedora's defaults also mark that parent `kill` at 80%; harmless.
- `oomctl` lists `wrasse-agents.slice` with limit 50% and duration 20 s, and `MemoryHigh` is 60% of RAM.
- **A setting in the slice file does not win over `/usr/lib/systemd/user/slice.d/10-oomd-per-slice-defaults.conf`** (the
  Fedora default, applied to every slice, which sorted later). With the limit written in `wrasse-agents.slice` itself, oomctl
  showed 80%. That is why the limit and duration live in `wrasse-agents.slice.d/20-oomd.conf`, a drop-in whose file name sorts
  after `10-`.
- `systemd-oomd` is not a separate package on Fedora 44: the binary ships in `systemd-udev`, and `systemd-oomd-defaults`
  adds the per-slice defaults. Fedora's preset (`90-default.preset`, `enable systemd-oomd.*`) already enables it; the image
  build also enables it explicitly so a changed preset cannot silently turn the slice into a no-op.

## What the user sees

- Under heavy load the agent gets slow first.
- If pressure stays above 50% for 20 s, the agent scope is killed. The terminal shows `Killed`. Nothing else is touched.
  `claude --resume` continues the session. `journalctl -b -u systemd-oomd` (or `journalctl --user`) records the kill.

## Tuning (per user, no image change)

```fish
mkdir -p ~/.config/systemd/user/wrasse-agents.slice.d
printf '[Slice]\nMemoryHigh=75%%\n' > ~/.config/systemd/user/wrasse-agents.slice.d/90-local.conf
systemctl --user daemon-reload
```

Running agents keep the old limits until restarted. Check the live values with `systemctl --user show wrasse-agents.slice -p MemoryHigh`
and `oomctl`.

## Not verified here

- A real out-of-memory run: oomd actually killing a runaway scope under pressure. Needs a machine you can afford to stress.
  Suggested test: `systemd-run --user --scope --slice=wrasse-agents.slice -- python3 -c 'import time; a = []; [a.append(bytearray(10**7)) or time.sleep(0.01) for _ in range(10**6)]'`,
  watching `oomctl` and `journalctl -f -u systemd-oomd` in other terminals.
- Behaviour with no user manager (a bare `su`): the stub then starts Claude Code without the slice and says so.
