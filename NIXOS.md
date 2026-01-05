# Sway-Home on NixOS

The NixOS specific config is in the [nixos](nixos) directory, and it
references the non-nix config files in the root directory
([config](config), [bashrc](bashrc), etc.)

Using [quickemu](https://github.com/quickemu-project/quickemu), you can create a NixOS VM for testing purposes.

## Install quickemu

See [Installation](https://github.com/quickemu-project/quickemu/wiki/01-Installation). This guide was tested with quickemu version 4.9.7.

## Create the VM

Ordinarily, you can use `quickget` to automatically create the VM config. However, I found this to be buggy and it would not download the correct `.iso` image. To work around this bug, you just need to create the config file and download the `.iso` file manually.

Run:

```bash
CHANNEL="nixos-25.11"
mkdir -p ~/VMs/${CHANNEL}
cd ~/VMs

cat <<EOF > ~/VMs/${CHANNEL}.conf
#!/usr/bin/env quickemu --vm
guest_os="linux"
disk_img="${CHANNEL}/disk.qcow2"
iso="${CHANNEL}/latest-nixos-graphical-x86_64-linux.iso"
disk_size="50G"
display="gtk"  
EOF
```

```bash
CHANNEL=nixos-25.11
ISO=latest-nixos-graphical-x86_64-linux.iso
curl -C - -L https://channels.nixos.org/${CHANNEL}/${ISO} \
     --output ~/VMs/${CHANNEL}/${ISO}

# Verify image
curl -L https://channels.nixos.org/${CHANNEL}/${ISO}.sha256 \
  --output ~/VMs/${CHANNEL}/${ISO}.sha256
echo "Verifying image ..."
(cd ~/VMs/${CHANNEL}; sed "s#  .*#  $ISO#" ${ISO}.sha256 | sha256sum -c -)
```

Edit whatever settings you need in `nixos-25.11-gnome.conf`.

## Start the VM

```bash
quickemu --vm ~/VMs/nixos-25.11.conf
```

The default settings will open a GNOME display window for the VM, which is good if you need to use a desktop, or for the initial installer.

## Install NixOS

Inside the graphical window that pops up, install NixOS as you normally would, [following the manual](https://nixos.org/manual/nixos/stable/).

* During install, you may select the option for `No desktop`.

After installation, shut down the VM.

## Create and Restore Snapshots

Create a snapshot named `initial`:

```bash
quickemu --vm ~/VMs/nixos-25.11.conf --snapshot create initial
```

Restore it like this:

```bash
quickemu --vm ~/VMs/nixos-25.11.conf --snapshot apply initial
```

## Restart the VM

```bash
quickemu --vm ~/VMs/nixos-25.11.conf
```

## Configure serial console

It may be more convenient to interact with the VM via serial console. This can facilitate remote login through your normal terminal emulator and allow you to copy and paste the rest of the commands.

Log in to the VM console, and then start the getty service:

```bash
sudo systemctl start serial-getty@ttyS0.service
```

(Note: this setting will **not** persist between reboots. To make it permanent, you will need to add this service to your Nix configuration.)

To connect to the VM from your host, run `socat`:

```bash
socat STDIO,raw,echo=0,escape=0x11 UNIX-CONNECT:$HOME/VMs/nixos-25.11/nixos-25.11-serial.socket
```

(Press Enter and you should now see a login prompt.)

To exit the session press `Ctrl-Q`.

Log in to the account you created.

## Bootstrap the config

Clone this repository:

```bash
nix-shell -p git --run 'bash -lc "
  git clone https://github.com/EnigmaCurry/sway-home.git \
    ~/git/vendor/enigmacurry/sway-home
"'
```

Create the host configuration:

```bash
GIT_REPO=~/git/vendor/enigmacurry/sway-home/
JUST_JUSTFILE=${GIT_REPO}//Justfile \
    nix-shell -p just -p python3 -p git --run "just add-host && git -C $GIT_REPO add nixos/hosts"
```

Apply the configuration:

```bash
JUST_JUSTFILE=~/git/vendor/enigmacurry/sway-home/Justfile \
    nix-shell -p just --run 'just switch'
```

## Start headless

After installation, you can restart the VM without a display, if you want:

```bash
quickemu --vm ~/VMs/nixos-25.11.conf --display none
```

## Stop the VM

To cleanly shut down the VM, you should run the `shutdown` command inside the VM or use the **Machine** / **Power Down** menu action.

If you need to kill it, you can run this command:

```bash
quickemu --vm ~/VMs/nixos-25.11.conf --kill
```
