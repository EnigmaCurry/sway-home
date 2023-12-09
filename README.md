# sway-home

These are the dotfiles I use on most laptops.

## Setup

```
git clone https://github.com/enigmacurry/sway-home \
   ~/git/vendor/enigmacurry/sway-home
cd ~/git/vendor/enigmacurry/sway-home
./setup.sh
```

## Keyboard setup

The keys labled on a modern PC keyboards do not have the same names in
Emacs, nor on the original Space Cadet keyboard. This configuiration
remaps the keys in the following manner:

 * The PC `Alt` key on the right side of the spacebar, is remapped
   to the old style `Alt` key, also known as `Mod1` in i3/sway.
 * The PC `Alt` key on the left side of the spacebar, uses the default
   map of `Meta`, also known as `Mod2` in i3/sway.
 * The PC `Windows Logo` key uses the default map of `Super`, but is
   remapped as `Mod3` in i3/sway.
 * The PC `Control` key on the left side, is remapped to the old
   `Hyper` key, also known as `Mod4` in i3/sway.
 * The PC `Caps lock` key is remapped to the left `Control` key.
 
Sway uses the following xkb files to perform the remapping of the
keyboard:

 * [xkb/us-emacs.xkb](config/xkb/us-emacs.xkb)
 * [xkb/symbols/emacs](config/xkb/symbols/emacs)
 
This is a modification from the [emacsnotes xkb
    guide](https://emacsnotes.wordpress.com/2022/10/30/use-xkb-to-setup-full-spectrum-of-modifiers-meta-alt-super-and-hyper-for-use-with-emacs/),
    Thank you!

