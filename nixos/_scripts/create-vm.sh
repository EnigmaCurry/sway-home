#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  create-vm.sh <vm_root> <channel>

Args:
  vm_root   Path where the VM config + files live (e.g. ~/VMs)
  channel   NixOS channel name (e.g. nixos-25.11)

Env overrides (optional):
  ARCH         Default: x86_64-linux
  ISO_NAME     Default: latest-nixos-graphical-${ARCH}.iso
  DISK_SIZE    Default: 50G
  DISPLAY      Default: gtk
  FORCE        If set to 1, overwrite existing .conf (won't delete VM dir)

Examples:
  ./nixos/_scripts/create-vm.sh "$HOME/VMs" nixos-25.11
  ARCH=aarch64-linux ./nixos/_scripts/create-vm.sh "$HOME/VMs" nixos-25.11
EOF
}

VM_ROOT="${1:-}"
CHANNEL="${2:-}"

if [[ -z "${VM_ROOT}" || -z "${CHANNEL}" ]]; then
  usage
  exit 2
fi

ARCH="${ARCH:-x86_64-linux}"
ISO_NAME="${ISO_NAME:-latest-nixos-graphical-${ARCH}.iso}"
DISK_SIZE="${DISK_SIZE:-50G}"
VM_DISPLAY="${VM_DISPLAY:-gtk}"
FORCE="${FORCE:-0}"

CONFIG_PATH="${VM_ROOT}/${CHANNEL}.conf"
VM_DIR="${VM_ROOT}/${CHANNEL}"
ISO_PATH="${VM_DIR}/${ISO_NAME}"
SHA_PATH="${VM_DIR}/${ISO_NAME}.sha256"

need() {
  command -v "$1" >/dev/null 2>&1 || { echo >&2 "ERROR: missing required command: $1"; exit 1; }
}

need curl
need sha256sum
need awk

mkdir -p "${VM_DIR}"

if [[ -e "${CONFIG_PATH}" && "${FORCE}" != "1" ]]; then
  echo >&2 "ERROR: config already exists: ${CONFIG_PATH}"
  echo >&2 "       Set FORCE=1 to overwrite."
  exit 1
fi

tmp_conf="$(mktemp)"
cat > "${tmp_conf}" <<EOF
#!/usr/bin/env quickemu --vm
guest_os="linux"
disk_img="${CHANNEL}/disk.qcow2"
iso="${CHANNEL}/${ISO_NAME}"
disk_size="${DISK_SIZE}"
EOF
chmod +x "${tmp_conf}"
mv -f "${tmp_conf}" "${CONFIG_PATH}"

echo "Wrote VM config: ${CONFIG_PATH}"
echo "Ensuring ISO present: ${ISO_PATH}"

# Download ISO (resume if partial)
curl -fL -C - "https://channels.nixos.org/${CHANNEL}/${ISO_NAME}" \
  --output "${ISO_PATH}"

# Download SHA256 file
curl -fL "https://channels.nixos.org/${CHANNEL}/${ISO_NAME}.sha256" \
  --output "${SHA_PATH}"

echo "Verifying ISO sha256..."
hash="$(awk 'NF{print $1; exit}' "${SHA_PATH}")"
if [[ -z "${hash}" ]]; then
  echo >&2 "ERROR: could not parse sha256 from ${SHA_PATH}"
  exit 1
fi

(
  cd "${VM_DIR}"
  echo "${hash}  ${ISO_NAME}" | sha256sum -c -
)

echo "OK: VM created."
echo "Next:"
echo "  just vm-start"
