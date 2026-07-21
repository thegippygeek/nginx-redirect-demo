# Makefile — the presenter's command surface (D-19).
#
# Convenience only (D-20): raw `docker compose up -d --wait` works standalone.
# GNU Make 3.81 compatible — macOS ships that 2006 release. Plain `target:`
# plus tab-indented recipe lines only; no Make 4.x-era directives or
# functions, and no custom recipe prefix.
#
# `contrast` (plan 01-03) and `reload` (plan 01-02) are declared here so the
# target vocabulary is stable from the start; their recipes arrive with the
# plans that own them.

.PHONY: up down status logs logs-demo test reset contrast reload check flip flip-old flip-new verify clear-evidence ssh fix-hostkeys rearm

# The evidence volume survives `docker compose down` and is removed only by
# `down -v`, so without the truncation below a down+up cycle would resume a
# previous take's counters mid-count — exactly the "looks second-hand" failure
# D-36 exists to prevent. Raw `docker compose up -d --wait` still works
# standalone (D-20) and simply inherits the prior log; `make` is the presenter
# surface, and `make clear-evidence` is the explicit lever.
up:
	docker compose up -d --build --wait
	@docker compose exec -T proxy sh -c ': > /var/log/demo/access.log'
	@echo "evidence log cleared — this take starts from zero"
	@$(MAKE) status

down:
	docker compose down

status:
	docker compose ps --format 'table {{.Service}}\t{{.Status}}\t{{.Ports}}'
	@grep -q 'app.demo.test' /etc/hosts && echo "hosts: OK  app.demo.test -> 127.0.0.1" || echo "hosts: MISSING — one-time setup (D-03), run:  echo '127.0.0.1  app.demo.test' | sudo tee -a /etc/hosts"

check: status

# D-30/D-32: the raw view, all three services. Seeing the request ARRIVE at the
# backend is what proves it truly landed there rather than being served from
# somewhere upstream. The extra noise is the price of that proof.
logs:
	docker compose logs -f proxy server-old server-new

# D-31: the same log, made legible from the back of a room. Timestamps come from
# Docker (-t), so log_format demo is not touched at all — it stays realistic,
# which is what supports the "this is what you'd actually see in production"
# claim, and two Phase 1 assertions grep it.
#
# Matched by REGEX on the backend= token, never by field position: indices shift
# by one when -t is added and by two more under the `proxy-1  |` service prefix,
# and D-32 requires that prefix. Colour is a terminal concern — it deliberately
# does not go into a config file the presenter shows on screen.
#
# Note the doubled $$ — Make consumes a single $ (RESEARCH Pitfall 9).
logs-demo:
	docker compose logs -f -t proxy server-old server-new | awk '\
	  /backend=NEW/ { printf "\033[1;97;42m NEW \033[0m %s\n", $$0; next } \
	  /backend=OLD/ { printf "\033[1;97;43m OLD \033[0m %s\n", $$0; next } \
	  { print }'

test:
	sh scripts/smoke.sh

# D-21: a full teardown AND a restore of the flip include. `down -v` removes
# containers, volumes and networks — it does not touch host files, so without
# the rewrite below a previous take's flip would leave the demo opening on NEW.
#
# The rewritten content is the FULL canonical five-line file, both comment lines
# included. Those comments ARE the mechanism by which the Phase 2 flip reads on
# screen (D-12); restoring only the map body would silently strip them on the
# first reset. Keep this byte-identical to proxy/active-backend.conf.
#
# Note the doubled $$ — Make consumes a single $ (RESEARCH Pitfall 9).
reset:
	docker compose down -v
	printf '# proxy/active-backend.conf — THE ONLY FILE THE PRESENTER EDITS\n# Change `old` to `new` to cut over. Nothing else.\nmap $$server_port $$active_backend {\n    default old;\n}\n' > proxy/active-backend.conf
	docker compose up -d --build --wait
	@$(MAKE) status

# D-09 / HTTP-04: the technical backup view for when a projector cannot show a
# URL bar. Two labelled lines, one command. `%{url_effective}` after -L is the
# cleanest single-line proof there is — far easier to read on stage than
# `curl -v`. Unlike the browser path this is immune to the 301 cache
# (RESEARCH Pitfall 7): curl does not cache.
#
# --resolve is what lets this run BEFORE the D-03 /etc/hosts step. The redirect
# target is a literal app.demo.test:9090, so following it needs that name to
# resolve; --resolve supplies it for this one invocation only, touching no host
# state. Without it the hop dies with "Could not resolve host" on a machine that
# has not done the prerequisite yet. It changes nothing the demo claims — the
# URL the client ends on is still the backend's, which is the entire point.
contrast:
	@echo "PROXIED   9092 -> "
	@curl -sSL -o /dev/null -w '  final=%{url_effective}  redirects=%{num_redirects}\n' http://localhost:9092/whoami
	@echo "REDIRECT  9093 -> "
	@curl -sSL --resolve app.demo.test:9090:127.0.0.1 -o /dev/null -w '  final=%{url_effective}  redirects=%{num_redirects}\n' http://localhost:9093/whoami

