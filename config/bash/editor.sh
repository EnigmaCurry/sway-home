#!/bin/bash

# Hardcode your preferred editor here:
preferred_editor="emacsclient   -q"

if [ "$0" != "$BASH_SOURCE" ]; then
    # Sourcing this file..
    export EDITOR="${HOME}/.config/bash/editor.sh"
    export VISUAL=${EDITOR}
else
    # Running this file as a script:
    notify-send "Opening file" "Opening '$1' in $EDITOR_COMMAND"
    exec $preferred_editor "$1"
fi
