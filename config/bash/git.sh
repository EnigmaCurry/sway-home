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


# git specific cd aliases for vendor roots + tab completion:
#  `cdv` takes you to the vendor root ~/git/vendor
#  `cdv enigmacurry/emacs` takes you to ~/git/vendor/enigmacurry/emacs
cdv() {
  local target_dir=~/git/vendor/$1
  if [ -d "$target_dir" ]; then
    cd "$target_dir" || return 1
  else
    echo "Error: Directory '$target_dir' does not exist."
    return 1
  fi
}
_cdv_completion() {
  local base_dir=$1
  local cur=${COMP_WORDS[COMP_CWORD]}
  local full_path="${base_dir}/${cur}"
  COMPREPLY=($(compgen -o dirnames -- "$full_path"))
  for i in "${!COMPREPLY[@]}"; do
    COMPREPLY[i]="${COMPREPLY[i]#${base_dir}/}/"
  done
}
complete -o nospace -F _cdv_completion cdv

# `cdg emacs` takes you to your personal emacs repository
# in ~/git/vendor/${GIT_USERNAME:-enigmacurry}/emacs
# (If you're not enigmacurry, you need to set GIT_USERNAME in ~/.bashrc.local)
cdg() {
  local username=${GIT_USERNAME:-enigmacurry}
  cdv "${username}/$1"
}
_cdg_completion() {
  local username=${GIT_USERNAME:-enigmacurry}
  _cdv_completion "~/git/vendor/${username}"
}
complete -o nospace -F _cdg_completion cdg
