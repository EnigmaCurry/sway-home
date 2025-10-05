#!/usr/bin/env bash
# cast
# Launch a floating WezTerm window at COLSxROWS and record with asciinema (quiet),
# while loading your normal shell profile/rc inside the recording.
# Default inner command: bash -i (override with -s 'your command')

set -Eeuo pipefail

# -------- defaults --------
ROWS=20
COLS=80
NAME="${NAME:-}"                    # can be set via env; CLI -n or positional overrides
OUT_PATH=""
OUT_DIR="${HOME}/casts"
CLASS=""
EXIT_BEHAVIOR="CloseOnCleanExit"    # Hold | Close | CloseOnCleanExit
WEZTERM_BIN="${WEZTERM_BIN:-}"
FONT_SIZE="24.0"
WINDOW_X=0
WINDOW_Y=42
SHELL_CMD="${SHELL_CMD:-bash -i}"   # default inner command; override with -s

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] [NAME|PATH]

Options:
  -r ROWS        Rows (default: ${ROWS})
  -c COLS        Cols (default: ${COLS})
  -n NAME        Base filename (no .cast); saved under ${OUT_DIR}
  -o PATH        Explicit output path (overrides -n and out dir)
  -d DIR         Output directory (default: ${OUT_DIR})
  -k CLASS       WezTerm/Hyprland app class (default: CAST-RECORD)
  -b BEHAVIOR    WezTerm exit behavior: Hold | Close | CloseOnCleanExit (default: ${EXIT_BEHAVIOR})
  -s CMD         Inner shell/command to run inside the recording (default: "bash -i")
  -h             Show help

Positional:
  NAME|PATH      If provided:
                   - 'foo' → saves to \${OUT_DIR}/foo-YYYYmmdd-HHMMSS.cast
                   - '/abs/file.cast' or './rel/file.cast' → saved exactly there
Examples:
  cast foo
  cast ./out.cast
  cast -s 'bash -il' foo
  cast -s 'zsh -i' -r 24 -c 100
EOF
}

# -------- parse flags --------
while getopts ":r:c:n:o:d:k:b:s:h" opt; do
  case "$opt" in
    r) ROWS="${OPTARG}" ;;
    c) COLS="${OPTARG}" ;;
    n) NAME="${OPTARG}" ;;
    o) OUT_PATH="${OPTARG}" ;;
    d) OUT_DIR="${OPTARG}" ;;
    k) CLASS="${OPTARG}" ;;
    b) EXIT_BEHAVIOR="${OPTARG}" ;;
    s) SHELL_CMD="${OPTARG}" ;;
    h) usage; exit 0 ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage; exit 2 ;;
    :)  echo "Option -$OPTARG requires an argument." >&2; usage; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

# -------- positional arg handling --------
if [[ -z "$OUT_PATH" && $# -ge 1 ]]; then
  if [[ "$1" == */* || "$1" == *.cast ]]; then
    OUT_PATH="$1"
  else
    NAME="$1"
  fi
fi

# -------- sanity --------
[[ "$EXIT_BEHAVIOR" =~ ^(Hold|Close|CloseOnCleanExit)$ ]] || { echo "ERROR: -b must be Hold|Close|CloseOnCleanExit" >&2; exit 2; }
[[ "$ROWS" =~ ^[0-9]+$ && "$ROWS" -gt 0 ]] || { echo "ERROR: invalid ROWS: $ROWS" >&2; exit 2; }
[[ "$COLS" =~ ^[0-9]+$ && "$COLS" -gt 0 ]] || { echo "ERROR: invalid COLS: $COLS" >&2; exit 2; }

# Detect wezterm
if [[ -z "$WEZTERM_BIN" ]]; then
  if command -v wezterm >/dev/null 2>&1; then WEZTERM_BIN="wezterm"
  elif command -v wezterm-gui >/dev/null 2>&1; then WEZTERM_BIN="wezterm-gui"
  else echo "ERROR: wezterm not found (install wezterm or set WEZTERM_BIN)" >&2; exit 127
  fi
fi
command -v "$WEZTERM_BIN" >/dev/null 2>&1 || { echo "ERROR: $WEZTERM_BIN not on PATH" >&2; exit 127; }

: "${CLASS:=CAST-RECORD}"

# Default name (with timestamp) if not using explicit OUT_PATH
if [[ -z "$OUT_PATH" ]]; then
  NAME="${NAME:-demo}-$(date +%Y%m%d-%H%M%S)"
fi

# Final OUT_PATH (build, then absolutize relative paths against caller's CWD)
if [[ -z "$OUT_PATH" ]]; then
  mkdir -p "$OUT_DIR"
  [[ "$NAME" == *.cast ]] && OUT_PATH="${OUT_DIR}/${NAME}" || OUT_PATH="${OUT_DIR}/${NAME}.cast"
fi
if [[ "$OUT_PATH" != /* ]]; then
  OUT_PATH="$(pwd -P)/$OUT_PATH"
  OUT_PATH="$(realpath "$OUT_PATH")"
fi
mkdir -p "$(dirname "$OUT_PATH")"

echo "[cast] size=${COLS}x${ROWS}  cmd=${SHELL_CMD}"
echo "[cast] Now recording: ${OUT_PATH}"

# Float + absolute position on Hyprland if present
if command -v hyprctl >/dev/null 2>&1; then
  hyprctl keyword windowrulev2 "float, class:^${CLASS}$" >/dev/null || true
  hyprctl keyword windowrulev2 "move ${WINDOW_X} ${WINDOW_Y}, class:^${CLASS}$" >/dev/null || true
fi

# Remember caller's CWD so the recorded shell starts there
CALLER_PWD="$(pwd -P)"

# Helper runs *inside* wezterm's shell (no quoting fuss)
HELPER_DIR="$HOME/.cache/cast"
HELPER="$HELPER_DIR/rec.sh"
mkdir -p "$HELPER_DIR"
cat >"$HELPER" <<'REC'
#!/usr/bin/env bash
set -Eeuo pipefail
: "${OUT:?}"; : "${ROWS:=24}"; : "${COLS:=80}"
: "${START_CWD:=}"; : "${RUN_CMD:=bash -i}"

# Start in the caller's working directory if provided
if [[ -n "$START_CWD" && -d "$START_CWD" ]]; then
  cd "$START_CWD" || true
fi

# Ensure the PTY grid asciinema sees matches your requested size
stty rows "$ROWS" cols "$COLS" 2>/dev/null || true

# Run your chosen command *inside* the recording, quietly
exec asciinema rec -q -c "$RUN_CMD" "$OUT"
REC
chmod +x "$HELPER"

# Launch wezterm sized by cells, no decorations, quiet recorder
EGL_LOG_LEVEL=fatal MESA_DEBUG=silent /usr/bin/time -f "[cast] Recorded (%E)" "$WEZTERM_BIN" \
  --config "initial_cols=${COLS}" \
  --config "initial_rows=${ROWS}" \
  --config "exit_behavior=\"${EXIT_BEHAVIOR}\"" \
  --config 'hide_tab_bar_if_only_one_tab=true' \
  --config 'window_decorations="NONE"' \
  --config "font_size=${FONT_SIZE}" \
  --config 'default_cursor_style="SteadyBlock"' \
  start --class "${CLASS}" -- \
  env OUT="$OUT_PATH" ROWS="$ROWS" COLS="$COLS" START_CWD="$CALLER_PWD" RUN_CMD="$SHELL_CMD" \
  bash --noprofile --norc -c "$HELPER"

echo "[cast] Finished recording: ${OUT_PATH}"
