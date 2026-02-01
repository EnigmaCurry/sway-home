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
}
