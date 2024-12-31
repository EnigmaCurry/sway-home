# Add ~/bin to your PATH for user programs:
PATH=${PATH}:${HOME}/bin:${HOME}/.local/bin

# Add go path:
PATH=${HOME}/go/bin:/usr/local/go/bin:${PATH}

# Load cargo path if installed:
test -f $HOME/.cargo/env && source "$HOME/.cargo/env"
