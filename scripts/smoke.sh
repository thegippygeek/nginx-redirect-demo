#!/bin/sh
# scripts/smoke.sh — demo rig smoke tests.
#
# Usage: sh scripts/smoke.sh [backends|proxy|redirect|cutover|ssh|all]
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

# The cutover section is DESTRUCTIVE by design: it rewrites the flip include,
# moves it out of the way, and stops both a backend and the proxy. This mirrors
# guard_check()'s discipline so an interrupted run still leaves the rig on `old`
# with everything running.
restore_flip_state() {
	_flipbak=$(mktemp)
	cp proxy/active-backend.conf "$_flipbak"
	trap 'cp "$_flipbak" proxy/active-backend.conf; docker compose up -d server-old server-new proxy status >/dev/null 2>&1; docker compose exec -T proxy nginx -s reload >/dev/null 2>&1; rm -f "$_flipbak"; exit 1' INT TERM
	trap 'cp "$_flipbak" proxy/active-backend.conf; docker compose up -d server-old server-new proxy status >/dev/null 2>&1; docker compose exec -T proxy nginx -s reload >/dev/null 2>&1; rm -f "$_flipbak"' EXIT
}

# ---- the evidence service (02-02) ----------------------------------------
#
# /api/status is rendered with a two-space indent, so every TOP-LEVEL key sits
# at column 3 and every nested key one level deeper. The readers below anchor on
# that indent plus the QUOTED key name, which is why a nested key of the same
# name — or a substring of one — cannot satisfy an assertion.
#
# Deliberately grep/sed rather than a JSON tool: the shipped demo has no host
# runtime (ENV-03), and the contract keys are fixed by 02-02-PLAN's api_contract.
STATUS_URL=http://localhost:9094/api/status

# status_get <outfile> — snapshot /api/status onto the host.
status_get() {
	curl -sS --max-time 3 "$STATUS_URL" >"$1" 2>/dev/null
}

# jfield <file> <key> — a TOP-LEVEL scalar, unquoted, comma stripped.
jfield() {
	sed -n "s/^  \"$2\": \(.*\)/\1/p" "$1" | head -1 | sed 's/,$//; s/^"//; s/"$//'
}

# jnest <file> <key> — a key one level in: counts.OLD/NEW and every boundary field.
jnest() {
	sed -n "s/^    \"$2\": \(.*\)/\1/p" "$1" | head -1 | sed 's/,$//; s/^"//; s/"$//'
}

# jrow0 <file> <key> — a key of rows[0]. `rows` is newest-first and is the only
# array of objects in the contract, so the first match at this depth IS rows[0].
jrow0() {
	sed -n "s/^      \"$2\": \(.*\)/\1/p" "$1" | head -1 | sed 's/,$//; s/^"//; s/"$//'
}

# jrows <file> — how many request rows the response carries.
jrows() {
	grep -c '^      "path":' "$1"
}

