#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   scripts/add-host.sh <hostname> <username>
#
# Examples:
#   scripts/add-host.sh x1 ryan
#   scripts/add-host.sh "$(hostname -s)" ryan

HOST="${1:-}"
USER_NAME="${2:-}"
ARCH="${ARCH:-x86_64-linux}"
CHANNEL="${CHANNEL:-nixpkgs_25_11}"

if [[ -z "${HOST}" || -z "${USER_NAME}" ]]; then
  echo >&2 "Usage: $0 <hostname> <username>"
  exit 2
fi

HOSTS_FILE="./nixos/modules/hosts.nix"
SRC_HW="/etc/nixos/hardware-configuration.nix"
DEST_DIR="./nixos/hosts/${HOST}"
DEST_HW="${DEST_DIR}/hardware.nix"

# --- Preconditions -----------------------------------------------------------

[[ -f "${HOSTS_FILE}" ]] || { echo >&2 "ERROR: missing ${HOSTS_FILE}"; exit 1; }
[[ -f "${SRC_HW}" ]] || { echo >&2 "ERROR: missing ${SRC_HW}"; exit 1; }

# Fail if host already exists (match: `  x1 = {` or `x1 = {`)
if grep -Eq "^[[:space:]]*${HOST}[[:space:]]*=[[:space:]]*\{" "${HOSTS_FILE}"; then
  echo >&2 "ERROR: host '${HOST}' already exists in ${HOSTS_FILE}"
  exit 1
fi

# --- Copy hardware config ----------------------------------------------------

mkdir -p "${DEST_DIR}"

if [[ -e "${DEST_HW}" ]]; then
  echo >&2 "ERROR: ${DEST_HW} already exists (won't overwrite)"
  exit 1
fi

cp "${SRC_HW}" "${DEST_HW}"

# --- Insert host entry into hosts.nix ---------------------------------------

ENTRY=$(cat <<EOF
  ${HOST} = {
    hostName = "${HOST}";
    userName = "${USER_NAME}";
    system = "${ARCH}";
    nixpkgsInput = "${CHANNEL}";
    hardwareModule = ../hosts/${HOST}/hardware.nix;
    unstablePackages = [ ];
    extraPackages = [ ];
  };

EOF
)

# Insert before the final closing brace of the top-level attrset.
# This assumes hosts.nix is of the form: { ... }
TMP="$(mktemp)"

python3 - "${HOSTS_FILE}" "${HOST}" "${ENTRY}" > "${TMP}" <<'PY'
import sys, re

hosts_file = sys.argv[1]
host = sys.argv[2]
entry = sys.argv[3]

text = open(hosts_file, "r", encoding="utf-8").read()

# Safety: re-check host doesn't exist
if re.search(rf'(?m)^\s*{re.escape(host)}\s*=\s*\{{', text):
    sys.stderr.write(f"ERROR: host '{host}' already exists in {hosts_file}\n")
    sys.exit(1)

# Find last '}' (top-level close)
m = list(re.finditer(r'\}', text))
if not m:
    sys.stderr.write(f"ERROR: {hosts_file} does not contain a closing '}}'\n")
    sys.exit(1)

last = m[-1].start()
new_text = text[:last].rstrip() + "\n\n" + entry + "\n" + text[last:]
sys.stdout.write(new_text)
PY

# Replace file atomically-ish
cp "${TMP}" "${HOSTS_FILE}"
rm -f "${TMP}"

echo "OK: wrote ${DEST_HW}"
echo "OK: added '${HOST}' to ${HOSTS_FILE}"
