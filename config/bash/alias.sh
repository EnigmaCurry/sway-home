alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias bb='rlwrap bb'
alias ec="${HOME}/git/vendor/enigmacurry/emacs/ec"
alias run='just run'
alias dev='toolbox enter dev'
alias arch-dev='toolbox enter arch'
alias dev-install="${HOME}/.config/toolbox/fedora-dev.sh"
alias arch-install="${HOME}/.config/toolbox/arch-dev.sh"
vars() { set -o posix; set | cut -d= -f1 | column; }
