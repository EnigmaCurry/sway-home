#!/usr/bin/env bash
set -euo pipefail

WEBHOOK_URL="${WEBHOOK_URL:?missing WEBHOOK_URL}"

HOSTNAME="$(cat /proc/sys/kernel/hostname)"
IP=""

# Wait until we can infer the primary source IP via the default route.
for _ in $(seq 1 60); do
  IP="$(
    ip -4 route get 1.1.1.1 2>/dev/null \
      | awk '{for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}' \
      || true
  )"

  if [[ -n "${IP}" ]]; then
    break
  fi

  sleep 2
done

if [[ -z "${IP}" ]]; then
  echo "webhook-notify: no IPv4 address discovered; skipping"
  exit 0
fi

echo "webhook-notify: posting HOSTNAME=${HOSTNAME} IP=${IP}"

curl -fsS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"hostname\":\"${HOSTNAME}\",\"ip\":\"${IP}\"}" \
  "${WEBHOOK_URL}" \
  || true
