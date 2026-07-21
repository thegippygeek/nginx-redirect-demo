#!/bin/sh
# scripts/fix-hostkeys.sh — THE FIX: give server-new server-old's identity.
#
# Usage: sh scripts/fix-hostkeys.sh          (no arguments — see below)
#
# This is what a real migration does. The client is never touched: the whole of
# D-49 is that the answer scales to a fleet, and editing every client's trust
# record does not. One server inherits the other's host keys, and every client
# in the world carries on without noticing.
#
# Five steps, in this exact order. Each exists because of a measurement:
#
#   1. gate BOTH backends       — a stopped container turns every step below
#                                 into a confusing half-applied state
#   2. announce                 — this runs on a projector and the room reads it
#   3. transfer, as a STREAM    — six files out of one container and into the
#                                 other, with no host path in between
#   4. SIGNAL THE DAEMON        — THIS is the fix (D-59). Step 3 alone is a
#                                 measured silent no-op
#   5. prove by FINGERPRINT     — not by listing files. A transfer can land and
#                                 the daemon still present the old key
#
# WHY THE SIGNAL IS NOT OPTIONAL (D-59): sshd reads its host keys ONCE, at
# startup, and holds them in memory. Research measured a connection made after
# a verified-successful transfer still failing on the OLD fingerprint. A version
# of this script that stops at the copy is not acceptable, and narrating this
# step as "we copied the keys across" is equally wrong. Say: "we gave the new
# server the old server's identity, and told sshd to pick it up."
#
# WHY A HANGUP AND NOT A RESTART: a hangup makes sshd re-exec itself, keeping
# its process id (measured: 16 before, 16 after), so supervisord never notices
# and in-flight sessions are undisturbed. Recreating the container would
# regenerate the very keys just installed — backend/entrypoint.sh runs
# ssh-keygen -A at every start — and can move the container's address out from
# under nginx, which resolved its upstreams at config-parse time.
#
# NO ARGUMENTS, deliberately (T-04-01). A "which server" parameter on a command
# that rewrites host key material is a foot-gun with no upside; this demo has
# exactly one direction. Any argument is a usage error.
#
# NOTES FOR THE READER ARRIVING COLD:
#
#   - The transferred .pub files keep their original comment field, which still
#     names root@server-old. That is cosmetic — the comment field has no
#     protocol effect whatsoever — and it must be NARRATED, never "fixed". It is
#     the most vivid evidence available that the new server is wearing the old
#     server's identity.
#   - The effect of this script survives a container restart. The entrypoint's
#     ssh-keygen -A only creates keys that are MISSING, so a restart finds the
#     transferred keys already in place and leaves them alone.
#   - scripts/rearm.sh is the exact reverse of this script, and puts the gotcha
#     back in about a second.
#
# POSIX sh. Deliberately NOT `set -e`, matching scripts/flip.sh: every failure
# path below reports in the repo's own register and chooses its own exit, and a
# bare abort mid-transfer would leave the presenter with no idea which step
# stopped.

SRC=server-old
DST=server-new
KEYDIR=/etc/ssh
PUBKEY=/etc/ssh/ssh_host_ed25519_key.pub

usage() {
	echo "usage: sh scripts/fix-hostkeys.sh        (takes no arguments)" >&2
	exit 2
}

[ $# -eq 0 ] || usage

# Read the ed25519 fingerprint a backend is presenting. Field 2 of ssh-keygen
# -l is the SHA256:… fingerprint itself; field 3 is the comment, which is
# exactly what this fix makes misleading, so it is deliberately not compared.
fingerprint() {
	docker compose exec -T "$1" ssh-keygen -lf "$PUBKEY" 2>/dev/null | awk '{print $2}'
}

# ---------------------------------------------------------------- 1. the gate
#
# Same shape as flip.sh's gate, and for the same reason: refuse BEFORE changing
# anything, so a refusal leaves the rig exactly as it was found.
for _b in "$SRC" "$DST"; do
	if ! docker compose exec -T "$_b" true >/dev/null 2>&1; then
		echo "REFUSING TO FIX: $_b is not running." >&2
		echo "  Nothing has been changed. Bring it back:" >&2
		echo "    docker compose up -d --wait $_b" >&2
		exit 1
	fi
done

# --------------------------------------------------------------- 2. announce
echo "FIX: transferring $SRC's host keys to $DST"

# --------------------------------------------------------------- 3. transfer
#
# SIX files, not three. sshd offers ed25519, rsa and ecdsa, and a client that
# has recorded more than one of them objects to whichever gets negotiated;
# leaving even one pair behind makes the fix intermittent.
#
# A STREAM between two container execs, never a host path. The project forbids
# key material on the host filesystem (T-04-02), and tar carries mode and
# ownership through, so no permission fix follows.
#
# This pipe is safe, and the reason is worth stating because Phase 3 carries a
# prohibition that looks like it applies: that prohibition is specifically about
# putting an `ssh` invocation on the LEFT of a pipe, because a pipeline reports
# only the LAST command's status and an ssh failure would vanish. Here the last
# command is the receiving tar, whose status is exactly the one wanted.
echo "  streaming six host-key files ($KEYDIR/ssh_host_*)"
if ! docker compose exec -T "$SRC" tar -C "$KEYDIR" -cf - \
	ssh_host_ed25519_key ssh_host_ed25519_key.pub \
	ssh_host_rsa_key ssh_host_rsa_key.pub \
	ssh_host_ecdsa_key ssh_host_ecdsa_key.pub |
	docker compose exec -T "$DST" tar -C "$KEYDIR" -xf -; then
	echo "FIX FAILED: the host-key transfer did not complete." >&2
	echo "  $DST may be half-updated — run it again, or 'make rearm' to reset." >&2
	exit 1
fi

# ----------------------------------------------------------------- 4. signal
#
# The fix itself. See the header: without this the transfer is inert.
echo "  telling sshd on $DST to load them (SIGHUP, pid preserved)"
if ! docker compose exec -T "$DST" sh -c 'kill -HUP $(cat /run/sshd.pid)'; then
	echo "FIX FAILED: could not signal sshd on $DST." >&2
	echo "  The key files were transferred but the running daemon is STILL" >&2
	echo "  presenting its old identity. Copying is not the fix." >&2
	exit 1
fi

# ------------------------------------------------------------------ 5. prove
#
# By FINGERPRINT EQUALITY, never by a file listing. Both halves of this fix can
# report success while the daemon still presents the old key, which is the exact
# failure mode T-04-04 exists to catch, so the proof reads what is presented.
_src_fp=$(fingerprint "$SRC")
_dst_fp=$(fingerprint "$DST")

if [ -z "$_src_fp" ] || [ -z "$_dst_fp" ]; then
	echo "FIX FAILED: could not read an ed25519 fingerprint from both servers." >&2
	exit 1
fi

if [ "$_src_fp" != "$_dst_fp" ]; then
	echo "FIX FAILED: $DST is still presenting a DIFFERENT identity." >&2
	echo "  $SRC  $_src_fp" >&2
	echo "  $DST  $_dst_fp" >&2
	exit 1
fi

# ----------------------------------------------------------------- 6. report
echo "  $_src_fp  (ED25519, now presented by BOTH servers)"
echo "done — $DST is wearing $SRC's cryptographic identity."
echo "  Its .pub comment still says server-old. That is cosmetic, it has no"
echo "  protocol effect, and it is the best evidence in the room."
