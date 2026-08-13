## Install
`set -g @plugin 'inzeets/tmux-link-window'`

## Default keybinding
`prefix+W`

## Keys in the picker
- `enter` - link the picked window here (link mode) / swap or move it (other modes)
- `M-j` - toggle link list (other sessions only) / join list (all but current window)
- `M-w` - toggle swap mode: enter swaps the pick with the current window
- `M-b` / `M-a` - toggle move mode: enter moves the pick to before / after the current window
- `M-v` / `M-s` - join the pick as a vertical / horizontal split (instant, vim sense)

## Options
`@link_window_key` - to set custom key
