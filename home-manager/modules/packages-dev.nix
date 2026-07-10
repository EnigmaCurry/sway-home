{ pkgs }:

# Developer toolchain: build tools, language runtimes / package managers,
# VCS, and general dev utilities. Part of the `dotfiles` profile.

with pkgs; [
  # Build toolchain
  libtool
  openssl.dev
  pkg-config
  gcc
  gnumake
  cmake

  # Language runtimes / package managers
  nodejs
  pnpm
  uv
  rustup
  cargo-generate
  cargo-watch
  wasm-pack
  babashka
  leiningen

  # Version control
  git
  git-lfs
  gh
  delta

  # Dev tools / linters / watchers
  entr
  inotify-tools
  shellcheck
  ruff
  pgformatter
  tree-sitter
  just
  live-server
]
