#!/bin/bash

# Hardcode your preferred editor here:
preferred_editor="emacsclient -q" # -q to keep stdout clean (no "Waiting for Emacs..")

if [ "$0" != "$BASH_SOURCE" ]; then
    # Sourcing this file..
    export EDITOR="${HOME}/.config/bash/editor.sh"
    export VISUAL=${EDITOR}
else
    # Running this file as a script:
    unset initial_checksum
    unset final_checksum
    if [[ -e "$1" ]]; then
        initial_checksum=$(sha256sum "$1" | awk '{ print $1 }')
    fi
    # Write meta message to stderr to keep stdout clean:
    echo "## Opening '$1' in ${preferred_editor%% *}." >/dev/stderr
    if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
        notify-send "Opening your editor" "Opening '$1' in ${preferred_editor%% *}"
    fi

    # Open editor:
    $preferred_editor "$1"

    if [[ -e "$1" ]]; then
        final_checksum=$(sha256sum "$1" | awk '{ print $1 }')
    fi
    if [ "$initial_checksum" = "$final_checksum" ]; then
        echo "## File not saved." >/dev/stderr
        exit 1
    else
        echo "## File saved." >/dev/stderr
    fi
fi
