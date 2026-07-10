{ pkgs }:

# Media: audio / video capture, transcode, download. Part of the
# `dotfiles` profile.

with pkgs; [
  yt-dlp
  ffmpeg
]
