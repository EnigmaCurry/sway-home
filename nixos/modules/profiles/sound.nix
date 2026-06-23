{ config, lib, ... }:

# PipeWire audio (ALSA + PulseAudio + 32-bit compat). Nothing else in
# sway-home enables sound, so a desktop host that wants audio needs this.
# Enable with `my.profiles.sound.enable = true;`.

let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.my.profiles.sound;
in
{
  options.my.profiles.sound.enable =
    mkEnableOption "PipeWire audio (ALSA + PulseAudio compat)";

  config = mkIf cfg.enable {
    services.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };
  };
}
