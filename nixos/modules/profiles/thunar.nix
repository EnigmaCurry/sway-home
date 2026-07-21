{ config, lib, pkgs, ... }:

# Thunar file manager with GVfs (so smb://, sftp://, mtp:// etc. work in the
# location bar), archive + volume-management plugins, and tumbler for
# thumbnails. Enable with `my.profiles.thunar.enable = true;`. Only useful
# alongside a graphical session (e.g. my.profiles.sway.enable).

let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.my.profiles.thunar;
in
{
  options.my.profiles.thunar.enable =
    mkEnableOption "Thunar file manager (with GVfs / SMB support)";

  config = mkIf cfg.enable {
    programs.thunar.enable = true;
    programs.thunar.plugins = with pkgs.xfce; [
      thunar-volman            # mount/eject removable media
      thunar-archive-plugin    # right-click extract/create archives
    ];

    # GVfs provides the smb://, sftp://, trash:// etc. backends that Thunar's
    # location bar and "Browse Network" rely on. The default gvfs build
    # includes the samba backend.
    services.gvfs.enable = true;

    # Thumbnails for images / video / PDFs in Thunar.
    services.tumbler.enable = true;

    # Thunar reads its own settings (custom actions, view preferences) from
    # dconf. Harmless if another profile already enabled it.
    programs.dconf.enable = true;

    # `gio mount smb://...` on the CLI, useful for scripting.
    environment.systemPackages = [ pkgs.glib ];
  };
}
