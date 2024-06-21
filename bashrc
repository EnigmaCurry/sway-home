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
    prompt-basic
    prompt
    bash_command_timer
    keychain
    completion
    theme
    alias
    editor
    git
    rust
    video
    local
    unset_funcs
)
for mod in "${modules[@]}"; do
    source ~/.config/bash/"${mod}.sh"
done
