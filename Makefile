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

.PHONY: up down status logs logs-demo test reset contrast reload check flip flip-old flip-new clear-evidence

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

# D-36, as an explicit lever. Truncate, never unlink: nginx holds the descriptor
# and would keep writing into an unlinked inode. Issued into the PROXY
# container — the status service's mount is read-only by design.
clear-evidence:
	@docker compose exec -T proxy sh -c ': > /var/log/demo/access.log'
	@echo "evidence log cleared — the next take starts from zero"
