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

reset:
	docker compose down -v
	docker compose up -d --build --wait
	@$(MAKE) status
