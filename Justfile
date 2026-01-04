# Optional but recommended: use bash + fail fast
set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# print help for Just targets
help:
    @just -l

# Rebuild NixOS and switch to the new generation
switch:
    cd nixos; sudo nixos-rebuild switch --flake .#${HOSTNAME}

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
