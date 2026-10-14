# Speech Dispatcher: route all TTS clients through the neural pocket-tts server
#
# speech-dispatcher itself is enabled at the NixOS level (services.speechd).
# Left alone it reads the stock nixpkgs speechd.conf, which registers no
# modules at all -- so the daemon auto-discovers the sd_* binaries shipped in
# its own package and settles on the first one it finds, SVOX pico. pico is a
# ~2MB diphone synth built for feature phones; flite and espeak-ng, the only
# other modules in the package, are formant/diphone engines of the same era.
# None of the three sound remotely modern.
#
# The sway session already runs Kyutai pocket-tts on localhost:8956 (see
# config/sway/config.d/default), which `say` (bin/say) uses for neural speech.
# This module wires speech-dispatcher's generic output module to that same
# server, so every speechd client -- Firefox read-aloud, Orca, emacs -- gets
# the neural voices instead of pico.
{ config, pkgs, lib, ... }:

let
  pocketTtsPort = 8956;

  # Default voice: pocket-tts' own fallback, a casual, natural-sounding read.
  defaultVoice = "alba";

  # Voice lookup matches the client's language tag EXACTLY and is
  # case-sensitive, so every tag a client might send needs its own entry in
  # lowercase: "en-US" from Firefox matches an `AddVoice "en-us"` line but not
  # an `AddVoice "en-US"` or a bare `AddVoice "en"` one. Unmatched languages
  # fall through to DefaultVoice below.
  englishTags = [ "en" "en-us" "en-gb" ];

  # pocket-tts' predefined voices, named in
  # pocket_tts.utils.utils._ORIGINS_OF_PREDEFINED_VOICES. Only MALE1-3 and
  # FEMALE1-3 exist per language, so these six fill the symbolic slots that
  # clients request by type (`spd-say -t female2`).
  englishVoices = [
    { type = "FEMALE1"; voice = "alba"; }
    { type = "FEMALE2"; voice = "anna"; }
    { type = "FEMALE3"; voice = "cosette"; }
    { type = "MALE1"; voice = "michael"; }
    { type = "MALE2"; voice = "charles"; }
    { type = "MALE3"; voice = "jean"; }
  ];

  # The rest of the English voices. They reuse the MALE3/FEMALE3 slots, which
  # is harmless -- duplicates still appear in `spd-say -L` and stay selectable
  # by name (`spd-say -y vera`). Listed before the six above so the canonical
  # voice wins the symbolic lookup for its slot.
  englishExtraFemale = [ "vera" "fantine" "eponine" "azelma" "mary" "jane" "eve" "caro_davy" ];
  englishExtraMale = [ "marius" "javert" "paul" "george" "bill_boerst" "peter_yearsley" "stuart_bell" ];

  # The non-English voices, one per language pocket-tts was trained on.
  otherVoices = [
    { tags = [ "fr" "fr-fr" ]; type = "FEMALE1"; voice = "estelle"; }
    { tags = [ "de" "de-de" ]; type = "MALE1"; voice = "juergen"; }
    { tags = [ "it" "it-it" ]; type = "MALE1"; voice = "giovanni"; }
    { tags = [ "es" "es-es" ]; type = "FEMALE1"; voice = "lola"; }
    { tags = [ "pt" "pt-br" "pt-pt" ]; type = "MALE1"; voice = "rafael"; }
  ];

  addVoice = tag: type: voice: ''AddVoice "${tag}" "${type}" "${voice}"'';

  voiceTable = lib.concatStringsSep "\n" (
    # Extras first (name-selectable only), on the bare "en" tag to keep the
    # voice list readable rather than repeating them per region.
    (map (addVoice "en" "FEMALE3") englishExtraFemale)
    ++ (map (addVoice "en" "MALE3") englishExtraMale)
    ++ [ "" ]
    ++ (lib.concatMap
      (tag: map (v: addVoice tag v.type v.voice) englishVoices)
      englishTags)
    ++ [ "" ]
    ++ (lib.concatMap
      (v: map (tag: addVoice tag v.type v.voice) v.tags)
      otherVoices)
  );

  # Synthesis helper invoked by sd_generic, reading the text on stdin.
  #
  # This script MUST always exit 0. sd_generic runs its command under
  # `set -o pipefail` and does not report end-of-speech when the command
  # fails: the first failure after the module has been working leaves the
  # calling client (Firefox, Orca) blocked indefinitely. So a pocket-tts
  # outage degrades to espeak-ng here rather than propagating a failure.
  pocketTtsSay = pkgs.writeShellScriptBin "speechd-pocket-tts" ''
    voice="''${1:-${defaultVoice}}"
    port="''${POCKET_TTS_PORT:-${toString pocketTtsPort}}"
    text=$(cat)
    [ -z "$text" ] && exit 0

    # sd_generic substitutes the literal string "no_voice" when a client's
    # language matches no AddVoice entry and no DefaultVoice applies.
    [ "$voice" = "no_voice" ] && voice="${defaultVoice}"

    # The /tts response is a streaming WAV (24kHz mono, open-ended header),
    # so playback starts before synthesis finishes.
    if ${pkgs.curl}/bin/curl -sf -m 2 -o /dev/null "http://localhost:''${port}/health"; then
      if printf '%s' "$text" \
         | ${pkgs.curl}/bin/curl -sS -m 300 -X POST "http://localhost:''${port}/tts" \
                -F "text=<-" -F "voice_url=''${voice}" \
         | ${pkgs.pulseaudio}/bin/paplay; then
        exit 0
      fi
    fi

    # pocket-tts unreachable: say it robotically rather than not at all.
    printf '%s' "$text" | ${pkgs.espeak-ng}/bin/espeak-ng --stdin >/dev/null 2>&1
    exit 0
  '';
