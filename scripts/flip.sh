#!/bin/sh
# scripts/flip.sh — THE CUTOVER.
#
# Usage: sh scripts/flip.sh <old|new|toggle>
#
# Six steps, in this exact order. Steps 1, 3, 4 and 5 each exist because of a
# measured failure, not because of caution:
#
#   1. health-gate BOTH backends   — a stopped backend blocks the flip in BOTH
#                                    directions, and the gate must refuse
#                                    WITHOUT touching the config file
#   2. rewrite one word + diff     — the diff is what the audience watches
#   3. nginx -t                    — catches a typo, and a backend that vanished
#   4. reload + CHECK THE EXIT     — a failed reload leaves the master silently
#                                    serving the PREVIOUS config
#   5. prove it landed             — the running config reporting its own
#                                    selector is the only source that cannot lie
#   6. settle, then EITHER one     — absorbs the measured interleave window.
#      confirming request (forward)  Forward: seeds the projected page's traffic
#      OR the evidence truncation    reading. Reset (`old`, D-36): truncates and
#      (reset) — never both          issues NO request, so the reset cannot flash
#                                    the convergence sequence (deferred D1)
#
# POSIX sh. Deliberately NOT `set -e`: `diff` exits non-zero when it finds a
# difference, which is the expected case here, and every genuine failure path
# below restores state before exiting.

CONF=switch/active-proxy.conf
EVIDENCE=/var/log/demo/access.log
ORACLE=http://localhost:8081/active-proxy

usage() {
	echo "usage: sh scripts/flip.sh <old|new|toggle>" >&2
	exit 2
}

# The selector, read from the one line that is actually configuration. Comments
# are not matched: the file's second line is
#     # Change `old` to `new` to cut over. Nothing else.
# and contains both backend words.
current_backend() {
	sed -n 's/^[[:space:]]*default[[:space:]][[:space:]]*\([A-Za-z0-9_.-][A-Za-z0-9_.-]*\)[[:space:]]*;.*/\1/p' "$CONF" | head -1
}

[ $# -eq 1 ] || usage

test -f "$CONF" || {
	echo "FLIP FAILED: $CONF not found — run this from the repo root." >&2
	exit 1
}

CURRENT=$(current_backend)
[ -n "$CURRENT" ] || {
	echo "FLIP FAILED: no 'default <backend>;' line in $CONF." >&2
	exit 1
}

case "$1" in
old | new) TARGET=$1 ;;
toggle)
	if [ "$CURRENT" = "new" ]; then TARGET=old; else TARGET=new; fi
	;;
*) usage ;;
esac

echo "FLIP: $CURRENT -> $TARGET"

# ---------------------------------------------------------------- 1. the gate
#
# D-35, one tier up. Probe BOTH of the switch's upstreams, not just the target:
# the switch resolves `upstream ... server proxy-old|proxy-new` at config-PARSE
# time and parses both upstream blocks on every reload, so either static proxy
# being down aborts the parse — and a reload whose config fails to load leaves
# the switch running the PREVIOUS configuration. Flipping BACK to old is equally
# blocked when proxy-new is down.
#
# Probing each proxy's :8081/nginx-health from inside the switch container
# exercises the exact path the switch's reload depends on (Docker DNS +
# reachability + the proxy answering) and is immune to `docker compose ps`
# output-format drift. The backends sit one hop further and are gated by the
# static proxies' own healthchecks (RESEARCH Pitfall 2).
#
# Nothing below this point has touched the config file yet. That is deliberate:
# a refusal must leave the repo byte-identical, or the file would claim an
# intent that never took effect.
for _p in proxy-old proxy-new; do
	if ! docker compose exec -T switch curl -fsS --max-time 2 "http://$_p:8081/nginx-health" >/dev/null 2>&1; then
		echo "REFUSING TO FLIP: $_p is not answering :8081/nginx-health."
		echo "  the switch parses BOTH upstream blocks on every reload, so this"
		echo "  would fail in either direction and the running config would"
		echo "  silently stay put. $CONF has NOT been modified."
		echo "  Bring it back:  docker compose up -d --wait $_p"
		exit 1
	fi
done

# ------------------------------------------------------- 2. the one-word edit
BAK=$(mktemp)
cp "$CONF" "$BAK"
sed "s/default [A-Za-z0-9_.-]*;/default $TARGET;/" "$BAK" >"$CONF"

