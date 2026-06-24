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

There are two ways to get a machine onto sway-home:

 * **[Option A: Custom network installer ISO](#option-a-build-a-custom-nixos-network-installer-iso)**
   — build a headless, SSH-ready installer ISO (optional pre-seeded
   WiFi, serial console, boot webhook), then run `setup nixos` to
   partition the disk (via [disko]) and generate this host's `~/nixos`
   repo automatically. Best for headless machines and for installing to
   several boxes on a network — no monitor or keyboard required.

 * **[Option B: Official NixOS installer](#option-b-use-the-official-nixos-installer)**
   — install stock NixOS with the upstream graphical installer, then
   follow the [bridge steps](#bridge-convert-an-official-installer-machine-into-a-sway-home-host)
   to build the `~/nixos` repo by hand. Best when you already have a
   monitor and keyboard (or an IP KVM) and don't want to build an ISO
   first.

Both routes end at the same place: a per-host `~/nixos` flake repo that
depends on sway-home, which you then `just switch` from going forward.

### Option A: Build a custom NixOS network installer ISO

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

### Option B: Use the official NixOS installer

The official installation instructions are in the [NixOS
manual](https://nixos.org/manual/nixos/stable/). Use the official
graphical installer. During the install, select `No desktop` — that
setting will be overridden by sway-home anyway. This method is only a
good option when you have a monitor and keyboard or IP KVM. It does not
give you the `setup-*` tools, so afterward follow the bridge steps
below to build the `~/nixos` repo by hand.

### Bridge: convert an official-installer machine into a sway-home host

If you installed with the **official graphical installer** ([Option
B](#option-b-use-the-official-nixos-installer)) instead of the custom
ISO, you don't have the `setup-*` tools — but you can build the same
`~/nixos` host repo by hand. The only real difference from the
ISO/[disko] flow is the disk: the graphical installer already
partitioned it and wrote the filesystems (and bootloader detection)
into `/etc/nixos/hardware-configuration.nix`, so **you skip disko
entirely and reuse that file** instead of generating a `disko.nix`.

This walkthrough has been verified end to end — a vanilla `No desktop`
install converted cleanly into a full sway host with these steps.

The same approach works on top of **any** existing NixOS install, not
just a fresh one: `nixos-rebuild switch --flake` builds a complete
system from this repo and fully **replaces** the old configuration (it
never reads the previous `/etc/nixos/configuration.nix`), so adopt it
in place without a disk-wiping reinstall. Your data is left alone —
partitions and home directories are untouched. On an
already-customized machine you'd just re-express anything worth keeping
from the old `configuration.nix` in your new `config.nix`, since that
old file is no longer in effect.

Boot into the freshly installed system and log in as the user you
created during the install. (To do this remotely, first enable sshd on
the stock system: add `services.openssh.enable = true;` to
`/etc/nixos/configuration.nix` and run `sudo nixos-rebuild switch` —
the stock default still allows password auth, so you can SSH in with
your install password. sway-home turns sshd key-only once you switch
to it, so add a key first; see the caveats below.)

```bash
# Your hostname, the user you created during install, and your time zone:
HOST=mybox
USER=$(whoami)
TZ=America/Denver

mkdir -p ~/nixos && cd ~/nixos

# Reuse the installer's detected hardware, keeping the filesystems
# (no disko here; the graphical installer owns the partitioning).
cp /etc/nixos/hardware-configuration.nix hardware.nix
```

Write **`~/nixos/flake.nix`** — the `$HOST`/`$USER` vars from above
fill it in; note the `modules` list is just `hardware.nix` +
`config.nix`, with **no** `disko.nix`:

```bash
cat > flake.nix <<EOF
{
  description = "NixOS host: $HOST";

  inputs.sway-home.url = "github:EnigmaCurry/sway-home/master";

  outputs = { self, sway-home, ... }: {
    nixosConfigurations.$HOST = sway-home.lib.mkHost {
      hostName = "$HOST";
      userName = "$USER";
      modules = [
        ./hardware.nix
        ./config.nix
      ];
    };
  };
}
EOF
```

Write **`~/nixos/config.nix`** (the `$USER`/`$TZ` vars fill it in; this
mirrors what `setup host` generates — flip the profile toggles you
want):

```bash
cat > config.nix <<EOF
{ inputs, host, config, pkgs, unstablePkgs, lib, ... }:

{
  time.timeZone = "$TZ";
  i18n.defaultLocale = "en_US.UTF-8";
  services.xserver.xkb = { layout = "us"; variant = ""; options = "ctrl:nocaps"; };
  console.useXkbConfig = true;

  # sshd is key-only — add at least one key or you can only log in at the console.
  users.users."$USER".openssh.authorizedKeys.keys = [
    # "ssh-ed25519 AAAA..."
  ];

  programs.git.config.safe.directory = "/home/$USER/nixos";

  # --- Profiles (sway-home) ---
  my.profiles.sway.enable     = true;   # Sway desktop (implies dotfiles)
  # my.profiles.dotfiles.enable = true; # shell/CLI env only, no GUI
  # my.profiles.sound.enable    = true;
  # my.profiles.podman.enable   = true;
  # my.profiles.flatpak.enable  = true;
  # my.profiles.libvirt.enable  = true;
}
EOF
```

Write **`~/nixos/Justfile`** (the `$HOST` var fills it in) — this is
what wires up the `admin` alias and the `just switch` workflow below,
so don't skip it:

```bash
cat > Justfile <<EOF
set shell := ["bash", "-eu", "-o", "pipefail", "-c"]
set positional-arguments

# print help
help:
    @just -l

# Rebuild NixOS and switch to the new generation
switch:
    sudo nixos-rebuild switch --flake .#$HOST

# Rebuild and test (reverts on reboot)
test:
    sudo nixos-rebuild test --flake .#$HOST

# Update the sway-home pin (and other inputs)
update:
    nix flake update

# Update inputs, then rebuild and switch
upgrade: update switch

# Run git in this config repo from any directory (e.g. admin git status)
git *args:
    @git -C "{{justfile_directory()}}" "\$@"
EOF
```

That's the whole repo. Drop your SSH public key into `config.nix`
(the commented `authorizedKeys.keys` line), then commit, pin
sway-home, and apply:

```bash
cd ~/nixos
git init -b main
git add -A
nix --extra-experimental-features "nix-command flakes" flake lock
git add flake.lock && git commit -m "Initial config for $HOST"

sudo nixos-rebuild switch --flake .#"$HOST"
```

From here the repo is identical to one created by `setup host`, and
the rest of this document applies unchanged (`just switch`, `just
update`, etc.). Open a fresh shell after the switch and `admin` will
be defined (the `Justfile` above is what unlocks it).

#### Caveats specific to skipping the ISO

 * **UEFI + systemd-boot is assumed.** [`base.nix`](nixos/modules/base.nix)
   hard-codes `boot.loader.systemd-boot.enable`, which matches the
   graphical installer's default on UEFI machines (and harmlessly
   overrides whatever it wrote into `/etc/nixos/configuration.nix`). On
   a **legacy BIOS / GRUB** machine this will fail to switch — add a
   `boot.loader.grub` block in `config.nix` (with `lib.mkForce` to
   disable systemd-boot) instead.
 * **Match the release.** `base.nix` pins `system.stateVersion =
   "26.05"`, so install the matching NixOS release (or override
   `system.stateVersion` in `config.nix` to whatever you installed).
 * **Your install password persists.** The shared config keeps
   `users.mutableUsers` at its default (`true`), so the password you
   set during the graphical install carries over. The SSH key in
   `config.nix` is still worth adding, since sshd becomes key-only.

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
 * `hardware.nix` — detected hardware (with the custom ISO this has no
   filesystems, since `disko.nix` owns them; via the official-installer
   bridge it keeps the filesystems),
 * `disko.nix` — the declarative disk layout (custom-ISO installs only;
   the bridge omits it),
 * `config.nix` — your host-specific overrides.

sway-home itself is a shared **library** of modules; this repo pulls it
in as an input. Edit `config.nix` (or add modules) for host-specific
changes, and edit sway-home for changes you want shared across all your
machines.

Apply changes with the **`admin`** alias. It runs this host's
`Justfile` from **any** directory — no `cd ~/nixos` needed — with
recipe and argument tab completion, and it even wraps git, so the whole
loop is directory-independent. Nix ignores uncommitted files, so commit
before you switch:

```
admin git status
admin git commit -am "progress"
admin switch
```

`admin switch` runs `sudo nixos-rebuild switch --flake .#<host>`. To
pull newer shared config from sway-home (and other inputs) and apply it
in one step, use `admin upgrade` — it runs `nix flake update` then
switches. Commit the refreshed lockfile afterward:

```
admin upgrade
admin git commit -am "update flake inputs"
```

Run `admin help` to list all recipes: `switch`, `test`, `update`,
`upgrade`, and `git` (which is `git -C ~/nixos`, so `admin git …` works
from anywhere). Each is the matching `just` recipe run in `~/nixos`, so
`just switch` from inside the repo still works too.

## Important concepts and reminders

 * **Back up the repo with git.** NixOS can roll back to previous
   *generations* (whole prior system builds) from the boot menu, but
   that only covers systems already built on this machine — it does
   **not** preserve the history of your declarative source. That history
   lives only in this `~/nixos` git repo, so commit often and push it to
   a remote you control.

 * **Commit (or at least `git add`) before you switch.** A flake builds
   only from files git tracks: a **new** file you haven't `git add`ed is
   invisible to Nix and silently left out of the build. A *modified*
   tracked file is still picked up, but you'll see a `warning: Git tree
   '/home/<user>/nixos' is dirty`. That warning is harmless — the
   rebuild proceeds — but commit anyway so the generation you just built
   is reproducible from a clean checkout. Trying something risky? Do it
   on a branch, not your main one.

 * **You can't edit the live dotfiles in place.** The files home-manager
   manages in `~/.config`, and the system binaries on your `PATH` (under
   `/run/current-system/sw/bin`), are symlinks into `/nix/store`, which
   is read-only. To change them you edit their source here and re-apply
   with `admin switch`, which rebuilds the store paths and repoints the
   symlinks. (NixOS does not populate `/usr/bin` at all, apart from
   `/usr/bin/env` — there's no system directory of editable binaries to
   tweak.) The ritual is a minor pain, but it keeps your config
   declarative and reproducible.

 * **Use `admin test` for throwaway experiments.** `admin test`
   (`nixos-rebuild test`) builds and activates a configuration but does
   **not** add it to the boot menu or make it the default. Reboot and
   you are back on the last generation you `admin switch`ed. Use it to
   try a change without committing to it across reboots.

 * **One small repo per machine; sway-home is shared.** This setup keeps
   **no** per-host config in sway-home itself. Each machine has its own
   flake repo at `~/nixos` that depends on sway-home and calls
   `sway-home.lib.mkHost`, holding that machine's `hardware.nix` and
   `config.nix` (plus a `disko.nix` when the disk was provisioned by the
   custom ISO / [disko] — the official-installer bridge omits it and
   keeps the filesystems in `hardware.nix` instead). Stand up another
   machine via `setup nixos` (custom ISO) or the bridge steps above
   (official installer). Shared changes go in sway-home; machine-specific
   changes go in `~/nixos`.

