#!/bin/bash
## Text to speech with Piper - https://github.com/rhasspy/piper
### Install depdendencies: bash podman curl pulseaudio-utils

# Unalias to prevent alias expansion breaking function definition on re-source
unalias say say_wrapped 2>/dev/null || true

say() {
    set -e
    local MODEL_DIR=${MODEL_DIR:-~/ai/piper/model}
    local MODEL=${MODEL:-en_US-lessac-medium}
    local IMAGE_NAME="piper"    
    local SPEED=${SPEED:-1}
    local SILENCE=${SILENCE:-0.2}
    local NOISE=${NOISE:-0.8}
    local LOG=${LOG:-false}
    local MODEL_FILE="${MODEL_DIR}/${MODEL}.onnx"
    local MODEL_JSON="${MODEL_FILE}.json"
    if [[ $MODEL == *"-high"* ]]; then
        local AUDIO_RATE=${AUDIO_RATE:-11025}
    elif [[ $MODEL == *"-medium"* ]]; then
        local AUDIO_RATE=${AUDIO_RATE:-11025}
    elif [[ $MODEL == *"-low"* ]]; then
        local AUDIO_RATE=${AUDIO_RATE:-8192}
    fi
    declare -A MODEL_URLS=(
        ["ar_JO-kareem-low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ar/ar_JO/kareem/low/ar_JO-kareem-low.onnx"
        ["ar_JO-kareem-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ar/ar_JO/kareem/medium/ar_JO-kareem-medium.onnx"
        ["ca_ES-upc_ona-x_low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ca/ca_ES/upc_ona/x_low/ca_ES-upc_ona-x_low.onnx"
        ["ca_ES-upc_ona-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ca/ca_ES/upc_ona/medium/ca_ES-upc_ona-medium.onnx"
        ["ca_ES-upc_pau-x_low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ca/ca_ES/upc_pau/x_low/ca_ES-upc_pau-x_low.onnx"
        ["cs_CZ-jirka-low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/cs/cs_CZ/jirka/low/cs_CZ-jirka-low.onnx"
        ["cs_CZ-jirka-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/cs/cs_CZ/jirka/medium/cs_CZ-jirka-medium.onnx"
        ["cy_GB-gwryw_gogleddol-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/cy/cy_GB/gwryw_gogleddol/medium/cy_GB-gwryw_gogleddol-medium.onnx"
        ["da_DK-talesyntese-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/da/da_DK/talesyntese/medium/da_DK-talesyntese-medium.onnx"
        ["de_DE-eva_k-x_low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/de/de_DE/eva_k/x_low/de_DE-eva_k-x_low.onnx"
        ["de_DE-karlsson-low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/de/de_DE/karlsson/low/de_DE-karlsson-low.onnx"
        ["de_DE-kerstin-low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/de/de_DE/kerstin/low/de_DE-kerstin-low.onnx"
        ["de_DE-mls-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/de/de_DE/mls/medium/de_DE-mls-medium.onnx"
        ["de_DE-pavoque-low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/de/de_DE/pavoque/low/de_DE-pavoque-low.onnx"
        ["de_DE-ramona-low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/de/de_DE/ramona/low/de_DE-ramona-low.onnx"
        ["de_DE-thorsten-low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/de/de_DE/thorsten/low/de_DE-thorsten-low.onnx"
        ["de_DE-thorsten-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/de/de_DE/thorsten/medium/de_DE-thorsten-medium.onnx"
        ["de_DE-thorsten-high"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/de/de_DE/thorsten/high/de_DE-thorsten-high.onnx"
        ["de_DE-thorsten_emotional-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/de/de_DE/thorsten_emotional/medium/de_DE-thorsten_emotional-medium.onnx"
        ["el_GR-rapunzelina-low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/el/el_GR/rapunzelina/low/el_GR-rapunzelina-low.onnx"
        ["en_GB-alan-low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_GB/alan/low/en_GB-alan-low.onnx"
        ["en_GB-alan-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_GB/alan/medium/en_GB-alan-medium.onnx"
        ["en_GB-alba-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_GB/alba/medium/en_GB-alba-medium.onnx"
        ["en_GB-aru-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_GB/aru/medium/en_GB-aru-medium.onnx"
        ["en_GB-cori-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_GB/cori/medium/en_GB-cori-medium.onnx"
        ["en_GB-cori-high"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_GB/cori/high/en_GB-cori-high.onnx"
        ["en_GB-jenny_dioco-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_GB/jenny_dioco/medium/en_GB-jenny_dioco-medium.onnx"
        ["en_GB-northern_english_male-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_GB/northern_english_male/medium/en_GB-northern_english_male-medium.onnx"
        ["en_GB-semaine-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_GB/semaine/medium/en_GB-semaine-medium.onnx"
        ["en_GB-southern_english_female-low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_GB/southern_english_female/low/en_GB-southern_english_female-low.onnx"
        ["en_GB-vctk-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_GB/vctk/medium/en_GB-vctk-medium.onnx"
        ["en_US-amy-low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/amy/low/en_US-amy-low.onnx"
        ["en_US-amy-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/amy/medium/en_US-amy-medium.onnx"
        ["en_US-arctic-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/arctic/medium/en_US-arctic-medium.onnx"
        ["en_US-bryce-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/bryce/medium/en_US-bryce-medium.onnx"
        ["en_US-danny-low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/danny/low/en_US-danny-low.onnx"
        ["en_US-hfc_female-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/hfc_female/medium/en_US-hfc_female-medium.onnx"
        ["en_US-hfc_male-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/hfc_male/medium/en_US-hfc_male-medium.onnx"
        ["en_US-joe-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/joe/medium/en_US-joe-medium.onnx"
        ["en_US-john-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/john/medium/en_US-john-medium.onnx"
        ["en_US-kathleen-low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/kathleen/low/en_US-kathleen-low.onnx"
        ["en_US-kristin-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/kristin/medium/en_US-kristin-medium.onnx"
        ["en_US-kusal-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/kusal/medium/en_US-kusal-medium.onnx"
        ["en_US-l2arctic-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/l2arctic/medium/en_US-l2arctic-medium.onnx"
        ["en_US-lessac-low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/lessac/low/en_US-lessac-low.onnx"
        ["en_US-lessac-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/lessac/medium/en_US-lessac-medium.onnx"
        ["en_US-lessac-high"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/lessac/high/en_US-lessac-high.onnx"
        ["en_US-libritts-high"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/libritts/high/en_US-libritts-high.onnx"
        ["en_US-libritts_r-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/libritts_r/medium/en_US-libritts_r-medium.onnx"
        ["en_US-ljspeech-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/ljspeech/medium/en_US-ljspeech-medium.onnx"
        ["en_US-ljspeech-high"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/ljspeech/high/en_US-ljspeech-high.onnx"
        ["en_US-norman-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/norman/medium/en_US-norman-medium.onnx"
        ["en_US-ryan-low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/ryan/low/en_US-ryan-low.onnx"
        ["en_US-ryan-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/ryan/medium/en_US-ryan-medium.onnx"
        ["en_US-ryan-high"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/ryan/high/en_US-ryan-high.onnx"
        ["es_ES-carlfm-x_low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_ES/carlfm/x_low/es_ES-carlfm-x_low.onnx"
        ["es_ES-davefx-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_ES/davefx/medium/es_ES-davefx-medium.onnx"
        ["es_ES-mls_10246-low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_ES/mls_10246/low/es_ES-mls_10246-low.onnx"
        ["es_ES-mls_9972-low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_ES/mls_9972/low/es_ES-mls_9972-low.onnx"
        ["es_ES-sharvard-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_ES/sharvard/medium/es_ES-sharvard-medium.onnx"
        ["es_MX-ald-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_MX/ald/medium/es_MX-ald-medium.onnx"
        ["es_MX-claude-high"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_MX/claude/high/es_MX-claude-high.onnx"
        ["fa_IR-amir-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/fa/fa_IR/amir/medium/fa_IR-amir-medium.onnx"
        ["fa_IR-gyro-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/fa/fa_IR/gyro/medium/fa_IR-gyro-medium.onnx"
        ["fi_FI-harri-low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/fi/fi_FI/harri/low/fi_FI-harri-low.onnx"
        ["fi_FI-harri-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/fi/fi_FI/harri/medium/fi_FI-harri-medium.onnx"
        ["fr_FR-gilles-low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/fr/fr_FR/gilles/low/fr_FR-gilles-low.onnx"
        ["fr_FR-mls-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/fr/fr_FR/mls/medium/fr_FR-mls-medium.onnx"
        ["fr_FR-mls_1840-low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/fr/fr_FR/mls_1840/low/fr_FR-mls_1840-low.onnx"
        ["fr_FR-siwis-low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/fr/fr_FR/siwis/low/fr_FR-siwis-low.onnx"
        ["fr_FR-siwis-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/fr/fr_FR/siwis/medium/fr_FR-siwis-medium.onnx"
        ["fr_FR-tom-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/fr/fr_FR/tom/medium/fr_FR-tom-medium.onnx"
        ["fr_FR-upmc-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/fr/fr_FR/upmc/medium/fr_FR-upmc-medium.onnx"
        ["hu_HU-anna-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/hu/hu_HU/anna/medium/hu_HU-anna-medium.onnx"
        ["hu_HU-berta-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/hu/hu_HU/berta/medium/hu_HU-berta-medium.onnx"
        ["hu_HU-imre-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/hu/hu_HU/imre/medium/hu_HU-imre-medium.onnx"
        ["is_IS-bui-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/is/is_IS/bui/medium/is_IS-bui-medium.onnx"
        ["is_IS-salka-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/is/is_IS/salka/medium/is_IS-salka-medium.onnx"
        ["is_IS-steinn-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/is/is_IS/steinn/medium/is_IS-steinn-medium.onnx"
        ["is_IS-ugla-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/is/is_IS/ugla/medium/is_IS-ugla-medium.onnx"
        ["it_IT-paola-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/it/it_IT/paola/medium/it_IT-paola-medium.onnx"
        ["it_IT-riccardo-x_low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/it/it_IT/riccardo/x_low/it_IT-riccardo-x_low.onnx"
        ["ka_GE-natia-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ka/ka_GE/natia/medium/ka_GE-natia-medium.onnx"
        ["kk_KZ-iseke-x_low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/kk/kk_KZ/iseke/x_low/kk_KZ-iseke-x_low.onnx"
        ["kk_KZ-issai-high"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/kk/kk_KZ/issai/high/kk_KZ-issai-high.onnx"
        ["kk_KZ-raya-x_low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/kk/kk_KZ/raya/x_low/kk_KZ-raya-x_low.onnx"
        ["lb_LU-marylux-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/lb/lb_LU/marylux/medium/lb_LU-marylux-medium.onnx"
        ["ne_NP-google-x_low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ne/ne_NP/google/x_low/ne_NP-google-x_low.onnx"
        ["ne_NP-google-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ne/ne_NP/google/medium/ne_NP-google-medium.onnx"
        ["nl_BE-nathalie-x_low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/nl/nl_BE/nathalie/x_low/nl_BE-nathalie-x_low.onnx"
        ["nl_BE-nathalie-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/nl/nl_BE/nathalie/medium/nl_BE-nathalie-medium.onnx"
        ["nl_BE-rdh-x_low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/nl/nl_BE/rdh/x_low/nl_BE-rdh-x_low.onnx"
        ["nl_BE-rdh-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/nl/nl_BE/rdh/medium/nl_BE-rdh-medium.onnx"
        ["nl_NL-mls-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/nl/nl_NL/mls/medium/nl_NL-mls-medium.onnx"
        ["nl_NL-mls_5809-low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/nl/nl_NL/mls_5809/low/nl_NL-mls_5809-low.onnx"
        ["nl_NL-mls_7432-low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/nl/nl_NL/mls_7432/low/nl_NL-mls_7432-low.onnx"
        ["pl_PL-darkman-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/pl/pl_PL/darkman/medium/pl_PL-darkman-medium.onnx"
        ["pl_PL-gosia-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/pl/pl_PL/gosia/medium/pl_PL-gosia-medium.onnx"
        ["pl_PL-mc_speech-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/pl/pl_PL/mc_speech/medium/pl_PL-mc_speech-medium.onnx"
        ["pl_PL-mls_6892-low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/pl/pl_PL/mls_6892/low/pl_PL-mls_6892-low.onnx"
        ["pt_BR-edresson-low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/pt/pt_BR/edresson/low/pt_BR-edresson-low.onnx"
        ["pt_BR-faber-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/pt/pt_BR/faber/medium/pt_BR-faber-medium.onnx"
        ["pt_PT-tugão-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/pt/pt_PT/tugão/medium/pt_PT-tugão-medium.onnx"
        ["ro_RO-mihai-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ro/ro_RO/mihai/medium/ro_RO-mihai-medium.onnx"
        ["ru_RU-denis-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ru/ru_RU/denis/medium/ru_RU-denis-medium.onnx"
        ["ru_RU-dmitri-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ru/ru_RU/dmitri/medium/ru_RU-dmitri-medium.onnx"
        ["ru_RU-irina-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ru/ru_RU/irina/medium/ru_RU-irina-medium.onnx"
        ["ru_RU-ruslan-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ru/ru_RU/ruslan/medium/ru_RU-ruslan-medium.onnx"
        ["sk_SK-lili-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/sk/sk_SK/lili/medium/sk_SK-lili-medium.onnx"
        ["sl_SI-artur-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/sl/sl_SI/artur/medium/sl_SI-artur-medium.onnx"
        ["sr_RS-serbski_institut-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/sr/sr_RS/serbski_institut/medium/sr_RS-serbski_institut-medium.onnx"
        ["sv_SE-nst-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/sv/sv_SE/nst/medium/sv_SE-nst-medium.onnx"
        ["sw_CD-lanfrica-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/sw/sw_CD/lanfrica/medium/sw_CD-lanfrica-medium.onnx"
        ["tr_TR-dfki-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/tr/tr_TR/dfki/medium/tr_TR-dfki-medium.onnx"
        ["tr_TR-fahrettin-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/tr/tr_TR/fahrettin/medium/tr_TR-fahrettin-medium.onnx"
        ["tr_TR-fettah-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/tr/tr_TR/fettah/medium/tr_TR-fettah-medium.onnx"
        ["uk_UA-lada-x_low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/uk/uk_UA/lada/x_low/uk_UA-lada-x_low.onnx"
        ["uk_UA-ukrainian_tts-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/uk/uk_UA/ukrainian_tts/medium/uk_UA-ukrainian_tts-medium.onnx"
        ["vi_VN-25hours_single-low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/vi/vi_VN/25hours_single/low/vi_VN-25hours_single-low.onnx"
        ["vi_VN-vais1000-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/vi/vi_VN/vais1000/medium/vi_VN-vais1000-medium.onnx"
        ["vi_VN-vivos-x_low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/vi/vi_VN/vivos/x_low/vi_VN-vivos-x_low.onnx"
        ["zh_CN-huayan-x_low"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/zh/zh_CN/huayan/x_low/zh_CN-huayan-x_low.onnx"
        ["zh_CN-huayan-medium"]="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/zh/zh_CN/huayan/medium/zh_CN-huayan-medium.onnx"
    )
    if [ "$#" -eq 0 ] && [ -t 0 ]; then
        echo 
        echo "## Text to speech with Piper - https://github.com/rhasspy/piper"
        echo "### Install depdendencies: podman curl pulseaudio-utils"
        echo
        echo "### Available voice models:"
        for key in "${!MODEL_URLS[@]}"; do
            echo "MODEL=$key"
        done | sort
        echo
        echo "## Examples:"
        echo
        echo "say Hello World"
        echo
        echo "MODEL=en_GB-cori-high say Hello World"
        echo
        echo "echo Hello World | say"
        echo
        echo "echo \"Hello World!\" | MODEL=en_GB-cori-high say"
        echo
        return
    fi
    check_dependency() {
        local cmd=$1
        local pkg=${2:-$1}
        if ! command -v "$cmd" >/dev/null; then
            echo "Missing $cmd dependency. Install the $pkg package." >/dev/stderr
            return
        fi
    }
    check_dependency podman
    check_dependency curl
    check_dependency paplay "pulseaudio-utils"
    if ! podman image exists ${IMAGE_NAME}; then
        echo "Building the image..."
        podman build -t ${IMAGE_NAME} - <<EOF
FROM alpine AS downloader
RUN apk add --no-cache wget tar
WORKDIR /download
ARG TAR_URL_AMD64=https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_amd64.tar.gz
ARG TAR_URL_ARM64=https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_arm64.tar.gz
ARG TAR_URL_ARMV7=https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_armv7.tar.gz
RUN ARCH="\$(uname -m)" && \
    if [ "\$ARCH" = "x86_64" ]; then \
        wget \$TAR_URL_AMD64 -O piper.tar.gz; \
    elif [ "\$ARCH" = "aarch64" ]; then \
        wget \$TAR_URL_ARM64 -O piper.tar.gz; \
    elif [ "\$ARCH" = "armv7l" ]; then \
        wget \$TAR_URL_ARMV7 -O piper.tar.gz; \
    else \
        echo "Unsupported platform: \$ARCH" && exit 1; \
    fi && \
    tar -xzf piper.tar.gz && \
    rm piper.tar.gz
FROM debian:bullseye
RUN apt-get update && apt-get install -y tini pulseaudio-utils alsa-utils ffmpeg
WORKDIR /app
COPY --from=downloader /download /app
RUN chmod +x /app/piper/piper
ENTRYPOINT ["/usr/bin/tini", "--"]
ENV PATH="/app/piper:${PATH}"
CMD ["/app/piper/piper"]
EOF
    fi
    if [ ! -f "${MODEL_FILE}" ]; then
        echo "Downloading voice model: ${MODEL_FILE}"
        mkdir -p "${MODEL_DIR}"
        curl -L -C - -o "${MODEL_FILE}" "${MODEL_URLS[${MODEL%.onnx}]}"
    fi
    if [ ! -f "${MODEL_JSON}" ]; then
        echo "Downloading voice model JSON: ${MODEL_JSON}"
        curl -L -C - -o "${MODEL_JSON}" "${MODEL_URLS[${MODEL%.onnx}]}.json"
    fi
    if [[ "${LOG}" == "true" || "$*" == *"--help"* ]]; then
        LOG=/dev/stderr
    else
        LOG=/dev/null
    fi
    if [ "$#" -gt 0 ]; then
        echo " " "$@"
    else
        echo " " && cat
    fi | podman run --rm -i \
        -v /run/user/$(id -u)/pulse:/run/user/$(id -u)/pulse \
        -v ~/.config/pulse/cookie:/run/user/$(id -u)/pulse/cookie \
        -e PULSE_SERVER=unix:/run/user/$(id -u)/pulse/native \
        -v ${MODEL_DIR}:/model:Z \
        ${IMAGE_NAME} \
        sh -c "piper -m /model/${MODEL}.onnx --length_scale ${SPEED} --sentence_silence ${SILENCE} --noise_w ${NOISE} --output_raw $@" 2>${LOG} | \
        paplay --raw --rate=${AUDIO_RATE} --channels=2;
}

say_wrapped() {
    python3 -c "
import sys

text = sys.stdin.buffer.read().decode('utf-8', errors='ignore')
paragraphs = text.split('\n\n')
unwrapped_paragraphs = [' '.join(paragraph.splitlines()) for paragraph in paragraphs]
print('\n\n'.join(unwrapped_paragraphs))
" | say
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    CMD=$1; shift
    ${CMD} $@
else
    unset say
    unset say_wrapped
    alias say="bash ${BASH_SOURCE[0]} say"
    alias say_wrapped="bash ${BASH_SOURCE[0]} say_wrapped"
    #alias piper=say
fi
