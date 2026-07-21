#!/bin/sh
# scripts/smoke.sh — demo rig smoke tests.
#
# Usage: sh scripts/smoke.sh [backends|proxy|redirect|all]
#   no argument == all
#
# POSIX sh only. Deliberately NOT `set -e`: every assertion runs so the
# presenter sees the full picture, not just the first failure.

FAILURES=0
PASSES=0

# assert <label> <shell-condition>
assert() {
	_label=$1
	_cond=$2
	if sh -c "$_cond" >/dev/null 2>&1; then
		echo "PASS $_label"
		PASSES=$((PASSES + 1))
	else
		echo "FAIL $_label"
		FAILURES=$((FAILURES + 1))
	fi
}

# fail <label> — unconditional failure (used by not-yet-implemented sections)
fail() {
	echo "FAIL $1"
	FAILURES=$((FAILURES + 1))
}

section_backends() {
	echo "--- backends ---"

	# ENV-01: one command brings the rig up.
	assert "ENV-01 docker compose up -d --wait" \
		'docker compose up -d --wait'

	# ENV-02 positive precondition. The teardown half is exercised by
	# `make reset`, not here — tearing down mid-suite would break every
	# assertion after it.
	assert "ENV-02 precondition: project has containers" \
		'test -n "$(docker compose ps -aq)"'

	# BACK-01: server-old serves HTTP and has sshd listening in-container.
	assert "BACK-01 server-old /healthz" \
		'curl -fsS http://localhost:9090/healthz'
	assert "BACK-01 server-old sshd on :22" \
		'docker compose exec -T server-old sh -c "nc -z localhost 22"'

	# BACK-02: same for server-new.
	assert "BACK-02 server-new /healthz" \
		'curl -fsS http://localhost:9091/healthz'
	assert "BACK-02 server-new sshd on :22" \
		'docker compose exec -T server-new sh -c "nc -z localhost 22"'

	# BACK-03: anchored identity, fixed two-field order.
	assert "BACK-03 server-old /whoami == 'OLD server-old'" \
		'curl -fsS http://localhost:9090/whoami | grep -q "^OLD server-old$"'
	assert "BACK-03 server-new /whoami == 'NEW server-new'" \
		'curl -fsS http://localhost:9091/whoami | grep -q "^NEW server-new$"'

	# D-11: the machine-greppable half of the identity signal (feeds Phase 2 EVID-01).
	assert "D-11 server-old X-Backend: OLD (direct)" \
		'curl -sSI http://localhost:9090/ | grep -qi "^X-Backend: OLD"'
	assert "D-11 server-new X-Backend: NEW (direct)" \
		'curl -sSI http://localhost:9091/ | grep -qi "^X-Backend: NEW"'

	# Phase 4 KEY-01 precondition: host keys are generated per container at
	# start, never baked into the shared image.
	assert "KEY-01 precondition: backends have DIFFERENT ssh host keys" \
		'o=$(docker compose exec -T server-old ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub); n=$(docker compose exec -T server-new ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub); test -n "$o" && test -n "$n" && test "$o" != "$n"'

	# Identity-model invariant (assumption-delta): one image, two instances.
	assert "D-16 invariant: server-old and server-new share one image ID" \
		'o=$(docker compose images --quiet server-old); n=$(docker compose images --quiet server-new); test -n "$o" && test "$o" = "$n"'

	# Empty-input edge: an unnamed backend must never serve a page.
	assert "BACK-03 empty edge: empty BACKEND_ID exits non-zero" \
		'docker image inspect demo-backend:1 >/dev/null 2>&1 && ! docker run --rm -e BACKEND_ID= --entrypoint /entrypoint.sh demo-backend:1 /bin/true'
}

# Pitfall 3: a typo'd selector passes `nginx -t` and reloads cleanly, then 502s
# every request — on stage, mid-cutover. The $backend_is_valid guard in
# nginx.conf turns that into a legible 503.
#
# This check is DESTRUCTIVE by design: it writes an invalid value into
# proxy/active-backend.conf. The file is backed up first and restored by a trap,
# so an interrupted run does not leave the rig broken.
guard_check() {
	_bak=$(mktemp)
	cp proxy/active-backend.conf "$_bak"
	trap 'cp "$_bak" proxy/active-backend.conf; docker compose exec -T proxy nginx -s reload >/dev/null 2>&1; rm -f "$_bak"; exit 1' INT TERM
	trap 'cp "$_bak" proxy/active-backend.conf; docker compose exec -T proxy nginx -s reload >/dev/null 2>&1; rm -f "$_bak"' EXIT

	sed 's/default old;/default nwe;/' "$_bak" > proxy/active-backend.conf
	assert "Pitfall 3 invalid selector still passes nginx -t" \
		'docker compose exec -T proxy nginx -t'
	assert "Pitfall 3 reload succeeds despite the invalid selector" \
		'docker compose exec -T proxy nginx -s reload'
	sleep 1
	assert "Pitfall 3 invalid selector returns 503, not a bare 502" \
		'test "$(curl -sS -o /dev/null -w "%{http_code}" http://localhost:9092/)" = "503"'
	assert "Pitfall 3 503 body names the offending value" \
		'curl -sS http://localhost:9092/ | grep -q "nwe"'

	cp "$_bak" proxy/active-backend.conf
	docker compose exec -T proxy nginx -s reload >/dev/null 2>&1
	trap - EXIT INT TERM
	rm -f "$_bak"
	sleep 1
	assert "Pitfall 3 restore: 9092 serves 200 again" \
		'test "$(curl -sS -o /dev/null -w "%{http_code}" http://localhost:9092/)" = "200"'
}

