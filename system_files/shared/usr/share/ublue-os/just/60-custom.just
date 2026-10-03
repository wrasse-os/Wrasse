# vim: set ft=make :
# Wrasse-specific recipes

# Enable or disable the Gradia Capture GNOME Shell extension (off by default)
[group('System')]
gradia-extension action="status":
    #!/usr/bin/bash
    set -euo pipefail

    UUID="gradia-integration@alexandervanhee.github.io"

    case "{{ action }}" in
        on)
            gnome-extensions enable "${UUID}"
            echo "Gradia Capture enabled. Log out and back in if it does not appear."
            ;;
        off)
            gnome-extensions disable "${UUID}"
            echo "Gradia Capture disabled."
            ;;
        status)
            gnome-extensions info "${UUID}" | grep -E '^\s+(Name|State|Enabled):' || {
                echo "Gradia Capture is not installed on this system." >&2
                exit 1
            }
            ;;
        *)
            echo "Usage: ujust gradia-extension on|off|status" >&2
            exit 2
            ;;
    esac

# Developer tools sysext (Docker, libvirt, VS Code, perf, GNOME dev), downloaded on demand: on|off [purge]|update|status
[group('System')]
dx action="status" option="":
    #!/usr/bin/bash
    set -euo pipefail

    case "{{ action }}" in
        on)
            # Downloads the sysext that matches the booted image (needs network, about 1.4 GB), then merges it.
            pkexec /usr/libexec/wrasse-dx on
            ;;
        off)
            case "{{ option }}" in
                "") pkexec /usr/libexec/wrasse-dx off ;;
                purge) pkexec /usr/libexec/wrasse-dx off --purge ;;
                *)
                    echo "Usage: ujust dx off [purge]" >&2
                    exit 2
                    ;;
            esac
            ;;
        update)
            # After an image update: fetch the sysext for the booted (and any staged) image and re-merge it.
            pkexec /usr/libexec/wrasse-dx update
            ;;
        status)
            /usr/libexec/wrasse-dx status
            ;;
        *)
            echo "Usage: ujust dx on|off [purge]|update|status" >&2
            exit 2
            ;;
    esac

# Make Ptyxis start Zellij in its default profile, or go back to a plain shell
[group('System')]
multiplexer choice="status":
    #!/usr/bin/bash
    set -euo pipefail

    # Profile schema is relocatable: org.gnome.Ptyxis.Profile at /org/gnome/Ptyxis/Profiles/<uuid>/.
    # Use the user's current default profile; Ptyxis picks its UUID at first launch.
    UUID="$(gsettings get org.gnome.Ptyxis default-profile-uuid | tr -d "'")"
    if [[ -z "${UUID}" ]]; then
        echo "No default Ptyxis profile found. Open Ptyxis once, then retry." >&2
        exit 1
    fi
    PROFILE="org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/${UUID}/"
    ZELLIJ="/home/linuxbrew/.linuxbrew/bin/zellij"

    case "{{ choice }}" in
        zellij)
            if [[ ! -x "${ZELLIJ}" ]]; then
                echo "zellij is not installed yet. Run: brew install zellij" >&2
                exit 1
            fi
            gsettings set "${PROFILE}" custom-command "${ZELLIJ}"
            gsettings set "${PROFILE}" use-custom-command true
            echo "New Ptyxis tabs and windows now start Zellij."
            ;;
        none)
            gsettings reset "${PROFILE}" use-custom-command
            gsettings reset "${PROFILE}" custom-command
            echo "Ptyxis starts your normal shell again."
            ;;
        status)
            echo "use-custom-command: $(gsettings get "${PROFILE}" use-custom-command)"
            echo "custom-command: $(gsettings get "${PROFILE}" custom-command)"
            ;;
        *)
            echo "Usage: ujust multiplexer zellij|none|status" >&2
            exit 2
            ;;
    esac

# Show the booted, staged and rollback images (bootc status)
[group('System')]
system-status:
    #!/usr/bin/bash
    set -euo pipefail

    # bootc needs root even to read status.
    pkexec bootc status

# Boot the previous image on the next restart (bootc rollback), after showing what changes
[group('System')]
rollback:
    #!/usr/bin/bash
    set -euo pipefail

    echo "Current deployments:"
    pkexec bootc status
    echo
    echo "This makes the rollback deployment above the one that boots next, and the current one becomes the rollback."
    echo "- A staged (downloaded but not yet booted) update is discarded."
    echo "- DX follows the image: it merges only the sysext that matches the booted image, so after the rollback it uses the one"
    echo "  downloaded earlier for that image if it is still cached; otherwise run: ujust dx update"
    echo "- /etc goes back to the previous deployment's state; edits made to /etc since then are not carried over."
    echo "- Automatic updates may move you forward again; see: ujust toggle-updates"
    echo

    if command -v gum >/dev/null 2>&1; then
        gum confirm "Roll back now?" || { echo "Cancelled."; exit 0; }
    else
        read -r -p "Roll back now? [y/N] " ANSWER
        [[ "${ANSWER}" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }
    fi

    pkexec bootc rollback
    echo
    echo "Rollback queued. Restart to boot into it."
    if command -v gum >/dev/null 2>&1; then
        if gum confirm "Restart now?"; then systemctl reboot; fi
    fi

# Update the OS image and restart userspace only when possible (bootc upgrade --soft-reboot=auto --apply)
[group('System')]
update-soft:
    #!/usr/bin/bash
    set -euo pipefail

    # uupd runs plain `bootc upgrade --quiet --progress-fd 3` and has no soft-reboot option, so this recipe
    # is the manual path. --soft-reboot=auto restarts userspace only if the new image keeps the same kernel,
    # initrd and kernel arguments; otherwise bootc does a regular reboot. Both end with a restart.
    echo "This downloads the next image and restarts NOW: a userspace-only (soft) restart if the kernel and"
    echo "initrd are unchanged, otherwise a full reboot. Save your work first."
    echo "Flatpaks and Homebrew are not updated here; use: ujust update"
    echo

    if command -v gum >/dev/null 2>&1; then
        gum confirm "Update and restart now?" || { echo "Cancelled."; exit 0; }
    else
        read -r -p "Update and restart now? [y/N] " ANSWER
        [[ "${ANSWER}" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }
    fi

    pkexec bootc upgrade --soft-reboot=auto --apply
