#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# We need to have the ublue-os signing keys on the image!
# Published images without these keys won't be able to pull ghcr.io/ublue-os/*
# and can therefore not update!
# https://github.com/ublue-os/main/blob/963609eaf01f7c2bb1a76821fe6d0ec269d2df25/build_files/install.sh#L56
# https://github.com/ublue-os/packages/tree/1f77c7e7faa9ebad120609a10d79e0412376c3b7/packages/ublue-os-signing/src

KEY1=$(jq -r '.transports.docker."ghcr.io/ublue-os"[0].keyPaths[0]' /etc/containers/policy.json)
BACKUP_KEY=$(jq -r '.transports.docker."ghcr.io/ublue-os"[0].keyPaths[1]' /etc/containers/policy.json)
KEY1_SHA256="af78ecfda6eb21c35195af3739341715e9cfc3f2f5911dd9c10b0670547bf6e8"
BACKUP_KEY_SHA256="b723467015ba562d40b4645c98c51c65d8254bb59444f6e9962debcfe2315da0"

echo "${KEY1_SHA256}  ${KEY1}" | sha256sum -c -
echo "${BACKUP_KEY_SHA256}  ${BACKUP_KEY}" | sha256sum -c -

# Wrasse's own images must verify against the Wrasse key (static checks only).
WRASSE_KEY=$(jq -r '.transports.docker."ghcr.io/wrasse-os"[0].keyPath' /etc/containers/policy.json)
test "$(jq -r '.transports.docker."ghcr.io/wrasse-os"[0].type' /etc/containers/policy.json)" = "sigstoreSigned"
test "${WRASSE_KEY}" = "/usr/lib/pki/containers/wrasse.pub"
grep -q -- '-----BEGIN PUBLIC KEY-----' "${WRASSE_KEY}"
grep -q 'use-sigstore-attachments: true' /etc/containers/registries.d/wrasse-os.yaml

for i in bin/ujust share/ublue-os/just/{00-entry.just,apps.just,default.just,system.just,update.just,} ; do
   stat /usr/$i
done

test -f /usr/share/ublue-os/homebrew/fonts.Brewfile

# If this file is not on the image bazaar will automatically be removed from users systems :(
# See: https://docs.flatpak.org/en/latest/flatpak-command-reference.html#flatpak-preinstall
test -f /usr/share/flatpak/preinstall.d/bazaar.preinstall

# Make sure this garbage never makes it to an image
test -f /usr/lib/systemd/system/flatpak-add-fedora-repos.service && false

IMPORTANT_PACKAGES=(
    distrobox
    fish
    flatpak
    mutter
    pipewire
    gnome-shell
    ptyxis
    gdm
    systemd
    tailscale
    uupd
    wireplumber
    zsh
)

for package in "${IMPORTANT_PACKAGES[@]}"; do
    rpm -q "${package}" >/dev/null || { echo "Missing package: ${package}... Exiting"; exit 1 ; }
done

# these packages are supposed to be removed
# and are considered footguns
UNWANTED_PACKAGES=(
    fedora-logos
    firefox
    gnome-software
    gnome-software-rpm-ostree
    podman-docker
)

for package in "${UNWANTED_PACKAGES[@]}"; do
    if rpm -q "${package}" >/dev/null 2>&1; then
        echo "Unwanted package found: ${package}... Exiting"; exit 1
    fi
done

if [[ "${IMAGE_NAME}" =~ nvidia ]]; then
  NV_PACKAGES=(
      libnvidia-container-tools
      kmod-nvidia
      nvidia-driver-cuda
)
  for package in "${NV_PACKAGES[@]}"; do
      rpm -q "${package}" >/dev/null || { echo "Missing NVIDIA package: ${package}... Exiting"; exit 1 ; }
  done
fi

# Claude Code integration: the lazy stub, the agent memory slice, the skill and the PATH snippets.
test -x /usr/bin/claude
test -f /usr/lib/systemd/user/wrasse-agents.slice
test -f /usr/lib/systemd/user/wrasse-agents.slice.d/20-oomd.conf
test -f /usr/share/wrasse/skills/wrasse/SKILL.md
test -x /usr/share/ublue-os/user-setup.hooks.d/30-wrasse-agent-skill.sh
test -f /usr/share/wrasse/AGENTS.md
test -x /usr/share/ublue-os/user-setup.hooks.d/31-wrasse-agents-md.sh
grep -qF 'ln -s "${AGENTS_SRC}" "${link}"' /usr/share/ublue-os/user-setup.hooks.d/31-wrasse-agents-md.sh
grep -q 'wrasse install' /usr/share/wrasse/AGENTS.md
grep -q 'AGENTS.md' /usr/share/wrasse/skills/wrasse/SKILL.md
test -f /etc/profile.d/wrasse-path.sh
test -f /usr/share/fish/vendor_conf.d/wrasse-path.fish
# The stub launches through wrasse-agent-run, which runs the command in a scope under the agent slice with a MemoryMax.
test -x /usr/bin/wrasse-agent-run
grep -q "wrasse-agent-run" /usr/bin/claude
grep -q -- "--slice=\"\${SLICE}\"" /usr/bin/wrasse-agent-run
grep -q '^SLICE="wrasse-agents.slice"$' /usr/bin/wrasse-agent-run
grep -q 'MemoryMax=' /usr/bin/wrasse-agent-run
# There is no user manager inside a container build, so `systemd-analyze --user verify` cannot run; check the settings statically.
grep -q '^MemoryHigh=' /usr/lib/systemd/user/wrasse-agents.slice
grep -q '^ManagedOOMMemoryPressure=kill$' /usr/lib/systemd/user/wrasse-agents.slice

# Claude Code sandbox default: bubblewrap and socat are installed, the managed drop-in turns the sandbox on and keeps prompts
# (autoAllowBashIfSandboxed defaults to true upstream, which would auto-approve sandboxed Bash, so it must stay false).
rpm -q bubblewrap socat >/dev/null
test -x /usr/bin/bwrap
python3 - <<'PY'
import json
d = json.load(open("/etc/claude-code/managed-settings.d/10-wrasse-sandbox.json"))
assert d == {"sandbox": {"enabled": True, "autoAllowBashIfSandboxed": False}}, d
PY

# Rollback and status recipes ship in the vendored ujust file.
grep -q '^rollback:' /usr/share/ublue-os/just/60-custom.just
grep -q '^system-status:' /usr/share/ublue-os/just/60-custom.just

# Sysext safe mode: the drop-in that skips systemd-sysext.service on wrasse.safe=1.
grep -q '^ConditionKernelCommandLine=!wrasse.safe=1$' /usr/lib/systemd/system/systemd-sysext.service.d/10-wrasse-safe-mode.conf

IMPORTANT_UNITS=(
    rpm-ostree-countme.timer
    systemd-oomd.service
    tailscaled.service
    ublue-system-setup.service
    uupd.timer
  )

for unit in "${IMPORTANT_UNITS[@]}"; do
    if ! systemctl is-enabled "$unit" 2>/dev/null | grep -q "^enabled$"; then
        echo "${unit} is not enabled"
        exit 1
    fi
done

echo "::endgroup::"
