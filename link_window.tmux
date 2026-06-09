#!/usr/bin/env bash
# tmux-link-window plugin entry point

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default key binding (override with @link_window_key in tmux.conf)
link_key=$(tmux show-option -gv @link_window_key 2>/dev/null || echo "W")

tmux bind-key "$link_key" run-shell "$CURRENT_DIR/link_window.sh"

