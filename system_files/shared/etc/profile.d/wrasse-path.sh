# shellcheck shell=sh
# Make ~/.local/bin win over /usr/bin, so the real Claude Code (installed there by
# Anthropic's native installer) is found before the lazy /usr/bin/claude stub.
_wrasse_lb="${HOME}/.local/bin"
_wrasse_p=":${PATH}:"
case "${_wrasse_p}" in
    *":${_wrasse_lb}:"*)
        # Present: only prepend again if /usr/bin comes before it.
        case "${_wrasse_p%%":${_wrasse_lb}:"*}:" in
            *:/usr/bin:*) PATH="${_wrasse_lb}:${PATH}"; export PATH ;;
        esac
        ;;
    *) PATH="${_wrasse_lb}:${PATH}"; export PATH ;;
esac
unset _wrasse_lb _wrasse_p
