#!/usr/bin/env bash
# tmux-link-window: fuzzy-find a window from any other session and link it here

CURRENT_SESSION=$(tmux display-message -p '#S')
TMPFILE=$(mktemp /tmp/tmux-link-window.XXXXXX)

# Build candidate list, one line per window, excluding current session.
# Display: "window_name  location  [~origin]  session:index(hidden target, last field)"
#   main:N        - window N of the main (root) session
#   pop(name:N):M - window M of the popup belonging to main window name:N
#   ~...          - where a linked window was born, when != listed session
MAIN_SESSION=$(tmux list-sessions -F '#{session_name}' | grep -v '^popup/' | head -1)
{
  tmux list-windows -t "$MAIN_SESSION" -F $'MAP\t#{window_id}\t#{window_name}:#{window_index}'
  tmux list-windows -a -F $'WIN\t#{session_name}\t#{window_index}\t#{window_name}\t#{@born}\t#{@icon}'
} | awk -F'\t' -v cur="$CURRENT_SESSION" -v main="$MAIN_SESSION" \
    -v iconmap="$(tmux show -gv @icon_map 2>/dev/null)" '
  function pretty(sess,   id) {                # session name -> friendly location
    if (sess == main) return "main"
    if (sess ~ /^popup\//) { id = substr(sess, 7); return "pop(" (id in map ? map[id] : id) ")" }
    return sess
  }
  # same icon scheme as the status bar: @icon wins, else prefix -> glyph
  # from the shared @icon_map ("prefix:icon" pairs, set in .tmux.conf),
  # and the prefix is display-stripped
  BEGIN {
    nmap = split(iconmap, _pairs, " ")
    for (k = 1; k <= nmap; k++) {
      split(_pairs[k], _kv, ":"); mpre[k] = _kv[1]; mico[k] = _kv[2]
    }
  }
  function iconized(name, ic,   k) {
    for (k = 1; k <= nmap; k++)
      if (index(name, mpre[k]) == 1) {
        if (ic == "") ic = mico[k]
        name = substr(name, length(mpre[k]) + 1)
        break
      }
    return ic name
  }
  $1 == "MAP" { map[$2] = $3; next }
  $2 == cur   { next }
  {
    born = ($5 != "" && $5 != $2) ? "~" pretty($5) : ""
    print iconized($4, $6) "\t" pretty($2) ":" $3 "\t" born "\t" $2 ":" $3
  }' | column -t -s $'\t' > "$TMPFILE.list"

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
       --preview 'out=\$(tmux capture-pane -ep -t \$(echo {} | awk \"{print \\\$NF}\")); printf \"%s\n\" \"\$out\" | head -n 2; printf \"\033[2m─── %d lines ────────────────────────────────────\033[0m\n\" \$(( \$(printf \"%s\n\" \"\$out\" | wc -l) - 2 )); printf \"%s\n\" \"\$out\" | tail -n +3' \
       --preview-window=~3:follow:right:70%:nowrap \
       < '$TMPFILE.list' > '$TMPFILE'"

#--preview 'out=\$(tmux capture-pane -ep -t \$(echo {} | awk \"{print \\\$2}\")); printf \"%s\n\" \"\$out\" | head -n 3; label=\" \$(( \$(printf \"%s\n\" \"\$out\" | wc -l) - 3 )) lines \"; pad=\$(( (FZF_PREVIEW_COLUMNS - \${#label}) / 2 )); printf \"\033[2m\"; printf \"─%.0s\" \$(seq \$pad); printf \"%s\" \"\$label\"; printf \"─%.0s\" \$(seq \$(( FZF_PREVIEW_COLUMNS - pad - \${#label} )) ); printf \"\033[0m\n\"; printf \"%s\n\" \"\$out\" | tail -n +4' \

# If user cancelled (Esc / q), tmpfile will be empty
if [[ ! -s "$TMPFILE" ]]; then
  rm -f "$TMPFILE" "$TMPFILE.list"
  exit 0
fi

# Last field is "session:index"
target=$(awk '{print $NF}' "$TMPFILE")
rm -f "$TMPFILE" "$TMPFILE.list"

[[ -z "$target" ]] && exit 0

target_session="${target%%:*}"
target_index="${target##*:}"

if tmux link-window -s "${target_session}:${target_index}" -t "${CURRENT_SESSION}:"; then
  tmux display-message "Linked [${target_session}:${target_index}] into session '${CURRENT_SESSION}'"
else
  tmux display-message "Failed to link window."
fi

