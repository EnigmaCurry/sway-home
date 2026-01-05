# Sway-Home on NixOS

These are the instructions for installing NixOS and configuring it
with [sway-home](README.md).

All of the NixOS specific config is in the [nixos](nixos) directory.
The non-nix specific config files in the root directory
([config](config), [bashrc](bashrc), etc.) are imported by the nix
config.

You can install this on a real machine, but you may want to test it
out in a VM first. See [NIXOS_VM.md](NIXOS_VM.md) for instructions.

## Install NixOS

Follow the [NixOS manual](https://nixos.org/manual/nixos/stable/) and
use the graphical installer to install NixOS on your host (or in a
VM).

 * During the install, you should select the option for `No desktop`,
   because this setting will be overriden anyway.

Special instructions *only if you are using a VM*:

 * After the install, you should **shut down** (not reboot) the VM.
 * Once shutdown, create an initial snapshot so you can reset to a
   fresh state.
 * Make sure to set up the serial console, so that you can easily copy
   and paste the following commands (otherwise you'll need to type
   them by hand).

## Bootstrap the config

Run the following commands on your freshly installed NixOS machine:

 * Clone this repository:

```bash
nix-shell -p git --run 'bash -lc "
  git clone https://github.com/EnigmaCurry/sway-home.git \
    ~/git/vendor/enigmacurry/sway-home
"'
```

 * Create the host configuration:

```bash
GIT_REPO=~/git/vendor/enigmacurry/sway-home
JUST_JUSTFILE=${GIT_REPO}/Justfile \
    nix-shell -p just -p python3 -p git --run "just add-host && git -C $GIT_REPO add nixos/hosts"
```

 * Apply the configuration:

```bash
GIT_REPO=~/git/vendor/enigmacurry/sway-home
JUST_JUSTFILE=${GIT_REPO}/Justfile \
    nix-shell -p just --run 'just switch'
```

## Reboot

At this point the system is fully installed and you can use your new
system.

## Making changes going forward

The entire system configuration is stored in your new user account:
`~/git/vendor/enigmacurry/sway-home`.

Change into that directory:

```
cd ~/git/vendor/enigmacurry/sway-home
```

Find the [flake.nix](nixos/flake.nix) and the [modules](nixos/modules)
directory. Make changes as you see fit.

After editing configs, to apply the new generation:

```
just switch
```

See the list of generations:

```
just list-generations
```

See the other commands via the help command:

```
just help
```

```
Available recipes:
    add-host
    help                     # print help for Just targets
    list-generations         # List all OS generations
    list-unstable-packages   # List the packages configured to pull from unstable nixpkgs
    metadata                 # Show flake inputs
    prune                    # Delete old generations except for the last 10.
    prune-everything         # Delete all generations except for the current one.
    switch                   # Rebuild NixOS and switch to the new generation
    test                     # Rebuild NixOS and test the new generation (ALL config reverts on reboot)
    update                   # Update flake.lock
    vm-connect               # Connect to VM serial port (See NIXOS_VM.md)
    vm-create                # Create test VM (See NIXOS_VM.md)
    vm-delete-disk           # Delete just the VM disk (See NIXOS_VM.md)
    vm-delete-snapshot *args # Delete VM snapshot by name (See NIXOS_VM.md)
    vm-destroy               # Delete the test VM AND its configuration (See NIXOS_VM.md)
    vm-kill                  # Kill the test VM (See NIXOS_VM.md)
    vm-list-snapshots *args  # List VM snapshots (See NIXOS_VM.md)
    vm-restore *args         # Restore VM snapshot by name (See NIXOS_VM.md)
    vm-snapshot *args        # Create VM snapshot by name (See NIXOS_VM.md)
    vm-start                 # Start the test VM (See NIXOS_VM.md)
```


## Important concepts and reminders

 * When working on any of these config files, remember to `git add` /
   `git commit` your changes your changes *before* running `just
   switch`. If you forget, you will see warnings like `warning: Git
   tree '/home/ryan/git/vendor/enigmacurry/sway-home' is dirty`.
   That's just a reminder to you that you should cancel the operation
   with `Ctrl-C` and you need commit your changes before you
   reattempt. (Therefore its recommended to always be working in a
   story branch when trying out new configs, not `master`.) It may not
   seem like it's always necessary to commit your changes, but
   sometimes files will be ignored by nix if they are not at least
   staged for commit.

 * All of the files in `~/.config` (and indeed all of `/usr/bin`) are
   actually symlinks into `/nix/store/...`. All of `/nix/store` is
   read-only, so that means you cannot edit your dot files directly.
   You must edit their source in this repository and re-apply with
   `just switch` to get them into `/nix/store/....`.

 * If you don't want to make permanent changes to your system (e.g.,
   you are working in a git story branch for some experiments), you
   can use `just test` instead of `just switch`. When using `just
   test`, all new generations are *temporary* and will not be added to
   your boot menu. If you do reboot, you will be forced to choose a
   generation that you made with `just switch` (by default, it will
   reboot to the latest generation *before you ran `just test`*. ).
