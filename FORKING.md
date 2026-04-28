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
```

## Step 1: Fork and clone

Fork the repository on your forge, then clone it into your vendor
directory:

```bash
mkdir -p ~/git/vendor/${FORGE_USER}
git clone https://YOUR_FORGE/${FORGE_USER}/sway-home.git \
  ~/git/vendor/${FORGE_USER}/sway-home
cd ~/git/vendor/${FORGE_USER}/sway-home
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
# Example: fork emacs
git clone https://YOUR_FORGE/${FORGE_USER}/emacs.git \
  ~/git/vendor/${FORGE_USER}/emacs
```

## Step 3: Update bash aliases

The file `config/bash/alias.sh` has hard-coded paths to
`~/git/vendor/enigmacurry/sway-home`. Update them:

```bash
sed -i "s|enigmacurry/sway-home|${FORGE_USER}/sway-home|g" \
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
sed -i "s|enigmacurry/sway-home|${FORGE_USER}/sway-home|g" \
  nixos/_scripts/bootstrap.sh

# Update the git remote URL (adjust for your forge):
sed -i "s|github.com/EnigmaCurry/sway-home|YOUR_FORGE/${FORGE_USER}/sway-home|g" \
  nixos/_scripts/bootstrap.sh
```

## Step 9: Update the flake lock files

After changing flake inputs, update the lock files:

```bash
cd home-manager && nix flake update && cd ..
cd nixos && nix flake update && cd ..
```

## Step 10: Verify

Search for any remaining references to make sure you got everything:

```bash
grep -ri "enigmacurry" --include='*.sh' --include='*.nix' .
```

## Summary of files changed

| File | What to change |
|---|---|
| `config/bash/alias.sh` | `hm-*` alias paths, `ec` alias |
| `config/bash/completion.sh` | `cdg` and `cdd` alias paths, d.rymcg.tech |
| `home-manager/flake.nix` | Flake inputs for emacs, optionally others |
| `nixos/flake.nix` | Flake input for emacs |
| `nixos/_scripts/bootstrap.sh` | Default GIT_URL and GIT_REPO |
