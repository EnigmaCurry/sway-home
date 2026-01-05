{ lib, config, ... }:

let
  cfg = config.my.host;
  inherit (lib) mkOption types mkDefault;
in
{
  options.my.host = mkOption {
    description = "Per-host settings sourced from hosts.nix.";
    default = {};
    type = types.submodule {
      options = {
        locale = mkOption {
          description = "Locale-related settings.";
          default = {};
          type = types.submodule {
            options = {
              timeZone = mkOption {
                type = types.str;
                default = "UTC";
              };

              defaultLocale = mkOption {
                type = types.str;
                default = "en_US.UTF-8";
              };

              extraLocaleSettings = mkOption {
                # e.g. { LC_TIME = "en_US.UTF-8"; ... }
                type = types.attrsOf types.str;
                default = {};
              };
            };
          };
        };

        xkb = mkOption {
          description = "Keyboard / XKB settings.";
          default = {};
          type = types.submodule {
            options = {
              layout = mkOption { type = types.str; default = "us"; };
              variant = mkOption { type = types.str; default = ""; };
              options = mkOption { type = types.str; default = ""; };
              consoleUseXkbConfig = mkOption { type = types.bool; default = false; };
            };
          };
        };
      };
    };
  };

  config = {
    # Locale
    time.timeZone = mkDefault cfg.locale.timeZone;
    i18n.defaultLocale = mkDefault cfg.locale.defaultLocale;
    i18n.extraLocaleSettings = mkDefault cfg.locale.extraLocaleSettings;

    # Keymap / XKB
    services.xserver.xkb = {
      layout = mkDefault cfg.xkb.layout;
      variant = mkDefault cfg.xkb.variant;
      options = mkDefault cfg.xkb.options;
    };

    console.useXkbConfig = mkDefault cfg.xkb.consoleUseXkbConfig;
  };
}
