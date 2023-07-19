#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

PS1='[\u@\h \W]\$ '
PATH=${PATH}:${HOME}/bin

eval $(keychain --eval --quiet)

alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias bb='rlwrap bb'