section_proxy() {
	echo "--- proxy ---"

	# ENV-04: the stream module is COMPILED IN. Phase 1 ships no stream block
	# at all (D-15) — Phase 3 writes it. This proves the module is there.
	assert "ENV-04 proxy nginx built --with-stream" \
		'docker compose exec -T proxy nginx -V 2>&1 | grep -q -- --with-stream'

	# HTTP-01: the host path, through the proxy, anchored.
	assert "HTTP-01 localhost:9092/whoami == 'OLD server-old'" \
		'curl -fsS http://localhost:9092/whoami | grep -q "^OLD server-old$"'

	# HTTP-01 via the REAL hostname (D-01/D-02): the client container resolves
	# app.demo.test through Docker DNS straight to the proxy container.
	assert "HTTP-01 client -> app.demo.test:9092/whoami == 'OLD server-old'" \
		'docker compose exec -T client curl -fsS http://app.demo.test:9092/whoami | grep -q "^OLD server-old$"'

	# HTTP-02, read as URL invariance (NOT source-IP invariance — on macOS
	# Docker Desktop every host-originated request arrives SNAT'd, see Pitfall 6).
	assert "HTTP-02 proxied request performs 0 redirects" \
		'test "$(curl -sSL -o /dev/null -w "%{num_redirects}" http://localhost:9092/)" = "0"'
	assert "HTTP-02 effective URL unchanged through the proxy" \
		'test "$(curl -sSL -o /dev/null -w "%{url_effective}" http://localhost:9092/whoami)" = "http://localhost:9092/whoami"'

	# D-11 survives the hop: proxy_pass forwards the backend's own header verbatim.
	assert "D-11 X-Backend: OLD through the proxy" \
		'curl -sSI http://localhost:9092/ | grep -qi "^X-Backend: OLD"'

	# HTTP-01 honesty: the identity above came from the BACKEND, not from us.
	# Comments are filtered so the config's own prose cannot self-invalidate this.
	assert "HTTP-01 honesty: no add_header in proxy/nginx.conf" \
		'test "$(grep -v "^[[:space:]]*#" proxy/nginx.conf | grep -ci "add_header")" = "0"'

	# Phase 2 EVID-01 precondition: the log names the serving backend.
	assert "EVID-01 precondition: proxy log carries backend=OLD" \
		'curl -fsS http://localhost:9092/whoami >/dev/null && docker compose logs proxy | grep -q "backend=OLD"'

	# HTTP-02 corroborating evidence: the log records the name the client asked
	# for, held constant across the flip. This — not $remote_addr — is the proof.
	assert "HTTP-02 evidence: proxy log records app.demo.test:9092" \
		'docker compose exec -T client curl -fsS http://app.demo.test:9092/whoami >/dev/null && docker compose logs proxy | grep -q "app.demo.test:9092"'

	# T-01-10: loopback-bound only, and no port 22 anywhere in this phase (D-15).
	#
	# `docker compose port`, not a grep of `ps --format {{.Ports}}`: once 9093
	# joined the proxy, Compose collapsed the two adjacent publishes into the
	# range `127.0.0.1:9092-9093->9092-9093/tcp` and the literal grep stopped
	# matching. `port` resolves one container port at a time and is immune.
	assert "T-01-10 9092 published on loopback only" \
		'docker compose port proxy 9092 | grep -q "^127.0.0.1:9092$"'
	assert "D-15 no host port 22 binding exists" \
		'! docker compose ps --format "{{.Ports}}" | grep -q ":22->"'

	# D-14: config changes are picked up by a graceful reload, never a restart.
	assert "D-14 nginx -t passes inside the proxy container" \
		'docker compose exec -T proxy nginx -t'

	guard_check
}

