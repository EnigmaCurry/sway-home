# Optional but recommended: use bash + fail fast
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
