## Unset utility functions loaded from funcs.sh

unset_funcs() {
    # Unset all functions found in FUNCS_SOURCE
    FUNCS_SOURCE=$1
    check_var FUNCS_SOURCE
    if [[ ! -f ${FUNCS_SOURCE} ]]; then
        error "Failed cleanup in ${BASH_SOURCE}"
        error "${FUNCS_SOURCE} does not exist." 
        return 1
    fi
    read -ra funcs < <(grep -P "^\w+()" "${FUNCS_SOURCE}" | \
                           grep -Po "^\w+" | \
                           cut -d"(" -f 1 | tr '\n' ' ')
    for func in "${funcs[@]}"; do
        unset -f ${func}
    done
}
unset_funcs ~/.config/bash/funcs.sh
unset unset_funcs
