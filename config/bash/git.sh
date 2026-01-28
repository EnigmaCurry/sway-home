# git specific cd aliases for vendor roots + tab completion:
#  `cdv` takes you to the vendor root ~/git/vendor
#  `cdv enigmacurry/emacs` takes you to ~/git/vendor/enigmacurry/emacs
cdv() {
  local target_dir=~/git/vendor/$1
  if [ -d "$target_dir" ]; then
    cd "$target_dir" || return 1
  else
    echo "Error: Directory '$target_dir' does not exist."
    return 1
  fi
}
_cdv_completion() {
  local base_dir=$1
  local cur=${COMP_WORDS[COMP_CWORD]}
  local full_path="${base_dir}/${cur}"
  COMPREPLY=($(compgen -o dirnames -- "$full_path"))
  for i in "${!COMPREPLY[@]}"; do
    COMPREPLY[i]="${COMPREPLY[i]#${base_dir}/}/"
  done
}
complete -o nospace -F _cdv_completion cdv

# `cdg emacs` takes you to your personal emacs repository
# in ~/git/vendor/${GIT_USERNAME:-enigmacurry}/emacs
# (If you're not enigmacurry, you need to set GIT_USERNAME in ~/.bashrc.local)
cdg() {
  local username=${GIT_USERNAME:-enigmacurry}
  cdv "${username}/$1"
}
_cdg_completion() {
  local username=${GIT_USERNAME:-enigmacurry}
  _cdv_completion "~/git/vendor/${username}"
}
complete -o nospace -F _cdg_completion cdg
