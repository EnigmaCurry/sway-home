## yt-dlp
## Watch any youtube/invidious video URL (or any URL yt-dlp supports) at the highest quality:
## Can read URL input directly if the argument is left blank (incognito mode)
## (Sometimes yt doesn't work, so use yt-720 as a backup)
#### Old version:
# yt() {
#     STREAM=$1; [[ "$STREAM" == "" ]] && read -e -p "Enter stream: " STREAM
#     yt-dlp -f bestvideo+bestaudio "$STREAM" -o - | mpv - --fs -force-seekable=yes
# }
#### New version: mpv can run use yt-dlp all by itself, just pass the URL:
alias yt=mpv

## Watch youtube/invidious video URL (or any URL yt-dlp supports)
## Uses a medium quality pre-muxed stream (its usually about 720p).
## Can read URL input directly if the argument is left blank (incognito mode)
## (yt-720 has higher reliability than yt, but its lower quality)
yt-720() {
    STREAM=$1; [[ "$STREAM" == "" ]] && read -e -p "Enter stream: " STREAM
    yt-dlp "$STREAM" -o - | mpv - --fs -force-seekable=yes
}
## Download best quality video and audio and mux together:
yt-download() {
    STREAM=$1; [[ "$STREAM" == "" ]] && read -e -p "Enter stream: " STREAM
    yt-dlp -f bestvideo+bestaudio "$STREAM" --merge-output-format mp4
}
## Download youtube audio only
yt-audio() {
    STREAM=$1; [[ "$STREAM" == "" ]] && read -e -p "Enter stream: " STREAM
    yt-dlp -x --audio-format mp3 $STREAM
}

screen-record() {
    mkdir -p ~/Screencasts
    DESCRIPTION="$@"
    wf-recorder -a -f ~/Screencasts/$(date +%Y-%m-%d-%H%M)-"$DESCRIPTION".mkv
}
