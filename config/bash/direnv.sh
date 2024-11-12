# direnv sets contextual aliases per working directory.
# Each project root directory should contain a .envrc file
# You must allow each directory to be loaded, e.g.,
#   direnv allow
if command -v direnv &>/dev/null ; then
    eval "$(direnv hook bash)"
fi
