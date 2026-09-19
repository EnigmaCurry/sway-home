{ pkgs }:

# Networking: transport, transfer, remote filesystems, diagnostics.
# Part of the `dotfiles` profile.

with pkgs; [
  openssl
  curl
  wget
  nmap
  ipcalc
  tcpdump
  socat
  sshfs
  rclone
  s3cmd
  tor
  apacheHttpd
  irssi
  keychain
  dig
  wireguard-tools         # wg, wg-quick; also lets NM import wg .conf files
]
