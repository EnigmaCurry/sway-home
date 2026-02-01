# FluidSynth and soundfonts module
{ config, pkgs, lib, ... }:

let
  # Script to send All Notes Off to fluidsynth (or specified port)
  # Sends CC 120 (All Sound Off) and CC 123 (All Notes Off) on all 16 channels
  midiReset = pkgs.writeShellScriptBin "midi_reset" ''
    PORT="''${1:-128:0}"
    MIDI_FILE=$(mktemp --suffix=.mid)
    trap "rm -f $MIDI_FILE" EXIT
    # Pre-computed MIDI file: header + CC 120/123 on all 16 channels + end of track
    printf '\x4D\x54\x68\x64\x00\x00\x00\x06\x00\x00\x00\x01\x00\x60' > "$MIDI_FILE"
    printf '\x4D\x54\x72\x6B\x00\x00\x00\x86' >> "$MIDI_FILE"
    # Channel 0-15: CC 120 (All Sound Off) and CC 123 (All Notes Off)
    printf '\x00\xB0\x78\x00\x00\xB0\x7B\x00' >> "$MIDI_FILE"
    printf '\x00\xB1\x78\x00\x00\xB1\x7B\x00' >> "$MIDI_FILE"
    printf '\x00\xB2\x78\x00\x00\xB2\x7B\x00' >> "$MIDI_FILE"
    printf '\x00\xB3\x78\x00\x00\xB3\x7B\x00' >> "$MIDI_FILE"
    printf '\x00\xB4\x78\x00\x00\xB4\x7B\x00' >> "$MIDI_FILE"
    printf '\x00\xB5\x78\x00\x00\xB5\x7B\x00' >> "$MIDI_FILE"
    printf '\x00\xB6\x78\x00\x00\xB6\x7B\x00' >> "$MIDI_FILE"
    printf '\x00\xB7\x78\x00\x00\xB7\x7B\x00' >> "$MIDI_FILE"
    printf '\x00\xB8\x78\x00\x00\xB8\x7B\x00' >> "$MIDI_FILE"
    printf '\x00\xB9\x78\x00\x00\xB9\x7B\x00' >> "$MIDI_FILE"
    printf '\x00\xBA\x78\x00\x00\xBA\x7B\x00' >> "$MIDI_FILE"
    printf '\x00\xBB\x78\x00\x00\xBB\x7B\x00' >> "$MIDI_FILE"
    printf '\x00\xBC\x78\x00\x00\xBC\x7B\x00' >> "$MIDI_FILE"
    printf '\x00\xBD\x78\x00\x00\xBD\x7B\x00' >> "$MIDI_FILE"
    printf '\x00\xBE\x78\x00\x00\xBE\x7B\x00' >> "$MIDI_FILE"
    printf '\x00\xBF\x78\x00\x00\xBF\x7B\x00' >> "$MIDI_FILE"
    printf '\x00\xFF\x2F\x00' >> "$MIDI_FILE"
    ${pkgs.alsa-utils}/bin/aplaymidi -p "$PORT" "$MIDI_FILE"
    echo "Sent All Notes Off to $PORT"
  '';
in
{
  home.packages = with pkgs; [
    fluidsynth
    soundfont-fluid
    soundfont-generaluser
    soundfont-ydp-grand
    x42-gmsynth
    midiReset
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
      After = [ "pipewire.service" "rtkit-daemon.service" ];
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
