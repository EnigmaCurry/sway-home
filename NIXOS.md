# Sway-Home on NixOS

These are the instructions for installing NixOS and configuring it
with [sway-home](README.md).

All of the NixOS specific config is in the [nixos](nixos) directory.
The non-nix specific config files are in the root directory
([config](config), [bashrc](bashrc), etc.) and are imported by the nix
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
GIT_URL=https://github.com/EnigmaCurry/sway-home.git
GIT_REPO=~/git/vendor/enigmacurry/sway-home
nix-shell -p git --run "git clone ${GIT_URL} ${GIT_REPO}"
```

 * Create the host configuration:

```bash
GIT_REPO=~/git/vendor/enigmacurry/sway-home
JUST_JUSTFILE=${GIT_REPO}/Justfile \
    nix-shell -p just -p python3 -p git --run "just add-host && git -C $GIT_REPO add nixos/hosts"
```

(This creates a new entry in the [hosts.nix](nixos/modules/hosts.nix)
module. You can create this yourself by copying/editing the `x1`
example. Make sure the config has the same name as your NixOS
hostname.)

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

 * You need to keep your config files safe by commiting it with `git`
   and pushing it, often, to a remote host. NixOS lets you reboot into
   previous generations (state), but you are responsible for
   maintaining the history of the declarative config, and so you need
   to prevent their corruption or accidental deletion by archiving it
   remotely in `git`.

 * When working on any of these config files, remember to `git add` /
   `git commit` your changes *before* running `just switch`. If you
   forget, you will see warnings like `warning: Git tree
   '/home/ryan/git/vendor/enigmacurry/sway-home' is dirty`. That's
   just a reminder to you that you should cancel the operation with
   `Ctrl-C` and you should add and commit your changes before you
   reattempt. (Therefore its recommended to always be working in a
   story branch when trying out new configs, not `master`.) It may not
   seem like it's always necessary to commit your changes, but
   sometimes files will be ignored by nix if they are not at least
   staged for commit.

 * All of the files that end up in `~/.config` (and indeed all of
   `/usr/bin` too) are actually symlinks into `/nix/store/...`. All of
   `/nix/store` is read-only, so that means you cannot edit your dot
   files directly. You must edit their source in this repository and
   re-apply with `just switch` to get them into `/nix/store/....`.
   This is a minor pain point, but this enforced ritual will ensure
   that your config remains declarative and reproducible.

 * If you don't want to make permanent changes to your system (e.g.,
   you are working in a git story branch for some experiments), you
   can use `just test` instead of `just switch`. When using `just
   test`, all new generations are *temporary* and will not be added to
   your boot menu. If you do reboot, you will be forced to choose an
   older normal generation that was made by `just switch` (by default,
   it will reboot into the latest generation from *before you ran
   `just test`*. ).

 * This configuration is designed to support the config of multiple
   machines that you own/control. The [add-host.sh] script handles the
   per-host config creation. Here's how it works: Each host should
   have a host-specific config directory in this repository in
   [`./nixos/hosts/${HOSTNAME}`](nixos/hosts). Each host (e.g, `x1`)
   should copy its hardware configuration (i.e., the one created by
   the installer: `/etc/nixos/hardware-configuration.nix`) into that
   directory (e.g,
   [`./nixos/hosts/x1/hardware.nix`](nixos/hosts/x1/hardware.nix)). In
   this same directory you may also place `storage.nix` (e.g.,
   [`./nixos/hosts/x1/storage.nix`](nixos/hosts/x1/storage.nix)) where
   you can write the configuration for the swap device ID (optional).
   The real reason for `storage.nix` to exist is only because of the
   warning at the top of the `hardware.nix` that it shouldn't be
   edited by the user. At your preference, once the `hardware.nix`
   file for your host has been saved in git, you may delete the
   original `/etc/nixos/hardware-configuration.nix`, because it's no
   longer being used.

 * There is an alternative `minimal` .iso image you can use instead of
   the `graphical` one, but I find the `graphical` one to be easier to
   bootstrap with. There is a boot menu option to enable a serial
   console, but it is not the default, so a graphical display appears
   to be required anyway. If I could figure out a way to enable the
   serial console during the install without needing the display to do
   it, then the `minimal` installer might be preferable to me, but if
   a virtual display (`gtk` window) is going to required anyway, I
   might as well just use the `graphical` installer.