section_redirect() {
	echo "--- redirect ---"

	# HTTP-03: 9093 answers with a 301 whose Location points at a REAL,
	# reachable backend address — not back at the proxy.
	assert "HTTP-03 9093 returns 301" \
		'curl -sS -o /dev/null -w "%{http_code}" http://localhost:9093/ | grep -q "^301$"'
	assert "HTTP-03 301 Location targets the backend on 9090" \
		'curl -sS -o /dev/null -w "%{redirect_url}" http://localhost:9093/ | grep -q "9090"'

	# The requested path survives the hop ($request_uri), so the redirect lands
	# on the same resource rather than dumping the client on the backend root.
	assert "HTTP-03 request path survives the redirect (/whoami)" \
		'curl -sS -i http://localhost:9093/whoami | grep -i "^Location:" | grep -q "/whoami"'

	# T-01-13: the Location target is a LITERAL address in the config, so no
	# request-supplied value can steer where the client is sent.
	assert "T-01-13 Location target is literal, not \$host-derived" \
		'grep "return 301" proxy/nginx.conf | grep -q "app.demo.test:9090.request_uri"'

	# T-01-15: loopback-bound, matching 9090/9091/9092. See the T-01-10 note in
	# section_proxy for why this uses `port` rather than a `ps` grep.
	assert "T-01-15 9093 published on loopback only" \
		'docker compose port proxy 9093 | grep -q "^127.0.0.1:9093$"'

	# ---- HTTP-04: the contrast IS the assertion ----
	# Both halves live in this one section deliberately. "9093 changes the URL"
	# and "9092 does not" are only meaningful side by side; asserted apart they
	# are two unrelated facts and the demo's whole point goes unverified.

	# Measured BEFORE any 9093 traffic — the first half of the order-independence
	# evidence below.
	_proxied_before=$(curl -sSL -o /dev/null -w '%{url_effective}' http://localhost:9092/whoami)

	# --resolve on the 9093 follows: the redirect target is a literal
	# app.demo.test:9090, and this suite must pass on a machine that has not
	# yet done the one-time /etc/hosts step (D-03). --resolve supplies the name
	# for a single invocation and touches no host state (ENV-03). Without it
	# the hop dies at DNS and the assertion would prove nothing about nginx.
	assert "HTTP-04 redirect side: 9093 ends on a DIFFERENT URL" \
		'test "$(curl -sSL --resolve app.demo.test:9090:127.0.0.1 -o /dev/null -w "%{url_effective}" http://localhost:9093/whoami)" != "http://localhost:9093/whoami"'
	assert "HTTP-04 proxy side: 9092 ends on the IDENTICAL URL requested" \
		'test "$(curl -sSL -o /dev/null -w "%{url_effective}" http://localhost:9092/whoami)" = "http://localhost:9092/whoami"'
	assert "HTTP-04 the redirect actually LANDS on OLD (target is reachable)" \
		'curl -fsSL --resolve app.demo.test:9090:127.0.0.1 http://localhost:9093/whoami | grep -q "^OLD server-old$"'
	assert "HTTP-04 9093 performs exactly 1 redirect" \
		'test "$(curl -sSL --resolve app.demo.test:9090:127.0.0.1 -o /dev/null -w "%{num_redirects}" http://localhost:9093/whoami)" = "1"'
	assert "HTTP-04 9092 performs 0 redirects" \
		'test "$(curl -sSL -o /dev/null -w "%{num_redirects}" http://localhost:9092/whoami)" = "0"'

	# The two listeners share no state. Sandwiching a 9093 request between two
	# 9092 measurements proves the redirect leaves no residue that changes the
	# proxied result — the mechanically checkable half of the concurrency
	# backstop. (The one genuine cross-run interference, a browser caching the
	# 301, is not CLI-checkable and is mitigated by README's incognito
	# instruction; curl does not cache and is immune.)
	_proxied_after=$(curl -sSL -o /dev/null -w '%{url_effective}' http://localhost:9092/whoami)
	assert "HTTP-04 order-independence: 9092 result identical before and after a 9093 request" \
		"test '$_proxied_before' = '$_proxied_after'"

	# Pattern 6: nginx answered directly, so there was no upstream and no
	# backend to name. The dashes are the honest record of that — and a
	# teaching moment when the presenter tails the log.
	assert "Pattern 6: the 9093 request logs upstream=- and backend=-" \
		'curl -sS -o /dev/null http://localhost:9093/whoami && docker compose logs proxy | grep ":9093" | grep -q "upstream=- backend=- "'
}

section=${1:-all}
case "$section" in
backends) section_backends ;;
proxy) section_proxy ;;
redirect) section_redirect ;;
all)
	section_backends
	section_proxy
	section_redirect
	;;
*)
	echo "usage: sh scripts/smoke.sh [backends|proxy|redirect|all]" >&2
	exit 2
	;;
esac

echo "--- $PASSES passed, $FAILURES failed ---"
test "$FAILURES" -eq 0
