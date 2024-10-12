#!/bin/bash
## Text to speech with Piper - https://github.com/rhasspy/piper
### Install depdendencies: bash podman curl pulseaudio-utils
say() {
    set -e
    local MODEL_DIR=${MODEL_DIR:-~/ai/piper/model}
    local MODEL=${MODEL:-en_US-lessac-high}
    local IMAGE_NAME="piper"
    local AUDIO_RATE=11025
    local SPEED=${SPEED:-1}
    local LOG=${LOG:-false}
    local MODEL_FILE="${MODEL_DIR}/${MODEL}.onnx"
    local MODEL_JSON="${MODEL_FILE}.json"
    declare -A MODEL_URLS=(
        ["en_US-ryan-high"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/ryan/high/en_US-ryan-high.onnx"
        ["en_US-ljspeech-high"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/ljspeech/high/en_US-ljspeech-high.onnx"
        ["en_US-libritts-high"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/libritts/high/en_US-libritts-high.onnx"
        ["en_US-lessac-high"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/lessac/high/en_US-lessac-high.onnx"
        ["en_GB-cori-high"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_GB/cori/high/en_GB-cori-high.onnx"
    )
    if [ "$#" -eq 0 ] && [ -t 0 ]; then
        echo 
        echo "## Text to speech with Piper - https://github.com/rhasspy/piper"
        echo "### Install depdendencies: podman curl pulseaudio-utils"
        echo "## Examples:"
        echo
        echo "say Hello World"
        echo
        echo "MODEL=en_GB-cori-high say Hello World"
        echo
        echo "echo Hello World | say"
        echo
        echo "echo \"Hello World!\" | MODEL=en_GB-cori-high say"
        echo
        return
    fi
    check_dependency() {
        local cmd=$1
        local pkg=${2:-$1}
        if ! command -v "$cmd" >/dev/null; then
            echo "Missing $cmd dependency. Install the $pkg package." >/dev/stderr
            return
        fi
    }
    check_dependency podman
    check_dependency curl
    check_dependency paplay "pulseaudio-utils"
    if ! podman image exists ${IMAGE_NAME}; then
        echo "Building the image..."
        podman build -t ${IMAGE_NAME} - <<EOF
FROM alpine AS downloader
RUN apk add --no-cache wget tar
WORKDIR /download
ARG TAR_URL_AMD64=https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_amd64.tar.gz
ARG TAR_URL_ARM64=https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_arm64.tar.gz
ARG TAR_URL_ARMV7=https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_armv7.tar.gz
RUN ARCH="\$(uname -m)" && \
    if [ "\$ARCH" = "x86_64" ]; then \
        wget \$TAR_URL_AMD64 -O piper.tar.gz; \
    elif [ "\$ARCH" = "aarch64" ]; then \
        wget \$TAR_URL_ARM64 -O piper.tar.gz; \
    elif [ "\$ARCH" = "armv7l" ]; then \
        wget \$TAR_URL_ARMV7 -O piper.tar.gz; \
    else \
        echo "Unsupported platform: \$ARCH" && exit 1; \
    fi && \
    tar -xzf piper.tar.gz && \
    rm piper.tar.gz
FROM debian:bullseye
RUN apt-get update && apt-get install -y tini pulseaudio-utils alsa-utils ffmpeg
WORKDIR /app
COPY --from=downloader /download /app
RUN chmod +x /app/piper/piper
ENTRYPOINT ["/usr/bin/tini", "--"]
ENV PATH="/app/piper:${PATH}"
CMD ["/app/piper/piper"]
EOF
    fi
    if [ ! -f "${MODEL_FILE}" ]; then
        echo "Downloading voice model: ${MODEL_FILE}"
        mkdir -p "${MODEL_DIR}"
        curl -L -C - -o "${MODEL_FILE}" "${MODEL_URLS[${MODEL%.onnx}]}"
    fi
    if [ ! -f "${MODEL_JSON}" ]; then
        echo "Downloading voice model JSON: ${MODEL_JSON}"
        curl -L -C - -o "${MODEL_JSON}" "${MODEL_URLS[${MODEL%.onnx}]}.json"
    fi
    if [[ "${LOG}" == "true" || "$*" == *"--help"* ]]; then
        LOG=/dev/stderr
    else
        LOG=/dev/null
    fi
    if [ "$#" -eq 0 ] && [ -t 0 ]; then
        echo "## Enter text - Press Ctrl-D to quit"
    fi
    if [ "$#" -gt 0 ]; then
        echo " " "$@"
    else
        echo " " && cat
    fi | podman run --rm -i \
        -v /run/user/$(id -u)/pulse:/run/user/$(id -u)/pulse \
        -v ~/.config/pulse/cookie:/run/user/$(id -u)/pulse/cookie \
        -e PULSE_SERVER=unix:/run/user/$(id -u)/pulse/native \
        -v ${MODEL_DIR}:/model:Z \
        ${IMAGE_NAME} \
        sh -c "piper -m /model/${MODEL}.onnx --length_scale ${SPEED} --output_raw $@" 2>${LOG} | \
        paplay --raw --rate=${AUDIO_RATE} --channels=2;
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    say $@
else
    unset say
    alias say="bash ${BASH_SOURCE[0]}"
    alias piper=say
fi
