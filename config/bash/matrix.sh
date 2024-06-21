# Send notifications to Matrix:

# Configure your Matrix server:
## https://matrix-org.github.io/matrix-hookshot/latest/hookshot.html
## https://github.com/spantaleev/matrix-docker-ansible-deploy/blob/master/docs/configuring-playbook-bridge-hookshot.md

matrix-alert() {
    if [[ -n "${MATRIX_ALERT_WEBHOOK}" ]]; then
        (set -x; curl -X POST "${MATRIX_ALERT_WEBHOOK}" --json '{"text":"'"$*"'"}' >/dev/null 2>&1)
    else
        echo "Missing MATRIX_ALERT_WEBHOOK env var." >/dev/stderr
        return 1
    fi
}

## Put this in your ~/.bashrc.local :
## MATRIX_ALERT_WEBHOOK=https://matrix.enigmacurry.com/hookshot/webhooks/XXXXXXX
## BCT_ACTION_COMMAND='matrix-send "Command completed on ${HOSTNAME} :: ${output_str}"'
