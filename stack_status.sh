#!/usr/bin/env bash
# Switch a session between one and two status lines depending on client width.
# Called from tmux hooks installed by main.tmux when TMUX_POWERLINE_STACK_BELOW_WIDTH is set.
#
# Usage: stack_status.sh <session_id> <client_width>
#
# Kept free of the tmux-powerline libs so it stays cheap; main.tmux stores the
# threshold and the two-line status formats in global tmux user options.

session="$1"
width="$2"

threshold=$(tmux show-options -gqv @tmux_powerline_stack_below_width)
[ -n "$threshold" ] && [ -n "$width" ] || exit 0

stacked=$(tmux show-options -t "$session" -qv @tmux_powerline_stacked)

if [ "$width" -lt "$threshold" ]; then
	[ "$stacked" = "1" ] && exit 0
	# Respect a status bar that has been turned off.
	[ "$(tmux display-message -p -t "$session" '#{status}')" = "off" ] && exit 0
	tmux set-option -t "$session" status 2 \; \
		set-option -t "$session" status-format[0] "$(tmux show-options -gqv @tmux_powerline_status_format_0)" \; \
		set-option -t "$session" status-format[1] "$(tmux show-options -gqv @tmux_powerline_status_format_1)" \; \
		set-option -t "$session" @tmux_powerline_stacked 1
else
	[ "$stacked" = "1" ] || exit 0
	# Fall back to the global settings from main.tmux.
	tmux set-option -t "$session" -u status \; \
		set-option -t "$session" -u status-format \; \
		set-option -t "$session" -u @tmux_powerline_stacked
fi
