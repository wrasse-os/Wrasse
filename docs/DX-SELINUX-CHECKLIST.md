# DX sysext: SELinux and bring-up checklist

Nothing here has been run. The DX sysext (`wrasse-dx.raw`) is downloaded by `ujust dx on` (it is not in the image) and was written
without a build, so every item below is a check for you on a booted Wrasse image with SELinux **enforcing** (`getenforce` prints `Enforcing`). Commands are fish.

Keep a second terminal on `journalctl -f` and a third on `sudo ausearch -m avc -ts recent` (or `sudo journalctl -t setroubleshoot`)
as you go. Any AVC denial is a finding: note the `scontext`, `tcontext`, `tclass` and the path.

If DX breaks boot, see `docs/SAFE-MODE.md` (`wrasse.safe=1` at the GRUB menu).

## Known risks (why this list exists)

- The `.raw` is labelled at build time from the image's `file_contexts` (`mkfs.erofs --file-contexts`), not by a running kernel.
  If the labels are wrong, everything under `/usr` from the sysext is `unlabeled_t` or `usr_t` and daemons are denied.
- Docker and libvirt rely on container-selinux and the `virt` policy that ship in the base image. The sysext only adds binaries.
- `/etc` content from RPMs lands in `/usr/etc` and is **not** read by the daemons (libvirt config, waydroid menu). Defaults apply.
- Adding yourself to `docker` is root equivalent. That is Docker's design, not a Wrasse bug.
- Waydroid needs `binder_linux`/binderfs support from the kernel and may not work at all on the Fedora kernel. Treat a failure
  there as expected until proven otherwise.

## 1. Image sanity (before `ujust dx on`)

```fish
grep -E '^(ID|VERSION_ID|IMAGE_ID|IMAGE_VERSION)=' /usr/lib/os-release
ls /usr/share/wrasse/sysexts   # must not exist
systemd-sysext status
ujust dx status
```

- [ ] `IMAGE_ID` and `IMAGE_VERSION` are set; there is no `/usr/share/wrasse/sysexts` (the image does not carry DX).
- [ ] `/var/lib/extensions/` has no `wrasse-dx.raw` yet; `docker` and `code` are not on `PATH` (DX is off by default); `ujust dx status` says `cached: no`.
- [ ] The package `ghcr.io/wrasse-os/wrasse-dx` is public (see `docs/CI-SECRETS.md`) and has a tag `<IMAGE_ID>-<IMAGE_VERSION>` for this image.

## 2. Turn it on

```fish
ujust dx on
ujust dx status
```

- [ ] `ujust dx on` downloads about 1.4 GB, finishes without errors and says to log out. `merged: yes` in `ujust dx status`.
- [ ] `/var/lib/wrasse/sysexts/<IMAGE_ID>-<IMAGE_VERSION>/` holds `wrasse-dx.raw` and `wrasse-dx.extension-release` (`ID` and `VERSION_ID` match
      os-release) and `/var/lib/extensions/wrasse-dx.raw` links to it.
- [ ] Labels of the on-demand paths: `ls -dZ /var/lib/wrasse /var/lib/wrasse/sysexts /var/lib/extensions` and `ls -lZ /var/lib/extensions/`; no AVC from
      `systemd-sysext` or `init_t` reading the linked file (a `var_lib_t` file behind a symlink in `/var/lib/extensions` is the thing to watch).
- [ ] Signature enforcement: with the network up, `skopeo --policy /usr/share/wrasse/dx/policy.json --registries.d /usr/share/wrasse/dx/registries.d inspect --no-tags docker://ghcr.io/wrasse-os/wrasse-dx:<IMAGE_ID>-<IMAGE_VERSION>`
      succeeds, and the same with `--policy` pointing at a policy using another key fails.
- [ ] `systemctl is-enabled wrasse-dx-select.service` says `enabled`; `ujust dx on` a second time says the sysext is already downloaded.
- [ ] `systemd-sysext status` lists `wrasse-dx` under `/usr`.
- [ ] `journalctl -b -u systemd-sysext` has no mount errors, and no AVC for `systemd-sysext` or `loop`.

Log out and back in (group membership), then:

```fish
id -nG | tr ' ' \n | grep -E 'docker|libvirt'
```

- [ ] You are in `docker` and `libvirt`.

## 3. Labels the build assigned

```fish
ls -Z /usr/bin/dockerd /usr/bin/docker /usr/bin/virsh /usr/bin/qemu-system-x86_64 /usr/bin/code
ls -Z /usr/lib/systemd/system/docker.socket /usr/lib/systemd/system/virtqemud.socket
ls -dZ /usr/share/code /usr/libexec/docker/cli-plugins
```

- [ ] `dockerd` is `container_runtime_exec_t`.
- [ ] `qemu-system-x86_64` is `qemu_exec_t`; `virtqemud` (find it with `ls -Z /usr/bin/virtqemud`) is `virtqemud_exec_t`.
- [ ] Unit files are `systemd_unit_file_t`; nothing important is `unlabeled_t` or `usr_t` where a real type is expected.

Cross-check against policy for any path that looks wrong:

```fish
matchpathcon /usr/bin/dockerd
sudo restorecon -Rnv /usr/bin /usr/lib/systemd/system | head -50
```

`restorecon -n` should print nothing for sysext files. If it lists many, the build-time labelling failed: report it.

## 4. Docker with SELinux enforcing

```fish
systemctl status docker.socket --no-pager
docker run --rm hello-world
docker run --rm -v /tmp:/data:Z alpine ls /data
docker compose version
docker buildx version
```

