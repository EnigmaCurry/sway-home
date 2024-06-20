# -*- shell-script -*-
# ~/.bashrc

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# Bash config is split into modules, loaded in the order listed below:
modules=(
    bugs
    path
    terminal
    prompt-basic
    prompt
    keychain
    completion
    theme
    alias
    editor
    git
    rust
    video
    local
)
for mod in "${modules[@]}"; do
    source ~/.config/bash/"${mod}.sh"
done
