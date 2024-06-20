## Rustup cargo environment

if [[ -f "$HOME/.cargo/env" ]]; then
    unset -f fedora-bootstrap-rust
    source "$HOME/.cargo/env"
else
    ## On a new machine, you should run bootstrap-rust.
    bootstrap-rust() {
        sudo dnf install -y rustup
        rustup-init -y --no-modify-path
        source "$HOME/.cargo/env"
        rustup component add rust-analyzer
    }
fi
