## git clone $1 to ~/git/vendor/ and optionally symlink to $2:
git-vendor() {
    local CLONE_URL="$1"
    local SYMLINK="${2}"
    local DEFAULT_FORGE_URL="https://github.com"
    local VENDOR_ROOT="${VENDOR_ROOT:-${HOME}/git/vendor}"
    if [[ -z "${CLONE_URL}" ]]; then
        echo "## Git clone to ${VENDOR_ROOT} and create optional symlink."
        echo "help: git-vendor URL [symlink]"
        return 1
    fi
    local REPO="$(echo ${CLONE_URL} | sed 's/\.git$//' | grep -Po '(.*[/:])?\K.+/.+')"
    if [[ -z "$REPO" ]]; then
        echo "Error: Invalid repository URL."
        return 1
    fi
    local VENDOR="$(echo ${REPO} | cut -d/ -f1)"
    local PROJECT="$(echo ${REPO} | cut -d/ -f2)"
    local CLONE_DIR="$(realpath "${VENDOR_ROOT}/${VENDOR}/${PROJECT}")"
    if [[ -e "${CLONE_DIR}" ]] && git -C "${CLONE_DIR}" remote -v | \
               tr '[:upper:]' '[:lower:]' | \
               grep "${VENDOR,,}/${PROJECT,,}" >/dev/null; then
        echo "## Project already cloned: ${CLONE_DIR}"
        if [[ -n "${SYMLINK}" ]]; then
            if [[ -e "${SYMLINK}" ]]; then
                echo "## Symlink already exists: ${SYMLINK}"
            else
                (set -x; ln -s "${CLONE_DIR}" "${SYMLINK}")
            fi
        fi
    elif [[ -e "${CLONE_DIR}" ]]; then
        echo "Something else exists at ${CLONE_DIR}. Exiting."
        return 1
    else
        (set -e
         if ! [[ "${CLONE_URL}" =~ ^"git@" ]] && \
                 ! [[ "${CLONE_URL}" =~ ^"https://" ]]; then
             CLONE_URL="${DEFAULT_FORGE_URL}/${VENDOR}/${PROJECT}.git"
         fi
         (set -x;
          git clone "${CLONE_URL}" "${VENDOR_ROOT}/${VENDOR}/${PROJECT}"
         )
         echo
         echo "${VENDOR_ROOT}/${VENDOR}/${PROJECT}"
         if [[ "${VENDOR,,}" != "${VENDOR}" ]]; then
             (set -x; ln -s $(realpath "${VENDOR_ROOT}/${VENDOR}") \
                         $(realpath "${VENDOR_ROOT}/${VENDOR,,}"))
         fi
         if [[ -n "${SYMLINK}" ]]; then
             if [[ -e "${SYMLINK}" ]]; then
                 echo "## Symlink already exists: ${SYMLINK}"
             else
                 (set -x; ln -s "${CLONE_DIR}" "${SYMLINK}")
             fi
         fi
        )
    fi
}

