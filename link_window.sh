#!/usr/bin/env bash
# tmux-link-window: fuzzy-find a window from any other session and link it here
# Enter = link the window; alt-v / alt-s = join its pane into a vertical /
# horizontal split (vim :vs / :sp sense) of the pane the picker was opened from.
# alt-j toggles the list between link mode (other sessions only) and join mode
# (every window except the current one - joins work within the session too).
# alt-w toggles swap mode (same candidates as join): enter swaps the picked
# window with the current one (swap-window - the pick lands at this index).
# alt-b / alt-a toggle move mode (same candidates as join): enter MOVES the
# picked window to the index before / after the current window (move-window -
# cross-session picks leave their session). Pressing the key again returns to
# link mode.

CURRENT_SESSION=$(tmux display-message -p '#S')
ORIG_PANE=$(tmux display-message -p '#{pane_id}')
CURRENT_WINDOW=$(tmux display-message -p '#{window_id}')
TMPFILE=$(mktemp /tmp/tmux-link-window.XXXXXX)

# Build two candidate lists, one line per window:
#   .link - excludes the current session (link-window candidates)
#   .join - excludes only the current window (join-pane candidates)
# Display: "window_name  location  [~origin]  session:index(hidden target, last field)"
#   main:N        - window N of the main (root) session
#   pop(name:N):M - window M of the popup belonging to main window name:N
#   ~...          - where a linked window was born, when != listed session
MAIN_SESSION=$(tmux list-sessions -F '#{session_name}' | grep -v '^popup/' | head -1)
{
  tmux list-windows -t "$MAIN_SESSION" -F $'MAP\t#{window_id}\t#{window_name}:#{window_index}'
  tmux list-windows -a -F $'WIN\t#{session_name}\t#{window_index}\t#{window_name}\t#{@born}\t#{@icon}\t#{window_id}'
} | awk -F'\t' -v cur="$CURRENT_SESSION" -v main="$MAIN_SESSION" -v curwin="$CURRENT_WINDOW" \
    -v linkf="$TMPFILE.linkraw" -v joinf="$TMPFILE.joinraw" \
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
  {
    born = ($5 != "" && $5 != $2) ? "~" pretty($5) : ""
    line = iconized($4, $6) "\t" pretty($2) ":" $3 "\t" born "\t" $2 ":" $3
    if ($2 != cur)    print line > linkf
    if ($7 != curwin) print line > joinf
  }'
touch "$TMPFILE.linkraw" "$TMPFILE.joinraw"
column -t -s $'\t' < "$TMPFILE.linkraw" > "$TMPFILE.link"
column -t -s $'\t' < "$TMPFILE.joinraw" > "$TMPFILE.join"
rm -f "$TMPFILE.linkraw" "$TMPFILE.joinraw"

cleanup() { rm -f "$TMPFILE" "$TMPFILE.link" "$TMPFILE.join" "$TMPFILE.mode"; }

if [[ ! -s "$TMPFILE.link" && ! -s "$TMPFILE.join" ]]; then
  tmux display-message "No windows available."
  cleanup
  exit 0
fi

if ! command -v fzf &>/dev/null; then
  tmux display-message "fzf not found — please install fzf"
  cleanup
  exit 1
fi

# Start in link mode; fall back to join mode when no other session exists.
# $TMPFILE.mode tracks the active mode across fzf toggles - the enter action
# after fzf exits depends on it (link vs swap).
if [[ -s "$TMPFILE.link" ]]; then
  START_LIST="$TMPFILE.link"; START_PROMPT='Link window > '
  echo link > "$TMPFILE.mode"
else
  START_LIST="$TMPFILE.join"; START_PROMPT='Join window > '
  echo join > "$TMPFILE.mode"
fi

