#!/bin/sh
# scripts/verify.sh — DID THE CUTOVER LAND, ON BOTH PROTOCOLS?
#
# Usage: sh scripts/verify.sh <old|new>        (or: make verify EXPECT=new)
#
# One command that issues an HTTP request AND an SSH connection, reports which
# backend answered EACH on its own labelled line, and can say no.
#
# Exit-code vocabulary — four distinct answers, because on stage they mean four
# different things and must never be confused with one another:
#
#   0  both protocols agree with each other AND match the expectation
#   1  a reading disagrees with the expectation, or a probe could not be taken
#   2  usage — the command was typed wrong. Deliberately NOT 1: a fumbled
#      invocation must never be readable as a failed cutover.
#   3  the two protocols disagree with EACH OTHER (D-45). Its own code and its
#      own words, because "HTTP on NEW while SSH is still on OLD" is the
#      interesting failure — reporting it as a plain mismatch would throw away
#      the one piece of information the presenter actually needs.
#
# POSIX sh. Deliberately NOT `set -e`: BOTH protocols are reported on every run,
# in a fixed order, in every outcome. Aborting after the first failure would
# leave the presenter guessing which of the two readings is missing.
#
# TEST SEAM, not a presenter option: VERIFY_SSH_HOST overrides the SSH target,
# which defaults to the proxied demo hostname. scripts/smoke.sh points it at a
# named backend while the selector says the other one, which produces a GENUINE
# disagreement and so proves the exit-3 branch is reachable rather than merely
# present in this file. It is not documented in the README and not surfaced by
# the Make target.

HTTP_URL=http://localhost:9092/whoami
SSH_TARGET=${VERIFY_SSH_HOST:-app.demo.test}
SSH_USER=demo

# The ssh option set, each entry with the measurement that put it here.
#
#   BatchMode=yes    kills every interactive prompt. Without it a missing key
#                    falls back to a password prompt and blocks forever.
#   ConnectTimeout=5 bounds the TCP connect ONLY — not the banner exchange and
#                    not authentication. That is why the invocation below also
#                    carries an EXTERNAL timeout.
#
# The two host-key options are DEMO-ONLY and MUST NOT be copied into anything
# real. They are here for one specific reason: phase 4 deliberately stages a
# host-key mismatch between the two backends, and without them this routing
# check would start failing for the wrong reason the moment that lands — a
# host-key error reported as a routing error. Nothing else in this repository
# relaxes host-key checking; the client's own ssh config sets no such option,
# because that default behaviour is phase 4's raw material.
#
# Two options are deliberately ABSENT, and each absence is load-bearing:
#   - Any quiet or log-level-lowering option. Each was measured suppressing the
#     pre-auth banner ENTIRELY, turning the capture into the empty string and
#     this reading into a blind one.
#   - Any forced-pty option. The banner needs no pty, and a forced pty with no
#     stdin was measured hanging indefinitely.
VERIFY_SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

usage() {
	echo "usage: sh scripts/verify.sh <old|new>" >&2
	exit 2
}

# The identity both protocols render, derived from the one capture handed in.
# Anchored whole-line, the same way section_backends anchors /whoami, so a
# stream naming BOTH words cannot satisfy two branches.
observed_label() {
	if printf '%s\n' "$1" | grep -qxE 'OLD server-old'; then
		echo OLD
	elif printf '%s\n' "$1" | grep -qxE 'NEW server-new'; then
		echo NEW
	else
		echo UNREADABLE
	fi
}

# The corroborating reading: the remote command's OWN stdout. The banner is the
# contractual claim (the backend asserting its identity); this proves a shell
# really ran there.
observed_hostname() {
	if printf '%s\n' "$1" | grep -qxE 'server-old'; then
		echo server-old
	elif printf '%s\n' "$1" | grep -qxE 'server-new'; then
		echo server-new
	else
		echo -
	fi
}

[ $# -eq 1 ] || usage
case "$1" in
old) EXPECT_LABEL=OLD ;;
new) EXPECT_LABEL=NEW ;;
*) usage ;;
esac

echo "VERIFY: expecting $EXPECT_LABEL (selector word: $1)"

# ------------------------------------------------- the HTTP reading, always 1st
# Captured into a variable with its status read on the NEXT line, for the same
# reason the SSH probe below is — and bounded, so a wedged proxy cannot stall
# the run.
HTTP_OUT=$(curl -fsS --max-time 5 "$HTTP_URL" 2>&1)
HTTP_RC=$?
HTTP_OBS=$(observed_label "$HTTP_OUT")

