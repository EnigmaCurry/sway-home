# Sway-Home with Home Manager

These are the instructions for using [Home
Manager](https://github.com/nix-community/home-manager) to manage your
dotfiles on any Linux distribution (Fedora, Ubuntu, Arch, etc.).

Home Manager is a Nix-based tool that manages user-level packages and
configuration files declaratively. Unlike the full NixOS installation
(see [NIXOS.md](NIXOS.md)), Home Manager runs on top of your existing
Linux distribution and only manages your home directory.

All of the Home Manager config is in the
[home-manager](home-manager) directory. The dotfiles themselves are in
the [config](config) directory and are symlinked into `~/.config` by
Home Manager.

## When to use Home Manager vs other methods

| Method                | Use case                                                    |
|-----------------------|-------------------------------------------------------------|
| [setup.sh](FEDORA.md) | Quick setup, no Nix required, manual package management     |
| **Home Manager**      | Declarative config, reproducible packages, any Linux distro |
| [NixOS](NIXOS.md)     | Full system management, complete reproducibility            |

## Prerequisites

### Install Nix

If you are on Fedora Linux, you should use the nix in the package
manager that supports SELinux:

```bash
sudo dnf install nix
sudo systemctl enable --now nix-daemon
```

For other Linux distros, you can use the Nix installer:

```bash
curl -L https://nixos.org/nix/install | sh -s -- --daemon
```

After installation, restart your shell or run:

```bash
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

Verify Nix is working:

```bash
nix --version
```

## Setup

Clone this repository:

```bash
git clone https://github.com/enigmacurry/sway-home \
   ~/git/vendor/enigmacurry/sway-home
cd ~/git/vendor/enigmacurry/sway-home
```

Back up your existing dotfiles (optional):

```bash
mv ~/.config ~/.config.orig
mv ~/.bashrc ~/.bashrc.orig
mv ~/.bash_profile ~/.bash_profile.orig
```

Activate Home Manager for your user:

```bash
just hm-install
```

(If you have any existing files in the way of the new config, they
will be renamed to `*.backup`)

After installation, restart your terminal session to load the new
shell configuration and aliases.

## Making changes going forward

The Home Manager configuration is stored in:
`~/git/vendor/enigmacurry/sway-home/home-manager`

To apply changes after editing configs:

```bash
hm-switch
```

List your generations (history of configurations):

```bash
hm-generations
```

Rollback to the previous generation if something breaks:

```bash
hm-rollback
```

Pull the latest sway-home configuration from git:

```bash
hm-pull
```

Update Home Manager and nixpkgs to latest versions:

```bash
hm-update
hm-switch
```

See all available commands:

```bash
just help
```

### Home Manager commands

```
Available recipes:
    hm-generations           # List home-manager generations
    hm-metadata              # Show home-manager flake inputs
    hm-pull                  # Pull latest sway-home config from git
    hm-rollback              # Rollback to previous home-manager generation
    hm-switch                # Switch home-manager configuration (use on Fedora/other Linux)
    hm-update                # Update home-manager flake.lock
```

## Customizing packages

Edit `home-manager/modules/packages.nix` to add or remove packages:

```nix
{ pkgs }:

with pkgs; [
  ripgrep
  just
  btop
  # Add your packages here
]
```

Then apply:

```bash
hm-switch
```

## Included modules

### Emacs

Emacs (`emacs-pgtk`) is enabled by default. The configuration is
pulled from [EnigmaCurry/emacs](https://github.com/EnigmaCurry/emacs)
and installed to `~/.emacs.d`.

To disable Emacs, edit `home-manager/flake.nix` and remove
`./modules/emacs.nix` from the `extraModules` list.

## Important concepts and reminders

 * **Commit before switching**: When working on config files, remember
   to `git add` / `git commit` your changes *before* running
   `hm-switch`. Uncommitted files may be ignored by Nix.

 * **Files are read-only**: All files in `~/.config` are symlinks into
   `/nix/store/...`, which is read-only. To edit your dotfiles, modify
   the source files in `config/` and run `hm-switch`.

 * **Generations provide rollback**: Home Manager keeps a history of
   configurations. If something breaks, use `hm-rollback` to
   restore the previous working state.

 * **Backup your config**: Keep your configuration safe by committing
   to git and pushing to a remote repository regularly.

## Keyboard setup

See the keyboard configuration section in [FEDORA.md](FEDORA.md#keyboard-setup)
for details on the Emacs-friendly key remapping.
