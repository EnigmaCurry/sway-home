## Detect if shell is in toolbox container.
## If so, modify the PS1 to show the current toolbox name:
function is_toolbox() {
	if [ -f "/run/.toolboxenv" ]
	then
		echo "$(cat /run/.containerenv | grep -E '^name="' | cut -d \" -f 2)"
    else
        return 1
	fi
}

function toolbox_name() {
    local name="$(is_toolbox)"
    if [ -n "${name}" ]; then
        if command -v host-spawn >/dev/null; then
            local host="$(host-spawn hostname | tr -d '\r')"
            echo "${host}-${name}"
        else
            echo "${name}"
        fi
    else
        echo "${HOSTNAME}"
    fi
}
export PS1_HOSTNAME=$(toolbox_name)

## PS1 generator
## adapted from https://gist.github.com/xenji/2292341
ps1_generator() {
    # docker context inspect --format '{{ .Name }}'
    Time12h="\T"; Time12a="\@"; ShortHost="${PS1_HOSTNAME:-\h}"; Username="\u";
    PathShort="\W"; PathFull="\w"; NewLine="\n"; Jobs="\j";
    source ~/.config/git-prompt.sh
    Color_Off="\[\033[0m\]"; IBlack="\[\033[0;90m\]"; BWhite="\[\033[1;37m\]"; BGreen="\[\033[1;32m\]";
    BIRed="\[\033[1;91m\]"; BIWhite="\[\033[1;97m\]"; BIPurple="\[\033[1;95m\]"; BIBlue="\[\033[1;94m\]";
    GIT_PS1='$(git branch &>/dev/null;\
if [ $? -eq 0 ]; then \
  echo "$(echo `git status` | grep "nothing to commit" > /dev/null 2>&1; \
  DIRTY="$?"; \
  HEADREV=`git log --pretty=%h -n 1`; \
  echo -n "|G:'${BWhite}'$HEADREV"; \
  if [ "$DIRTY" -eq "0" ]; then \
    # @4 - Clean repository - nothing to commit
    echo "@'${BGreen}'"$(__git_ps1 "(%s)"); \
  else \
    # @5 - Changes to working tree
    echo "'${BIBlue}'@'${BIRed}'"$(__git_ps1 "{%s}"); \
  fi)'${Color_Off}'"; \
else \
  # @2 - Prompt when not in GIT repo
  echo ""; \
fi)'
    if docker context inspect >/dev/null 2>&1; then
        DOCKER_PS1='|D:'${BIBlue}'$(docker context inspect --format "{{ .Name }}")'
    fi
    USER_PS1=${BIPurple}${Username}'@'${ShortHost}${Color_Off}
    PATH_PS1='|'${BWhite}${PathShort}${Color_Off}
    export PS1='['${USER_PS1}${GIT_PS1}${DOCKER_PS1}${PATH_PS1}']\n$ '
}
# Set prompt:
set_prompt() {
    ps1_generator
}
if is_toolbox >/dev/null; then
    export TOOLBOX_CONTAINER=$(is_toolbox)
fi
set_prompt
unset -f is_toolbox toolbox_name ps1_generator set_prompt

## Emacs vterm hooks:
if [[ "$INSIDE_EMACS" == 'vterm' ]]; then
    vterm_printf() {
        if [ -n "$TMUX" ] && ([ "${TERM%%-*}" = "tmux" ] || [ "${TERM%%-*}" = "screen" ]); then
            # Tell tmux to pass the escape sequences through
            printf "\ePtmux;\e\e]%s\007\e\\" "$1"
        elif [ "${TERM%%-*}" = "screen" ]; then
            # GNU screen (screen, screen-256color, screen-256color-bce)
            printf "\eP\e]%s\007\e\\" "$1"
        else
            printf "\e]%s\e\\" "$1"
        fi
    }
    function clear() {
        vterm_printf "51;Evterm-clear-scrollback";
        tput clear;
    }
    function vterm_prompt_end(){
        vterm_printf "51;A$(whoami)@$(hostname):$(pwd)"
    }
    PS1=$PS1'\[$(vterm_prompt_end)\]'
fi
