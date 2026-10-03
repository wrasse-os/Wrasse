#!/usr/bin/bash
# Builds /out/wrasse-dx.raw, a systemd-sysext (erofs) with the Wrasse developer tools.
# Runs in the `dx-build` Containerfile stage, which is `FROM base` (the finished image),
# so `dnf download --resolve` only fetches what the image does not already ship and the
# extension-release can be copied from the image's own os-release.
# Method follows github.com/fedora-sysexts/fedora (sysext.just): download RPMs, extract
# them with rpm2cpio, move /etc to /usr/etc, merge sbin into bin, label, mkfs.erofs.

echo "::group:: ===$(basename "$0")==="

set -euo pipefail

SYSEXT_NAME="wrasse-dx"
OUT_DIR="/out"
WORK_DIR="/tmp/dx-work"
ROOTFS="${WORK_DIR}/rootfs"
RPMS="${WORK_DIR}/rpms"
FILES_DIR="/ctx/build_files/dx/files"
FILE_CONTEXTS="/etc/selinux/targeted/contexts/files/file_contexts"

# Packages from Fedora repos. Dependencies already in the image are not downloaded.
PACKAGES=(
    # Docker (Fedora's moby-engine, not Docker Inc's docker-ce, so no third-party repo
    # has to track branched Fedora)
    moby-engine
    docker-compose
    docker-buildx
    # Podman extras (podman itself is in the image)
    podman-compose
    podman-machine
    podman-tui
    udica
    # libvirt / QEMU
    libvirt-client
    libvirt-daemon-config-network
    libvirt-daemon-kvm
    libvirt-nss
    qemu-img
    qemu-kvm
    edk2-ovmf
    swtpm
    virt-install
    virt-manager
    virt-viewer
    # VS Code (Microsoft repo, enabled for this stage only)
    code
    cascadia-code-fonts
    # Performance tools
    bcc
    bpftop
    bpftrace
    iotop-c
    nicstat
    numactl
    perf
    sysprof
    sysstat
    tiptop
    trace-cmd
    # GNOME / GTK development
    flatpak-builder
    gjs-devel
    gtk4-devel
    libadwaita-devel
    mutter-devel
    # Android
    waydroid
)

# Same RPM-to-sysext constraints as fedora-sysexts: a sysext only merges /usr (and /opt).
for tool in rpm2cpio cpio mkfs.erofs fsck.erofs dump.erofs; do
    if ! command -v "${tool}" >/dev/null; then
        dnf5 -y install cpio erofs-utils
        break
    fi
done

tee /etc/yum.repos.d/vscode.repo <<'REPO'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=0
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
REPO

rm -rf "${WORK_DIR}"
mkdir -p "${RPMS}" "${ROOTFS}" "${OUT_DIR}"

arch="$(uname -m)"
case "${arch}" in
    x86_64) sysext_arch="x86-64" ;;
    aarch64) sysext_arch="arm64" ;;
    *) echo "Unsupported architecture: ${arch}" >&2; exit 1 ;;
esac

echo "Downloading ${#PACKAGES[@]} packages plus dependencies missing from the image"
dnf5 -y download --resolve --enablerepo=code --arch=noarch --arch="${arch}" \
    --destdir="${RPMS}" "${PACKAGES[@]}"

