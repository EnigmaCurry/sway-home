#!/bin/bash
## Text to speech via pocket-tts server

say() {
    "$(dirname "${BASH_SOURCE[0]}")/../bin/say" "$@"
}
