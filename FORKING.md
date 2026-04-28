# Forking sway-home

This guide walks through the steps to fork sway-home and make it your
own. The goal is to replace hard-coded `enigmacurry` references with
your own username and repository locations.

Eventually this document will become a script. For now, the steps are
written as bash snippets you can run manually.

## Prerequisites

You need `git` installed and a git forge account (GitHub, Codeberg,
GitLab, Forgejo, etc.). Throughout this guide, set `FORGE_USER` to
your username on whatever forge you use:

```bash
FORGE_USER="your-username"
CONFIG_REPO="sway-home"  # rename if you called your fork something else
```

## Step 1: Fork and clone

Fork the repository on your forge, then clone it into your [vendor
directory](#a-note-on-directory-layout). If you renamed your fork,
set `CONFIG_REPO` accordingly in the prerequisites above.

Copy the SSH clone URL from your forge and use it below. The URL
format varies by forge:

- GitHub: `git@github.com:USER/REPO.git`
- Codeberg: `git@codeberg.org:USER/REPO.git`
- Forgejo/Gitea (custom port): `ssh://git@forgejo.example.com:2222/USER/REPO.git`

```bash
CLONE_URL="git@github.com:${FORGE_USER}/${CONFIG_REPO}.git"  # adjust for your forge
mkdir -p ~/git/vendor/${FORGE_USER}
git clone ${CLONE_URL} ~/git/vendor/${FORGE_USER}/${CONFIG_REPO}
cd ~/git/vendor/${FORGE_USER}/${CONFIG_REPO}
```

## Step 2: Decide which upstream repos to fork

sway-home pulls in several EnigmaCurry repositories as flake inputs.
You likely want to fork some and keep others upstream:

| Repository | Likely action | Why |
|---|---|---|
| `emacs` | **Fork** | Personal editor config — you'll want your own |
| `nixos-vm-template` | Keep upstream | General-purpose tool, not personal config |
| `blog.rymcg.tech` | Keep upstream (or remove) | EnigmaCurry's blog — you probably don't need it |
| `script-wizard` | Keep upstream | Shared utility, not personal config |

Fork the ones you want on your forge, then clone them:

```bash
# Example: fork emacs (adjust the clone URL for your forge)
git clone git@github.com:${FORGE_USER}/emacs.git \
  ~/git/vendor/${FORGE_USER}/emacs
```

## Step 3: Update bash aliases

The file `config/bash/alias.sh` has hard-coded paths to
`~/git/vendor/enigmacurry/sway-home`. Update them:

```bash
sed -i "s|enigmacurry/sway-home|${FORGE_USER}/${CONFIG_REPO}|g" \
  config/bash/alias.sh

sed -i "s|enigmacurry/emacs|${FORGE_USER}/emacs|g" \
  config/bash/alias.sh
```

This updates the `hm-*` aliases (hm-switch, hm-generations,
hm-rollback, etc.) and the `ec` emacs alias.

## Step 4: Update bash cd aliases and completion

The file `config/bash/completion.sh` defines `cdg` and `cdd` aliases
with hard-coded paths (the `cdg` in `config/bash/git.sh` is
deprecated — the `completion.sh` version is canonical):

```bash
sed -i "s|enigmacurry|${FORGE_USER}|g" \
  config/bash/completion.sh
```

## Step 5: Update d.rymcg.tech references (optional)

If you don't use [d.rymcg.tech](https://github.com/EnigmaCurry/d.rymcg.tech),
you can remove or comment out its block in `config/bash/completion.sh`
(lines 5-13). Otherwise update the path:

```bash
# Remove the d.rymcg.tech block if you don't use it:
sed -i '/d.rymcg.tech/d' config/bash/completion.sh
```

## Step 6: Update home-manager flake inputs

Edit `home-manager/flake.nix` to point to your repos where
appropriate. The upstream inputs use `github:` nix flake URL syntax.
If your forge is GitHub, you can simply replace the username. For
other forges, use the appropriate nix flake URL scheme:

- GitHub: `github:USER/REPO`
- GitLab: `gitlab:USER/REPO`
- Sourcehut: `sourcehut:~USER/REPO`
- Generic git: `git+https://YOUR_FORGE/USER/REPO`

```bash
# If your fork is on GitHub, a simple sed works:
sed -i 's|github:EnigmaCurry/emacs|github:'"${FORGE_USER}"'/emacs|g' \
  home-manager/flake.nix

# For other forges, edit the URL manually. For example, Codeberg:
#   emacs_enigmacurry = { url = "git+https://codeberg.org/YOU/emacs"; flake = false; };

# Optional: update other repos only if you forked them:
# sed -i 's|github:EnigmaCurry/nixos-vm-template|github:'"${FORGE_USER}"'/nixos-vm-template|g' \
#   home-manager/flake.nix
# sed -i 's|github:EnigmaCurry/blog.rymcg.tech|github:'"${FORGE_USER}"'/blog.rymcg.tech|g' \
#   home-manager/flake.nix
# sed -i 's|github:EnigmaCurry/script-wizard|github:'"${FORGE_USER}"'/script-wizard|g' \
#   home-manager/flake.nix
```

If you don't need the blog at all, you can remove the `blog-rymcg-tech`
input entirely from `home-manager/flake.nix` (and any modules that
reference it).

## Step 7: Update NixOS flake inputs

The NixOS flake at `nixos/flake.nix` also references the emacs repo.
Use the same flake URL scheme as in step 6:

```bash
# If your fork is on GitHub:
sed -i 's|github:EnigmaCurry/emacs|github:'"${FORGE_USER}"'/emacs|g' \
  nixos/flake.nix

# For other forges, edit the URL manually as described in step 6.
```

## Step 8: Update the bootstrap script

The bootstrap script `nixos/_scripts/bootstrap.sh` has defaults for
the git URL and local clone path. Update both:

```bash
# Update the local clone path:
sed -i "s|enigmacurry/sway-home|${FORGE_USER}/${CONFIG_REPO}|g" \
  nixos/_scripts/bootstrap.sh

# Update the git remote URL to match your forge:
# (review the GIT_URL default in the script and replace it with your own)
```

## Step 9: NixOS host configuration

If you use the NixOS install method, `nixos/hosts/hosts.nix` contains
host-specific settings you'll want to change:

- `userName` — hardcoded to `ryan`
- `hostName` — hardcoded to `x1`
- `timeZone` — set to `America/Denver`
- Keyboard layout options (e.g. `ctrl:nocaps`)

Use `nixos/_scripts/add-host.sh` to create your own host entry, or
edit `hosts.nix` directly.

## Step 10: Firefox bookmarks

`home-manager/modules/firefox.nix` has default bookmarks pointing to
EnigmaCurry projects (sway-home, d.rymcg.tech, blog.rymcg.tech,
book.rymcg.tech, nixos-vm-template). Replace or remove these.

## Step 11: blog.rymcg.tech utility scripts

`home-manager/modules/home.nix` symlinks ~16 utility scripts from the
`blog-rymcg-tech` flake input into `~/bin/` (git-vendor, proxmox
helpers, rclone, wireguard, restic, etc.). Review these and remove any
you don't need.

## Step 12: Other personal config

- `config/ksnip/ksnip.conf` — `SaveDirectory` is hardcoded to
  `/home/ryan`, update to your home directory
- `config/waybar/config` — weather widget has a `<your_location>`
  placeholder, set it to your location

## Step 13: Add or remove packages

To customize which packages are installed, edit
`home-manager/modules/packages.nix`. It's a simple list of nixpkgs
attribute names:

```nix
{ pkgs }:

with pkgs; [
  ripgrep
  jq
  # add your packages here
]
```

Search for packages at [search.nixos.org](https://search.nixos.org/packages)
and add them to the list. Remove any you don't need.

## Step 14: Update the flake lock files

After changing flake inputs, update the lock files:

```bash
cd home-manager && nix flake update && cd ..
cd nixos && nix flake update && cd ..
```

## Step 15: Verify

Search for any remaining references to make sure you got everything:

```bash
grep -ri "enigmacurry" --include='*.sh' --include='*.nix' --include='*.conf' .
```

## Summary of files changed

| File | What to change |
|---|---|
| `config/bash/alias.sh` | `hm-*` alias paths, `ec` alias |
| `config/bash/completion.sh` | `cdg` and `cdd` alias paths, d.rymcg.tech |
| `home-manager/flake.nix` | Flake inputs for emacs, optionally others |
| `home-manager/modules/firefox.nix` | Default bookmarks |
| `home-manager/modules/home.nix` | blog.rymcg.tech utility scripts |
| `nixos/flake.nix` | Flake input for emacs |
| `nixos/hosts/hosts.nix` | Username, hostname, timezone, keyboard |
| `nixos/_scripts/bootstrap.sh` | Default GIT_URL and GIT_REPO |
| `config/ksnip/ksnip.conf` | SaveDirectory home path |
| `config/waybar/config` | Weather widget location |

---

## A note on directory layout

The `~/git/vendor/USERNAME` directory convention is useful for
organizing repositories by origin, but it's not required. You can
clone your fork wherever you like — just update the paths in the
steps above accordingly.
