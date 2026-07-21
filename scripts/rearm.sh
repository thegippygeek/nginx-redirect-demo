#!/bin/sh
# scripts/rearm.sh — PUT THE GOTCHA BACK, in about a second.
#
# Usage: sh scripts/rearm.sh          (no arguments — see below)
#
# The exact reverse of scripts/fix-hostkeys.sh. It gives server-new a fresh
# identity of its own again and forgets what the client had learned, so the
# whole host-key narrative can be run a second time from the top.
#
# THE FAST PATH, NOT THE HEADLINE. `make reset` is the documented re-arm (D-51)
# and stays that way: it tears the rig down, regenerates BOTH backends' keys,
# rebuilds and restores the selector. Research measured it at 16.5 s. This
# script reaches the same armed state in about 1 s with no rebuild, which is
# what a presenter doing three takes in a row actually wants — and what the
# smoke suite needs, since it cannot call a full teardown from inside itself.
#
# Six steps:
#
#   1. gate                     — refuse before changing anything
#   2. announce
#   3. DELETE, then regenerate  — in that order, see below
#   4. signal the daemon        — same reason as the fix: keys live in memory
#   5. clear the client's trust record
#   6. prove the fingerprints now DIFFER
#
# WHY THE DELETION IS LOAD-BEARING: backend/entrypoint.sh's `ssh-keygen -A` is
# a GAP-FILLER — it creates only keys that are MISSING. Run against a server
# still holding the transferred keys it is a silent no-op, and the rig would
# look re-armed while still being fixed. That is the failure this ordering
# exists to prevent, and step 6 exists to catch.
#
# WHY IN PLACE, AND NEVER A CONTAINER RECREATE: nginx resolves
# `upstream ... server <name>` when it PARSES its configuration, and this rig
# deliberately declares no runtime resolver. A recreated backend can therefore
# leave the proxy holding an address that no longer answers — and research saw
# the address happen to be reused, which is the worst kind of hazard: it works
# in rehearsal and fails on stage. If a recreate is ever unavoidable it must be
# followed by `docker compose exec proxy nginx -s reload`.
#
# WHY NOTHING HERE INTRODUCES STORAGE FOR THE TRUST RECORD (D-48 as corrected
# by research): the client's record is only ever DELETED here, never authored.
# It lives in the client container's writable layer, and that is precisely what
# keeps its lifetime in step with the backends' key lifetime. A named volume
# would survive `docker compose down` and make the gotcha fire BEFORE the flip,
# killing the demo; a bind mount would defeat `make reset` and write key-adjacent
# state to the host. compose.yaml is not touched by this phase.
#
# WHY THE FAILURE IS NEVER SYNTHESISED (T-04-06): this regenerates the SERVER's
# real key material. Nothing anywhere fabricates a trust record, fakes a
# fingerprint, or prints a warning the client did not itself emit. A demo that
# stages its own evidence proves nothing.
#
# NO ARGUMENTS, deliberately (T-04-01): the first thing this does is delete host
# keys, and a "which server" parameter on that is a foot-gun with no upside.
#
# POSIX sh. Deliberately NOT `set -e`, matching scripts/flip.sh.

TARGET=server-new
PEER=server-old
CLIENT=client
KEYGLOB=/etc/ssh/ssh_host_*
PUBKEY=/etc/ssh/ssh_host_ed25519_key.pub
KNOWNGLOB=/root/.ssh/known_hosts*

usage() {
	echo "usage: sh scripts/rearm.sh        (takes no arguments)" >&2
	exit 2
}

[ $# -eq 0 ] || usage

fingerprint() {
	docker compose exec -T "$1" ssh-keygen -lf "$PUBKEY" 2>/dev/null | awk '{print $2}'
}

# ---------------------------------------------------------------- 1. the gate
for _c in "$PEER" "$TARGET" "$CLIENT"; do
	if ! docker compose exec -T "$_c" true >/dev/null 2>&1; then
		echo "REFUSING TO RE-ARM: $_c is not running." >&2
		echo "  Nothing has been changed. Bring it back:" >&2
		echo "    docker compose up -d --wait $_c" >&2
		exit 1
	fi
done

# --------------------------------------------------------------- 2. announce
echo "RE-ARM: giving $TARGET a fresh identity and clearing the client's memory"

# ------------------------------------------------- 3. delete, THEN regenerate
#
# The order is the whole point — see the header. `ssh-keygen -A` alone is a
# measured no-op while the transferred keys are still on disk.
echo "  regenerating $TARGET's host keys (delete first, then ssh-keygen -A)"
if ! docker compose exec -T "$TARGET" sh -c "rm -f $KEYGLOB && ssh-keygen -A >/dev/null"; then
	echo "RE-ARM FAILED: could not regenerate host keys on $TARGET." >&2
	exit 1
fi

# ----------------------------------------------------------------- 4. signal
#
# Same reason as the fix: sshd loaded its keys at startup and holds them in
# memory, so without this it would carry on presenting the identity that was
# just deleted from disk. Hangup, never a restart — the pid is preserved and
# supervisord is left undisturbed.
echo "  telling sshd on $TARGET to load them (SIGHUP, pid preserved)"
if ! docker compose exec -T "$TARGET" sh -c 'kill -HUP $(cat /run/sshd.pid)'; then
	echo "RE-ARM FAILED: could not signal sshd on $TARGET." >&2
	exit 1
fi

# ------------------------------------------- 5. clear the client's trust record
#
# The record AND any backup of it: a successful connection can leave a .old
# sibling behind, and a stale one would make the next priming beat ambiguous.
#
# /root/.ssh/config is deliberately LEFT ALONE. It is what points ssh at the
# demo keypair, which is what keeps the presenter's on-stage command free of an
# -i flag, and Phase 3's assertions depend on it.
echo "  clearing the client's trust record (leaving its identity config alone)"
if ! docker compose exec -T "$CLIENT" sh -c "rm -f $KNOWNGLOB"; then
	echo "RE-ARM FAILED: could not clear the client's trust record." >&2
	exit 1
fi

# ------------------------------------------------------------------ 6. prove
#
# The fingerprints must now DIFFER. A re-arm that silently did nothing is the
# exact failure mode this step exists to catch — see the deletion note above.
_peer_fp=$(fingerprint "$PEER")
_target_fp=$(fingerprint "$TARGET")

if [ -z "$_peer_fp" ] || [ -z "$_target_fp" ]; then
	echo "RE-ARM FAILED: could not read an ed25519 fingerprint from both servers." >&2
	exit 1
fi

if [ "$_peer_fp" = "$_target_fp" ]; then
	echo "RE-ARM FAILED: both servers still present the SAME identity." >&2
	echo "  $_peer_fp" >&2
	echo "  The gotcha is NOT armed. Try 'make reset' for a full rebuild." >&2
	exit 1
fi

# ----------------------------------------------------------------- 7. report
echo "  $PEER  $_peer_fp"
echo "  $TARGET  $_target_fp"
echo "armed — the two servers present different identities again."
echo "  Prime the client on the CURRENT backend before flipping, or the"
echo "  gotcha has nothing to contradict."
