#!/bin/sh
# scripts/smoke.sh — demo rig smoke tests.
#
# Usage: sh scripts/smoke.sh [backends|proxy|redirect|cutover|all]
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

# settle_flip <target> — wait until the flip has actually landed.
#
# Polls the RUNNING config's own view of its selector through the unpublished
# :8081 oracle. That is the only source that cannot lie: a request through :9092
# cannot distinguish "the reload failed" from "the reload landed and this request
# raced the interleave window".
#
# The trailing sleep is not superstition. Measured interleave windows after
# `nginx -s reload` returned were 26 ms, 58 ms and 28 ms (RESEARCH Pitfall 5) —
# both worker generations briefly drain the same listening socket. 200 ms clears
# every observation with 3x margin. Every timing-sensitive assertion below calls
# this rather than re-deriving the wait.
settle_flip() {
	_target=$1
	_i=0
	while [ "$_i" -lt 25 ]; do
		_got=$(docker compose exec -T proxy curl -sS --max-time 1 \
			http://localhost:8081/active-backend 2>/dev/null | tr -d '\r\n')
		if [ "$_got" = "$_target" ]; then
			sleep 0.2
			return 0
		fi
		_i=$((_i + 1))
		sleep 0.2
	done
	return 1
}

# The cutover section is DESTRUCTIVE by design: it rewrites the flip include and
# stops a backend. This mirrors guard_check()'s discipline so an interrupted run
# still leaves the rig on `old` with everything running.
restore_flip_state() {
	_flipbak=$(mktemp)
	cp proxy/active-backend.conf "$_flipbak"
	trap 'cp "$_flipbak" proxy/active-backend.conf; docker compose up -d server-old server-new >/dev/null 2>&1; docker compose exec -T proxy nginx -s reload >/dev/null 2>&1; rm -f "$_flipbak"; exit 1' INT TERM
	trap 'cp "$_flipbak" proxy/active-backend.conf; docker compose up -d server-old server-new >/dev/null 2>&1; docker compose exec -T proxy nginx -s reload >/dev/null 2>&1; rm -f "$_flipbak"' EXIT
}

# Clears what restore_flip_state installed, once the section has put the rig
# back on `old` under its own power.
finish_flip_state() {
	cp "$_flipbak" proxy/active-backend.conf
	docker compose exec -T proxy nginx -s reload >/dev/null 2>&1
	trap - EXIT INT TERM
	rm -f "$_flipbak"
}

section_cutover() {
	echo "--- cutover ---"

	restore_flip_state

	# Host-side scratch copy of the evidence log. The file lives inside the proxy
	# container; copying it out once per group of assertions keeps the quoting in
	# the assertions readable.
	_evtmp=$(mktemp)
	_out=$(mktemp)

	# ---- CUT-01: the flip rewrites exactly one word ----

	sh scripts/flip.sh old >/dev/null 2>&1
	settle_flip old
	_base=$(mktemp)
	cp proxy/active-backend.conf "$_base"

	assert "CUT-01 flip.sh new succeeds with both backends healthy" \
		'sh scripts/flip.sh new'
	settle_flip new

	# Plain `diff`, so a changed line shows as exactly one `<` plus one `>`.
	assert "CUT-01 exactly one line differs from the pre-flip baseline" \
		"test \"\$(diff '$_base' proxy/active-backend.conf | grep -c '^[<>]')\" = '2'"

	# D-12: the file the audience reads on screen stays five lines, both
	# presenter comments intact. This goes red the instant a future phase
	# reintroduces a structure nobody can read in full on a projector.
	assert "CUT-01 the include is still 5 lines with both presenter comments" \
		'test "$(wc -l < proxy/active-backend.conf)" -eq 5 && test "$(grep -c "^#" proxy/active-backend.conf)" -eq 2'

	assert "CUT-01 nginx -t passes against the flipped config" \
		'docker compose exec -T proxy nginx -t'

	# ---- CUT-02: the IDENTICAL command string, held in a variable ----
	# The assertion is that the string did not change, not merely that the
	# result did. Same host, same port, same path, same flags.

	_cmd='curl -fsS http://localhost:9092/whoami'
	sh scripts/flip.sh old >/dev/null 2>&1
	settle_flip old
	_before=$(sh -c "$_cmd" 2>/dev/null)
	sh scripts/flip.sh new >/dev/null 2>&1
	settle_flip new
	_after=$(sh -c "$_cmd" 2>/dev/null)
	assert "CUT-02 the identical command string returns OLD, then NEW" \
		"test '$_before' = 'OLD server-old' && test '$_after' = 'NEW server-new'"

	# Same again through the REAL hostname from inside the client container
	# (D-01/D-02/D-22 — app.demo.test, never the mDNS .local variant).
	_ccmd='docker compose exec -T client curl -fsS http://app.demo.test:9092/whoami'
	sh scripts/flip.sh old >/dev/null 2>&1
	settle_flip old
	_cbefore=$(sh -c "$_ccmd" 2>/dev/null | tr -d '\r')
	sh scripts/flip.sh new >/dev/null 2>&1
	settle_flip new
	_cafter=$(sh -c "$_ccmd" 2>/dev/null | tr -d '\r')
	assert "CUT-02 the same command from the client container: OLD, then NEW" \
		"test '$_cbefore' = 'OLD server-old' && test '$_cafter' = 'NEW server-new'"

	# ---- CUT-03: the flip is decisive ----

	assert "CUT-03 post-settle /whoami is NEW server-new" \
		'curl -fsS http://localhost:9092/whoami | grep -q "^NEW server-new$"'

	# Guards against the measured 26-90 ms interleave leaking past the settle.
	assert "CUT-03 twenty consecutive post-settle requests yield zero OLD" \
		'n=0; i=0; while [ $i -lt 20 ]; do curl -fsS http://localhost:9092/whoami | grep -q "^OLD" && n=$((n + 1)); i=$((i + 1)); done; test "$n" -eq 0'

	# ---- CUT-05: no container is restarted, ever (D-14) ----

	_ids=$(docker compose ps -q proxy server-old server-new)
	_started_before=$(echo "$_ids" | xargs docker inspect -f '{{.State.StartedAt}}' 2>/dev/null)
	sh scripts/flip.sh old >/dev/null 2>&1
	settle_flip old
	sh scripts/flip.sh new >/dev/null 2>&1
	settle_flip new
	sh scripts/flip.sh old >/dev/null 2>&1
	settle_flip old
	_started_after=$(echo "$_ids" | xargs docker inspect -f '{{.State.StartedAt}}' 2>/dev/null)
	assert "CUT-05 flip-old -> flip-new -> flip-old restarts no container" \
		"test -n '$_started_before' && test '$_started_before' = '$_started_after'"

	# D-36: flipping back to old is the between-takes reset, so the next take
	# starts with an empty evidence log rather than a prior take's counters.
	assert "CUT-05 flip.sh old leaves the evidence log at 0 bytes" \
		'test "$(docker compose exec -T proxy sh -c "wc -c < /var/log/demo/access.log" | tr -d "[:space:]")" = "0"'

	# ---- D-35: the health gate refuses, and touches nothing ----
	# nginx parses BOTH upstream blocks on every reload, so a stopped backend
	# blocks the flip in BOTH directions (RESEARCH Pitfall 3).

	docker compose stop server-new >/dev/null 2>&1
	_sha_before=$(shasum proxy/active-backend.conf | awk '{print $1}')
	sh scripts/flip.sh new >"$_out" 2>&1
	_rc=$?
	_sha_after=$(shasum proxy/active-backend.conf | awk '{print $1}')

	assert "D-35 flip refuses and exits non-zero when a backend is down" \
		"test '$_rc' -ne 0"
	assert "D-35 the refusal names the backend that is not answering" \
		"grep -q 'server-new' '$_out'"
	assert "D-35 the config file is byte-identical after the refusal" \
		"test -n '$_sha_before' && test '$_sha_before' = '$_sha_after'"

	docker compose up -d --wait server-new >/dev/null 2>&1
	assert "D-35 with server-new back, the same flip succeeds" \
		'sh scripts/flip.sh new'
	settle_flip new

	# ---- EVID-01: the two sinks ----

	curl -sS -o /dev/null http://localhost:9092/whoami
	sleep 0.3
	docker compose exec -T proxy cat /var/log/demo/access.log >"$_evtmp" 2>/dev/null
	assert "EVID-01 the last :9092 evidence line reads backend NEW after a flip" \
		"grep '\"port\":\"9092\"' '$_evtmp' | tail -1 | grep -q '\"backend\":\"NEW\"'"

	# Adjacency: one request, two sinks, exactly once in each. Not -f: the path
	# is deliberately unknown to the backend, and a 404 is logged just the same.
	_uniq="/evid-adjacency-$$"
	curl -sS -o /dev/null "http://localhost:9092$_uniq"
	sleep 0.3
	docker compose exec -T proxy cat /var/log/demo/access.log >"$_evtmp" 2>/dev/null
	_stdout_hits=$(docker compose logs proxy 2>/dev/null | grep -c "$_uniq")
	_file_hits=$(grep -c "$_uniq" "$_evtmp")
	assert "EVID-01 one request appears exactly once in EACH of the two sinks" \
		"test '$_stdout_hits' = '1' && test '$_file_hits' = '1'"

	# Pitfall 7: the 3-second healthcheck must never push a synthetic row into
	# the projected table. `access_log off;` on :8081 suppresses BOTH sinks.
	_lines_before=$(docker compose exec -T proxy sh -c 'wc -l < /var/log/demo/access.log' 2>/dev/null | tr -d '[:space:]')
	i=0
	while [ "$i" -lt 10 ]; do
		docker compose exec -T proxy curl -sS http://localhost:8081/nginx-health >/dev/null 2>&1
		i=$((i + 1))
	done
	_lines_after=$(docker compose exec -T proxy sh -c 'wc -l < /var/log/demo/access.log' 2>/dev/null | tr -d '[:space:]')
	assert "EVID-01 ten :8081 probes add zero evidence lines" \
		"test -n '$_lines_before' && test '$_lines_before' = '$_lines_after'"

	# Concurrency: thirty requests in flight, thirty complete JSON objects. nginx
	# writes each line with a single write(), so no line is interleaved.
	docker compose exec -T proxy sh -c ': > /var/log/demo/access.log' >/dev/null 2>&1
	i=0
	while [ "$i" -lt 30 ]; do
		curl -sS -o /dev/null http://localhost:9092/whoami &
		i=$((i + 1))
	done
	wait
	sleep 0.5
	docker compose exec -T proxy cat /var/log/demo/access.log >"$_evtmp" 2>/dev/null
	_total=$(wc -l <"$_evtmp" | tr -d '[:space:]')
	_wellformed=$(grep -c '^{.*}$' "$_evtmp")
	assert "EVID-01 thirty parallel requests produce exactly thirty complete lines" \
		"test '$_total' = '30' && test '$_wellformed' = '30'"

	# D-36 / Pattern 5: truncate, never unlink. nginx holds the descriptor with
	# O_APPEND, so the next write lands at offset 0 with no sparse NUL hole.
	docker compose exec -T proxy sh -c ': > /var/log/demo/access.log' >/dev/null 2>&1
	_zero=$(docker compose exec -T proxy sh -c 'wc -c < /var/log/demo/access.log' 2>/dev/null | tr -d '[:space:]')
	curl -sS -o /dev/null http://localhost:9092/whoami
	sleep 0.3
	docker compose exec -T proxy cat /var/log/demo/access.log >"$_evtmp" 2>/dev/null
	assert "EVID-01 truncation leaves the evidence file at 0 bytes" \
		"test '$_zero' = '0'"
	assert "EVID-01 the post-truncation line is a complete JSON object at offset 0" \
		"head -1 '$_evtmp' | grep -q '^{.*}\$'"
	assert "EVID-01 the post-truncation file contains no NUL padding" \
		"test \"\$(wc -c <'$_evtmp' | tr -d '[:space:]')\" = \"\$(tr -d '\\000' <'$_evtmp' | wc -c | tr -d '[:space:]')\""

	# The `make logs-demo` filter must colourise without swallowing anything.
	# Matched by regex on the backend= token, never by field position: indices
	# shift by one under `-t` and by two more under D-32's service prefix.
	_awk='/backend=NEW/ { printf "\033[1;97;42m NEW \033[0m %s\n", $0; next } /backend=OLD/ { printf "\033[1;97;43m OLD \033[0m %s\n", $0; next } { print }'
	_awk_in=$(docker compose logs --tail 5 -t proxy 2>/dev/null | grep -c .)
	_awk_out=$(docker compose logs --tail 5 -t proxy 2>/dev/null | awk "$_awk" | grep -c .)
	assert "EVID-01 the logs-demo awk filter passes every line through" \
		"test '$_awk_in' != '0' && test '$_awk_in' = '$_awk_out'"

	# ---- leave the rig the way the presenter expects to find it ----
	sh scripts/flip.sh old >/dev/null 2>&1
	settle_flip old
	assert "CUT-05 the section ends with the rig selecting OLD" \
		'curl -fsS http://localhost:9092/whoami | grep -q "^OLD server-old$"'

	rm -f "$_evtmp" "$_out" "$_base"
	finish_flip_state
}

section=${1:-all}
case "$section" in
backends) section_backends ;;
proxy) section_proxy ;;
redirect) section_redirect ;;
cutover) section_cutover ;;
all)
	section_backends
	section_proxy
	section_redirect
	section_cutover
	;;
*)
	echo "usage: sh scripts/smoke.sh [backends|proxy|redirect|cutover|all]" >&2
	exit 2
	;;
esac

echo "--- $PASSES passed, $FAILURES failed ---"
test "$FAILURES" -eq 0
