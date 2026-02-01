# -*- shell-script -*-
# ~/.bashrc

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# Bash config is split into modules, loaded in the order listed below:
modules=(
    funcs
    git-setup
    vars
    bugs
    path
    terminal
    keychain
    completion
    prompt-basic
    prompt
    theme
    just-completion
    alias
    editor
    git
    rust
    video
    music
    matrix
    tts
    bash_command_timer
    local
    unset_funcs
)
for mod in "${modules[@]}"; do
    source ~/.config/bash/"${mod}.sh"
done
