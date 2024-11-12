# Use bash-completion, if available
[[ $PS1 && -f /usr/share/bash-completion/bash_completion ]] && \
    . /usr/share/bash-completion/bash_completion

#### To enable Bash shell completion support for d.rymcg.tech,
#### add the following lines into your ~/.bashrc ::
if [[ -d ${HOME}/git/vendor/enigmacurry/d.rymcg.tech ]]; then
    export PATH=${PATH}:${HOME}/git/vendor/enigmacurry/d.rymcg.tech/_scripts/user
    eval "$(d.rymcg.tech completion bash)"
    ## Example project alias: creates a shorter command used just for the Traefik project:
    __d.rymcg.tech_cli_alias d
    __d.rymcg.tech_project_alias traefik
fi

# https://github.com/casey/just
command -v just >/dev/null && source <(just --completions bash)

## project root `cd` aliases with tab completion:
create_cd_alias() {
    local alias_name="$1"
    local root_dir="$2"
    # Define the function for changing directories
    eval "
    ${alias_name}() {
        cd \"${root_dir}/\$1\"
    }
    "
    # Define the completion function for the alias
    local completion_func="_${alias_name}_completion"
    eval "
    ${completion_func}() {
        local cur=\"\${COMP_WORDS[COMP_CWORD]}\"

        if [[ \"\$cur\" != */* ]]; then
            # Top-level completion: only show first-level subdirectories with trailing slash
            COMPREPLY=( \$(find \"${root_dir}/\" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sed 's|$|/|' | grep -i \"^\$cur\") )
        else
            # Nested-level completion: complete within the specified subdirectory path
            local parent_dir=\"${root_dir}/\${cur%/*}\"
            local partial_subdir=\"\${cur##*/}\"
            COMPREPLY=( \$(find \"\$parent_dir\" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sed 's|$|/|' | grep -i \"^\$partial_subdir\") )

            # Prepend the current path to each result to maintain the nested path structure
            for i in \"\${!COMPREPLY[@]}\"; do
                COMPREPLY[\$i]=\"\${cur%/*}/\${COMPREPLY[\$i]}\"
            done
        fi
    }
    "
    eval "complete -o nospace -F ${completion_func} ${alias_name}"
}

create_cd_alias cdd "${HOME}/git/vendor/enigmacurry/d.rymcg.tech"
create_cd_alias cdg "${HOME}/git/vendor/enigmacurry"
create_cd_alias cdv "${HOME}/git/vendor"
