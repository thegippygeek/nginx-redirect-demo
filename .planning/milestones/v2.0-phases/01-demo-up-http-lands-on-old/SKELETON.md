# Walking Skeleton — Server Migration Redirect Demo

**Phase:** 1
**Generated:** 2026-07-21

## Capability Proven End-to-End

A presenter runs one `docker compose up`, sends a real HTTP request to `http://app.demo.test:9092/whoami` from either the host browser or the in-network `client` container, and gets back a body naming `server-old` as the backend that answered — with the URL unchanged and the serving backend visible by name in the proxy's access log.

That is the whole spine: **compose up → one real request through nginx → landing on an identified backend → observable in logs.** Every later phase adds a slice on top of that spine without renegotiating it.

## Architectural Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Orchestration | Docker Compose v2+ (`compose.yaml`, `name: demo`, no `version:` key) | ENV-01 names it directly. `depends_on: condition: service_healthy` is load-bearing here, not decorative — nginx resolves upstream hostnames at config-parse time and aborts if Docker DNS cannot answer, so the health gate is what makes cold start deterministic. |
| Proxy image | `nginx:1.30-alpine` (stable line, pinned minor) | Every official nginx variant ships `--with-stream` [VERIFIED across four variants], so ENV-04 imposes no real constraint. Chosen on size and version stability instead — a demo that must reproduce identically months later belongs on the stable line, not mainline. |
| Backend image | The SAME `nginx:1.30-alpine` base, one Dockerfile, built once as `demo-backend:1`, instantiated twice | D-16. One nginx version to explain on stage. `envsubst` is already present in the image, so `BACKEND_ID`-driven templating needs zero added packages. |
| Backend identity model | A runtime `BACKEND_ID` parameter (`OLD` \| `NEW`), never a per-backend image | The generalized primary noun is `backend`; `OLD`/`NEW` is demoted to a per-instance parameter. A third backend, or Phase 4's re-keyed `server-new`, needs no new image. |
| Two processes per backend | `supervisord` as the container's supervisor, `init: true` for tini as PID 1 | D-17 requires nginx and sshd co-located so the Phase 4 host-key story sits on the same box. `supervisord` chosen over `s6-overlay` for explainability: a 14-line config that reads on screen beats a multi-file service tree. `autorestart=true` means a dead sshd cannot silently break Phase 3. |
| Template rendering | An explicit `ENTRYPOINT` in the backend image running `envsubst` with a three-variable allowlist, then `exec "$@"` | The base image's own `/docker-entrypoint.d/` machinery guards on `$1 = nginx` and silently no-ops under a supervisor `CMD` — the direct D-16 + D-17 collision. Templates live at `/templates/`, deliberately not `/etc/nginx/templates/`, so nobody later assumes the image's mechanism is in play. |
| SSH host key generation | `ssh-keygen -A` at container start, inside the entrypoint — never in a Dockerfile layer | A build-time generation bakes identical keys into both backends (one image), making Phase 4's KEY-01 unstageable. Runtime generation satisfies KEY-01 for free and keeps key material entirely out of the build context and out of git. |
| Flip mechanism | A `map` in a small include file selecting between pre-declared upstreams by name | D-12 (one-word edit in one small file) and D-13 (same include reusable from `stream` in Phase 3) are in tension: an `upstream {}` block cannot be shared across the `http` and `stream` contexts. Putting the SELECTOR rather than the TARGET in the shared file resolves both. Verified working from both contexts. |
| Flip safety | A `$backend_is_valid` map plus a `return 503` guard, living in `nginx.conf` not in the include | A typo'd selector passes `nginx -t`, reloads cleanly, then 502s on stage. The guard turns that into a legible message. It sits outside `active-backend.conf` so the file the audience reads during the flip stays three lines. |
| Config reload | `nginx -s reload` after `nginx -t`, never `docker compose restart` | D-14. A graceful reload is what you would do in production and it makes the zero-downtime point implicitly. `make reload` establishes test-then-reload-then-verify as the pattern `make flip` inherits in Phase 2. |
| Hostname resolution | Compose network `aliases: [app.demo.test]` on the proxy, plus a documented host `/etc/hosts` entry | The alias resolves the real hostname straight to the proxy container and preserves the client's real source IP in the log. `extra_hosts: host-gateway` was tested and rejected — it resolved to IPv6 and routed the client out to the host and back in. The browser runs outside Docker and needs the host entry (D-03). |
| Evidence / log format | A named `demo` `log_format` carrying `$host:$server_port`, `$upstream_addr`, and `$upstream_http_x_backend`, written to `/dev/stdout` | `backend=OLD`/`backend=NEW` is a word the audience can read from the back of the room as it flips — that is Phase 2's EVID-01. It only populates because the backends set `X-Backend` (D-11), so the header and the log format are one decision. stdout logging makes `docker compose logs -f proxy` the live tail with no volume mount. |
| Port binding | All published ports bound explicitly to `127.0.0.1` | Costs the demo nothing (D-03 maps the hostname to loopback anyway) and keeps a throwaway SSH credential off conference wifi. |
| Test approach | POSIX shell assertions in `scripts/smoke.sh`, section-dispatched | No language runtime exists or is required; adding a test framework would contradict ENV-03's "no prior setup". Phase 3's verify script (EVID-04/05) has the same shape, so it extends this script rather than introducing a second idiom. |
| Presenter surface | A `Makefile`, GNU Make 3.81-compatible only | D-19. macOS ships Make 3.81 (2006), so no `.ONESHELL:`, no `$(file ...)`, no `.RECIPEPREFIX`. D-20 keeps it strictly convenience — raw `docker compose up` works standalone. |
| Directory layout | `compose.yaml` + `Makefile` + `README.md` at root; `proxy/`, `backend/`, `client/`, `scripts/` | `proxy/active-backend.conf` sits at the top of `proxy/` rather than a subdirectory because the presenter will `cat` it on stage and a short path reads better. |

