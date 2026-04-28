set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

HOSTNAME := env_var_or_default("HOSTNAME", `hostname -s`)
USERNAME := env_var_or_default("USERNAME", `whoami`)
# print help for Just targets
help:
    @just -l

# Rebuild NixOS and switch to the new generation
switch:
    cd nixos; sudo nixos-rebuild switch --flake .#${HOSTNAME}

# Rebuild NixOS and test the new generation (ALL config reverts on reboot)
test:
    cd nixos; sudo nixos-rebuild test --flake .#${HOSTNAME}

# List the packages configured to pull from unstable nixpkgs
list-unstable-packages:
    cd nixos; nix eval --raw .#nixosConfigurations.${HOSTNAME}._module.args.pkgsUnstable.path && echo

# Update flake.lock
update:
    cd nixos; nix flake update

# List all OS generations
list-generations:
    cd nixos; sudo nix-env -p /nix/var/nix/profiles/system --list-generations

# Delete old generations except for the last 10.
prune:
    cd nixos; sudo nix-env -p /nix/var/nix/profiles/system --delete-generations +10
    df -h /

# Delete all generations except for the current one.
prune-everything:
    cd nixos; sudo nix-collect-garbage -d
    df -h /

# Show flake inputs
metadata:
    cd nixos; nix flake metadata

add-host:
    ./nixos/_scripts/add-host.sh "{{HOSTNAME}}" "{{USERNAME}}"

# --- Home Manager (standalone, for non-NixOS systems) ---

# Initial home-manager installation (run once, then use hm-switch)
hm-install: _ensure-git-config
    cd home-manager; nix run home-manager/release-25.11 -- switch --flake .#default --impure -b backup

# Switch home-manager configuration (use on Fedora/other Linux)
hm-switch: _ensure-git-config
    cd home-manager; home-manager switch --flake .#default --impure -b backup

# Ensure git local config exists (prompts user if missing)
_ensure-git-config:
    #!/usr/bin/env bash
    set -euo pipefail
    CONFIG_FILE="$HOME/.config/git/config.local"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Git local config not found. Let's set it up."
        read -rp "Enter your git user.name: " GIT_NAME
        read -rp "Enter your git user.email: " GIT_EMAIL
        mkdir -p "$(dirname "$CONFIG_FILE")"
        cat > "$CONFIG_FILE" << EOF
    [user]
        name = $GIT_NAME
        email = $GIT_EMAIL
    EOF
        echo "Created $CONFIG_FILE"
    fi

# Update home-manager flake.lock
hm-update:
    cd home-manager; nix flake update

# Pull latest changes from remote (resets flake.lock to trust remote)
hm-pull:
    git checkout home-manager/flake.lock 2>/dev/null || true
    git pull

# List home-manager generations
hm-generations:
    home-manager generations

# Rollback to previous home-manager generation
hm-rollback:
    home-manager rollback

# Show home-manager flake inputs
hm-metadata:
    cd home-manager; nix flake metadata

# Update flake, pull repo, and switch home-manager
hm-upgrade: hm-pull hm-update hm-switch
    @echo ""
    @echo "NOTE: Restart your shell to pick up all changes."

# --- NixOS ISO Building ---

build-iso machine:
    ./nixos/_scripts/build-iso.sh "{{machine}}"

new-iso machine:
    mkdir ./nixos/build-iso/{{machine}}
    cp ./nixos/build-iso/flake.example.nix ./nixos/build-iso/{{machine}}/flake.nix
    cp ./nixos/build-iso/webhook-notify.sh ./nixos/build-iso/{{machine}}/webhook-notify.sh
