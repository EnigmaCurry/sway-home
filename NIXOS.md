# Sway-Home on NixOS

These are the instructions for installing NixOS and configuring it
with [sway-home](README.md).

All of the NixOS specific config is in the [nixos](nixos) directory.
The non-nix specific config files are in the root directory
([config](config), [bashrc](bashrc), etc.) and are imported by the nix
config.

For VM-based NixOS development, see
[nixos-vm-template](https://github.com/EnigmaCurry/nixos-vm-template),
which has an included profile for sway-home.

## Install NixOS

### Option A: Use the official NixOS installer

The official installation instructions are in the [NixOS
manual](https://nixos.org/manual/nixos/stable/). Use the official
graphical installer. During the install, select `No desktop` — that
setting will be overridden by sway-home anyway. This method is only a
good option when you have a monitor and keyboard or IP KVM.

### Option B: Build a custom NixOS network installer ISO

This builds a **headless** NixOS installer ISO that boots straight
into an SSH-ready environment (with optional serial console,
pre-seeded WiFi, and a boot-time webhook), so you never need a monitor
or keyboard on the target machine. Once you write the image to a USB
stick (or tftp server), this makes it a lot easier to install to
multiple computers on the same network.

To get started, you need to have a workstation machine that already
has [Nix](https://nixos.org/download/) installed — it does **not**
have to be NixOS. The build runs through
[`bin/nix_build_iso.bb`](bin/nix_build_iso.bb), a Babashka wizard that
is launched via `nix run nixpkgs#babashka`, so Nix is the only host
requirement.

Run the ISO creation tool from this repo:

```bash
just build-iso
```

or directly over the network on any machine that has nix installed:

```bash
nix shell --extra-experimental-features "nix-command flakes" \
  nixpkgs#babashka github:EnigmaCurry/script-wizard --command \
  bb -e '(load-string (slurp "https://raw.githubusercontent.com/EnigmaCurry/sway-home/master/bin/nix_build_iso.bb"))'
```

#### What the build tool asks you

The wizard prompts for:

 * **Installer hostname** (default `nixos-installer`).
 * **Your SSH public key(s)** — password auth is disabled, so you have
   to install at least one authorized SSH key to bake into the ISO. It
   will prompt you to select any keys that are loaded in your running
   ssh-agent.
 * **WiFi credentials** (optional) — SSID, pre-shared key, and a
   NetworkManager connection name, so the installer joins your network
   automatically.
 * **Serial console** (optional, off by default) — device (`ttyS0`) and
   baud rate (`115200`), so you can reach it over a serial link.
 * **Webhook URL** (optional) — once the network is up, the installer
   POSTs its hostname and IP address as JSON to this URL, so you can
   discover where it landed on the network.

After a review screen it builds `.#iso` and copies the result to
`~/Downloads` (override with `--outdir`). Other flags: `--system`
(e.g. `aarch64-linux`), `--output DIR` to only generate the flake
workspace, `--keep`, and `--help`.

#### What gets embedded in the ISO — keep it private

Everything you answer is baked into the image, including:

 * your SSH **public** keys and hostname,
 * the **WiFi pre-shared key in cleartext** (written to an
   `/etc/NetworkManager/system-connections/*.nmconnection` file),
 * the webhook URL, if you set one.

> ⚠️ **Do not publish or share this ISO.** It contains personal
> secrets — most notably your WiFi password in plaintext. Treat the
> built `.iso` like any other file holding your credentials.

#### Install from the ISO

Flash the ISO to a USB stick and boot the target machine. Connect to
it over SSH (or the serial console) using the key you embedded, then run:

```bash
setup nixos
```

That drives the whole install — partition/format/mount the disk,
generate this machine's config repo, and run `nixos-install` — using
the `setup-*` tools described below. Reboot when it finishes; there is
no separate "bootstrap" step anymore (the config repo is created during
the install and lands in your home directory).

#### Installer tools on the ISO

The ISO bundles a small family of `setup-*` tools (Babashka +
script-wizard), arranged like git extensions: `setup <name>` runs
`setup-<name>`.

 * **`setup`** — with no arguments, open an interactive menu to run the
   install steps (Configure Disk → Configure Host → Install) in the order
   you choose, returning to the menu after each until you pick **Done**.
   `setup help` lists the available commands.
 * **`setup nixos`** — run the whole install end to end: `disk`, then
   `host`, then `install` (below), each with its own prompts. This is
   the one command you normally run.
 * **`setup disk`** — interactively partition, format, and mount a disk
   for the install, declaratively via [disko]. v1 lays out a btrfs root
   with `@`/`@home`/`@nix` subvolumes plus an ESP (UEFI) or bios_grub
   (legacy BIOS), an optional swap partition, and mounts everything
   under `/mnt`. Swap is worth adding on low-RAM machines: the live
   ISO's Nix store is RAM-backed (tmpfs), so without swap a large
   download/build during `nixos-install` can exhaust memory. Disks that
   are in use by the running system (most importantly the live boot
   medium) are hidden so you can't wipe them; pass `--include-mounted`
   to override. If the selected disk **already** has this `@`/`@home`/`@nix`
   layout, `setup disk` offers a **reinstall** option: it wipes only `@`
   (the root filesystem), keeps `@home` and `@nix`, and reformats the ESP
   for a fresh bootloader. After a reinstall, skip `setup host` (your
   config repo under `/home` is preserved) and go straight to
   `setup install`, which rebuilds that existing config.
 * **`setup host`** — generate a fresh, self-contained flake repo for
   this one machine at `/mnt/home/<user>/nixos`. It asks for a
   **profile** — `sway` (full desktop) or `minimal` (a bare server:
   sshd + your user, no desktop, no home-manager) — runs
   `nixos-generate-config --no-filesystems` (disko owns the
   filesystems), copies in the `disko.nix` from `setup disk`, writes a
   `flake.nix` that depends on `sway-home` (pinned) and calls
   `sway-home.lib.mkHost`, and seeds `config.nix` with the SSH public
   keys currently authorized on the ISO (so the installed machine is
   reachable — sshd is key-only). Then `git init` + commits. sway-home
   holds **no** per-host config; each machine's config lives in its own
   repo.
 * **`setup install`** — `nixos-install --flake /mnt/home/<user>/nixos#<host>`,
   set the user password (root's is set by nixos-install), `chown` the
   repo to the user inside the new system, and copy the live ISO's
   NetworkManager profiles (e.g. the pre-seeded WiFi) into the target so
   a headless machine stays reachable after reboot, and copy the live SSH
   **host keys** into the target so the installed machine keeps the same
   SSH identity (no "REMOTE HOST IDENTIFICATION HAS CHANGED" for anyone
   who already trusted the live host key). Reboot when it finishes.
   (`--no-network-copy` / `--no-host-keys` to skip either copy;
   `--no-update` to install from the committed pin instead of re-pinning
   sway-home.)

`babashka` and `script-wizard` are also on `PATH` for manual use. disko
is not bundled into the ISO -- `setup disk` fetches it on demand via
`nix run github:nix-community/disko`, since running disko builds a
derivation from the binary cache (so it needs the network anyway, as
does `nixos-install` right after).

[disko]: https://github.com/nix-community/disko

#### Iterating on the installer tools

The `setup-*` tools are packaged as a flake, so you can pull the latest
development versions onto a **running** ISO without rebuilding it:

```bash
setup dev
```

The first time per boot it asks you (via script-wizard) to confirm
upgrading the live ISO to the development source; later runs that same
boot don't ask again (a reboot resets this). It installs the tools from
the GitHub branch into root's nix profile, which is already on `PATH`
ahead of the bundled versions — so the dev tools take effect immediately
(no rebuild, no new shell), re-running pulls new commits in place without
growing `PATH`, and a reboot reverts to the baked-in tools (root's home
is tmpfs). Point it at another branch with
`setup dev github:EnigmaCurry/sway-home/SOMEBRANCH`.

## Reboot

When `setup nixos` (or `setup install`) finishes, reboot. The machine
comes up fully configured — there is no separate bootstrap step. Your
config repo is already on disk at `~/nixos`, owned by your user.

## Making changes going forward

Your machine's entire configuration lives in **its own** git repo in
your home directory:

```
cd ~/nixos
```

It contains:

 * `flake.nix` — depends on `sway-home` (pinned) and calls
   `sway-home.lib.mkHost`,
 * `disko.nix` — the declarative disk layout,
 * `hardware.nix` — detected hardware (no filesystems; disko owns those),
 * `config.nix` — your host-specific overrides.

sway-home itself is a shared **library** of modules; this repo pulls it
in as an input. Edit `config.nix` (or add modules) for host-specific
changes, and edit sway-home for changes you want shared across all your
machines.

After editing, commit (Nix ignores uncommitted files) and apply:

```
git commit -am "..."
just switch          # = sudo nixos-rebuild switch --flake .#<host>
```

To pull newer shared config from sway-home (and other inputs):

```
nix flake update     # or: just update
just switch
```

Other recipes are listed by `just help`.

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

 * This configuration is designed to support multiple machines you
   own/control, but it keeps **no** per-host config itself. Each machine
   has its own small flake repo (at `~/nixos`, created by `setup host`)
   that depends on sway-home and calls `sway-home.lib.mkHost`. That repo
   holds the machine's `disko.nix` (disk layout), `hardware.nix`
   (detected by `nixos-generate-config --no-filesystems`), and
   `config.nix` (your overrides). To stand up another machine, install
   it with `setup nixos` — it generates that machine's own repo. Shared
   changes go in sway-home; machine-specific changes go in `~/nixos`.