## Stack Touched in Phase 1

- [x] Project scaffold — `compose.yaml`, `Makefile`, `.gitignore`, `scripts/smoke.sh` (the test runner)
- [x] Routing — a real reverse-proxy route on 9092 and a real redirect route on 9093
- [x] "Data layer" equivalent — the flip include is the demo's single piece of mutable state; it is read at proxy start and re-read on reload, and `make reset` writes it back to a known-good value
- [x] UI — the OLD/NEW identity banner, served from a real container, reachable in a real browser
- [x] Full-stack run command — `docker compose up -d --wait` exercises every service end to end, gated on real healthchecks

## Out of Scope (Deferred to Later Slices)

Explicit, so later phases do not re-litigate Phase 1's minimalism:

- **The cutover itself.** No `make flip`, no upstream change, no reload-during-demo. Phase 2 (CUT-01..03, CUT-05).
- **The status page and live log narration.** Phase 2 (EVID-01..03). Phase 1 only guarantees the log format those depend on.
- **Any `stream` block.** D-15 is explicit. Phase 1 proves the module is compiled in and ships no stream config, which also keeps the base image's `*.stream-template` auto-append machinery dormant. Phase 3 (SSH-02).
- **SSH routing, host port 22, and the port-22 mapping strategy.** sshd is built and listening from Phase 1 (D-18) but nothing is routed and no host port is bound. Phase 3 settles the mapping; the `client` container is the intended path, keeping "no client change" honest with no host port and no client-side flag.
- **Host-key mismatch staging and the transfer fix.** Phase 4 (KEY-01..04). Phase 1's only obligation is to generate keys at runtime so the mismatch is stageable at all.
- **The written presenter walkthrough.** Phase 4 (WALK-01..03). Phase 1's `README.md` covers setup and command reference, not the narrative script.
- **Config-only fast flip-back.** Phase 2 (CUT-05). Phase 1 ships only the full teardown reset (D-21).
- **TLS/HTTPS, weighted traffic shifting, production hardening, real cloud infrastructure.** Out of scope for v1 entirely per `REQUIREMENTS.md`.

## Subsequent Slice Plan

Each later phase adds one vertical slice on top of this skeleton without altering its architectural decisions:

- **Phase 2 — The Live HTTP Cutover.** Edits the one-word selector in `proxy/active-backend.conf`, reloads, and the identical `curl` lands on `server-new`. Consumes the `demo` log format and the `X-Backend` header established here. Adds `make flip` and a status page.
- **Phase 3 — SSH Through the Stream Proxy.** Adds a `stream {}` block that includes THE SAME `active-backend.conf` file, with `upstream old`/`upstream new` pointing at port 22 in the stream namespace. Consumes the sshd already built into the backend image. Extends `scripts/smoke.sh` into the EVID-04/05 verify script.
- **Phase 4 — Host-Key Gotcha and the Presenter Walkthrough.** Exploits the per-container runtime host key generation established here to stage the mismatch, then documents the transfer fix and the full narrative.