# manual_flip <old|new> — rewrite the selector and reload WITHOUT flip.sh, so
# the evidence log survives. flip.sh old truncates it (D-36), which would
# destroy a deliberately-constructed two-transition window.
manual_flip() {
	_mtmp=$(mktemp)
	sed "s/default [A-Za-z0-9_.-]*;/default $1;/" proxy/active-backend.conf >"$_mtmp"
	cp "$_mtmp" proxy/active-backend.conf
	rm -f "$_mtmp"
	docker compose exec -T proxy nginx -s reload >/dev/null 2>&1
	settle_flip "$1"
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

	# ================================================================
	# EVID-02 / EVID-03 — the evidence service (02-02)
	# ================================================================
	#
	# Every assertion below reads /api/status, which recomputes the whole world
	# from two files plus one liveness probe on each request. The service holds
	# no counter, cursor or cache, so there is nothing here to "reset" between
	# groups beyond the evidence log itself.

	_st=$(mktemp)

	assert "D-25 the status service is the healthy fourth container" \
		'docker compose ps status --format "{{.Health}}" | grep -q "^healthy$"'

	# T-02-05 / Pitfall 9: `docker compose port`, never a ps --format grep —
	# Compose collapses adjacent published ports on one service into a range.
	assert "T-02-05 the status port is published on loopback only" \
		'docker compose port status 9094 | grep -q "^127.0.0.1:9094$"'

	# T-02-04: the tier that REPORTS the evidence must provably be unable to
	# alter it. Both mounts are :ro, which is what makes the reading believable.
	# The positive half of each pair matters: without it a missing service would
	# satisfy the negation vacuously and the mount would go unasserted.
	assert "T-02-04 the status container CANNOT truncate the evidence it reports" \
		'docker compose exec -T status sh -c "test -r /var/log/demo/access.log" && ! docker compose exec -T status sh -c ": > /var/log/demo/access.log"'
	assert "T-02-04 the status container CANNOT alter the config it reports" \
		'docker compose exec -T status sh -c "test -r /etc/nginx/demo/active-backend.conf" && ! docker compose exec -T status sh -c ": > /etc/nginx/demo/active-backend.conf"'

	# T-02-06 / D-29: the container-runtime socket is a full privilege
	# escalation on a machine that may not be the presenter's. Never mounted.
	assert "T-02-06 no container-runtime socket is mounted anywhere" \
		'test "$(grep -c docker.sock compose.yaml)" = "0"'

	assert "D-25 /healthz answers 200 for the container healthcheck" \
		'test "$(curl -sS -o /dev/null -w "%{http_code}" http://localhost:9094/healthz)" = "200"'

	# ---- EVID-02 / D-27: TWO readings, never one merged value ----

	sh scripts/flip.sh old >/dev/null 2>&1
	settle_flip old
	curl -sS -o /dev/null http://localhost:9092/whoami
	sleep 0.4
	status_get "$_st"
	_ecfg=$(jfield "$_st" config)
	_etraf=$(jfield "$_st" traffic)
	_ehascfg=$(grep -c '^  "config":' "$_st")
	_ehastraf=$(grep -c '^  "traffic":' "$_st")
	assert "EVID-02 /api/status carries config AND traffic as two independently sourced keys" \
		"test '$_ehascfg' = '1' && test '$_ehastraf' = '1' && test '$_ecfg' = 'OLD' && test '$_etraf' = 'OLD'"

	# The gap between editing the file and nginx picking it up is the most
	# instructive part of the mechanism (D-27). Edit WITHOUT reloading.
	manual_edit=$(mktemp)
	sed 's/default old;/default new;/' proxy/active-backend.conf >"$manual_edit"
	cp "$manual_edit" proxy/active-backend.conf
	rm -f "$manual_edit"
	sleep 0.5
	status_get "$_st"
	_pcfg=$(jfield "$_st" config)
	_ptraf=$(jfield "$_st" traffic)
	_psync=$(jfield "$_st" sync)
	assert "EVID-02 config edited without a reload: sync PENDING, config NEW, traffic still OLD" \
		"test '$_pcfg' = 'NEW' && test '$_ptraf' = 'OLD' && test '$_psync' = 'PENDING'"

	docker compose exec -T proxy nginx -s reload >/dev/null 2>&1
	settle_flip new
	curl -sS -o /dev/null http://localhost:9092/whoami
	sleep 0.4
	status_get "$_st"
	_icfg=$(jfield "$_st" config)
	_itraf=$(jfield "$_st" traffic)
	_isync=$(jfield "$_st" sync)
	assert "EVID-02 the reload closes the gap: sync IN_SYNC with config == traffic == NEW" \
		"test '$_icfg' = 'NEW' && test '$_itraf' = 'NEW' && test '$_isync' = 'IN_SYNC'"

	# ---- EVID-02 / D-28 / Pitfall 6: a readable log is not proof nginx is alive ----
	# After `stop proxy` the evidence file is still perfectly readable. A
	# file-only design keeps rendering a confident backend reading — the single
	# most damaging defect available in this phase.

	docker compose stop proxy >/dev/null 2>&1
	_i=0
	_ustate=""
	while [ "$_i" -lt 10 ]; do
		status_get "$_st"
		_ustate=$(jfield "$_st" state)
		[ "$_ustate" = "UNAVAILABLE" ] && break
		_i=$((_i + 1))
		sleep 0.5
	done
	_ufail=$(jfield "$_st" failing_source)
	_utraf=$(grep -cE '^  "traffic": "(OLD|NEW)"' "$_st")
	_ucfg=$(grep -cE '^  "config": "(OLD|NEW)"' "$_st")
	_ustatus_up=$(docker compose ps status --format '{{.State}}' | tr -d '[:space:]')
	_evstillthere=$(docker compose exec -T status sh -c 'test -r /var/log/demo/access.log && echo yes' 2>/dev/null | tr -d '[:space:]')

	assert "EVID-02 stopping the proxy reaches UNAVAILABLE within 5 s" \
		"test '$_ustate' = 'UNAVAILABLE'"
	assert "EVID-02 the UNAVAILABLE reading blanks BOTH readings and names proxy as the source" \
		"test '$_utraf' = '0' && test '$_ucfg' = '0' && test '$_ufail' = 'proxy'"
	assert "D-28 the evidence file is still readable — the proxy probe is what caught it" \
		"test '$_evstillthere' = 'yes'"
	assert "D-25 stopping the proxy does NOT stop the status service" \
		"test '$_ustatus_up' = 'running'"

	docker compose up -d --wait proxy >/dev/null 2>&1
	settle_flip new
	curl -sS -o /dev/null http://localhost:9092/whoami
	sleep 0.4
	status_get "$_st"
	_rstate=$(jfield "$_st" state)
	assert "EVID-02 restarting the proxy restores state OK" \
		"test '$_rstate' = 'OK'"

	# ---- EVID-02 / UI-SPEC 3a: partial failure collapses to FULL UNAVAILABLE ----
	# The evidence log stays perfectly healthy throughout; only the config goes.

	_cbak=$(mktemp)
	cp proxy/active-backend.conf "$_cbak"
	rm -f proxy/active-backend.conf
	sleep 0.5
	status_get "$_st"
	_dstate=$(jfield "$_st" state)
	_dsync=$(jfield "$_st" sync)
	_dfail=$(jfield "$_st" failing_source)
	_ddetail=$(jfield "$_st" detail)
	_dcfg=$(grep -cE '^  "config": "(OLD|NEW)"' "$_st")
	_dtraf=$(grep -cE '^  "traffic": "(OLD|NEW)"' "$_st")
	_drows=$(jrows "$_st")
	cp "$_cbak" proxy/active-backend.conf
	rm -f "$_cbak"
	sleep 0.5

	assert "EVID-02 an unreadable config yields FULL UNAVAILABLE — never a half-lit page" \
		"test '$_dstate' = 'UNAVAILABLE' && test '$_dcfg' = '0' && test '$_dtraf' = '0' && test '$_drows' = '0'"
	assert "EVID-02 the unreadable config reports sync CANNOT_DETERMINE, failing_source config" \
		"test '$_dsync' = 'CANNOT_DETERMINE' && test '$_dfail' = 'config'"
	# T-02-09: the detail line is a path plus a lowercased OS error and nothing
	# else. No traceback, no environment — it is projected in front of a room.
	assert "T-02-09 the UNAVAILABLE detail names the path and the reason, with no traceback" \
		"echo '$_ddetail' | grep -q '^/.* — .*$' && ! echo '$_ddetail' | grep -q 'Traceback'"

	# ---- EVID-03: the recent-requests table ----

	sh scripts/flip.sh old >/dev/null 2>&1
	settle_flip old
	_upath="/evid-row0-$$"
	curl -sS -o /dev/null "http://localhost:9092$_upath"
	sleep 0.4
	status_get "$_st"
	_r0path=$(jrow0 "$_st" path)
	_r0back=$(jrow0 "$_st" backend)
	assert "EVID-03 a uniquely-pathed :9092 request is rows[0] with the backend that answered it" \
		"test '$_r0path' = '$_upath' && test '$_r0back' = 'OLD'"

	# The flip, seen from the evidence side. flip.sh issues exactly one
	# confirming request, so there is exactly one post-flip row afterwards.
	sh scripts/flip.sh new >/dev/null 2>&1
	settle_flip new
	sleep 0.4
	status_get "$_st"
	_bfrom=$(jnest "$_st" from)
	_bto=$(jnest "$_st" to)
	_bidx=$(jnest "$_st" row_index)
	_bsince=$(jfield "$_st" since_flip_s)
	assert "EVID-03 after a flip the boundary reports from OLD to NEW" \
		"test '$_bfrom' = 'OLD' && test '$_bto' = 'NEW'"
	# 02-UI-SPEC.md:456 — row_index is the count of rows rendered ABOVE the
	# boundary, and rows above it are by definition post-flip.
	assert "EVID-03 boundary.row_index is 1 with one post-flip row (min(3, post_flip_row_count))" \
		"test '$_bidx' = '1'"
	assert "EVID-03 since_flip_s is computed server-side and is present" \
		"test -n '$_bsince' && test '$_bsince' != 'null'"

	_i=0
	while [ "$_i" -lt 4 ]; do
		curl -sS -o /dev/null http://localhost:9092/whoami
		_i=$((_i + 1))
	done
	sleep 0.4
	status_get "$_st"
	_bidx2=$(jnest "$_st" row_index)
	assert "EVID-03 boundary.row_index pins at 3 once post-flip rows exceed the ceiling" \
		"test '$_bidx2' = '3'"

	# Pitfall 7: three healthcheck intervals of pure silence. The proxy's probe
	# targets :8081, whose `access_log off` suppresses BOTH sinks; the status
	# service's own liveness probe targets the same listener.
	#
	# The settle before the FIRST snapshot is load-bearing. The loop above ends
	# with a curl whose evidence line may not be visible to the next read yet; if
	# it lands between the two snapshots, this assertion reports a reading change
	# during the silent window and blames the healthchecks for traffic it issued
	# itself. Observed once as an intermittent red on an otherwise green run.
	sleep 0.5
	status_get "$_st"
	_hc1o=$(jnest "$_st" OLD)
	_hc1n=$(sed -n 's/^    "NEW": \([0-9]*\).*/\1/p' "$_st" | head -1)
	_hcl1=$(docker compose exec -T proxy sh -c 'wc -l < /var/log/demo/access.log' 2>/dev/null | tr -d '[:space:]')
	sleep 10
	status_get "$_st"
	_hc2o=$(jnest "$_st" OLD)
	_hc2n=$(sed -n 's/^    "NEW": \([0-9]*\).*/\1/p' "$_st" | head -1)
	_hcl2=$(docker compose exec -T proxy sh -c 'wc -l < /var/log/demo/access.log' 2>/dev/null | tr -d '[:space:]')
	assert "EVID-03 three healthcheck intervals with no user traffic change no reading" \
		"test -n '$_hc1o' && test '$_hc1o' = '$_hc2o' && test '$_hc1n' = '$_hc2n' && test '$_hcl1' = '$_hcl2'"

	# The 9093 redirect listener deliberately does NOT follow the flip (Phase 1
	# known constraint), so counting it would misreport the cutover. Filter
	# contract: port == "9092" AND backend != "".
	status_get "$_st"
	_r1o=$(jnest "$_st" OLD)
	_r1n=$(sed -n 's/^    "NEW": \([0-9]*\).*/\1/p' "$_st" | head -1)
	_r1rows=$(jrows "$_st")
	curl -sS -o /dev/null http://localhost:9093/
	sleep 0.5
	status_get "$_st"
	_r2o=$(jnest "$_st" OLD)
	_r2n=$(sed -n 's/^    "NEW": \([0-9]*\).*/\1/p' "$_st" | head -1)
	_r2rows=$(jrows "$_st")
	assert "EVID-03 a request to :9093 leaves the counters and rows untouched" \
		"test '$_r1rows' -gt 0 && test '$_r1o' = '$_r2o' && test '$_r1n' = '$_r2n' && test '$_r1rows' = '$_r2rows'"

	# EVID-03 / concurrency: TWO transitions inside the 8-row window still yield
	# exactly ONE boundary object — the MOST RECENT — never a list. The backwards
	# scan is also what absorbs the measured 26-90 ms reload interleave.
	sh scripts/flip.sh old >/dev/null 2>&1
	settle_flip old
	curl -sS -o /dev/null http://localhost:9092/whoami
	sh scripts/flip.sh new >/dev/null 2>&1
	settle_flip new
	manual_flip old
	curl -sS -o /dev/null http://localhost:9092/whoami
	sleep 0.4
	status_get "$_st"
	_tbcount=$(grep -c '^    "from":' "$_st")
	_tblist=$(grep -c '^  "boundary": \[' "$_st")
	_tbto=$(jnest "$_st" to)
	assert "EVID-03 two transitions in the window yield exactly ONE boundary, the most recent" \
		"test '$_tbcount' = '1' && test '$_tblist' = '0' && test '$_tbto' = 'OLD'"

	# EVID-01: nginx writes each line with a single write(), but a reader that
	# opens the file mid-write can still see a partial trailing line.
	docker compose exec -T proxy sh -c 'printf "{\"t\":\"2026-01-01T00:00:00+00:00\",\"ms\":\"1,\"pa" >> /var/log/demo/access.log' >/dev/null 2>&1
	sleep 0.4
	_torncode=$(curl -sS -o /dev/null -w '%{http_code}' http://localhost:9094/api/status)
	status_get "$_st"
	_tornrows=$(jrows "$_st")
	assert "EVID-01 a torn trailing line is skipped silently; /api/status still returns 200" \
		"test '$_torncode' = '200'"
	assert "EVID-01 the complete rows preceding the torn line are still returned" \
		"test '$_tornrows' -gt 0"

	# ---- CUT-05 / D-36: the between-takes reset, all four readings at once ----

	sh scripts/flip.sh old >/dev/null 2>&1
	settle_flip old
	sleep 0.4
	status_get "$_st"
	_nstate=$(jfield "$_st" state)
	_nsync=$(jfield "$_st" sync)
	_no=$(jnest "$_st" OLD)
	_nn=$(sed -n 's/^    "NEW": \([0-9]*\).*/\1/p' "$_st" | head -1)
	_nrows=$(jrows "$_st")
	_nbound=$(grep -c '^  "boundary": null' "$_st")
	_nsince=$(grep -c '^  "since_flip_s": null' "$_st")
	assert "CUT-05 flip.sh old resets counters, table, boundary and clock atomically" \
		"test '$_nstate' = 'NO_TRAFFIC' && test '$_no' = '0' && test '$_nn' = '0' && test '$_nrows' = '0' && test '$_nbound' = '1' && test '$_nsince' = '1'"
	assert "CUT-05 the reset reports sync AWAITING_FIRST_REQUEST, not a stale IN_SYNC" \
		"test '$_nsync' = 'AWAITING_FIRST_REQUEST'"

	# ---- D1: the reset direction issues NO confirming request ----
	#
	# Ordering, not politeness. A confirming request followed a second later by
	# the truncation makes the traffic reading genuinely move NEW -> OLD for that
	# window, and a 1 s poll landing inside it fires the projected page's
	# convergence sequence — the money shot, spent on a reset. Measured at 1 in 3
	# before the fix. The page cannot see a truncation coming, so this has to be
	# structural: the reset seeds nothing and therefore requests nothing.
	_d1f=$(mktemp)
	_d1r=$(mktemp)
	sh scripts/flip.sh new >"$_d1f" 2>&1
	settle_flip new
	curl -sS -o /dev/null http://localhost:9092/whoami
	sleep 0.3
	sh scripts/flip.sh old >"$_d1r" 2>&1
	settle_flip old
	sleep 0.4
	assert "D1 the forward flip still issues exactly one confirming request" \
		"test \"\$(grep -c 'localhost:9092/whoami  ->' '$_d1f')\" = '1'"
	assert "D1 the reset flip issues NO confirming request" \
		"test \"\$(grep -c 'localhost:9092/whoami  ->' '$_d1r')\" = '0'"
	assert "D1 the truncation is the reset's last observable act — 0 bytes, no post-truncation row" \
		'test "$(docker compose exec -T proxy sh -c "wc -c < /var/log/demo/access.log" | tr -d "[:space:]")" = "0"'
	rm -f "$_d1f" "$_d1r"

	rm -f "$_st"

	# ================================================================
	# UI-SPEC token audit (02-UI-SPEC executor acceptance tests 2, 10, 11)
	# ================================================================
	#
	# Static assertions over status/index.html. They exist because every rule
	# below is invisible on the machine that breaks it: each one looks correct on
	# a laptop and fails on the projector, which is the only place it matters and
	# the last place anyone tests.
	#
	# They live in section_cutover rather than in a fifth section because the file
	# they read is written by the same phase, and a section that could run before
	# the file exists would pass vacuously.

	# --- typography: exactly 4 sizes, exactly 2 weights ---
	#
	# The four sizes are declared once as tokens and referenced everywhere else,
	# so a fifth size can only enter as a fifth token or as a literal value. Both
	# are asserted. The root scale hook is the one font-size declaration that is
	# not a token reference, and it is excluded by name.
	assert "UI-SPEC 10 exactly 4 distinct font sizes (excluding the root scale hook)" \
		'test "$(grep -oE "font-size: *[^;}]*" status/index.html | sed "s/font-size: *//" | grep -v "^calc(" | sort -u | wc -l | tr -d "[:space:]")" = "4"'
	assert "UI-SPEC 10 exactly 4 --fs- token definitions — a fifth is a contract failure" \
		'test "$(grep -oE "\-\-fs-[a-z]+ *:" status/index.html | sort -u | wc -l | tr -d "[:space:]")" = "4"'
	assert "UI-SPEC 10 no literal font-size value bypasses the token scale" \
		'test "$(grep -oE "font-size: *[^;}]*" status/index.html | grep -v "var(--fs-" | grep -cv "calc(100vw / 120)")" = "0"'
	# Two weights is not a stylistic preference. The system font stack resolves to
	# a different family per OS, and intermediate weights either synthesise or
	# snap unpredictably across those families — 400 and 700 are the only cuts
	# guaranteed real everywhere. A page that looks right on the presenter's Mac
	# has to look the same on a borrowed Windows laptop.
	assert "UI-SPEC 10 exactly 2 font weights, and they are 400 and 700" \
		'test "$(grep -oE "font-weight: *[^;}]*" status/index.html | sed "s/font-weight: *//" | sort -u | tr "\n" " ")" = "400 700 "'

	# --- colour used as fill, never as text or border ---
	#
	# #b45309 and #15803d are 5.0:1 against white and compliant as fills behind
	# white text. As text on the dark ground they fall to roughly 2.7:1 and fail.
	# Both the raw hexes and the token indirections are checked, because a later
	# edit is far likelier to write var(--old) than the literal.
	assert "UI-SPEC colour rule: the accents never appear as a text or border colour" \
		'test "$(grep -cE "(^|[^-a-zA-Z])(border-)?color[[:space:]]*:[^;}]*(#b45309|#15803d|var\(--old\)|var\(--new\))" status/index.html)" = "0"'

	# --- panel separation carried by the border, not by the fill ---
	#
	# The secondary fill sits at 1.6:1 against the ground and is the first thing
	# heavy projector washout destroys. An implementation relying on the fill
	# alone looks correct on a laptop and dissolves into one flat field in the
	# room.
	assert "UI-SPEC colour rule: the .panel rule carries a 2px hairline border" \
		'grep -E "^\.panel\{" status/index.html | grep -q "border:2px solid var(--line)"'
	assert "UI-SPEC colour rule: at least three panels actually use it" \
		'test "$(grep -c "class=\"[^\"]*panel" status/index.html)" -ge 3'

	# --- the root scale hook, in the one form calc() accepts ---
	#
	# calc() permits a length divided by a plain NUMBER, never by a length. The
	# invalid form is dropped silently, the root size falls back to the browser
	# default, and the whole rem scale collapses to its reference values — which
	# still looks correct at 1920 wide. That is exactly what makes it dangerous.
	assert "UI-SPEC 11 the valid root scale form is present exactly once" \
		'test "$(grep -c "calc(100vw / 120)" status/index.html)" = "1"'
	assert "UI-SPEC 11 the invalid divide-by-a-length form is absent" \
		'test "$(grep -cE "calc\(100vw *\/ *[0-9.]+(px|rem|em|vw|vh)" status/index.html)" = "0"'

	# --- offline: ENV-03 / UI-SPEC 2 ---
	#
	# Conference wifi is the assumption this demo refuses to make. The page must
	# render identically with the network unplugged.
	assert "UI-SPEC 2 zero hosted fonts and zero CDN references" \
		'test "$(grep -cE "@font-face|cdn\.|googleapis|gstatic|unpkg|jsdelivr|bootstrapcdn" status/index.html)" = "0"'
	assert "UI-SPEC 2 zero src/href attributes of any kind — nothing is fetched" \
		'test "$(grep -cE "(src|href)[[:space:]]*=" status/index.html)" = "0"'
	# The one absolute URL in the file is the demo host inside the empty-state
	# copy, which UI-SPEC's copywriting contract mandates verbatim. It is a string
	# the presenter reads aloud, not an origin the page contacts.
	assert "UI-SPEC 2 no absolute URL to any origin other than localhost or the demo host" \
		'test "$(grep -oE "https?://[^ \")]+" status/index.html | grep -vcE "localhost|app\.demo\.test")" = "0"'

	# --- T-02-01: the render discipline cannot be undone by a later edit ---
	#
	# A request path is attacker-influenced, travels verbatim through $uri into
	# the evidence log and onto the projector. textContent is the whole
	# mitigation, so every markup-parsing sink is asserted absent — not just the
	# one that happens to be idiomatic today.
	assert "T-02-01 no markup-parsing assignment sink exists in status/index.html" \
		'test "$(grep -cE "innerHTML|outerHTML|insertAdjacentHTML|document\.write|createContextualFragment" status/index.html)" = "0"'
	# One funnel, not a convention. Every log-derived value reaches the DOM
	# through the single `txt()` helper, so there is exactly one assignment to
	# audit rather than a habit to trust.
	assert "T-02-01 exactly one textContent assignment exists — the shared txt() funnel" \
		'test "$(grep -c "\.textContent *=" status/index.html)" = "1"'
	assert "T-02-01 the rendered cells actually go through that funnel" \
		'test "$(grep -o "txt(" status/index.html | wc -l | tr -d "[:space:]")" -ge 10'

	# --- UI-SPEC long-text backstop: the truncation is real, not incidental ---
	#
	# A NOTE ON HOW TO TEST THIS BY HAND. The evidence log records `path` from
	# $uri, which has the query string STRIPPED ($request_uri keeps it, in a
	# separate field). So `/whoami?trace=<something very long>` logs as `/whoami`
	# — 7 characters — and any "long path" check driven that way passes without
	# ever reaching the 28-character threshold. Use a long path SEGMENT:
	#
	#   curl -sS -o /dev/null http://localhost:9092/whoami/this-is-a-deliberately-long-path-segment-well-past-twenty-eight-characters
	#
	# The server deliberately stores the full string — truncating lossily at the
	# source would destroy evidence — so truncation is a rendering concern, and
	# these are its three prerequisites. `nowrap` is the load-bearing one: it is
	# what guarantees the uniform row height the boundary rule's pixel position
	# depends on.
	assert "UI-SPEC long-text: rows clip rather than wrap" \
		'grep -E "^\.row span\{" status/index.html | grep -q "overflow: *hidden" && grep -E "^\.row span\{" status/index.html | grep -q "white-space:nowrap"'
	assert "UI-SPEC long-text: the path cell ends in an ellipsis" \
		'grep -E "^\.row \.c-path\{" status/index.html | grep -q "text-overflow:ellipsis"'
	assert "UI-SPEC long-text: the path column is a fixed width, so nothing reflows" \
		'grep -q "grid-template-columns: .75rem 12.5rem 38.75rem 7.5rem 14rem;" status/index.html'
	assert "UI-SPEC long-text: the renderer routes the path through the 28-char helper" \
		'test "$(grep -c "var PATH_MAX = 28;" status/index.html)" = "1" && grep -q "shortPath(r.path)" status/index.html'

	# --- D-22: the hostname, everywhere, in the reserved form ---
	#
	# The mDNS variant stalls host name resolution for about five seconds on the
	# presenter's machine, on stage, with no error. `.test` is reserved by RFC
	# 6761 precisely so it cannot. No other assertion in this suite would catch a
	# single stray occurrence.
	# The label deliberately does not spell the token out: this assertion greps
	# scripts/, which includes this file, and a literal occurrence here would
	# make the check report on its own label.
	assert "D-22 every demo-hostname token in the repo is the reserved .test form" \
		'test "$(grep -rhoE "app\.demo\.[a-z]*" status/ scripts/ proxy/ Makefile compose.yaml README.md | sort -u | grep -vc "^app\.demo\.test$")" = "0"'

	# --- T-02-16: the repository still never modifies host state ---
	#
	# Phase 1's control, re-asserted after Phase 2's additions. The escalation
	# token may appear in README prose and in `make status`'s printed remediation
	# line; it may never appear in a recipe position.
	# Two assertions rather than one. The first pins the executable trio to a
	# single occurrence — the printed remediation line and nothing else — and is
	# exact. The second covers this file, where an exact count is impossible
	# because the audit necessarily names the token it audits; there the rule is
	# that any occurrence must sit on a line that also prints.
	assert "T-02-16 the Makefile, flip.sh and compose carry exactly one escalation token" \
		'test "$(grep -v "^[[:space:]]*#" Makefile scripts/flip.sh compose.yaml | grep -c "sudo")" = "1"'
	assert "T-02-16 and that one occurrence is inside a printed remediation line, not a recipe" \
		'test "$(grep -v "^[[:space:]]*#" Makefile scripts/flip.sh compose.yaml | grep "sudo" | grep -cE "(echo|printf)")" = "1"'
	# And nowhere in the four files does the token appear in a RECIPE position —
	# first word of a line, or first word after a pipe or a command separator.
	# This one is stated structurally rather than by counting, so it holds for
	# this file too without the audit tripping over its own text.
	assert "T-02-16 the escalation token never appears in a command position anywhere" \
		'test "$(grep -cE "(^[[:space:]]*|[;&(] *)sudo " Makefile scripts/flip.sh scripts/smoke.sh compose.yaml | grep -vc ":0$")" = "0"'

	# ---- leave the rig the way the presenter expects to find it ----
	sh scripts/flip.sh old >/dev/null 2>&1
	settle_flip old
	assert "CUT-05 the section ends with the rig selecting OLD" \
		'curl -fsS http://localhost:9092/whoami | grep -q "^OLD server-old$"'

	rm -f "$_evtmp" "$_out" "$_base"
	finish_flip_state
}

# BACK-04 / BACK-05: SSH into a named backend, and the backend saying who it is
# the instant the connection opens.
#
# This section is NON-DESTRUCTIVE — it neither rewrites the selector nor stops a
# container — so unlike guard_check() and section_cutover() it installs no trap.
section_ssh() {
	echo "--- ssh ---"

	# The shared SSH option set every assertion in this phase uses.
	#
	# EXPORTED, and that is not stylistic: assert runs its condition through a
	# fresh `sh -c`, which inherits exported VARIABLES but not shell functions.
	# A helper function would be invisible inside an assertion; this is not.
	#
	#   BatchMode=yes    kills every interactive prompt. Without it a missing key
	#                    falls back to a password prompt and blocks forever.
	#   ConnectTimeout=5 bounds the TCP connect ONLY — not auth, not the banner.
	#
	# The two host-key options are DEMO-ONLY and they are here for one specific
	# reason: Phase 4 deliberately stages a host-key mismatch between the two
	# backends. Without them every routing assertion in this suite would start
	# failing for the wrong reason the moment KEY-02 lands — a host-key error
	# reported as a routing error. Relaxing host-key checking is never the
	# default anywhere else in this repo: the client's own ssh config sets no
	# such option, because that default behaviour is Phase 4's raw material.
	#
	# Two things are deliberately ABSENT, and each absence is load-bearing:
	#
	#   - Any quiet or log-level-lowering option. Research measured each of them
	#     suppressing the banner ENTIRELY, turning the captured output into the
	#     empty string. That is how BACK-04 gets broken by a future maintainer
	#     "cleaning up noisy output"; the guards at the foot of this section
	#     exist to catch exactly that.
	#   - Any forced-pty option. The banner needs no pty, and a forced pty with
	#     no stdin was measured hanging indefinitely.
	export SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

	# The `client` service has no healthcheck, deliberately — D-02 makes it a
	# command source, not a service — so `docker compose up -d --wait` returns
	# before its entrypoint has finished writing the key. Nothing in the running
	# rig is affected, because sshd re-reads AuthorizedKeysFile on every
	# authentication attempt, but a probe fired immediately after a bring-up can
	# lose the race. Poll rather than assume.
	_i=0
	while [ "$_i" -lt 10 ]; do
		docker compose exec -T server-old test -f /keys/authorized_keys >/dev/null 2>&1 && break
		_i=$((_i + 1))
		sleep 1
	done

	# ---- the capture idiom used by every ssh assertion below ----
	#
	# Assign the invocation into a variable with command substitution, folding
	# stderr into stdout, and read the exit status on the VERY NEXT line. The
	# invocation is NEVER placed on the left of a pipe: a pipeline reports the
	# LAST command's status, and research measured `ssh ... | head` returning 0
	# while the output read `Host key verification failed.` Grepping the captured
	# VARIABLE afterwards is fine — the prohibition is on piping the invocation.
	#
	# 2>&1 is mandatory: the banner arrives on stderr, the remote command's
	# result on stdout, and both are needed.
	#
	# `timeout 10` wraps every invocation and is also mandatory. ConnectTimeout
	# does not cover the post-connect banner exchange or auth, so a proxy that
	# accepts the TCP connection while the upstream never replies would hang on
	# sshd's 120s login grace period. timeout in this image returns 143 on
	# SIGTERM, not 124 — test that the status is non-zero, never for a code.

	# ---- BACK-05: non-interactive key auth into both backends, directly ----
	#
	# No -i flag and no password: the key comes from the client's own ssh config.
	# A pass here is also the confirmation of research assumption A2 — the client
	# writes the key only AFTER both backends are already running, and no HUP is
	# ever issued anywhere, so key auth can only succeed if sshd re-reads
	# AuthorizedKeysFile per authentication attempt.
	assert "BACK-05 client -> server-old: key auth, non-interactive, no -i flag" \
		'out=$(docker compose exec -T client timeout 10 ssh $SSH_OPTS demo@server-old hostname 2>&1)
		 rc=$?
		 test "$rc" -eq 0 && printf "%s\n" "$out" | grep -qx "server-old"'
	assert "BACK-05 client -> server-new: key auth, non-interactive, no -i flag" \
		'out=$(docker compose exec -T client timeout 10 ssh $SSH_OPTS demo@server-new hostname 2>&1)
		 rc=$?
		 test "$rc" -eq 0 && printf "%s\n" "$out" | grep -qx "server-new"'

	# ---- BACK-05: the EFFECTIVE sshd config, not what the file claims ----
	#
	# This is `sshd -T` and NOT a grep of sshd_config, and the distinction is the
	# whole point. Alpine's stock config carries an ACTIVE AuthorizedKeysFile
	# directive well BELOW its drop-in Include line, and sshd uses the FIRST
	# value it obtains for a keyword — so an appended override is accepted in
	# silence and never takes effect, producing a generic permission-denied that
	# reads like a key problem. `sshd -T` reports the effective value and is the
	# only check that catches it.
	assert "BACK-05 effective config: server-old authorizedkeysfile is the shared volume" \
		'docker compose exec -T server-old sshd -T | grep -qix "authorizedkeysfile /keys/authorized_keys"'
	assert "BACK-05 effective config: server-new authorizedkeysfile is the shared volume" \
		'docker compose exec -T server-new sshd -T | grep -qix "authorizedkeysfile /keys/authorized_keys"'
	assert "BACK-04 effective config: server-old banner path took effect" \
		'docker compose exec -T server-old sshd -T | grep -qix "banner /etc/ssh/banner"'
	assert "BACK-04 effective config: server-new banner path took effect" \
		'docker compose exec -T server-new sshd -T | grep -qix "banner /etc/ssh/banner"'

	# D-41: `demo:demo` survives as the DOCUMENTED fallback so a presenter can
	# demo from their own terminal. Nothing in this phase may disable it.
	assert "D-41 fallback intact: server-old still accepts password authentication" \
		'docker compose exec -T server-old sshd -T | grep -qix "passwordauthentication yes"'
	assert "D-41 fallback intact: server-new still accepts password authentication" \
		'docker compose exec -T server-new sshd -T | grep -qix "passwordauthentication yes"'

	# ---- BACK-04 / D-43: the identity, from a remote command with NO stdout ----
	#
	# `true` produces nothing, so the captured line can ONLY have come from the
	# pre-auth banner. And this is `ssh host <command>`, which never runs a login
	# shell — so a pass here IS the proof that the mechanism is sshd's Banner and
	# not /etc/motd. Research measured motd as ABSENT for this invocation shape
	# even with a forced pty; motd is not an alternative here, it is a wrong
	# answer.
	assert "BACK-04 server-old names itself pre-auth (remote command emits no stdout)" \
		'out=$(docker compose exec -T client timeout 10 ssh $SSH_OPTS demo@server-old true 2>&1)
		 rc=$?
		 test "$rc" -eq 0 && printf "%s\n" "$out" | grep -qx "OLD server-old"'
	assert "BACK-04 server-new names itself pre-auth (remote command emits no stdout)" \
		'out=$(docker compose exec -T client timeout 10 ssh $SSH_OPTS demo@server-new true 2>&1)
		 rc=$?
		 test "$rc" -eq 0 && printf "%s\n" "$out" | grep -qx "NEW server-new"'

	# ---- BACK-04 empty edge ----
	#
	# A backend with no identity must never render a banner at all. The
	# complementary half — a backend with an empty BACKEND_ID refusing to start
	# in the first place — is already asserted in section_backends.
	assert "BACK-04 empty edge: server-old /etc/ssh/banner is non-empty and names an identity" \
		'docker compose exec -T server-old test -s /etc/ssh/banner &&
		 docker compose exec -T server-old cat /etc/ssh/banner | grep -qxE "(OLD|NEW) [a-z0-9.-]+"'
	assert "BACK-04 empty edge: server-new /etc/ssh/banner is non-empty and names an identity" \
		'docker compose exec -T server-new test -s /etc/ssh/banner &&
		 docker compose exec -T server-new cat /etc/ssh/banner | grep -qxE "(OLD|NEW) [a-z0-9.-]+"'

	# ---- BACK-04 ordering edge ----
	#
	# Exactly two fields in fixed order — identity, single space, hostname — on a
	# single line, anchored the same way section_backends anchors /whoami.
	assert "BACK-04 ordering edge: server-old banner is one line of exactly two fields" \
		'docker compose exec -T server-old cat /etc/ssh/banner | awk "NF!=2{bad=1} END{exit (bad || NR!=1)}"'
	assert "BACK-04 ordering edge: server-new banner is one line of exactly two fields" \
		'docker compose exec -T server-new cat /etc/ssh/banner | awk "NF!=2{bad=1} END{exit (bad || NR!=1)}"'
	assert "BACK-04 ordering edge: server-old banner is exactly OLD server-old" \
		'docker compose exec -T server-old cat /etc/ssh/banner | grep -qE "^OLD server-old$"'
	assert "BACK-04 ordering edge: server-new banner is exactly NEW server-new" \
		'docker compose exec -T server-new cat /etc/ssh/banner | grep -qE "^NEW server-new$"'

	# D-16: the SSH identity and the HTTP identity come from ONE variable, so the
	# two surfaces cannot drift. Asserted as string equality, not as two greps
	# that happen to agree.
	assert "D-16 server-old: the ssh banner and the HTTP /whoami body are the identical string" \
		'b=$(docker compose exec -T server-old cat /etc/ssh/banner | tr -d "\r"); w=$(curl -fsS http://localhost:9090/whoami); test -n "$b" && test "$b" = "$w"'
	assert "D-16 server-new: the ssh banner and the HTTP /whoami body are the identical string" \
		'b=$(docker compose exec -T server-new cat /etc/ssh/banner | tr -d "\r"); w=$(curl -fsS http://localhost:9091/whoami); test -n "$b" && test "$b" = "$w"'

	# ---- BACK-04 adjacency edge ----
	#
	# In ONE captured stream the banner's identity line must appear strictly
	# BEFORE the remote command's own stdout, because Banner is emitted pre-auth.
	assert "BACK-04 adjacency edge: the banner precedes the remote command's own stdout" \
		'out=$(docker compose exec -T client timeout 10 ssh $SSH_OPTS demo@server-old hostname 2>&1)
		 rc=$?
		 test "$rc" -eq 0 || exit 1
		 printf "%s\n" "$out" | awk "/^OLD server-old\$/{b=NR} /^server-old\$/{h=NR} END{exit !(b>0 && h>0 && b<h)}"'

	# ---- T-03-01: the keypair exists only inside the named volume ----
	#
	# A private key in git reads as a real credential leak to anyone who clones
	# or scans this repo, however obviously throwaway it is — unlike `demo:demo`,
	# which is visibly a joke. The keys live in a Docker named volume, never on
	# the host filesystem, which is also why no .gitignore entry is needed.
	assert "T-03-01 no key material is tracked by git" \
		'test -z "$(git ls-files | grep -iE "authorized_keys|ed25519|id_rsa")"'

	# ---- T-03-05: StrictModes for a path outside the user's home ----
	assert "T-03-05 server-old /keys/authorized_keys is mode 644 owned by root" \
		'test "$(docker compose exec -T server-old stat -c "%a %U" /keys/authorized_keys | tr -d "\r")" = "644 root"'
	assert "T-03-05 server-new /keys/authorized_keys is mode 644 owned by root" \
		'test "$(docker compose exec -T server-new stat -c "%a %U" /keys/authorized_keys | tr -d "\r")" = "644 root"'

	# ---- guards over this section's own text ----
	#
	# Every literal below is written with a bracket expression so this audit's
	# own source lines cannot satisfy the patterns it audits — the same trick
	# section_cutover uses for the escalation-token check.
	#
	# The extraction range is anchored on the function's opening line and a
	# column-zero closing brace. If it ever failed to bind, every region-scoped
	# check would pass VACUOUSLY against zero lines, so the range is asserted
	# non-empty first.
	assert "BACK-04 guard: the extraction range binds to a non-empty region" \
		'test "$(awk "/^section_[s]sh\(\) \{/,/^\}/" scripts/smoke.sh | grep -c .)" -gt 20'
	assert "BACK-04 guard: no quiet, log-level-lowering or forced-pty ssh option in this section" \
		'test "$(awk "/^section_[s]sh\(\) \{/,/^\}/" scripts/smoke.sh | grep -v "^[[:space:]]*#" | grep -cE "(^|[[:space:]])[-]q([[:space:]]|$)|LogL[e]vel=|[[:space:]][-]tt([[:space:]]|$)")" = "0"'
	assert "BACK-04 guard: no ssh invocation sits on the left of a pipe in this section" \
		'test "$(awk "/^section_[s]sh\(\) \{/,/^\}/" scripts/smoke.sh | grep -v "^[[:space:]]*#" | grep -c "s[s]h .*|")" = "0"'
}

section=${1:-all}
case "$section" in
backends) section_backends ;;
proxy) section_proxy ;;
redirect) section_redirect ;;
cutover) section_cutover ;;
ssh) section_ssh ;;
all)
	section_backends
	section_proxy
	section_redirect
	section_cutover
	# AFTER cutover, deliberately: that section leaves the rig selecting OLD,
	# which is the state this one expects to find.
	section_ssh
	;;
*)
	echo "usage: sh scripts/smoke.sh [backends|proxy|redirect|cutover|ssh|all]" >&2
	exit 2
	;;
esac

echo "--- $PASSES passed, $FAILURES failed ---"
test "$FAILURES" -eq 0
