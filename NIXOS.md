# Sway-Home on NixOS

The NixOS specific config is in the [nixos](nixos) directory, and it
references the non-nix config files in the root directory
([config](config), [bashrc](bashrc), etc.)

You can install this on a real machine, but you may want to test it
out in a VM first. See [NIXOS_VM.md](NIXOS_VM.md) for instructions.

## Install NixOS

Follow the [NixOS manual](https://nixos.org/manual/nixos/stable/) and
use the graphical installer to install NixOS on your host, or in a VM.

 * During install, you should select the option for `No desktop`.

Special instructions *only if you are using a VM*:

 * After the install, you should **shut down** (not reboot) the VM.
 * Once shutdown, create a snapshot so you can come back to the
   initial state at any time. 
 * Make sure to set up the serial console, so that you can easily copy
   and paste the following commands.

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
GIT_REPO=~/git/vendor/enigmacurry/sway-home/
JUST_JUSTFILE=${GIT_REPO}//Justfile \
    nix-shell -p just -p python3 -p git --run "just add-host && git -C $GIT_REPO add nixos/hosts"
```

 * Apply the configuration:

```bash
JUST_JUSTFILE=~/git/vendor/enigmacurry/sway-home/Justfile \
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

See the other commands via the help command:

```
just help
```
