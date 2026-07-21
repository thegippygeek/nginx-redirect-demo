---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_phase: 1
current_phase_name: Demo Up, HTTP Lands on OLD
status: executing
stopped_at: Completed 01-01-PLAN.md
last_updated: "2026-07-21T06:07:06.715Z"
last_activity: 2026-07-21
last_activity_desc: Phase 1 execution started
progress:
  total_phases: 1
  completed_phases: 0
  total_plans: 3
  completed_plans: 1
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-07-21)

**Core value:** A live, on-stage flip of the nginx upstream from old to new where the client keeps hitting the same hostname and port, and unmistakably lands on the new server.
**Current focus:** Phase 1 — Demo Up, HTTP Lands on OLD

## Current Position

Phase: 1 (Demo Up, HTTP Lands on OLD) — EXECUTING
Plan: 2 of 3
Status: Ready to execute
Last activity: 2026-07-21 — Phase 1 execution started

Progress: [███░░░░░░░] 33%

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

### Pending Todos

None yet.

### Blockers/Concerns

- Port 22 on the host may already be bound by the laptop's own sshd — Phase 1/3 must confirm the mapping strategy that keeps "no client change" honest.

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none)* | | | |

## Session Continuity

Last session: 2026-07-21T06:07:06.707Z
Stopped at: Completed 01-01-PLAN.md
Resume file: None
