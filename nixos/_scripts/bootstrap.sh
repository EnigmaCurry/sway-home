#!/usr/bin/env bash
set -euo pipefail

# Bootstrap a fresh NixOS machine with the sway-home repo + host config + switch.
#
# Usage:
#   nix-shell -p curl --command \
#     "curl -fsSL https://raw.githubusercontent.com/EnigmaCurry/sway-home/master/nixos/_scripts/bootstrap.sh | bash"
#
# Optional env overrides:
#   GIT_URL=...           (default: https://github.com/EnigmaCurry/sway-home.git)
#   GIT_REPO=...          (default: ~/git/vendor/enigmacurry/sway-home)
#   HOSTNAME=...          (default: hostname -s)
#   USERNAME=...          (default: whoami, or SUDO_USER if running as root via sudo)
#   SKIP_SWITCH=1         (skip the final "just switch")
#
# Example override:
#   nix-shell -p curl --command \
#     "curl -fsSL https://raw.githubusercontent.com/EnigmaCurry/sway-home/master/nixos/_scripts/bootstrap.sh | HOSTNAME=x1 USERNAME=ryan bash"
#
# Notes:
# - Run as your normal user if possible. The final "just switch" will prompt for sudo.
# - This script uses nix-shell so you don't need git/just/python3 installed ahead of time.

log()  { printf "\033[1;32m==>\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33mWARN:\033[0m %s\n" "$*"; }
die()  { printf "\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

main() {
  need_cmd nix-shell

  # Prefer running as the real user. If invoked via sudo, operate on SUDO_USER's home.
  local HOME_DIR="${HOME}"
  local -a RUN_AS=()

  if [[ "${EUID}" -eq 0 ]]; then
    if [[ -n "${SUDO_USER:-}" ]]; then
      RUN_AS=(sudo -u "${SUDO_USER}" -H)
      HOME_DIR="$(eval echo "~${SUDO_USER}")"
      warn "Running as root via sudo; will operate as user: ${SUDO_USER} (HOME=${HOME_DIR})"
    else
      die "Don’t run this as plain root. Log in as your normal user and rerun, or use sudo so SUDO_USER is set."
    fi
  fi

  # Compute defaults (after HOME_DIR is known).
  local GIT_URL_DEFAULT="https://github.com/EnigmaCurry/sway-home.git"
  local GIT_REPO_DEFAULT="${HOME_DIR}/git/vendor/enigmacurry/sway-home"

  local GIT_URL="${GIT_URL:-$GIT_URL_DEFAULT}"
  local GIT_REPO="${GIT_REPO:-$GIT_REPO_DEFAULT}"
  local JUSTFILE="${GIT_REPO}/Justfile"

  local BOOT_HOSTNAME="${HOSTNAME:-$(hostname -s)}"
  local BOOT_USERNAME="${USERNAME:-${SUDO_USER:-$(whoami)}}"

  log "Using:"
  log "  GIT_URL   = ${GIT_URL}"
  log "  GIT_REPO  = ${GIT_REPO}"
  log "  HOSTNAME  = ${BOOT_HOSTNAME}"
  log "  USERNAME  = ${BOOT_USERNAME}"

  # Ensure parent dir exists
  "${RUN_AS[@]}" mkdir -p "$(dirname "${GIT_REPO}")"

  # Clone/update repo
  if "${RUN_AS[@]}" test -d "${GIT_REPO}/.git"; then
    log "Repo already exists; fetching updates..."
    nix-shell -p git --command "git -C '${GIT_REPO}' fetch --all --prune"
  else
    log "Cloning repo..."
    nix-shell -p git --command "git clone '${GIT_URL}' '${GIT_REPO}'"
  fi

  # Sanity checks
  "${RUN_AS[@]}" test -f "${JUSTFILE}" || die "Expected Justfile not found at: ${JUSTFILE}"

  # Export vars for nix-shell subcommands (avoids quote gymnastics)
  export GIT_URL GIT_REPO JUSTFILE
  export HOSTNAME="${BOOT_HOSTNAME}"
  export USERNAME="${BOOT_USERNAME}"

  # Create host configuration and stage changes
  log "Creating host configuration (just add-host) and staging nixos/hosts..."
  nix-shell -p just -p python3 -p git --command '
    set -euo pipefail
    cd "$GIT_REPO"
    just --justfile "$JUSTFILE" add-host
    git -C "$GIT_REPO" add nixos/hosts
  '

  # Apply configuration
  if [[ "${SKIP_SWITCH:-0}" == "1" ]]; then
    warn "SKIP_SWITCH=1 set; skipping \"just switch\"."
  else
    log "Applying configuration (just switch). You may be prompted for sudo..."
    nix-shell -p just --command '
      set -euo pipefail
      cd "$GIT_REPO"
      just --justfile "$JUSTFILE" switch
    '
  fi

  log "Done."
  log "Tip: review what was staged with: git -C \"$GIT_REPO\" status"
}

main "$@"
