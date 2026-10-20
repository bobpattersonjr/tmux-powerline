#!/usr/bin/env bash
# shellcheck disable=SC2317
# Entry point for this TPM plugin.

set -o errexit
set -o pipefail

TMUX_POWERLINE_DIR_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TMUX_POWERLINE_DIR_HOME

# Obtain the left/right status length settings by reading the tmux-powerline config.
source "${TMUX_POWERLINE_DIR_HOME}/lib/headers.sh"
tp_process_settings

# Apply default status-format to ensure default single-line status bar is working as
# expected, especially when switching from dual-line status-bar.
tmux set-option -gu status-format

# Configure tmux to use tmux-powerline.
# It's assumed that this will override these setting if already set in tmux.conf, as TPM is recommended to be loaded last in the tmux.conf. Ref: https://github.com/tmux-plugins/tpm
tmux set-option -g status "$TMUX_POWERLINE_STATUS_VISIBILITY"
tmux set-option -g status-interval "$TMUX_POWERLINE_STATUS_INTERVAL"
tmux set-option -g status-justify "$TMUX_POWERLINE_STATUS_JUSTIFICATION"
tmux set-option -g status-style "$TMUX_POWERLINE_STATUS_STYLE"
tmux set-option -g message-style "$TMUX_POWERLINE_STATUS_STYLE"

tmux set-option -g status-left-length "$TMUX_POWERLINE_STATUS_LEFT_LENGTH"
tmux set-option -g status-right-length "$TMUX_POWERLINE_STATUS_RIGHT_LENGTH"

# Rendered at most once per TMUX_POWERLINE_CACHE_TTL and shared by all clients.
tmux set-option -g status-left "#(${TMUX_POWERLINE_DIR_HOME}/powerline-cached.sh left #{q:session_name})"
tmux set-option -g status-right "#(${TMUX_POWERLINE_DIR_HOME}/powerline-cached.sh right #{q:session_name})"

# Formats for the two-line status bar, used both by status=2 and by width-based stacking.
# handle TMUX_POWERLINE_WINDOW_STATUS_LINE=0 and fallback for misconfiguration
window_status_format="${TMUX_POWERLINE_STATUS_FORMAT_WINDOW:-${TMUX_POWERLINE_STATUS_FORMAT_WINDOW_DEFAULT}}"
left_right_status_format="${TMUX_POWERLINE_STATUS_FORMAT_LEFT:-${TMUX_POWERLINE_STATUS_FORMAT_LEFT_DEFAULT}}${TMUX_POWERLINE_STATUS_FORMAT_RIGHT:-${TMUX_POWERLINE_STATUS_FORMAT_RIGHT_DEFAULT}}"
if [ "$TMUX_POWERLINE_WINDOW_STATUS_LINE" != "1" ]; then
	status_format_0="$window_status_format"
	status_format_1="$left_right_status_format"
else
	status_format_0="$left_right_status_format"
	status_format_1="$window_status_format"
fi

if [ "$TMUX_POWERLINE_STATUS_VISIBILITY" = "2" ]; then
	tmux set-option -g status-format[0] "$status_format_0"
	tmux set-option -g status-format[1] "$status_format_1"
fi

# Width-based stacking: hooks call stack_status.sh, which overrides status/status-format
# per session. Start from a clean slate so a reload picks up new formats or a disabled setting.
for stack_hook in client-attached client-resized client-session-changed; do
	tmux set-hook -gu "${stack_hook}[${TMUX_POWERLINE_STACK_HOOK_INDEX}]"
done
tmux list-sessions -F '#{session_id}' -f '#{@tmux_powerline_stacked}' | while read -r stacked_session; do
	tmux set-option -t "$stacked_session" -u status \; \
		set-option -t "$stacked_session" -u status-format \; \
		set-option -t "$stacked_session" -u @tmux_powerline_stacked
done
tmux set-option -gu @tmux_powerline_stack_below_width

if [[ "$TMUX_POWERLINE_STACK_BELOW_WIDTH" =~ ^[0-9]+$ ]]; then
	tmux set-option -g @tmux_powerline_stack_below_width "$TMUX_POWERLINE_STACK_BELOW_WIDTH"
	tmux set-option -g @tmux_powerline_status_format_0 "$status_format_0"
	tmux set-option -g @tmux_powerline_status_format_1 "$status_format_1"
	for stack_hook in client-attached client-resized client-session-changed; do
		tmux set-hook -g "${stack_hook}[${TMUX_POWERLINE_STACK_HOOK_INDEX}]" \
			"run-shell -b \"'${TMUX_POWERLINE_DIR_HOME}/stack_status.sh' '#{session_id}' '#{client_width}'\""
	done
	# Apply to clients that are already attached.
	tmux list-clients -F '#{session_id} #{client_width}' | while read -r client_session client_width; do
		"${TMUX_POWERLINE_DIR_HOME}/stack_status.sh" "$client_session" "$client_width"
	done
elif [ -n "$TMUX_POWERLINE_STACK_BELOW_WIDTH" ]; then
	tmux display-message "tmux-powerline: TMUX_POWERLINE_STACK_BELOW_WIDTH must be a number, got '${TMUX_POWERLINE_STACK_BELOW_WIDTH}'"
fi

# The window formats are static strings (tmux fills in #I, #W, #F itself), so render
# them once here instead of spawning powerline.sh for every window of every client.
tmux set-option -g window-status-current-format "$(TMUX_POWERLINE_SKIP_MUTE_CHECK=1 "${TMUX_POWERLINE_DIR_HOME}/powerline.sh" window-current-format)"
tmux set-option -g window-status-format "$(TMUX_POWERLINE_SKIP_MUTE_CHECK=1 "${TMUX_POWERLINE_DIR_HOME}/powerline.sh" window-format)"
tmux set-option -g window-status-separator "$TMUX_POWERLINE_WINDOW_STATUS_SEPARATOR"

if [ -n "$TMUX_POWERLINE_MUTE_LEFT_KEYBINDING" ]; then
	tmux bind "$TMUX_POWERLINE_MUTE_LEFT_KEYBINDING" run "$TMUX_POWERLINE_DIR_HOME/mute_powerline.sh left"
fi

if [ -n "$TMUX_POWERLINE_MUTE_RIGHT_KEYBINDING" ]; then
	tmux bind "$TMUX_POWERLINE_MUTE_RIGHT_KEYBINDING" run "$TMUX_POWERLINE_DIR_HOME/mute_powerline.sh right"
fi
