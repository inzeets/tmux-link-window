#!/usr/bin/env bash
# tmux-link-window: fuzzy-find a window from any other session and link it here

CURRENT_SESSION=$(tmux display-message -p '#S')
TMPFILE=$(mktemp /tmp/tmux-link-window.XXXXXX)

# Build candidate list, one line per window, excluding current session
# Format: "session_name:window_index  [session_name] window_name"
#tmux list-windows -a -F '#{session_name}:#{window_index} #{window_name}' \
tmux list-windows -a -F '#{window_name} #{session_name}:#{window_index}' \
  | grep -v "^${CURRENT_SESSION}:" | column -t > "$TMPFILE.list"

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
tmux popup -E -w 95% -h 90% -T " Link Window " \
  "fzf --layout reverse \
       --prompt='Link window > ' \
       --bind 'ctrl-r:toggle-sort,ctrl-/:toggle-preview,alt-up:preview-up,alt-down:preview-down,ctrl-k:change-preview-window:bottom:85%:nowrap|' \
       --preview 'out=\$(tmux capture-pane -ep -t \$(echo {} | awk \"{print \\\$2}\")); printf \"%s\n\" \"\$out\" | head -n 2; printf \"\033[2m─── %d lines ────────────────────────────────────\033[0m\n\" \$(( \$(printf \"%s\n\" \"\$out\" | wc -l) - 2 )); printf \"%s\n\" \"\$out\" | tail -n +3' \
       --preview-window=~3:follow:right:70%:nowrap \
       < '$TMPFILE.list' > '$TMPFILE'"

#--preview 'out=\$(tmux capture-pane -ep -t \$(echo {} | awk \"{print \\\$2}\")); printf \"%s\n\" \"\$out\" | head -n 3; label=\" \$(( \$(printf \"%s\n\" \"\$out\" | wc -l) - 3 )) lines \"; pad=\$(( (FZF_PREVIEW_COLUMNS - \${#label}) / 2 )); printf \"\033[2m\"; printf \"─%.0s\" \$(seq \$pad); printf \"%s\" \"\$label\"; printf \"─%.0s\" \$(seq \$(( FZF_PREVIEW_COLUMNS - pad - \${#label} )) ); printf \"\033[0m\n\"; printf \"%s\n\" \"\$out\" | tail -n +4' \

# If user cancelled (Esc / q), tmpfile will be empty
if [[ ! -s "$TMPFILE" ]]; then
  rm -f "$TMPFILE" "$TMPFILE.list"
  exit 0
fi

# First field is "session:index"
target=$(awk '{print $2}' "$TMPFILE")
rm -f "$TMPFILE" "$TMPFILE.list"

[[ -z "$target" ]] && exit 0

target_session="${target%%:*}"
target_index="${target##*:}"

if tmux link-window -s "${target_session}:${target_index}" -t "${CURRENT_SESSION}:"; then
  tmux display-message "Linked [${target_session}:${target_index}] into session '${CURRENT_SESSION}'"
else
  tmux display-message "Failed to link window."
fi

