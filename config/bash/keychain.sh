# Skip keychain if SSH agent is already forwarded
if [[ -z "${SSH_AUTH_SOCK}" ]] || [[ ! -S "${SSH_AUTH_SOCK}" ]]; then
    which keychain 2>/dev/null >&2 && \
        eval $(keychain --eval --quiet)
fi
