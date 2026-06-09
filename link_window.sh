#!/usr/bin/env bash
# tmux-link-window: fuzzy-find a window from any other session and link it here

CURRENT_SESSION=$(tmux display-message -p '#S')
TMPFILE=$(mktemp /tmp/tmux-link-window.XXXXXX)

# Build candidate list, one line per window, excluding current session
# Format: "session_name:window_index  [session_name] window_name"
tmux list-windows -a -F '#{session_name}:#{window_index} #{window_name}' \
  | grep "^q_" | column -t > "$TMPFILE.list"

if [[ ! -s "$TMPFILE.list" ]]; then
  tmux display-message "No windows available in other sessions."
  rm -f "$TMPFILE" "$TMPFILE.list"
  exit 0
fi

if ! command -v fzf &>/dev/null; then
  tmux display-message "fzf not found — please install fzf"
  rm -f "$TMPFILE" "$TMPFILE.list"
  exit 1
fi

# Run fzf inside a popup; write selection to temp file (only way to get output back)
tmux popup -E -w 90% -h 80% -T " Link Window " \
  "fzf --layout reverse \
       --prompt='Link window > ' \
       --preview 'tmux capture-pane -ep -t \$(echo {} | awk \"{print \\\$1}\")' \
       --preview-window=right:80%:nowrap \
       < '$TMPFILE.list' > '$TMPFILE'"

# If user cancelled (Esc / q), tmpfile will be empty
if [[ ! -s "$TMPFILE" ]]; then
  rm -f "$TMPFILE" "$TMPFILE.list"
  exit 0
fi

# First field is "session:index"
target=$(awk '{print $1}' "$TMPFILE")
rm -f "$TMPFILE" "$TMPFILE.list"

[[ -z "$target" ]] && exit 0

target_session="${target%%:*}"
target_index="${target##*:}"

if tmux link-window -s "${target_session}:${target_index}" -t "${CURRENT_SESSION}:"; then
  tmux display-message "Linked [${target_session}:${target_index}] into session '${CURRENT_SESSION}'"
else
  tmux display-message "Failed to link window."
fi

