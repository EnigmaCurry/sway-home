alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
alias ll='eza -l --git'
alias lt='eza -l --git -T --level=4 --color=always | less -R'
alias grep='grep --color=auto'
alias ec="${HOME}/git/vendor/enigmacurry/emacs/ec"
alias run='just run'
alias dev='distrobox enter dev'
alias dev-install="${HOME}/.config/toolbox/fedora-dev.sh"
alias arch-dev='distrobox enter arch'
alias arch-dev-install="${HOME}/.config/toolbox/arch-dev.sh"
alias k=kubectl
alias cast="${HOME}/.config/bash/cast.sh"
alias hm-switch='just -f ~/git/vendor/enigmacurry/sway-home/Justfile hm-switch'
alias hm-generations='just -f ~/git/vendor/enigmacurry/sway-home/Justfile hm-generations'
alias hm-rollback='just -f ~/git/vendor/enigmacurry/sway-home/Justfile hm-rollback'
alias hm-metadata='just -f ~/git/vendor/enigmacurry/sway-home/Justfile hm-metadata'
alias hm-news='just -f ~/git/vendor/enigmacurry/sway-home/Justfile hm-news'
alias hm-update='just -f ~/git/vendor/enigmacurry/sway-home/Justfile hm-update'
alias hm-install='just -f ~/git/vendor/enigmacurry/sway-home/Justfile hm-install'
alias hm-pull='just -f ~/git/vendor/enigmacurry/sway-home/Justfile hm-pull'
alias hm-upgrade='just -f ~/git/vendor/enigmacurry/sway-home/Justfile hm-upgrade'
alias ssh-new='ssh -o ControlMaster=no -o ControlPath=none'
alias ssh-exit='ssh -O exit'
# 'admin' runs just in ~/nixos (this host's NixOS config repo, created by
# 'setup host'), with full recipe + arg tab completion. Only on installed
# NixOS systems where that repo exists.
if [ -f "$HOME/nixos/Justfile" ]; then
  _justfile_alias admin "$HOME/nixos/Justfile"
fi
# nixos-vm-template: per-backend aliases + data-driven tab completion. The
# completion script ships in the repo (symlinked to ~/nixos-vm-template by
# home-manager) and defines the `nixos-vm-template-alias` helper.
if [ -f "$HOME/nixos-vm-template/completions/vm.bash" ]; then
  source "$HOME/nixos-vm-template/completions/vm.bash"
  nixos-vm-template-alias vm  "$HOME/.config/nixos-vm-template/env"      # libvirt
  nixos-vm-template-alias pve "$HOME/.config/nixos-vm-template/pve.env"  # proxmox
fi
vars() { set -o posix; set | cut -d= -f1 | column; }
