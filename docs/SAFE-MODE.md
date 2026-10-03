# Safe mode: boot with all sysexts off

If the DX sysext (`wrasse-dx.raw`) breaks boot or the desktop, you can boot once without it, then fix it from a working session.

## What it does

`/usr/lib/systemd/system/systemd-sysext.service.d/10-wrasse-safe-mode.conf` adds `ConditionKernelCommandLine=!wrasse.safe=1` to
`systemd-sysext.service`. With `wrasse.safe=1` on the kernel command line the unit is skipped, so nothing under
`/etc/extensions`, `/run/extensions` or `/var/lib/extensions` is merged into `/usr` for that boot. The condition is a plain (non
`|`) one, so it is ANDed with the unit's existing "directory not empty" OR group (see `systemctl cat systemd-sysext.service`).
The `ujust dx` symlink in `/etc/extensions` is left alone, so the next normal boot merges DX again.

## Use it (one boot)

1. At the GRUB menu press `e` on the Wrasse entry (hold Shift or tap Esc during firmware start-up if the menu is hidden).
2. Append `wrasse.safe=1` to the end of the line that starts with `linux`.
3. Press `Ctrl+X` (or `F10`) to boot.
4. Check: `cat /proc/cmdline` has `wrasse.safe=1` and `systemd-sysext status` shows no extensions.

The edit is not saved; the next reboot is normal.

## Make it permanent

Turn DX off with `ujust dx off` (removes the `/etc/extensions/wrasse-dx.raw` link). Do not use `ujust dx on` or `systemd-sysext
refresh` while in safe mode: they merge the sysext into the running system regardless of the kernel argument.

Other ways to get a sysext-free boot were not chosen: `systemd.mask=systemd-sysext.service` works too but needs a longer argument and
also masks a unit other tools may expect; a `bootc` `kargs.d` entry would apply to every boot, which is what `ujust dx off` is for;
an extra BLS or GRUB entry would need image-level boot loader changes that bootc owns.

## Limits

- Not tested on a booted system yet; the build-time test only checks that the drop-in is present.
- With DX unmerged, the Docker and libvirt units are missing, so units enabled by `ujust dx on` show as failed or not found.
- If the system will not boot even with `wrasse.safe=1`, pick the previous entry at GRUB or run `bootc rollback` from a working
  session (`ujust rollback`).
