# -*- shell-script -*-
# ~/.bashrc

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# Bash config is split into modules, loaded in the order listed below:
modules=(
    funcs
    bugs
    path
    terminal
    keychain
    completion
    prompt-basic
    prompt
    theme
    alias
    editor
    git
    rust
    video
    matrix
    bash_command_timer
    local
    unset_funcs
)
for mod in "${modules[@]}"; do
    source ~/.config/bash/"${mod}.sh"
done
