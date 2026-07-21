---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_phase: 3
current_phase_name: SSH Through the Stream Proxy
status: executing
stopped_at: Completed 03-02-PLAN.md
last_updated: "2026-07-21T11:52:31.453Z"
last_activity: 2026-07-21
last_activity_desc: Phase 3 execution started
progress:
  total_phases: 3
  completed_phases: 2
  total_plans: 10
  completed_plans: 9
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-07-21)

**Core value:** A live, on-stage flip of the nginx upstream from old to new where the client keeps hitting the same hostname and port, and unmistakably lands on the new server.
**Current focus:** Phase 3 — SSH Through the Stream Proxy

## Current Position

Phase: 3 (SSH Through the Stream Proxy) — EXECUTING
Plan: 3 of 3
Status: Ready to execute
Last activity: 2026-07-21 — Phase 3 execution started

Progress: [█████████░] 90%

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: —
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

*Updated after each plan completion*
**Per-Plan Metrics:**

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 01 P01 | 25 min | 3 tasks | 10 files |
| Phase 01 P02 | 5 min | 2 tasks | 5 files |
| Phase 01 P03 | 22 min | 3 tasks | 5 files |
| Phase 02 P01 | 35 min | 3 tasks | 6 files |
| Phase 02 P02 | 25 min | 3 tasks | 4 files |
| Phase 02 P03 | 42 min | 3 tasks | 1 files |
| Phase 02 P04 | 71 min | 2 tasks | 4 files |
| Phase 03 P01 | 38 min | 3 tasks | 7 files |
| Phase 03 P02 | 25 min | 2 tasks | 2 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Init: Docker Compose locally instead of AWS/Terraform — zero cost, disposable, identical routing mechanics
- Init: nginx `stream` TCP proxy for SSH, not DNS cutover or ProxyJump
- Init: Show reverse proxy and 301 redirect side by side — the conceptual crux for the audience
- Init: Stage the SSH host-key mismatch rather than pre-solve it
- Roadmap: Four vertical MVP slices, each demoable on its own; walkthrough folded into the final gotcha phase rather than standing alone
- [Phase 01]: SSH host keys are generated at container start in entrypoint.sh, never in a Dockerfile RUN layer — A build-time ssh-keygen -A bakes identical host keys into both backends (they share one image per D-16), which would make Phase 4 KEY-01's host-key-mismatch story unstageable without a rebuild.
- [Phase 01]: The backend image ships its own ENTRYPOINT and puts templates at /templates/, not /etc/nginx/templates/ — The nginx image's /docker-entrypoint.sh guards templating behind [ $1 = nginx ], so under a supervisord CMD it silently no-ops and serves the stock config. The neutral path stops future readers assuming the base mechanism is in play.
- [Phase 01]: Only server-old carries a build: key; server-new references demo-backend:1 by tag with depends_on — Makes the D-16 one-image invariant structural rather than conventional, and the smoke suite asserts both services resolve to one image ID.
- [Phase 01]: Selector-in-the-include, target-in-the-main-config: active-backend.conf holds a map choosing old|new; nginx.conf holds upstream old/new. Lets Phase 3 include the SAME file from a stream context (D-12 + D-13). — An upstream block cannot be shared between http and stream: separate namespaces and different ports (80 vs 22). Putting the selector rather than the target in the shared file resolves D-12 and D-13 simultaneously.
- [Phase 01]: active-backend.conf line 2 reworded to 'Nothing else.' so the make reset restore stays a single-quoted printf under GNU Make 3.81 and byte-identity holds. — An apostrophe in the canonical content would force awkward escaping inside the Make recipe that guarantees the D-12 presenter annotation survives a reset.
- [Phase 01]: D-22: demo hostname is app.demo.test, not app.demo.local — .local is RFC 6762 mDNS territory and macOS routes it to an mDNSResponder resolver that Tailscale leaves unreachable, stalling getaddrinfo 5s despite a correct /etc/hosts entry. .test is RFC 6761-reserved for exactly this. Phase 2+ must not reintroduce .local; the test suite cannot catch it.
- [Phase 01]: The 301 Location target is a literal address in proxy/nginx.conf, never $host-derived — readable on a projector and structurally incapable of being an open redirect (T-01-13).
- [Phase 01]: The redirect target is deliberately static and does not follow $active_backend: after Phase 2's flip, 9092 lands on NEW while 9093 still redirects to 9090/OLD. Intended — the contrast is about the mechanism, not the destination.
- [Phase 02]: Status container mounts ./proxy as a directory, not active-backend.conf as a single file — D-34 documents live-editing the file in an editor; an inode replacement would freeze a single-file mount on stale content, making a landed cutover read as permanently PENDING
- [Phase 02]: The evidence service derives everything from three inputs, never two — config unreadable OR log unreadable OR proxy not answering -> full UNAVAILABLE. The active proxy liveness probe is the only input that catches a dead proxy behind a still-readable log (D-28)
- [Phase 02]: boundary.row_index and since_flip_s are computed server-side and consumed verbatim by the page — Client-side re-derivation duplicates the windowing logic, and a client-side clock keeps counting while the service is dead
- [Phase 02]: Status page table row height ships at 52px, not UI-SPEC's 68px reference — UI-SPEC's own vertical numbers sum to ~1267px against a 1080px frame it also declares must never scroll; the no-scrollbar invariant outranks the derived row-height figure, and row uniformity is preserved exactly
- [Phase 02]: The recent-requests table edge bar renders white, not accent-on-accent — UI-SPEC specifies both a full-width accent row fill and an accent edge bar, which together make the bar invisible and delete a shape channel that is mandatory because OLD and NEW are isoluminant
- [Phase 02]: D1 closed by removing flip.sh's confirming request in the reset direction, not by reordering it — Truncate-then-request leaves one evidence line and breaks three CUT-05 assertions; the reset has nothing to seed by definition. Removing the request removes the race window itself — the page cannot see a truncation coming, so no client-side guard could make it deterministic.
- [Phase 02]: 02-UI-SPEC.md corrected in place: row height 68px to 52px, edge bar accent to #ffffff, long-path example query-string to path-segment — A contract that contradicts the artifact it specifies stops being a contract. Each correction carries its arithmetic or its reason, so a later reader can audit the change rather than trust it.
- [Phase 02]: The UI token audit lives in section_cutover(), and no mechanical guard is accepted until a deliberate violation has been shown to turn it red — A fifth section could run before status/index.html exists and would pass vacuously. Eight violations across seven classes were introduced, caught and reverted.
- [Phase 03]: SSH banner is one line, byte-identical to the backend's HTTP /whoami body, so one anchored grep proves identity over both protocols
- [Phase 03]: Demo keypair lives only in a demo-keys named volume, generated idempotently by client/entrypoint.sh; nothing key-shaped is ever committed
- [Phase 03]: Every sshd setting this phase adds goes through /etc/ssh/sshd_config.d/10-demo.conf; the check is sshd -T, never a grep of the config
- [Phase 03]: The stream log reuses the HTTP log's backend= field name so make logs-demo colours SSH lines free, with selector= on the same line and a config comment stating the provenance difference (proxy's own selector, not an observed identity)
- [Phase 03]: worker_shutdown_timeout stays unset (D-40): an in-flight SSH session survives the reload on its original backend, measured live by the smoke suite rather than asserted in prose
- [Phase 03]: Editing proxy/nginx.conf requires a proxy container recreate — it is a single-file bind mount and an inode-replacing edit leaves the container on stale config while nginx -t still reports success

### Pending Todos

None yet.

### Blockers/Concerns

- Port 22 on the host may already be bound by the laptop's own sshd — Phase 1/3 must confirm the mapping strategy that keeps "no client change" honest.
- scripts/flip.sh truncates the evidence AFTER its confirming request, so flip.sh old fires the status page convergence sequence ~1 time in 3 (measured). One-line structural fix logged in deferred-items.md D1; file is owned by 02-01, deferred to 02-04.

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none)* | | | |

## Session Continuity

Last session: 2026-07-21T11:52:22.301Z
Stopped at: Completed 03-02-PLAN.md
Resume file: None
