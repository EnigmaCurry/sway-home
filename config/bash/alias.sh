alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias bb='rlwrap bb'
alias ec="${HOME}/git/vendor/enigmacurry/emacs/ec"

vars() { set -o posix; set | cut -d= -f1 | column; }
