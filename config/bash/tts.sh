#!/bin/bash
## Text to speech via pocket-tts server

say() {
    local port="${POCKET_TTS_PORT:-8956}"
    local voice=""
    local args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --voice) voice="$2"; shift 2 ;;
            *) args+=("$1"); shift ;;
        esac
    done
    local text="${args[*]}"
    if [[ -z "$text" ]]; then
        text=$(cat)
    fi
    if [[ -z "$text" ]]; then
        echo "Usage: say [--voice <name|url>] <text>" >&2
        return 1
    fi
    local curl_args=(-s -X POST "http://localhost:${port}/tts" -F "text=<-")
    if [[ -n "$voice" ]]; then
        curl_args+=(-F "voice_url=${voice}")
    fi
    echo "$text" | curl "${curl_args[@]}" | paplay
}