# D-14 + RESEARCH Pitfall 3: test, then reload, then verify. Never
# `docker compose restart proxy` — that contradicts D-14 and throws away the
# zero-downtime point. Phase 2's `make flip` inherits this discipline.
reload:
	docker compose exec proxy nginx -t
	docker compose exec proxy nginx -s reload
	@sleep 1 && curl -fsS http://localhost:9092/whoami

# D-33: both command shapes ship. `flip` toggles whatever is currently selected
# and is the memorable money-shot command; the named targets are unfumbleable
# when you have lost your place on stage.
#
# The recipe body lives in the script, not here: the sequence needs a retry loop
# and early exits, and Make 3.81 without a one-shell directive runs every recipe
# line in its own shell.
flip:
	@sh scripts/flip.sh toggle

flip-old:
	@sh scripts/flip.sh old

flip-new:
	@sh scripts/flip.sh new

# EVID-04/EVID-05: did the cutover land, on BOTH protocols? One HTTP request,
# one SSH connection, one labelled line each, and a non-zero exit when the
# answer is wrong. `make verify` alone checks the state the demo opens and
# closes in; `make verify EXPECT=new` is the explicit form to use after a flip.
#
# The recipe body lives in the script for the same reason `flip`'s does: the
# sequence needs early exits and a distinct exit-code vocabulary, and Make 3.81
# without a one-shell directive runs every recipe line in its own shell.
EXPECT ?= old
verify:
	@sh scripts/verify.sh $(EXPECT)

# make ssh — PRESENTER MODE (D-52), and the only mode in which the Phase 4
# host-key gotcha is reachable.
#
# There are exactly TWO named connection modes in this repository and they have
# opposite intentions about trust:
#
#   TEST MODE      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
#                  lives in scripts/verify.sh and smoke.sh's section_ssh, each
#                  with an inline demo-only justification. It DISCARDS trust so
#                  that 186 routing assertions cannot trip over a host-key
#                  change. Neither of those pins may ever appear below.
#   PRESENTER MODE this target. It REMEMBERS trust, so a changed host key is the
#                  only thing you see.
#
# `accept-new` IS NOT `no`, and the difference matters to every person watching
# this typed on a projector: it records an UNSEEN host silently — no
# trust-on-first-use prompt, no dead air on the priming beat — and it STILL
# refuses a CHANGED key with the full warning banner (measured, rc=255). This
# demo must never teach a room to switch host-key verification off.
#
# UpdateHostKeys=no — without it OpenSSH rewrites the client's own trust record
# on the first successful post-fix connection, appending the server's other host
# keys and leaving a backup behind (measured: 95 bytes becoming 837, plus a
# known_hosts.old, with nobody touching anything). With it pinned, KEY-04's "no
# client-side edit" is a checksum comparison rather than a claim about intent.
#
# DOCKER_CLI_HINTS=false — Compose appends a trailing "What's next" hint block
# after any NON-ZERO exec, but only when output is a terminal. So it never shows
# in the test suite and always shows on the projector, directly underneath the
# failure the room is meant to be reading.
#
# NO trust-record path is named here, deliberately (D-48 as corrected by
# research). The default location in the client container's writable layer is
# what couples the client's trust lifetime to the backends' key lifetime; naming
# a path is the first step toward a persistence mechanism that would survive
# `docker compose down` and make the gotcha fire BEFORE the flip.
#
# The destination is hard-coded to the PROXIED hostname. The trust record is
# keyed on the name the client typed, so a connection made to a backend's own
# service name records a different, useless entry and the gotcha will not fire.
ssh:
	@DOCKER_CLI_HINTS=false docker compose exec client ssh \
	  -o StrictHostKeyChecking=accept-new -o UpdateHostKeys=no \
	  demo@app.demo.test

# D-50: the fix, as one memorable command. It gives server-new server-old's host
# keys AND signals the running daemon to load them — sshd caches its keys in
# memory at startup, so the transfer alone is a measured silent no-op (D-59).
# Never narrate this as "we copied the keys".
#
# The recipe body lives in the script for the same reason `flip`'s and
# `verify`'s do: the sequence needs early exits, and Make 3.81 without a
# one-shell directive runs every recipe line in its own shell.
fix-hostkeys:
	@sh scripts/fix-hostkeys.sh

# D-51: the between-takes fast path, about a second, in place, no rebuild.
# `make reset` remains the documented headline re-arm — it also regenerates BOTH
# backends' keys and rebuilds, at a measured 16.5 s. Use this one when you are
# running takes back to back.
rearm:
	@sh scripts/rearm.sh

# D-36, as an explicit lever. Truncate, never unlink: nginx holds the descriptor
# and would keep writing into an unlinked inode. Issued into the PROXY
# container — the status service's mount is read-only by design.
clear-evidence:
	@docker compose exec -T proxy sh -c ': > /var/log/demo/access.log'
	@echo "evidence log cleared — the next take starts from zero"
