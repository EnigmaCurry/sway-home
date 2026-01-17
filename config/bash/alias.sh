alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias bb='rlwrap bb'
alias ec="${HOME}/git/vendor/enigmacurry/emacs/ec"
alias run='just run'
alias dev='distrobox enter dev'
alias dev-install="${HOME}/.config/toolbox/fedora-dev.sh"
alias arch-dev='distrobox enter arch'
alias arch-dev-install="${HOME}/.config/toolbox/arch-dev.sh"
alias k=kubectl
alias cast="${HOME}/.config/bash/cast.sh"
vars() { set -o posix; set | cut -d= -f1 | column; }
