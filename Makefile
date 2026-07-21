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

.PHONY: up down status logs test reset contrast reload check

up:
	docker compose up -d --build --wait
	@$(MAKE) status

down:
	docker compose down

status:
	docker compose ps --format 'table {{.Service}}\t{{.Status}}\t{{.Ports}}'
	@grep -q 'app.demo.local' /etc/hosts && echo "hosts: OK  app.demo.local -> 127.0.0.1" || echo "hosts: MISSING — one-time setup (D-03), run:  echo '127.0.0.1  app.demo.local' | sudo tee -a /etc/hosts"

check: status

logs:
	docker compose logs -f proxy

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
# target is a literal app.demo.local:9090, so following it needs that name to
# resolve; --resolve supplies it for this one invocation only, touching no host
# state. Without it the hop dies with "Could not resolve host" on a machine that
# has not done the prerequisite yet. It changes nothing the demo claims — the
# URL the client ends on is still the backend's, which is the entire point.
contrast:
	@echo "PROXIED   9092 -> "
	@curl -sSL -o /dev/null -w '  final=%{url_effective}  redirects=%{num_redirects}\n' http://localhost:9092/whoami
	@echo "REDIRECT  9093 -> "
	@curl -sSL --resolve app.demo.local:9090:127.0.0.1 -o /dev/null -w '  final=%{url_effective}  redirects=%{num_redirects}\n' http://localhost:9093/whoami

# D-14 + RESEARCH Pitfall 3: test, then reload, then verify. Never
# `docker compose restart proxy` — that contradicts D-14 and throws away the
# zero-downtime point. Phase 2's `make flip` inherits this discipline.
reload:
	docker compose exec proxy nginx -t
	docker compose exec proxy nginx -s reload
	@sleep 1 && curl -fsS http://localhost:9092/whoami
