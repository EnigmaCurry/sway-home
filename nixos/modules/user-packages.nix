{ pkgs }:

with pkgs; [
  emacs
  libtool
  openssl.dev
  foot
  cargo-generate
  cargo-watch
  live-server
  wasm-pack
  pgformatter
  tree-sitter
  rustup
  pkg-config
  gcc
  gnumake
  cmake
  uv
  distrobox
	jq
	just
	ruff
  ripgrep
	git
  waybar
  minicom
]
