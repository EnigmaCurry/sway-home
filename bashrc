# -*- shell-script -*-
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

PS1='[\u@\h \W]\$ '
PATH=${PATH}:${HOME}/bin:${HOME}/.cargo/bin
export EDITOR=emacsclient
export ENIGMACURRY_EMACS_DEV=true
unset USERNAME
export GTK_THEME=Adwaita:dark
export QT_QPA_PLATFORMTHEME=qt5ct

# Set TERM, but only for specific terminals we know about:
case "$TERM" in
    xterm) export TERM=xterm-256color;;
    foot) export TERM=xterm-256color;;
esac

which keychain 2>/dev/null >&2 && \
    eval $(keychain --eval --quiet)

alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias bb='rlwrap bb'
alias ec="${HOME}/git/vendor/enigmacurry/emacs/ec"

# Use bash-completion, if available
[[ $PS1 && -f /usr/share/bash-completion/bash_completion ]] && \
    . /usr/share/bash-completion/bash_completion

## Rustup cargo environment
## On a new machine, you should run rustup-init first.
test -f "$HOME/.cargo/env" && source "$HOME/.cargo/env"

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
    test -f ~/.config/git-prompt.sh || \
        curl -L https://raw.github.com/git/git/master/contrib/completion/git-prompt.sh \
             > ~/.config/git-prompt.sh
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
# Set prompt specific to various distributions:
set_prompt() {
    if [ -f /etc/os-release ]; then
        local os_id="$(grep -Po "^ID=\K.*" /etc/os-release)"
        local variant_id="$(grep -Po "^VARIANT_ID=\K.*" /etc/os-release)"
        if [[ "${os_id}" == "fedora" ]] && [[ "${variant_id}" == *"-atomic"* ]]; then
            # Fedora Atomic
            # Only set fancy PS1 if we are in a toolbox container:
            if is_toolbox >/dev/null; then
                ps1_generator
            fi
        else
            ps1_generator
        fi
    else
        ps1_generator
    fi    
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

#### To enable Bash shell completion support for d.rymcg.tech,
#### add the following lines into your ~/.bashrc ::
if [[ -d ${HOME}/git/vendor/enigmacurry/d.rymcg.tech ]]; then
    export PATH=${PATH}:${HOME}/git/vendor/enigmacurry/d.rymcg.tech/_scripts/user
   eval "$(d.rymcg.tech completion bash)"
   ## Example project alias: creates a shorter command used just for the Traefik project:
   __d.rymcg.tech_cli_alias d
   __d.rymcg.tech_project_alias traefik
fi

## yt-dlp
## Watch any youtube/invidious video URL (or any URL yt-dlp supports) at the highest quality:
## Can read URL input directly if the argument is left blank (incognito mode)
## (Sometimes yt doesn't work, so use yt-720 as a backup)
#### Old version:
# yt() {
#     STREAM=$1; [[ "$STREAM" == "" ]] && read -e -p "Enter stream: " STREAM
#     yt-dlp -f bestvideo+bestaudio "$STREAM" -o - | mpv - --fs -force-seekable=yes
# }
#### New version: mpv can run use yt-dlp all by itself, just pass the URL:
alias yt=mpv

## Watch youtube/invidious video URL (or any URL yt-dlp supports)
## Uses a medium quality pre-muxed stream (its usually about 720p).
## Can read URL input directly if the argument is left blank (incognito mode)
## (yt-720 has higher reliability than yt, but its lower quality)
yt-720() {
    STREAM=$1; [[ "$STREAM" == "" ]] && read -e -p "Enter stream: " STREAM
    yt-dlp "$STREAM" -o - | mpv - --fs -force-seekable=yes
}
## Download best quality video and audio and mux together:
yt-download() {
    STREAM=$1; [[ "$STREAM" == "" ]] && read -e -p "Enter stream: " STREAM
    yt-dlp -f bestvideo+bestaudio "$STREAM" --merge-output-format mp4
}
## Download youtube audio only
yt-audio() {
    STREAM=$1; [[ "$STREAM" == "" ]] && read -e -p "Enter stream: " STREAM
    yt-dlp -x --audio-format mp3 $STREAM
}

screen-record() {
    mkdir -p ~/Screencasts
    DESCRIPTION="$@"
    wf-recorder -a -f ~/Screencasts/$(date +%Y-%m-%d-%H%M)-"$DESCRIPTION".mkv
}

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
    local REPO="$(echo ${CLONE_URL} | sed 's/\.git$//' | grep -Po '(.*/)?\K.+/.+')"
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

## Run local (unversioned) config:
test -f ~/.bashrc.local && source ~/.bashrc.local
