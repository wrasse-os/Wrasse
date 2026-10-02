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
