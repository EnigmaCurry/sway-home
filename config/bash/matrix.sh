# Send notifications to Matrix:

# Configure your Matrix server:
## https://matrix-org.github.io/matrix-hookshot/latest/hookshot.html
## https://github.com/spantaleev/matrix-docker-ansible-deploy/blob/master/docs/configuring-playbook-bridge-hookshot.md

## Put these required config vars into your ~/.bashrc.local :
## MATRIX_ALERT_WEBHOOK=https://matrix.enigmacurry.com/hookshot/webhooks/XXXXXXX
## BCT_ACTION_COMMAND='matrix-send "Command completed on ${HOSTNAME} :: ${output_str}"'

matrix-alert() {
    if [[ -n "${MATRIX_ALERT_WEBHOOK}" ]]; then
        curl -X POST "${MATRIX_ALERT_WEBHOOK}" --json '{"text":"'"$*"'"}' >/dev/null 2>&1
    else
        echo "Missing MATRIX_ALERT_WEBHOOK env var." >/dev/stderr
        return 1
    fi
}

matrix-markdown() {
    local MARKDOWN_FILE=$1;
    if [[ ! -f "${MARKDOWN_FILE}" ]]; then
        echo "Markdown file does not exist: ${MARKDOWN_FILE}" >/dev/stderr
        return 1
    fi
    if [[ -z "${MATRIX_ALERT_WEBHOOK}" ]]; then
        echo "Missing MATRIX_ALERT_WEBHOOK env var." >/dev/stderr
        return 1
    else        
        curl -X POST "${MATRIX_ALERT_WEBHOOK}" --json "$(echo "{}" | jq -c --rawfile md $1 '.text=$md')" >/dev/null 2>&1
    fi
}

