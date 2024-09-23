# Add ~/bin to your PATH for user programs:
PATH=${PATH}:${HOME}/bin

# Load cargo path if installed:
test -f $HOME/.cargo/env && source "$HOME/.cargo/env"
