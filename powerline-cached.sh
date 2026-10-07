#!/usr/bin/env bash
# Cheap front-end for `powerline.sh left|right`, meant to be called from tmux #().
#
# tmux runs status-left/right once per attached client every status-interval, and
# a full powerline.sh render sources the whole library, forks dozens of subshells
# and round-trips to the tmux server. With many clients that swamps the CPU.
# The rendered output is client-independent (tmux expands #S etc. afterwards), so
# render it at most once per TTL and let every client read the cached copy.
#
# Usage: powerline-cached.sh <left|right> <session_name>
#   session_name is passed in via #{session_name} so the mute check does not need
#   to ask the tmux server.

side="$1"
session="$2"

dir_home="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Must match TMUX_POWERLINE_DIR_TEMPORARY in config/paths.sh.
dir_tmp="${TMPDIR:-/tmp/tmux-powerline_${USER}}"
dir_tmp="${dir_tmp%/}/tmux-powerline"
dir_cache="${dir_tmp}/tmux-powerline-cache"
cache="${dir_cache}/${side}"
lock="${dir_cache}/${side}.lock"
ttl="${TMUX_POWERLINE_CACHE_TTL:-60}"

# Muting is per session; same file lib/muting.sh uses.
[ -e "${dir_tmp}/mute_${session}_${side}" ] && exit 0

[ -d "$dir_cache" ] || mkdir -p "$dir_cache"

now=$(date +%s)
mtime=$(stat -f %m "$cache" 2>/dev/null || stat -c %Y "$cache" 2>/dev/null || echo 0)

if [ $((now - mtime)) -lt "$ttl" ]; then
	cat "$cache"
	exit 0
fi

# Clear a lock left behind by a render that died.
if [ -d "$lock" ]; then
	lock_mtime=$(stat -f %m "$lock" 2>/dev/null || stat -c %Y "$lock" 2>/dev/null || echo 0)
	[ $((now - lock_mtime)) -gt 120 ] && rmdir "$lock" 2>/dev/null
fi

if mkdir "$lock" 2>/dev/null; then
	trap 'rmdir "$lock" 2>/dev/null' EXIT
	tmp="${cache}.$$"
	TMUX_POWERLINE_SKIP_MUTE_CHECK=1 "${dir_home}/powerline.sh" "$side" >"$tmp" && mv "$tmp" "$cache"
	rm -f "$tmp"
	cat "$cache" 2>/dev/null
elif [ -f "$cache" ]; then
	# Another client is rendering; a slightly stale bar beats a second render.
	cat "$cache"
else
	# First render ever and someone else holds the lock: wait briefly for it.
	for _ in 1 2 3 4 5 6 7 8 9 10; do
		sleep 0.5
		[ -f "$cache" ] && cat "$cache" && break
	done
fi
exit 0
