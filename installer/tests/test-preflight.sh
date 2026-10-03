#!/usr/bin/bash
# Tests for wrasse-installer-preflight (RAM minimum). No root, no hardware.
# Usage: installer/tests/test-preflight.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="${root}/installer/iso/variant/wrasse/wrasse-installer-preflight"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# shellcheck source=../iso/variant/wrasse/wrasse-installer-preflight
source "${script}"

# 1. The threshold is the documented one and the decision is at the boundary.
[[ "${WRASSE_MIN_RAM_KB}" == 7000000 ]] || fail "threshold changed: ${WRASSE_MIN_RAM_KB}"
ram_sufficient 7000000 || fail "7000000 must pass"
ram_sufficient 6999999 && fail "6999999 must fail"
ram_sufficient 8000000 || fail "8000000 must pass"
ram_sufficient 3900000 && fail "4 GB VM must fail"
ram_sufficient 5900000 && fail "6 GB machine must fail"
ram_sufficient 7340000 || fail "8 GB machine with 1 GB iGPU reservation must pass"
ram_sufficient "" && fail "empty must fail"
ram_sufficient abc && fail "garbage must fail"

# 2. MemTotal parsing.
printf 'MemTotal:        3912340 kB\nMemFree:  1 kB\n' > "${work}/m4"
printf 'MemTotal:       16384000 kB\n' > "${work}/m16"
printf 'nothing here\n' > "${work}/mbad"
[[ "$(meminfo_total_kb "${work}/m4")" == 3912340 ]] || fail "parse 4 GB"
[[ "$(meminfo_total_kb "${work}/m16")" == 16384000 ]] || fail "parse 16 GB"
meminfo_total_kb "${work}/mbad" >/dev/null && fail "garbage meminfo accepted"
meminfo_total_kb "${work}/missing" >/dev/null && fail "missing meminfo accepted"

# 3. Kernel argument: a whole word only.
printf 'BOOT_IMAGE=/vmlinuz quiet wrasse.ignore_ram=1 rhgb\n' > "${work}/c1"
printf 'quiet wrasse.ignore_ram=10 xwrasse.ignore_ram=1\n' > "${work}/c2"
printf 'quiet wrasse.ignore_ram=0\n' > "${work}/c3"
ignore_ram_requested "${work}/c1" || fail "ignore_ram=1 not seen"
ignore_ram_requested "${work}/c2" && fail "partial match accepted"
ignore_ram_requested "${work}/c3" && fail "ignore_ram=0 accepted"
ignore_ram_requested "${work}/missing" && fail "missing cmdline accepted"

# 4. Message: the amount found, the requirement and the escape hatch.
msg="$(ram_message 3912340)"
[[ "${msg}" == *"3.7 GiB"* ]] || fail "message lacks the amount: ${msg}"
[[ "${msg}" == *"at least 8 GB"* ]] || fail "message lacks the requirement"
[[ "${msg}" == *"wrasse.ignore_ram=1"* ]] || fail "message lacks the escape hatch"

# 5. End to end through the script: stub dialog records the text, the installer stub records that it ran.
cat > "${work}/dialog" <<STUB
#!/usr/bin/bash
printf '%s' "\$1" > "${work}/dialog.out"
STUB
cat > "${work}/installer" <<STUB
#!/usr/bin/bash
printf '%s' "\$*" > "${work}/installer.out"
STUB
chmod +x "${work}/dialog" "${work}/installer"
run() { # <meminfo> <cmdline> -> exit status of the wrapper
    rm -f "${work}/dialog.out" "${work}/installer.out"
    WRASSE_MEMINFO="${1}" WRASSE_CMDLINE="${2}" WRASSE_PREFLIGHT_DIALOG="${work}/dialog" \
        "${script}" "${work}/installer" --arg "two words" >/dev/null 2>&1
}
printf 'quiet\n' > "${work}/plain"

run "${work}/m4" "${work}/plain" && fail "4 GB must be refused"
[[ -f "${work}/dialog.out" && ! -f "${work}/installer.out" ]] || fail "4 GB: dialog not shown or installer ran"
grep -q 'wrasse.ignore_ram=1' "${work}/dialog.out" || fail "dialog lacks the escape hatch"

run "${work}/m16" "${work}/plain" || fail "16 GB must start the installer"
[[ ! -f "${work}/dialog.out" && "$(cat "${work}/installer.out")" == "--arg two words" ]] || fail "16 GB: arguments not passed through"

run "${work}/m4" "${work}/c1" || fail "ignore_ram=1 must start the installer"
[[ -f "${work}/installer.out" && ! -f "${work}/dialog.out" ]] || fail "ignore_ram=1: wrong behaviour"

run "${work}/mbad" "${work}/plain" || fail "unreadable MemTotal must not block"
[[ -f "${work}/installer.out" ]] || fail "unreadable MemTotal: installer not started"

"${script}" >/dev/null 2>&1 && fail "no command accepted"

# 6. configure-live.d.sh wires both launchers to the wrapper and installs it.
hook="${root}/installer/iso/variant/wrasse/configure-live.d.sh"
grep -q 'install -Dm755 "${here}/wrasse-installer-preflight" /usr/libexec/wrasse-installer-preflight' "${hook}" || fail "hook does not install the wrapper"
grep -q '/etc/xdg/autostart/tuna-installer.desktop' "${hook}" && grep -q '/usr/share/applications/org.bootcinstaller.Installer.desktop' "${hook}" || fail "hook lost a launcher"
grep -q 'Exec=/usr/libexec/wrasse-installer-preflight ' "${hook}" || fail "hook does not rewrite Exec"

# 7. The Exec rewrite keeps the original command exactly (same sed as the hook, on a sample entry).
orig='Exec=flatpak run --env=BOOTC_CUSTOM_RECIPE=/run/host/etc/bootc-installer/recipe.json org.bootcinstaller.Installer'
printf '[Desktop Entry]\n%s\nType=Application\n' "${orig}" > "${work}/x.desktop"
sed -i -e 's|^Exec=\(.*\)$|Exec=/usr/libexec/wrasse-installer-preflight \1|' "${work}/x.desktop"
[[ "$(grep '^Exec=' "${work}/x.desktop")" == "Exec=/usr/libexec/wrasse-installer-preflight ${orig#Exec=}" ]] || fail "Exec rewrite changed the command"

echo "ok"
