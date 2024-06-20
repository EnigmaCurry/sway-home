## Rustup cargo environment

if [[ -f "$HOME/.cargo/env" ]]; then
    unset -f fedora-bootstrap-rust
    source "$HOME/.cargo/env"
else
    ## On a new machine, you should run rust-bootsrap
    rust-bootstrap() {
        bash <(curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs)\
             -y --no-modify-path
        source "$HOME/.cargo/env"
        rustup component add rust-analyzer
        unset -f rust-bootstrap
    }
fi