echo "Extracting RPMs"
cd "${ROOTFS}"
for rpm in "${RPMS}"/*.rpm; do
    rpm2cpio "${rpm}" | cpio -idm --quiet
done

# Overlay files shipped by Wrasse (sysctl, modules-load, tmpfiles, units, VS Code hook).
cp -a "${FILES_DIR}/usr" "${ROOTFS}/"

# /etc is not merged by sysext: move defaults to /usr/etc.
if [[ -d etc ]]; then
    mkdir -p usr/etc
    cp -a --no-clobber etc/. usr/etc/
    rm -rf etc
fi

# bin/sbin merge (Fedora 42+): everything under /usr/sbin goes to /usr/bin, /sbin to /usr/bin.
for d in usr/sbin sbin; do
    if [[ -d "${d}" ]]; then
        mkdir -p usr/bin
        cp -a --no-clobber "${d}"/. usr/bin/
        rm -rf "${d}"
    fi
done
if [[ -d lib64 ]]; then
    mkdir -p usr/lib64
    cp -a --no-clobber lib64/. usr/lib64/
    rm -rf lib64
fi

# Libraries from /etc/ld.so.conf.d are not read from /usr/etc; install them where ldconfig looks.
if [[ -d usr/etc/ld.so.conf.d ]]; then
    mkdir -p usr/lib/ld.so.conf.d
    cp -a --no-clobber usr/etc/ld.so.conf.d/. usr/lib/ld.so.conf.d/
fi

# sysext ignores /var, /run and /boot: drop them (state comes from tmpfiles.d/sysusers.d).
rm -rf var run boot

# /opt is not supported by this layout; fail loudly so a package gets handled explicitly.
if [[ -e opt ]]; then
    echo "Package payload contains /opt, which sysext cannot serve here. Move it under /usr/lib." >&2
    ls -la opt >&2
    exit 1
fi

# Everything left at the top must be usr.
extra="$(find . -mindepth 1 -maxdepth 1 ! -name usr -printf '%f\n')"
if [[ -n "${extra}" ]]; then
    echo "Unexpected top-level entries in the sysext: ${extra}" >&2
    exit 1
fi

# Sanity: the tools and units that ujust dx on relies on must be in the payload.
for path in \
    usr/bin/dockerd usr/bin/docker usr/bin/virsh usr/bin/code usr/bin/bpftrace usr/bin/waydroid \
    usr/lib/systemd/system/docker.socket usr/lib/systemd/system/virtqemud.socket \
    usr/lib/systemd/system/virtnetworkd.socket usr/lib/systemd/system/wrasse-dx-libvirt-relabel.service \
    usr/lib/sysusers.d/moby-engine.conf; do
    [[ -e "${path}" || -L "${path}" ]] || { echo "Missing from sysext: ${path}" >&2; exit 1; }
done
ls usr/libexec/docker/cli-plugins/ 2>/dev/null || true

# extension-release must match the host image. ID is taken from the image's os-release
# (so it follows any rename of the OS), VERSION_ID is the Fedora release.
# shellcheck disable=SC1091
image_id="$(. /usr/lib/os-release && printf '%s' "${ID}")"
# shellcheck disable=SC1091
image_version_id="$(. /usr/lib/os-release && printf '%s' "${VERSION_ID}")"
if [[ -z "${image_id}" || -z "${image_version_id}" ]]; then
    echo "os-release has no ID or VERSION_ID" >&2
    exit 1
fi
install -d -m 0755 usr/lib/extension-release.d
cat > "usr/lib/extension-release.d/extension-release.${SYSEXT_NAME}" <<EOT
ID=${image_id}
VERSION_ID=${image_version_id}
ARCHITECTURE=${sysext_arch}
EXTENSION_RELOAD_MANAGER=1
EOT

# Plain-text copy next to the image so the final stage (no erofs tools) can check it
# against os-release without mounting the sysext.
cp "usr/lib/extension-release.d/extension-release.${SYSEXT_NAME}" "${OUT_DIR}/${SYSEXT_NAME}.extension-release"

# Label every file from the image's own policy so SELinux sees the right types after merge.
if [[ ! -f "${FILE_CONTEXTS}" ]]; then
    echo "Missing ${FILE_CONTEXTS}; cannot label the sysext" >&2
    exit 1
fi

echo "Creating erofs image (lz4, SELinux labels from ${FILE_CONTEXTS})"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(date +%s)}"
mkfs.erofs -zlz4 -T "${SOURCE_DATE_EPOCH}" --all-root \
    --file-contexts="${FILE_CONTEXTS}" \
    "${OUT_DIR}/${SYSEXT_NAME}.raw" "${ROOTFS}" >/dev/null

fsck.erofs "${OUT_DIR}/${SYSEXT_NAME}.raw"
dump.erofs --path="/usr/lib/extension-release.d/extension-release.${SYSEXT_NAME}" "${OUT_DIR}/${SYSEXT_NAME}.raw"

# Size report, shown in the build log (CI also reports it from the finished image).
stat -c 'wrasse-dx.raw: %s bytes' "${OUT_DIR}/${SYSEXT_NAME}.raw"
du -sh "${ROOTFS}" | sed 's/^/uncompressed rootfs: /'

echo "::endgroup::"