if [ "$HTTP_RC" -eq 0 ] && [ "$HTTP_OBS" != UNREADABLE ]; then
	printf 'HTTP  %-34s ->  %s server-%s\n' "$HTTP_URL" "$HTTP_OBS" "$(echo "$HTTP_OBS" | tr 'A-Z' 'a-z')"
else
	HTTP_OBS=UNREADABLE
	printf 'HTTP  %-34s ->  UNREADABLE (curl exit %s)\n' "$HTTP_URL" "$HTTP_RC"
fi

# ------------------------------------------------- the SSH reading, always 2nd
#
# THE SINGLE MOST IMPORTANT LINE IN THIS FILE is the capture below, and what
# makes it correct is what it is NOT: it is not on the left of a pipe.
# Research measured, verbatim, `ssh ... | head` returning EXIT=0 while its own
# output read `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!` and
# `Host key verification failed.` — a pipeline reports the LAST command's
# status. Written that way this script would report success on a total failure,
# and EVID-05 would be a lie. Capture with command substitution, read the status
# on the VERY NEXT LINE, and grep the captured VARIABLE afterwards.
#
# 2>&1 is mandatory: the banner — the contractual identity claim — arrives on
# stderr while the remote command's result arrives on stdout, and both are
# wanted from the one connection.
#
# The EXTERNAL timeout is mandatory too. ConnectTimeout covers the TCP connect
# only, so a proxy that accepts the connection while the upstream never answers
# would wait out sshd's 120s login grace period and hang this script. timeout in
# this image reports a SIGTERM status rather than a fixed code, so nothing here
# tests for a specific number — only for non-zero.
SSH_OUT=$(docker compose exec -T client timeout 10 ssh $VERIFY_SSH_OPTS "$SSH_USER@$SSH_TARGET" hostname 2>&1)
SSH_RC=$?
SSH_OBS=$(observed_label "$SSH_OUT")
SSH_HOST=$(observed_hostname "$SSH_OUT")

# The capture is GREPPED, never compared: the host-key options above make ssh
# emit a "Permanently added ..." notice on stderr on every single run, and an
# equality test would break on it.
if [ "$SSH_RC" -eq 0 ] && [ "$SSH_OBS" != UNREADABLE ]; then
	printf 'SSH   %-34s ->  %s server-%s  [banner; remote hostname: %s]\n' \
		"$SSH_USER@$SSH_TARGET:22" "$SSH_OBS" "$(echo "$SSH_OBS" | tr 'A-Z' 'a-z')" "$SSH_HOST"
else
	SSH_OBS=UNREADABLE
	printf 'SSH   %-34s ->  UNREADABLE (exit %s)\n' "$SSH_USER@$SSH_TARGET:22" "$SSH_RC"
fi

# The two SSH readings must agree with each other before either is trusted: a
# banner is rendered from an env var and a hostname comes from the kernel, so
# the two disagreeing means the identity surface is lying about where the shell
# actually ran.
CORROBORATED=yes
if [ "$SSH_OBS" != UNREADABLE ]; then
	if [ "$SSH_HOST" != "server-$(echo "$SSH_OBS" | tr 'A-Z' 'a-z')" ]; then
		CORROBORATED=no
	fi
fi

# ------------------------------------------------------ the verdict, in order
#
# The disagreement case is tested FIRST. Both readings are individually valid
# there, so the mismatch branch below would also fire — and would report the
# cutover as simply "wrong" while discarding the fact that it landed on exactly
# one of the two protocols.
if [ "$HTTP_OBS" != UNREADABLE ] && [ "$SSH_OBS" != UNREADABLE ] && [ "$HTTP_OBS" != "$SSH_OBS" ]; then
	echo "PROTOCOLS DISAGREE  HTTP reported $HTTP_OBS, SSH reported $SSH_OBS — the flip landed on one protocol only."
	echo "  One word in proxy/active-backend.conf drives both. If they differ, they are not reading the same word:"
	echo "  check that the stream block includes the same file the http block does, and that the reload really landed."
	exit 3
fi

if [ "$CORROBORATED" = no ]; then
	echo "MISMATCH  the SSH banner claims $SSH_OBS while the remote shell reports '$SSH_HOST' — the identity surface disagrees with itself."
	exit 1
fi

if [ "$HTTP_OBS" != "$EXPECT_LABEL" ] || [ "$SSH_OBS" != "$EXPECT_LABEL" ]; then
	echo "MISMATCH  expected $EXPECT_LABEL; HTTP reported $HTTP_OBS, SSH reported $SSH_OBS."
	exit 1
fi

echo "OK  both protocols report $EXPECT_LABEL — the expectation holds on HTTP and on SSH."
exit 0
