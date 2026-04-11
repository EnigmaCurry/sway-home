#!/bin/bash
## Text to speech via pocket-tts server

say() {
    local text="$*"
    local port="${POCKET_TTS_PORT:-8956}"
    if [[ -z "$text" ]]; then
        text=$(cat)
    fi
    if [[ -z "$text" ]]; then
        echo "Usage: say <text>" >&2
        return 1
    fi
    local tmpfile
    tmpfile=$(mktemp /tmp/tts-XXXXXX.wav)
    curl -s -X POST "http://localhost:${port}/tts" \
        -F "text=${text}" \
        -o "$tmpfile" \
        && mpv --keep-open=no "$tmpfile"
    rm -f "$tmpfile"
}
