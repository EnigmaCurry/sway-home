# Install NixOS in a VM

Using [quickemu](https://github.com/quickemu-project/quickemu), you
can create a NixOS VM for testing purposes. 

Once you've created the VM, head back to
[NIXOS.md](NIXOS.md#install-nixos) to finish the installation.

This guide was tested with quickemu version 4.9.7 from *unstable*
nixpkg.

> [!NOTE]
> This method is not the only method you can use to create a
> NixOS VM. You can use any alternative hypervisor. In fact, quickemu
> may not be a particularly good method, mainly due to a wide version
> disrepency in the release packages of quickemu on various platforms.
> Annecdotaly, quickemu works great if you install the *unstable* nix
> package (it seems that this version contains bug fixes that have
> been merged but unreleased PRs). OTOH, at the time of testing, the
> Ubuntu PPA for quickemu was broken/missing, and the Debian package
> was buggy and refused to run because it couldn't detect a qemu
> version properly. YMMV.

## Install quickemu

Reference the quickemu
[Installation](https://github.com/quickemu-project/quickemu/wiki/01-Installation)
wiki page.

## Create the VM

Ordinarily, you should be able to use `quickget` to automatically
create the VM config. However, I found this to be buggy and it would
not download the correct `.iso` image. To work around this bug, I just
needed to create the config file and download the `.iso` file
manually. I have wrapped this fix into a script inside
[create-vm.sh](nixos/_scripts/create-vm.sh).

Create the VM config file:

```bash
just vm-create
```

Edit whatever settings you need in `~/VMs/nixos-25.11.conf` [according
to the
docs](https://github.com/quickemu-project/quickemu/wiki/05-Advanced-quickemu-configuration)
(all command line arguments are also valid config file parameters).

## Start the VM

```bash
just vm-start
```

The default `display` setting will open a GTK display window for the
VM, which is good if you want to use a desktop, or for the initial
installer. However, the drawback is that it is not possible to copy
and paste text between the graphical terminal and your workstation. An
alternative serial interface may be setup to fascilitate connecting
from your worksation's terminal.

## Stop the VM

To cleanly shut down the VM, you should run the `shutdown` command
inside the VM or use the **Machine** / **Power Down** menu action.

If you need to kill it, you can run this command:

```bash
just vm-kill
```

## Create and Restore Snapshots

Create a snapshot named `initial`:

```bash
just vm-snapshot initial
```

(Note: the VM must be shutdown to create a snapshot.)

You may restore the snapshot like this:

```bash
just vm-restore initial
```

## Configure serial console

It may be more convenient to interact with the VM via serial console.
This can facilitate remote login through your normal terminal emulator
and allow you to copy and paste the rest of the commands.

Start the VM, and log into the VM console, and then start the getty
service (you'll need to type this manually into the VM console):

```bash
sudo systemctl start serial-getty@ttyS0.service
```

(Note: this setting will **not** persist between reboots. To make it
permanent, you will need to add this service later on, in your own Nix
configuration.)

To connect to the VM from your host via serial connection:

```bash
just vm-connect
```

(Press Enter and you should now see a login prompt.)

To exit the session press `Ctrl-Q`.

Log into the account you created with the installer.

## Finish installation

See [NIXOS.md](NIXOS.md#install-nixos) and skip to the Install NixOS
section and follow the rest of the steps from that point.

## Start headless

After installation, you can restart the VM without a display, if you want:

```bash
VM_DISPLAY=none just vm-start
```

