#!/usr/bin/env bash
# Regression tests for main.tmux: bash tests/main_tmux.sh (requires tmux).
# Each case runs main.tmux the way tpm does, via run-shell, on a private tmux server.
set -eu

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
socket="tmux-powerline-test-$$"
cleanup() {
	tmux -L "$socket" kill-server 2>/dev/null || true
	rm -rf "$test_dir"
}
trap cleanup EXIT

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

export TMUX_POWERLINE_CONFIG_FILE="$test_dir/config.sh"
cat >"$TMUX_POWERLINE_CONFIG_FILE" <<'SH'
export TMUX_POWERLINE_THEME="default"
export TMUX_POWERLINE_STACK_BELOW_WIDTH="160"
SH

# Runs main.tmux and records its exit status, since run-shell swallows it.
cat >"$test_dir/run_main.sh" <<SH
#!/usr/bin/env bash
bash '$repo/main.tmux' >'$test_dir/main.log' 2>&1
echo \$? >'$test_dir/main.rc'
SH
chmod +x "$test_dir/run_main.sh"
echo "run-shell '$test_dir/run_main.sh'" >"$test_dir/tmux.conf"

expected_current=$(TMUX_POWERLINE_SKIP_MUTE_CHECK=1 "$repo/powerline.sh" window-current-format)
expected_window=$(TMUX_POWERLINE_SKIP_MUTE_CHECK=1 "$repo/powerline.sh" window-format)
[ -n "$expected_current" ] || fail "powerline.sh rendered an empty window-current-format"

assert_configured() {
	local when="$1" rc
	rc=$(cat "$test_dir/main.rc")
	[ "$rc" = 0 ] || fail "$when: main.tmux exited $rc: $(cat "$test_dir/main.log")"
	[ "$(tmux -L "$socket" show-options -gv window-status-current-format)" = "$expected_current" ] ||
		fail "$when: window-status-current-format was not set"
	[ "$(tmux -L "$socket" show-options -gv window-status-format)" = "$expected_window" ] ||
		fail "$when: window-status-format was not set"
	[ -z "$(tmux -L "$socket" show-options -gv window-status-separator)" ] ||
		fail "$when: window-status-separator was not set"
	tmux -L "$socket" show-hooks -g client-resized | grep -q stack_status.sh ||
		fail "$when: stacking hooks were not installed"
}

# Server start: tpm runs main.tmux from tmux.conf before any session exists, when
# list-clients fails with "no current target". That used to abort main.tmux under
# errexit/pipefail before the window formats were set.
tmux -L "$socket" -f "$test_dir/tmux.conf" new-session -d -s test -x 200 -y 50
for _ in $(seq 50); do
	[ -s "$test_dir/main.rc" ] && break
	sleep 0.1
done
[ -s "$test_dir/main.rc" ] || fail "server start: main.tmux did not finish"
assert_configured "server start"

# Reload (prefix + r) once sessions exist.
rm -f "$test_dir/main.rc"
tmux -L "$socket" run-shell "$test_dir/run_main.sh"
assert_configured "reload"

echo "main.tmux tests passed"