in
{
  config = lib.mkIf config.my.home.sway.enable {
    home.packages = [ pocketTtsSay ];

    # A user speechd.conf REPLACES the system one rather than merging with it,
    # so everything speech-dispatcher needs is restated here.
    xdg.configFile."speech-dispatcher/speechd.conf".text = ''
      # Managed by sway-home (home-manager/modules/speechd.nix).
      LogLevel 3
      LogDir "default"

      DefaultVolume 100
      DefaultLanguage "en"
      DefaultVoiceType "FEMALE1"

      # Text preprocessing (symbol/emoji expansion) as shipped by nixpkgs.
      SymbolsPreproc "char"
      SymbolsPreprocFile "gender-neutral.dic"
      SymbolsPreprocFile "font-variants.dic"
      SymbolsPreprocFile "symbols.dic"
      SymbolsPreprocFile "emojis.dic"
      SymbolsPreprocFile "orca.dic"
      SymbolsPreprocFile "orca-chars.dic"

      # Declaring any module disables speech-dispatcher's auto-discovery, so
      # pico and flite drop out entirely. espeak-ng stays registered as a
      # manually selectable backstop: `spd-say -o espeak-ng "hello"`.
      AddModule "pocket-tts" "sd_generic"   "pocket-tts.conf"
      AddModule "espeak-ng"  "sd_espeak-ng" "espeak-ng.conf"

      DefaultModule "pocket-tts"
    '';

    xdg.configFile."speech-dispatcher/modules/pocket-tts.conf".text = ''
      # Managed by sway-home (home-manager/modules/speechd.nix).
      Debug 0

      GenericExecuteSynth \
      "printf %s \'$DATA\' | ${pocketTtsSay}/bin/speechd-pocket-tts \'$VOICE\'"

      GenericDefaultCharset "utf-8"

      # pocket-tts exposes no rate/pitch/volume controls, so the usual
      # Generic{Rate,Pitch,Volume}{Add,Multiply} conversions are omitted --
      # a client's rate and pitch requests have no effect on these voices.

      ${voiceTable}

      DefaultVoice "${defaultVoice}"
    '';
  };
}