echo
# D-34: the printed diff IS the demo. `diff` exits non-zero on a difference —
# expected here, and it must not abort the script.
diff -u -L "$CONF (before)" -L "$CONF (after)" "$BAK" "$CONF"
echo

# --------------------------------------------------------------- 3. validate
if ! docker compose exec -T switch nginx -t; then
	echo "CONFIG TEST FAILED — restoring $CONF and leaving nginx untouched."
	cp "$BAK" "$CONF"
	rm -f "$BAK"
	exit 1
fi

# ----------------------------------------------------------------- 4. reload
# D-14: a graceful reload, never a container restart. And CHECK THE EXIT CODE —
# nginx writes [emerg] to stderr and exits 1 while continuing to serve the old
# configuration, which on stage is the presenter staring at OLD while saying
# "and now it's new".
if ! docker compose exec -T switch nginx -s reload; then
	echo "RELOAD FAILED — nginx is still running the PREVIOUS config."
	echo "  Restoring $CONF so the repo does not claim a cutover that did not happen."
	cp "$BAK" "$CONF"
	rm -f "$BAK"
	exit 1
fi

# -------------------------------------------------------- 5. prove it landed
# The RUNNING config reporting its own selector, through the unpublished :8081
# listener. Not a request through :9092: that would write a line into the
# projected evidence, and it cannot distinguish "the reload failed" from "the
# reload landed and this request raced the interleave window".
_i=0
_got=
while [ "$_i" -lt 25 ]; do
	_got=$(docker compose exec -T switch curl -sS --max-time 1 "$ORACLE" 2>/dev/null | tr -d '\r\n')
	[ "$_got" = "$TARGET" ] && break
	_i=$((_i + 1))
	sleep 0.2
done
if [ "$_got" != "$TARGET" ]; then
	echo "RELOAD DID NOT TAKE within 5s — the running config still reports '$_got'."
	cp "$BAK" "$CONF"
	rm -f "$BAK"
	exit 1
fi
rm -f "$BAK"

# ------------------------------------------------------ 6. settle and confirm
# Measured interleave windows after the reload command returned were 26 ms,
# 58 ms and 28 ms: for a few tens of milliseconds both worker generations drain
# the same listening socket, so a connection can still be accepted by an old
# worker holding the old config. 200 ms clears every observation with 3x margin,
# and step 5 has already consumed real time.
sleep 0.2
echo

# The two directions diverge here, and the split is structural rather than
# cosmetic (deferred item D1).
#
# FORWARD (`new`, or `old` when it is a genuine cutover rather than a reset):
# one confirming request, whose stated purpose is to seed the projected page's
# traffic reading for the take that is STARTING.
#
# RESET (`old`, D-36): the evidence is truncated and NO confirming request is
# issued. Ordering matters. A confirming request followed by a truncation makes
# the traffic reading genuinely move NEW -> OLD for the few hundred milliseconds
# between the two, and a 1 s poll landing in that window fires the projected
# page's convergence sequence — the money shot, spent on a reset, in front of a
# room. Measured at 1 occurrence in 3 before this change. The page cannot see a
# truncation coming, so no client-side guard can make it deterministic; removing
# the request removes the window itself. The reset direction has nothing to seed
# by definition: it exists to leave the counters, the table, the boundary and
# the since-flip clock all reading zero.
#
# TRUNCATE, never unlink. nginx holds the descriptor with O_APPEND, so after a
# truncation the next write lands at offset 0 with no sparse NUL hole. `rm`
# would leave nginx writing into an unlinked inode while the status page
# correctly reported a missing file.
#
# Issued INTO THE SWITCH CONTAINER: the switch owns the rw evidence mount, the
# status service's mount is read-only by design, and the switch is deliberately
# the tier that writes — and so can truncate — the evidence.
if [ "$TARGET" = "old" ]; then
	docker compose exec -T switch sh -c ": > $EVIDENCE"
	echo "evidence cleared — the next take starts from zero"
	echo "  (no confirming request: the reset direction seeds nothing, and a"
	echo "   request here would flash the convergence sequence on the projector)"
else
	printf 'curl -fsS http://localhost:9092/whoami  ->  '
	curl -fsS http://localhost:9092/whoami
fi
