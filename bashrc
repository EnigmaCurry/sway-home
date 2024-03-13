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

eval $(keychain --eval --quiet)

alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias bb='rlwrap bb'
alias ec="${HOME}/git/vendor/enigmacurry/emacs/ec"

## Rustup cargo environment
## On a new machine, you should run rustup-init first.
test -f "$HOME/.cargo/env" && source "$HOME/.cargo/env"

## Emacs vterm hooks:
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
if [[ "$INSIDE_EMACS" = 'vterm' ]]; then
    function clear() {
        vterm_printf "51;Evterm-clear-scrollback";
        tput clear;
    }
fi
vterm_prompt_end(){
    vterm_printf "51;A$(whoami)@$(hostname):$(pwd)"
}
PS1=$PS1'\[$(vterm_prompt_end)\]'

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
yt() {
    STREAM=$1; [[ "$STREAM" == "" ]] && read -e -p "Enter stream: " STREAM
    yt-dlp -f bestvideo+bestaudio "$STREAM" -o - | mpv - --fs -force-seekable=yes
}
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

## Run local (unversioned) config:
test -f ~/.bashrc.local && source ~/.bashrc.local
