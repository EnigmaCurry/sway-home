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
## Download youtube audio only, supports playlists:
yt-audio() {
    STREAM=$1; [[ "$STREAM" == "" ]] && read -e -p "Enter stream: " STREAM
    FOLDER=$(mktemp -d)  # Create a temporary folder to store individual audio files
    yt-dlp -f bestaudio --extract-audio --audio-format mp3 --postprocessor-args "-threads $(nproc)" -o "$FOLDER/%(title)s.%(ext)s" $STREAM
    # Count the number of mp3 files
    MP3_FILES=("$FOLDER"/*.mp3)
    MP3_COUNT=${#MP3_FILES[@]}
    # If only one track, simply rename it to the output file
    if [[ "$MP3_COUNT" -eq 1 ]]; then
        OUTPUT_FILE=$(basename "${MP3_FILES[0]}" .mp3).mp3
        mv "${MP3_FILES[0]}" "$OUTPUT_FILE"
        echo "Single track downloaded and saved as '$OUTPUT_FILE'."
    else
        # Extract the common prefix of the downloaded file names
        COMMON_PREFIX=$(ls "$FOLDER"/*.mp3 | sed 's#.*/##' | sed -e 's/\.mp3$//' | awk 'NR==1{prefix=$0; next} {while(substr($0,1,length(prefix))!=prefix) {prefix=substr(prefix,1,length(prefix)-1)}} END{print prefix}')
        # Create a list of mp3 files to concatenate
        CONCAT_LIST="$FOLDER/concat_list.txt"
        find "$FOLDER" -type f -name "*.mp3" | sort | sed "s/^/file '/; s/$/'/" > "$CONCAT_LIST"
        # Use ffmpeg to concatenate all mp3 files without re-encoding
        OUTPUT_FILE="${COMMON_PREFIX}.mp3"
        ffmpeg -f concat -safe 0 -i "$CONCAT_LIST" -c copy "$OUTPUT_FILE"  
        echo "All tracks have been merged into '$OUTPUT_FILE'."
    fi    
    # Clean up the temporary folder
    rm -rf "$FOLDER"
}

screen-record() {
    mkdir -p ~/Screencasts
    DESCRIPTION="$@"
    wf-recorder -a -f ~/Screencasts/$(date +%Y-%m-%d-%H%M)-"$DESCRIPTION".mkv
}
