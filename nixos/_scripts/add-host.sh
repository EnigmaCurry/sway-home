#!/usr/bin/env nix-shell
#!nix-shell -i bash -p python3

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

HOSTS_FILE="./nixos/hosts/hosts.nix"
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

# --- Generate storage.nix (wrap hardware + optional swap override) ------------

STORAGE_NIX="${DEST_DIR}/storage.nix"

if [[ -e "${STORAGE_NIX}" ]]; then
  echo >&2 "ERROR: ${STORAGE_NIX} already exists (won't overwrite)"
  exit 1
fi

python3 - "${DEST_HW}" "${STORAGE_NIX}" <<'PY'
import sys, re

hw_path = sys.argv[1]
out_path = sys.argv[2]
text = open(hw_path, "r", encoding="utf-8").read()

def extract_swap_block(src: str):
    # Find: swapDevices = [ ... ];
    m = re.search(r'(?ms)^\s*swapDevices\s*=\s*\[', src)
    if not m:
        return None

    # Walk forward to the matching closing ']'
    i = m.start()
    j = m.end() - 1  # index at '['
    depth = 0
    k = j
    while k < len(src):
        c = src[k]
        if c == '[':
            depth += 1
        elif c == ']':
            depth -= 1
            if depth == 0:
                # Expect following '];' (allow whitespace/newlines)
                tail = src[k:]
                mm = re.match(r'(?s)\]\s*;', tail)
                if not mm:
                    raise SystemExit("ERROR: swapDevices block found, but missing closing '];'")
                end = k + mm.end()
                return src[i:end]
        k += 1
    raise SystemExit("ERROR: unterminated swapDevices block")

swap_block = extract_swap_block(text)

if swap_block is None:
    forced = "  # No swapDevices found in hardware.nix; override to none.\n  swapDevices = lib.mkForce [ ];\n"
else:
    # Convert `swapDevices = ...` into `swapDevices = lib.mkForce ...`
    swap_block = swap_block.strip()
    swap_block = re.sub(r'(?m)^\s*swapDevices\s*=\s*', '  swapDevices = lib.mkForce ', swap_block)
    forced = swap_block.rstrip(';') + ";\n"
    if not forced.endswith("\n"):
        forced += "\n"

storage = f"""{{ lib, ... }}:

{{
  # Wrapper module so you can add host-specific storage tweaks
  # without editing the generated hardware.nix.
  imports = [ ./hardware.nix ];

{forced}}}
"""
open(out_path, "w", encoding="utf-8").write(storage)
print(f"OK: wrote {out_path}")
PY

# --- Insert host entry into hosts.nix ---------------------------------------

ENTRY=$(cat <<EOF
  ${HOST} = {
    hostName = "${HOST}";
    userName = "${USER_NAME}";
    system = "${ARCH}";
    nixpkgsInput = "${CHANNEL}";
    # Use storage.nix so you can override storage bits (swap, luks, etc.)
    # while still importing the generated hardware.nix.
    hardwareModule = ../hosts/${HOST}/storage.nix;
    unstablePackages = [ ];
    extraPackages = [ ];
    # Per-host schema consumed by modules/host-locale.nix
    locale = {
      timeZone = "America/Denver";
      defaultLocale = "en_US.UTF-8";
      # extraLocaleSettings = {
      #   LC_TIME = "en_US.UTF-8";
      # };
    };
    xkb = {
      layout = "us";
      variant = "";
      options = "ctrl:nocaps";
      consoleUseXkbConfig = true;
    };
    emacs = {
      enable = true;
      input = "emacs_enigmacurry";
    };
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
echo "OK: wrote ${STORAGE_NIX}"
echo "OK: added '${HOST}' to ${HOSTS_FILE}"
