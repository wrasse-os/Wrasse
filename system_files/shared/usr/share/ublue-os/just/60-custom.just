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

# Turn the developer tools sysext (Docker, libvirt, VS Code, perf, GNOME dev) on or off
[group('System')]
dx action="status":
    #!/usr/bin/bash
    set -euo pipefail

    case "{{ action }}" in
        on)
            pkexec /usr/libexec/wrasse-dx on
            ;;
        off)
            pkexec /usr/libexec/wrasse-dx off
            ;;
        status)
            /usr/libexec/wrasse-dx status
            ;;
        *)
            echo "Usage: ujust dx on|off|status" >&2
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
