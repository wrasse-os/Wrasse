# Memory tuning

The image is tuned for a desktop with zram swap. The pieces and how they fit:

| Layer | File | Value | Why |
|---|---|---|---|
| zram | `usr/lib/systemd/zram-generator.conf.d/60-wrasse-tiered.conf` | `lz4 zstd(level=3)` | Fast swap-out, cold pages recompressed by `wrasse-zram-recompress.timer`. |
| swap preference | `usr/lib/sysctl.d/99-wrasse-swappiness.conf` | `vm.swappiness=180` | zram swap is cheaper than refaulting file cache. |
| background reclaim | `99-wrasse-proactive-reclaim.conf` | `vm.watermark_scale_factor=125` | kswapd starts reclaim early. |
| MGLRU | `usr/lib/tmpfiles.d/wrasse-mglru.conf` | `min_ttl_ms=1000` | Protect the working set from thrashing for 1 s before the kernel OOM killer acts. |
| oomd | `usr/lib/systemd/oomd.conf.d/20-wrasse.conf` | see below | Kill the right cgroup before the desktop freezes. |

`20-wrasse.conf` keys (`oomd.conf(5)`, section `[OOM]`):

- `SwapUsedLimit=90%`: oomd acts on swap only when both memory and swap are over this. With high swappiness swap fills
  early, so the combined condition keeps a busy but healthy system from being touched. This is the upstream default, pinned.
- `DefaultMemoryPressureLimit=60%`: pressure is the fraction of a 10 s window in which all tasks of the cgroup were stalled
  on memory. Upstream default, pinned. Only cgroups with `ManagedOOMMemoryPressure=kill` are watched; the agent slice
  tightens it to 50% (`docs/AGENT-SLICE.md`).
- `DefaultMemoryPressureDurationSec=20s`: pressure must persist this long. Fedora ships 20 s as well; upstream default is
  30 s. Well above MGLRU's 1 s protection window, short enough to act before the desktop starves.

`systemd-oomd.service` is enabled in `17-cleanup.sh` and checked in `20-tests.sh`.
