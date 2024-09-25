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
