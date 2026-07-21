---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_phase: 1
current_phase_name: Demo Up, HTTP Lands on OLD
status: planning
stopped_at: Phase 1 context gathered
last_updated: "2026-07-21T04:49:30.736Z"
last_activity: 2026-07-21
last_activity_desc: Roadmap created, 33/33 v1 requirements mapped across 4 phases
progress:
  total_phases: 1
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-07-21)

**Core value:** A live, on-stage flip of the nginx upstream from old to new where the client keeps hitting the same hostname and port, and unmistakably lands on the new server.
**Current focus:** Phase 1 — Demo Up, HTTP Lands on OLD

## Current Position

Phase: 1 of 4 (Demo Up, HTTP Lands on OLD)
Plan: 0 of TBD in current phase
Status: Ready to plan
Last activity: 2026-07-21 — Roadmap created, 33/33 v1 requirements mapped across 4 phases

Progress: [░░░░░░░░░░] 0%

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

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Init: Docker Compose locally instead of AWS/Terraform — zero cost, disposable, identical routing mechanics
- Init: nginx `stream` TCP proxy for SSH, not DNS cutover or ProxyJump
- Init: Show reverse proxy and 301 redirect side by side — the conceptual crux for the audience
- Init: Stage the SSH host-key mismatch rather than pre-solve it
- Roadmap: Four vertical MVP slices, each demoable on its own; walkthrough folded into the final gotcha phase rather than standing alone

### Pending Todos

None yet.

### Blockers/Concerns

- Port 22 on the host may already be bound by the laptop's own sshd — Phase 1/3 must confirm the mapping strategy that keeps "no client change" honest.

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none)* | | | |

## Session Continuity

Last session: 2026-07-21T04:49:30.724Z
Stopped at: Phase 1 context gathered
Resume file: .planning/phases/01-demo-up-http-lands-on-old/01-CONTEXT.md
