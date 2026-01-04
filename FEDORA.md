# Sway-Home on Fedora
## Install Fedora Sway Atomic

[Fedora Sway Atomic](https://fedoraproject.org/atomic-desktops/sway/)
is a good base layer to start with. It includes the basic essential
binaries:

 * Sway
 * Waybar
 * Rofi
 * Foot
 * Grimshot

## Setup

```
## Rename existing configs to .orig, for posterity:
mv ~/.config ~/.config.orig
mv ~/.bashrc ~/.bashrc.orig
mv ~/.bash_profile ~/.bash_profile.orig

## Clone the new config repo:
git clone https://github.com/enigmacurry/sway-home \
   ~/git/vendor/enigmacurry/sway-home
cd ~/git/vendor/enigmacurry/sway-home

## Run setup script:
./setup.sh
```

## Keyboard setup

The keys labled on a modern PC keyboards do not have the same names in
Emacs, nor on the original Space Cadet keyboard. This configuiration
remaps the keys in the following manner:

 * The PC `Caps lock` key is remapped to function as `Control`.
 * The PC `Windows Logo` key uses the default map of `Super`, but is
   remapped as `Mod3` in i3/sway, and is hidden from all other apps.
 * The PC `Control` key on the left side, is remapped to `Hyper`, also
   known as `Mod4` in i3/sway. (Note: Emacs 29 falsely recognizes this
   key as `Super`, but since the real `Super` key is masked by Sway,
   this works out fine.)
 
Sway uses the following xkb files to perform the remapping of the
keyboard:

 * [xkb/us-emacs.xkb](config/xkb/us-emacs.xkb)
 * [xkb/symbols/emacs](config/xkb/symbols/emacs)
 
This is a modification from the [emacsnotes xkb
guide](https://emacsnotes.wordpress.com/2022/10/30/use-xkb-to-setup-full-spectrum-of-modifiers-meta-alt-super-and-hyper-for-use-with-emacs/),
Thank you!
