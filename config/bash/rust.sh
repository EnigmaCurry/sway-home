## Rustup cargo environment
## On a new machine, you should run rustup-init first.
PATH=${PATH}:${HOME}/.cargo/bin
test -f "$HOME/.cargo/env" && source "$HOME/.cargo/env"
