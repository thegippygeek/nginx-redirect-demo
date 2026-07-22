---
phase: 07-instant-rollback-v1-preservation-and-the-v2-walkthrough
plan: 02
subsystem: docs
tags: [walkthrough, presenter, smoke-test, executable-contract, makefile, migration-narrative]

# Dependency graph
requires:
  - phase: 07-01
    provides: "section_rollback + section_preserve and the rollback/checksum idioms the v2 walkthrough's final beats reference"
  - phase: 05/06
    provides: "the switch topology, pre-flip validation (make verify-new-stack), and the both-protocol flip the walkthrough narrates"
provides:
  - "WALKTHROUGH.md rewritten for the v2 11-beat narrative (validate app-new -> show old -> redirect contrast -> prime -> flip -> host-key gotcha -> wrong fix -> right fix -> instant rollback -> old-proxy-untouched -> reset)"
  - "make proxies-untouched presenter target (beat-10 Run command, shasum -a 256 of the two static configs) in .PHONY"
  - "section_walkthrough updated in lockstep so the executable-contract lint stays green against the new beat list"
affects: [milestone-audit, presenter]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "doc + executable-contract-lint updated in ONE atomic commit — a WALKTHROUGH.md rewrite without the section_walkthrough update would turn make test red"
    - "walkthrough beats reference only real make targets / binaries and resolvable paths (switch/active-proxy.conf, not the orphaned v1 active-backend.conf)"

key-files:
  created: []
  modified:
    - "WALKTHROUGH.md - full rewrite to the v2 11-beat narrative, Run/Expect/Say + takeaway per beat, real commands only"
    - "scripts/smoke.sh - section_walkthrough expectations updated in lockstep with the doc (step count derived, narrative keyword order, target/trap closure)"
    - "Makefile - added proxies-untouched target + .PHONY entry"

key-decisions:
  - "Host-key gotcha SURFACED as inherited v1 beats via existing make ssh / fix-hostkeys / rearm — not re-engineered or re-scoped"
  - "Rollback beat confirms with make verify (a positive assertion), not the flip-old-zeroed counters"
  - "MIG-02 automated half (walkthrough self-contained + lint green) is done; comprehensibility (criterion 4) is left as a BLOCKING human cold-read for the end-of-phase gate — not auto-claimed"

patterns-established:
  - "Lockstep doc/lint commits: any WALKTHROUGH.md structural change lands with its section_walkthrough contract update in the same commit"

requirements-completed: []
requirements-partial:
  - "MIG-02 - automated executable-contract half complete (make test 257/0, section_walkthrough green); comprehensibility cold-read pending as a blocking human checkpoint"

# Verification
verification:
  automated: "make test — 257 passed, 0 failed (includes the rewritten section_walkthrough lint: WALK-01/02/03 guards green)"
  manual-pending: "WALKTHROUGH.md comprehensibility cold-read (MIG-02 criterion 4) — a presenter runs the v2 narrative cold; no assertion can prove a room can follow it"

# Executor note
notes: "The Wave-2 executor was interrupted by a transient API error (ENOTFOUND) after committing both file tasks (c82cf19 make target, 0988d94 doc+lint lockstep). The orchestrator verified the lockstep landed atomically (both files in 0988d94), confirmed make test 257/0, and completed the tail (this SUMMARY + REQUIREMENTS handling). No file work was lost or double-applied."
---

# Plan 07-02 Summary — The v2 Presenter Walkthrough

Rewrote `WALKTHROUGH.md` for the v2 migration story and kept its executable-contract lint (`section_walkthrough`) green in lockstep — the milestone's presenter-facing close-out.

## What shipped

- **WALKTHROUGH.md (MIG-02):** an 11-beat v2 narrative — validate the new stack via `app-new.demo.test` (the milestone's headline: prove NEW live over HTTP+SSH before committing) → show OLD through the switch → the 301 redirect contrast → prime SSH trust → flip the switch (one edit, both protocols) → the host-key gotcha (inherited v1 behaviour, surfaced) → the wrong fix → the right fix → **instant rollback** (flip back, no teardown) → **the old proxy was never touched** (`make proxies-untouched` checksum) → reset. Each beat carries Run / Expect / Say + a takeaway, and every Run command is a real target or binary.
- **`make proxies-untouched`:** the beat-10 Run command — `shasum -a 256` of `proxy-old/nginx.conf` + `proxy-new/nginx.conf`, declared in `.PHONY` so the lint's target-closure check stays green.
- **`section_walkthrough` (lockstep):** the executable-contract expectations updated to the new beat list in the SAME commit as the doc — no red-lint intermediate.

## Commits
- `c82cf19` feat(07-02): add make proxies-untouched presenter target (VAL-04 checksum)
- `0988d94` docs(07-02): rewrite WALKTHROUGH.md for the v2 11-beat narrative + section_walkthrough in lockstep (MIG-02)

## Verification
- **Automated:** `make test` → **257 passed, 0 failed** (exit 0), including the rewritten `section_walkthrough` lint.
- **Pending (blocking human):** the comprehensibility cold-read of `WALKTHROUGH.md` (MIG-02 criterion 4) — surfaced at the end-of-phase gate, not auto-claimed.
