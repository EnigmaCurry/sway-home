set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

HOSTNAME := env_var_or_default("HOSTNAME", `hostname -s`)
USERNAME := env_var_or_default("USERNAME", `whoami`)
VM_ROOT := env_var_or_default("VM_ROOT", "${HOME}/VMs")
VM := env_var_or_default("VM", "nixos-25.11")
VM_DISPLAY := env_var_or_default("VM_DISPLAY", "gtk")

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

# Start the test VM (See NIXOS_VM.md)
vm-start:
    quickemu --vm {{VM_ROOT}}/{{VM}}.conf --display {{VM_DISPLAY}}

# Kill the test VM (See NIXOS_VM.md)
vm-kill:
    quickemu --vm {{VM_ROOT}}/{{VM}}.conf --kill

# Create test VM (See NIXOS_VM.md)
vm-create:
    ./nixos/_scripts/create-vm.sh "{{VM_ROOT}}" "{{VM}}"

# Delete just the VM disk (See NIXOS_VM.md)
vm-delete-disk:
    quickemu --vm {{VM_ROOT}}/{{VM}}.conf --delete-disk

# Delete the test VM AND its configuration (See NIXOS_VM.md)
vm-destroy:
    quickemu --vm {{VM_ROOT}}/{{VM}}.conf --delete-vm

# Create VM snapshot by name (See NIXOS_VM.md)
vm-snapshot *args:
    quickemu --vm {{VM_ROOT}}/{{VM}}.conf --snapshot create {{args}}

# Restore VM snapshot by name (See NIXOS_VM.md)
vm-restore *args:
    quickemu --vm {{VM_ROOT}}/{{VM}}.conf --snapshot apply {{args}}

# List VM snapshots (See NIXOS_VM.md)
vm-list-snapshots *args:
    quickemu --vm {{VM_ROOT}}/{{VM}}.conf --snapshot info

# Delete VM snapshot by name (See NIXOS_VM.md)
vm-delete-snapshot *args:
    quickemu --vm {{VM_ROOT}}/{{VM}}.conf --snapshot delete

# Connect to VM serial port (See NIXOS_VM.md)
vm-connect:
    @echo "## Connecting to VM tty. "
    @echo "## Remember that your VM needs to be running the serial-getty@ttyS0 service."
    @echo "## Press Ctrl-Q to exit socat."
    @echo "## Press Enter to show initial login console (or just start typing your username)."
    @socat STDIO,raw,echo=0,escape=0x11 UNIX-CONNECT:{{VM_ROOT}}/{{VM}}/{{VM}}-serial.socket