# Run fzf inside a popup; write selection to temp file (only way to get output back)
tmux popup -E -w 95% -h 90% -T " Link Window " \
  "fzf --layout reverse \
       --prompt='$START_PROMPT' \
       --expect=alt-v,alt-s \
       --header='enter: link window   M-j: link/join list   M-w: swap list   M-b/M-a: move before/after list   M-v: vsplit join   M-s: split join' \
       --bind 'alt-j:transform{case \$FZF_PROMPT in Join*) echo \"reload(cat $TMPFILE.link)+change-prompt(Link window > )+execute-silent(echo link > $TMPFILE.mode)\";; *) echo \"reload(cat $TMPFILE.join)+change-prompt(Join window > )+execute-silent(echo join > $TMPFILE.mode)\";; esac}' \
       --bind 'alt-w:transform{case \$FZF_PROMPT in Swap*) echo \"reload(cat $TMPFILE.link)+change-prompt(Link window > )+execute-silent(echo link > $TMPFILE.mode)\";; *) echo \"reload(cat $TMPFILE.join)+change-prompt(Swap window > )+execute-silent(echo swap > $TMPFILE.mode)\";; esac}' \
       --bind 'alt-b:transform{case \$FZF_PROMPT in Move-before*) echo \"reload(cat $TMPFILE.link)+change-prompt(Link window > )+execute-silent(echo link > $TMPFILE.mode)\";; *) echo \"reload(cat $TMPFILE.join)+change-prompt(Move-before > )+execute-silent(echo move-before > $TMPFILE.mode)\";; esac}' \
       --bind 'alt-a:transform{case \$FZF_PROMPT in Move-after*) echo \"reload(cat $TMPFILE.link)+change-prompt(Link window > )+execute-silent(echo link > $TMPFILE.mode)\";; *) echo \"reload(cat $TMPFILE.join)+change-prompt(Move-after > )+execute-silent(echo move-after > $TMPFILE.mode)\";; esac}' \
       --bind 'ctrl-r:toggle-sort,ctrl-/:toggle-preview,alt-up:preview-up,alt-down:preview-down,ctrl-k:change-preview-window:bottom:85%:nowrap|' \
       --preview 'out=\$(tmux capture-pane -ep -t \$(echo {} | awk \"{print \\\$NF}\")); printf \"%s\n\" \"\$out\" | head -n 2; printf \"\033[2m─── %d lines ────────────────────────────────────\033[0m\n\" \$(( \$(printf \"%s\n\" \"\$out\" | wc -l) - 2 )); printf \"%s\n\" \"\$out\" | tail -n +3' \
       --preview-window=~3:follow:right:70%:nowrap \
       < '$START_LIST' > '$TMPFILE'"

#--preview 'out=\$(tmux capture-pane -ep -t \$(echo {} | awk \"{print \\\$2}\")); printf \"%s\n\" \"\$out\" | head -n 3; label=\" \$(( \$(printf \"%s\n\" \"\$out\" | wc -l) - 3 )) lines \"; pad=\$(( (FZF_PREVIEW_COLUMNS - \${#label}) / 2 )); printf \"\033[2m\"; printf \"─%.0s\" \$(seq \$pad); printf \"%s\" \"\$label\"; printf \"─%.0s\" \$(seq \$(( FZF_PREVIEW_COLUMNS - pad - \${#label} )) ); printf \"\033[0m\n\"; printf \"%s\n\" \"\$out\" | tail -n +4' \

# If user cancelled (Esc / q), tmpfile will be empty
if [[ ! -s "$TMPFILE" ]]; then
  cleanup
  exit 0
fi

# With --expect: line 1 = key pressed ("" for enter), line 2 = selection.
# Last field of the selection is "session:index".
key=$(sed -n '1p' "$TMPFILE")
target=$(sed -n '2p' "$TMPFILE" | awk '{print $NF}')
mode=$(cat "$TMPFILE.mode" 2>/dev/null)
cleanup

[[ -z "$target" ]] && exit 0

target_session="${target%%:*}"
target_index="${target##*:}"

case "$key" in
  alt-v|alt-s)
    # vim sense: alt-v = side-by-side (tmux -h), alt-s = stacked (tmux -v)
    if [[ "$key" == alt-v ]]; then dir=-h; label=vertical; else dir=-v; label=horizontal; fi
    if tmux join-pane "$dir" -s "${target_session}:${target_index}" -t "$ORIG_PANE"; then
      tmux display-message "Joined [${target_session}:${target_index}] as a $label split"
    else
      tmux display-message "Failed to join window."
    fi
    ;;
  *)
    if [[ "$mode" == swap ]]; then
      if tmux swap-window -s "${target_session}:${target_index}" -t "$CURRENT_WINDOW"; then
        tmux display-message "Swapped [${target_session}:${target_index}] with the current window"
      else
        tmux display-message "Failed to swap window."
      fi
    elif [[ "$mode" == move-before || "$mode" == move-after ]]; then
      if [[ "$mode" == move-before ]]; then flag=-b; where=before; else flag=-a; where=after; fi
      # target session:window-id pins the placement to THIS session's winlink
      # (a bare window id is ambiguous when the current window is linked twice)
      if tmux move-window "$flag" -s "${target_session}:${target_index}" -t "${CURRENT_SESSION}:${CURRENT_WINDOW}"; then
        tmux display-message "Moved [${target_session}:${target_index}] $where the current window"
      else
        tmux display-message "Failed to move window."
      fi
    elif [[ "$target_session" == "$CURRENT_SESSION" ]]; then
      tmux display-message "Window is already in this session - use M-v/M-s to join it as a split."
    elif tmux link-window -s "${target_session}:${target_index}" -t "${CURRENT_SESSION}:"; then
      tmux display-message "Linked [${target_session}:${target_index}] into session '${CURRENT_SESSION}'"
    else
      tmux display-message "Failed to link window."
    fi
    ;;
esac

