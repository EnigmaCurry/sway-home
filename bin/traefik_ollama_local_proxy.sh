#!/usr/bin/env bash
set -euo pipefail

# traefik-ollama-local-proxy.sh
#
# Localhost-only Traefik proxy that forwards to a remote Ollama endpoint,
# injecting an Authorization header on the forwarded request.
#
# Traefik resolution:
#   1) If `traefik` is in PATH, use it.
#   2) Else, if `nix` is in PATH, run Traefik via `nix run`.
#   3) Else, error.
#
# Defaults:
#   - listens on 127.0.0.1:11435
#   - DOES NOT skip TLS verification unless --insecure-skip-verify is set

usage() {
  cat <<'EOF'
Usage:
  traefik-ollama-local-proxy.sh [options]

Options:
  --upstream URL              Remote Ollama base URL (e.g. https://host:11434) (or env OLLAMA_UPSTREAM)
  --token TOKEN               API token to inject (or env OLLAMA_TOKEN)
  --listen ADDR:PORT          Local listen address (default: 127.0.0.1:11435)
  --bearer-prefix STR         Authorization prefix (default: "Bearer")
  --insecure-skip-verify      Skip TLS cert verification to upstream (for self-signed certs). Default: OFF
  --log-level LEVEL           Traefik log level (default: INFO)
  --nix-traefik-ref REF       Nix ref to run for traefik (default: nixpkgs#traefik)
  -h, --help                  Show help

Examples:
  ./traefik-ollama-local-proxy.sh --upstream https://ollama.example.com --token 'abc123'
  ./traefik-ollama-local-proxy.sh --upstream https://10.0.0.50:11434 --token 'abc123' --insecure-skip-verify

Notes:
  - The local proxy does NOT require auth; it injects Authorization to the upstream.
  - The token is written into a temporary config file with permissions 0600.
EOF
}

# Defaults
LISTEN_ADDR="127.0.0.1:11435"
LOG_LEVEL="INFO"
INSECURE_SKIP_VERIFY="false"
BEARER_PREFIX="Bearer"
NIX_TRAEFIK_REF="nixpkgs#traefik"

# Inputs (can come from env)
UPSTREAM="${OLLAMA_UPSTREAM:-}"
TOKEN="${OLLAMA_TOKEN:-}"

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --upstream) UPSTREAM="${2:-}"; shift 2;;
    --token) TOKEN="${2:-}"; shift 2;;
    --listen) LISTEN_ADDR="${2:-}"; shift 2;;
    --bearer-prefix) BEARER_PREFIX="${2:-}"; shift 2;;
    --insecure-skip-verify) INSECURE_SKIP_VERIFY="true"; shift 1;;
    --log-level) LOG_LEVEL="${2:-}"; shift 2;;
    --nix-traefik-ref) NIX_TRAEFIK_REF="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2;;
  esac
done

if [[ -z "$UPSTREAM" ]]; then
  echo "ERROR: --upstream (or env OLLAMA_UPSTREAM) is required" >&2
  usage
  exit 2
fi

if [[ -z "$TOKEN" ]]; then
  echo "ERROR: --token (or env OLLAMA_TOKEN) is required" >&2
  usage
  exit 2
fi

# Decide how to run traefik
TRAEFIK_MODE=""
if command -v traefik >/dev/null 2>&1; then
  TRAEFIK_MODE="path"
elif command -v nix >/dev/null 2>&1; then
  TRAEFIK_MODE="nix"
else
  echo "ERROR: traefik not found in PATH, and nix not found either." >&2
  echo "Install traefik, or install nix so the script can run Traefik via nix." >&2
  exit 127
fi

# Create temp config
umask 077
CFG="$(mktemp -t traefik-ollama-proxy.XXXXXX.yml)"

cleanup() {
  rm -f "$CFG"
}
trap cleanup EXIT INT TERM

# Build config (dynamic file provider)
cat > "$CFG" <<EOF
http:
  routers:
    ollama:
      rule: "PathPrefix(\`/\`)"
      entryPoints: ["ollama"]
      service: "ollama"
      middlewares: ["ollama-auth"]

  middlewares:
    ollama-auth:
      headers:
        customRequestHeaders:
          Authorization: "${BEARER_PREFIX} ${TOKEN}"
EOF

if [[ "$INSECURE_SKIP_VERIFY" == "true" ]]; then
  cat >> "$CFG" <<'EOF'

  serversTransports:
    ollama-transport:
      insecureSkipVerify: true
EOF
fi

cat >> "$CFG" <<EOF

  services:
    ollama:
      loadBalancer:
        passHostHeader: false
EOF

if [[ "$INSECURE_SKIP_VERIFY" == "true" ]]; then
  cat >> "$CFG" <<'EOF'
        serversTransport: "ollama-transport"
EOF
fi

cat >> "$CFG" <<EOF
        servers:
          - url: "${UPSTREAM}"
EOF

echo "Starting Traefik localhost proxy:"
echo "  Listen : http://${LISTEN_ADDR}"
echo "  Upstream: ${UPSTREAM}"
echo "  TLS skip-verify: ${INSECURE_SKIP_VERIFY}"
echo "  Config: ${CFG}"
echo "  Traefik: ${TRAEFIK_MODE}${TRAEFIK_MODE:+ }"
if [[ "$TRAEFIK_MODE" == "nix" ]]; then
  echo "  Nix ref: ${NIX_TRAEFIK_REF}"
fi
echo
echo "Test:"
echo "  curl -s http://${LISTEN_ADDR}/api/tags"
echo

# Run Traefik in foreground
if [[ "$TRAEFIK_MODE" == "path" ]]; then
  exec traefik \
    --log.level="$LOG_LEVEL" \
    --entrypoints.ollama.address="$LISTEN_ADDR" \
    --providers.file.filename="$CFG" \
    --providers.file.watch=true
else
  # Run Traefik from nix. The "--" separates nix-run args from traefik args.
  exec nix run "$NIX_TRAEFIK_REF" -- \
    --log.level="$LOG_LEVEL" \
    --entrypoints.ollama.address="$LISTEN_ADDR" \
    --providers.file.filename="$CFG" \
    --providers.file.watch=true
fi
