#!/usr/bin/env bash
set -euo pipefail

## Use this script to block all outgoing routes to LAN addresses (RFC1918)
## Essentially, this computer will only be able to reach public IP addresses.

POLICY="block-lan-egress"

# Rules: allow DNS, then drop RFC1918 + IPv6 ULA/link-local routes
RULES=(
  'rule priority="-10" port port="53" protocol="udp" accept'
  'rule priority="-10" port port="53" protocol="tcp" accept'

  'rule family="ipv4" priority="0" destination address="10.0.0.0/8" drop'
  'rule family="ipv4" priority="0" destination address="172.16.0.0/12" drop'
  'rule family="ipv4" priority="0" destination address="192.168.0.0/16" drop'

  'rule family="ipv6" priority="0" destination address="fc00::/7" drop'
  'rule family="ipv6" priority="0" destination address="fe80::/10" drop'
)

usage() {
  cat <<EOF
Usage:
  $(basename "$0") enable
  $(basename "$0") disable

What it does (enable):
  - Creates a firewalld policy named: ${POLICY}
  - Applies it to host-originated traffic (HOST -> ANY)
  - Allows outbound DNS (TCP/UDP 53)
  - Drops outbound traffic to RFC1918 IPv4 and IPv6 ULA/link-local destinations
EOF
}

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      exec sudo -E bash "$0" "$@"
    else
      echo "ERROR: must run as root (sudo not found)." >&2
      exit 1
    fi
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }
die() { echo "ERROR: $*" >&2; exit 1; }

ensure_firewalld() {
  have_cmd firewall-cmd || die "firewall-cmd not found. Install firewalld (e.g. sudo dnf install -y firewalld)."

  if ! systemctl is-active --quiet firewalld; then
    echo "firewalld not active; starting and enabling it..."
    systemctl enable --now firewalld
  fi

  firewall-cmd --state >/dev/null 2>&1 || die "firewalld is not responding."
}

supports_policies() {
  firewall-cmd --help 2>/dev/null | grep -q -- '--new-policy'
}

policy_exists() {
  firewall-cmd --permanent --get-policies 2>/dev/null | tr ' ' '\n' | grep -Fxq "$POLICY"
}

add_policy_if_missing() {
  if ! policy_exists; then
    echo "Creating policy: $POLICY"
    firewall-cmd --permanent --new-policy "$POLICY"
  else
    echo "Policy already exists: $POLICY"
  fi

  # Apply to host-originated traffic -> anywhere
  firewall-cmd --permanent --policy "$POLICY" --add-ingress-zone HOST
  firewall-cmd --permanent --policy "$POLICY" --add-egress-zone ANY

  # Only act on our explicit rules (don’t default-drop all output)
  firewall-cmd --permanent --policy "$POLICY" --set-target CONTINUE
}

list_permanent_rules() {
  firewall-cmd --permanent --policy "$POLICY" --list-rich-rules 2>/dev/null || true
}

ensure_rich_rules() {
  local existing
  existing="$(list_permanent_rules)"

  for r in "${RULES[@]}"; do
    if grep -Fxq "$r" <<<"$existing"; then
      echo "OK: rule exists: $r"
    else
      echo "ADD: $r"
      firewall-cmd --permanent --policy "$POLICY" --add-rich-rule="$r"
    fi
  done
}

remove_policy() {
  if policy_exists; then
    echo "Deleting policy: $POLICY"
    firewall-cmd --permanent --delete-policy "$POLICY"
  else
    echo "Policy not present (nothing to do): $POLICY"
  fi
}

reload_firewalld() {
  echo "Reloading firewalld..."
  firewall-cmd --reload
}

summary() {
  echo
  echo "==================== Status ====================="
  echo "firewalld state:   $(firewall-cmd --state 2>/dev/null || echo 'unknown')"
  echo "firewalld version: $(firewall-cmd --version 2>/dev/null || echo 'unknown')"
  echo "policy present:    $(policy_exists && echo yes || echo no)"
  echo

  if firewall-cmd --get-policies 2>/dev/null | tr ' ' '\n' | grep -Fxq "$POLICY"; then
    echo "Policy '$POLICY' (runtime):"
    firewall-cmd --info-policy "$POLICY" || true
    echo
    echo "Rich rules (runtime):"
    firewall-cmd --policy "$POLICY" --list-rich-rules || true
  fi

  echo "================================================="
}

main() {
  if [[ $# -ne 1 ]]; then
    usage
    exit 2
  fi

  local action="$1"
  case "$action" in
    enable|disable) ;;
    -h|--help|help) usage; exit 0 ;;
    *) echo "ERROR: action must be 'enable' or 'disable'"; echo; usage; exit 2 ;;
  esac

  need_root "$@"
  ensure_firewalld

  if ! supports_policies; then
    die "Your firewalld does not appear to support policies (--new-policy missing). Upgrade firewalld or use the 'direct' interface instead."
  fi

  if [[ "$action" == "enable" ]]; then
    add_policy_if_missing
    ensure_rich_rules
    reload_firewalld
    summary
  else
    remove_policy
    reload_firewalld
    summary
  fi
}

main "$@"
