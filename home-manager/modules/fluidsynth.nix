# FluidSynth and soundfonts module
{ config, pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    fluidsynth
    soundfont-fluid
    soundfont-generaluser
    soundfont-ydp-grand
    x42-gmsynth
  ];

  # Create ~/soundfonts with symlinks to nix store soundfonts
  home.file = {
    "soundfonts/GeneralUser-GS.sf2".source =
      "${pkgs.soundfont-generaluser}/share/soundfonts/GeneralUser-GS.sf2";
    "soundfonts/FluidR3_GM2-2.sf2".source =
      "${pkgs.soundfont-fluid}/share/soundfonts/FluidR3_GM2-2.sf2";
  };

  # FluidSynth user service
  systemd.user.services.fluidsynth = {
    Unit = {
      Description = "FluidSynth software synthesizer";
      After = [ "pipewire.service" ];
    };
    Service = {
      ExecStart = "${pkgs.fluidsynth}/bin/fluidsynth -a pulseaudio -m alsa_seq -s -i %h/soundfonts/GeneralUser-GS.sf2";
      Restart = "on-failure";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
