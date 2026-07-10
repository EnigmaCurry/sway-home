{ pkgs }:

# Networking: transport, transfer, remote filesystems, diagnostics.
# Part of the `dotfiles` profile.

with pkgs; [
  curl
  wget
  nmap
  tcpdump
  socat
  sshfs
  rclone
  s3cmd
  tor
  apacheHttpd
]