- [ ] `hello-world` runs, no AVC from `container_runtime_t`.
- [ ] A `:Z` bind mount works and relabels (`ls -dZ /tmp` shows a `container_file_t` MCS label afterwards; run `restorecon -v /tmp` to undo).
- [ ] `docker compose` and `docker buildx` work (plugins live in `/usr/libexec/docker/cli-plugins`).
- [ ] After `sudo systemctl restart docker`, containers with a published port are reachable (iptables or nftables, `ip_forward=1`:
      `sysctl net.ipv4.ip_forward`).
- [ ] `lsmod | grep iptable_nat` is loaded (modules-load drop-in from the sysext).
- [ ] Docker-in-docker: `docker run --rm --privileged docker:dind --version` starts (privileged containers are a known SELinux edge).
- [ ] Rootless Podman still works next to Docker: `podman run --rm alpine true`.

## 5. libvirt and QEMU with SELinux enforcing

```fish
systemctl is-active virtqemud.socket virtnetworkd.socket virtstoraged.socket
virsh -c qemu:///system list --all
virsh -c qemu:///system net-start default
ls -dZ /var/lib/libvirt /var/log/libvirt
```

- [ ] The sockets are active; `virsh` connects without a polkit prompt failing (your user is in `libvirt`).
- [ ] The `default` network starts (dnsmasq and nftables work).
- [ ] `/var/lib/libvirt` is `virt_var_lib_t`, `/var/log/libvirt` is `virt_log_t` (the `wrasse-dx-libvirt-relabel.service` fixed them:
      `systemctl status wrasse-dx-libvirt-relabel.service`).
- [ ] Create and boot a small VM in virt-manager (UEFI with `edk2-ovmf`, TPM with `swtpm`). Check
      `ps -eZ | grep qemu` shows `svirt_t` with an MCS pair, and there is no AVC for `svirt_t` or `virtqemud_t`.
- [ ] A VM disk image kept in `~/` is refused until labelled (expected); one in `/var/lib/libvirt/images` works.
- [ ] Optional: `/usr/etc/libvirt` holds the stock configs. If you need changes, copy to `/etc/libvirt` and restart the daemons.

## 6. VS Code

```fish
code --version
ls -Z /usr/share/code/code
```

- [ ] `code` starts from the app grid and a terminal; the extensions in the first-login hook install (`code --list-extensions`).
- [ ] The Dev Containers extension can attach to a container started with the Docker socket.

## 7. Perf and GNOME dev tools

```fish
sudo bpftrace -e 'BEGIN { printf("ok\n"); exit(); }'
sudo bpftop --help | head -2
pkg-config --modversion gtk4 libadwaita-1
```

- [ ] bpftrace runs under enforcing; if it is denied, record the AVC (BPF needs `bpf` and `perfmon` permissions).
- [ ] `mutter-devel`, `gjs-devel`, `gtk4-devel`, `libadwaita-devel` headers exist under `/usr/include`.

## 8. Waydroid (best effort)

```fish
systemctl status waydroid-container.service --no-pager
sudo waydroid init
```

- [ ] Note whether `binder_linux` or binderfs is available (`ls /dev/binderfs` or `dmesg | grep -i binder`). If not, waydroid cannot run here.

## 9. Reboot persistence

```fish
systemctl reboot
```

After the reboot:

- [ ] `ujust dx status` says `merged: yes` without you doing anything (`wrasse-dx-select.service` re-linked the cached file before `systemd-sysext.service`;
      `journalctl -b -u wrasse-dx-select.service`).
- [ ] `docker.socket` and `virtqemud.socket` are active; no failed units (`systemctl --failed`).

## 10. Update and rollback

- [ ] `sudo bootc upgrade`, then `ujust dx update` before rebooting: it also downloads the sysext of the staged image (`ujust dx status` after the
      reboot says `cached: yes`). Reboot: DX is still on and `systemd-sysext status` shows the new image's sysext.
- [ ] Upgrade again and reboot **without** `ujust dx update`: DX is off (`merged: no`, no `/var/lib/extensions/wrasse-dx.raw`, the selector logs
      "no cached DX sysext"), the system boots normally, and `ujust dx update` brings it back.
- [ ] After a Fedora major bump the old sysext must **not** merge (it is not even linked: different `IMAGE_VERSION`). Verify with
      `journalctl -b -u wrasse-dx-select.service -u systemd-sysext`.
- [ ] `sudo bootc rollback`, reboot: DX uses the rollback image's cached file (if `ujust dx update` pruned it, `ujust dx update` fetches it again).
- [ ] Offline (network off): `ujust dx on` with nothing cached fails with the "needs network" message and changes nothing; with the file cached it succeeds.

## 11. Turn it off

```fish
docker ps -q | xargs -r docker stop
ujust dx off
ujust dx status
ls /var/lib/docker | head -3
```

- [ ] `merged: no`; `docker` and `code` are gone from `PATH`; the units are disabled (`systemctl is-enabled docker.socket` fails);
      `systemctl is-enabled wrasse-dx-select.service` fails and `/var/lib/extensions/wrasse-dx.raw` is gone; the cache is still there until `ujust dx off purge`.
- [ ] If it says something under `/usr` is still in use, close VS Code and any containers, then reboot. The link is already
      removed, so DX will be off after the reboot.
- [ ] `/var/lib/docker` and `/var/lib/libvirt` still exist. Turning DX on again finds them and everything still works.
- [ ] `getent group docker` still lists nobody from your user (`id -nG`), and `getenforce` is still `Enforcing`.

## What to send back

For every unchecked box: the exact command, the output, and the AVC lines from `sudo ausearch -m avc -ts recent`. With the AVC
list, `audit2allow -a` suggests rules, but treat those as a hint, not a fix to apply blindly.
