# Justfile parser for bash completion of just target args

## Example alias 'mrfusion-proxmox' with argument based tab completion:
# (put this ~/.bashrc.local)
#
# _justfile_alias mrfusion-proxmox \
#   "$HOME/git/vendor/enigmacurry/nixos-vm-template/Justfile" \
#   "$HOME/git/vendor/enigmacurry/nixos-vm-template/.env-mrfusion

# --- shared hint printer (no garbling, preserves current input line) ---
_justfile_alias_hint() {
  printf '\e7' >&2        # save cursor
  printf '\e[J' >&2       # clear to end of screen
  printf '\n\e[2K%s\n' "$1" >&2
  printf '\e8' >&2        # restore cursor
}

# Internal: run just with per-alias config (-f, -d, optional -E)
_justfile_alias_run_just() {
  local alias_name="$1"; shift
  local workdir="${_JUSTFILE_ALIAS_WORKDIR[$alias_name]}"
  local justfile="${_JUSTFILE_ALIAS_JUSTFILE[$alias_name]}"
  local dotenv="${_JUSTFILE_ALIAS_DOTENV[$alias_name]}"

  local -a cmd=(just -f "$justfile" -d "$workdir")
  [[ -n "$dotenv" ]] && cmd+=(-E "$dotenv")
  "${cmd[@]}" "$@"
}

# Internal: fetch the recipe signature line ("recipe arg1 arg2=...:")
_justfile_alias_recipe_header() {
  local alias_name="$1"
  local recipe="$2"

  _justfile_alias_run_just "$alias_name" --show "$recipe" 2>/dev/null |
    sed -n -E \
      -e '/^[[:space:]]*#/d' \
      -e '/^[[:space:]]*$/d' \
      -e "/^[[:space:]]*${recipe}([[:space:]].*)?:[[:space:]]*$/ { p; q; }"
}

# Internal: get param token (e.g. profile="core") at arg_index (0-based)
_justfile_alias_param_token() {
  local alias_name="$1"
  local recipe="$2"
  local arg_index="$3"

  local hdr
  hdr="$(_justfile_alias_recipe_header "$alias_name" "$recipe")" || return 1
  [[ -z "$hdr" ]] && return 1

  hdr="${hdr%:}"
  hdr="${hdr#"$recipe"}"
  hdr="${hdr# }"

  local -a params
  read -r -a params <<<"$hdr"

  printf '%s' "${params[$arg_index]}"
}

# --- shared: derive "next arg" hint from signature ---
_justfile_alias_next_arg_hint() {
  local alias_name="$1"
  local recipe="$2"
  local arg_index="$3" # 0-based

  local tok
  tok="$(_justfile_alias_param_token "$alias_name" "$recipe" "$arg_index")" || return 0
  [[ -z "$tok" ]] && return 0

  local name="${tok%%=*}"
  if [[ "$tok" == *"="* ]]; then
    local default="${tok#*=}"
    _justfile_alias_hint "Next arg: ${name} (default ${default})"
  else
    _justfile_alias_hint "Next arg: ${name} (required)"
  fi
}

# Internal: get completion candidates for a param name using `_completion <param>`
_justfile_alias_param_candidates() {
  local alias_name="$1"
  local param_name="$2"
  local recipe="_completion_${param_name}"

  _justfile_alias_run_just "$alias_name" "$recipe" 2>/dev/null
}

_justfile_alias_sanitize_name() {
  # keep letters, numbers, underscores; turn others into underscore
  echo "$1" | sed -E 's/[^A-Za-z0-9_]/_/g'
}

# --- generic completion dispatcher: called for every alias we create ---
_justfile_alias_complete() {
  local alias_name="${COMP_WORDS[0]}"

  local cur="${COMP_WORDS[COMP_CWORD]}"
  local recipe="${COMP_WORDS[1]}"

  # If completing recipe name or flags, delegate to just's stock completion.
  if (( COMP_CWORD <= 1 )) || [[ "$cur" == -* ]]; then
    # Use env vars here so _just still works from any directory.
    local workdir="${_JUSTFILE_ALIAS_WORKDIR[$alias_name]}"
    local justfile="${_JUSTFILE_ALIAS_JUSTFILE[$alias_name]}"
    JUST_JUSTFILE="$justfile" JUST_WORKING_DIRECTORY="$workdir" \
      _just "$alias_name"
    return 0
  fi

  # We are completing a positional arg:
  # COMP_WORDS: [0]=alias [1]=recipe [2]=arg0 ...
  local arg_index=$((COMP_CWORD - 2))

  # Try to discover the param name at this position
  local tok name
  tok="$(_justfile_alias_param_token "$alias_name" "$recipe" "$arg_index")" || tok=""
  name="${tok%%=*}"

  # If we have a param name, try `_completion <name>` and use it as candidates.
  if [[ -n "$name" ]]; then
    local -a cands
    mapfile -t cands < <(_justfile_alias_param_candidates "$alias_name" "$name")

    if (( ${#cands[@]} > 0 )); then
      # Optional: still show hint when completing an empty token
      [[ -z "$cur" ]] && _justfile_alias_next_arg_hint "$alias_name" "$recipe" "$arg_index"

      # Filter candidates by prefix using bash's compgen
      local IFS=$'\n'
      COMPREPLY=($(compgen -W "${cands[*]}" -- "$cur"))
      return 0
    fi
  fi

  # No candidates available: keep your existing hint behavior when cur is empty
  if [[ -z "$cur" ]]; then
    _justfile_alias_next_arg_hint "$alias_name" "$recipe" "$arg_index"
    COMPREPLY=()
    return 0
  fi

  # Otherwise fall back to just completion behavior
  local workdir="${_JUSTFILE_ALIAS_WORKDIR[$alias_name]}"
  local justfile="${_JUSTFILE_ALIAS_JUSTFILE[$alias_name]}"
  JUST_JUSTFILE="$justfile" JUST_WORKING_DIRECTORY="$workdir" \
    _just "$alias_name"
}

# --- public helper: define alias + completion ---
# Usage:
#   justfile_alias <alias-name> <justfile-path> [dotenv-file] [workdir]
_justfile_alias() {
  local name="$1"
  local justfile="$2"
  local dotenv="${3:-}"
  local workdir="${4:-}"

  if [[ -z "$name" || -z "$justfile" ]]; then
    echo "usage: justfile_alias <alias-name> <justfile-path> [dotenv-file] [workdir]" >&2
    return 2
  fi

  if [[ -z "$workdir" ]]; then
    workdir="$(cd "$(dirname "$justfile")" && pwd -P)" || return 1
  fi

  declare -gA _JUSTFILE_ALIAS_JUSTFILE
  declare -gA _JUSTFILE_ALIAS_WORKDIR
  declare -gA _JUSTFILE_ALIAS_DOTENV

  _JUSTFILE_ALIAS_JUSTFILE["$name"]="$justfile"
  _JUSTFILE_ALIAS_WORKDIR["$name"]="$workdir"
  _JUSTFILE_ALIAS_DOTENV["$name"]="$dotenv"

  if [[ -n "$dotenv" ]]; then
    alias "$name=just -f \"${justfile}\" -d \"${workdir}\" -E \"${dotenv}\""
  else
    alias "$name=just -f \"${justfile}\" -d \"${workdir}\""
  fi

  # No -o default / bashdefault => no pathname fallback
  complete -F _justfile_alias_complete "$name"
}

