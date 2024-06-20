# Set TERM, but only for specific terminals we know about:
case "$TERM" in
    xterm) export TERM=xterm-256color;;
    foot) export TERM=xterm-256color;;
esac
