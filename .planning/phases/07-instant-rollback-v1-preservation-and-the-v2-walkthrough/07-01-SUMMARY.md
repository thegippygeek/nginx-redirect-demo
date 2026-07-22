---
phase: 07-instant-rollback-v1-preservation-and-the-v2-walkthrough
plan: 01
subsystem: testing
tags: [nginx, docker-compose, smoke-test, posix-sh, shasum, git-plumbing, ssh, rollback]

# Dependency graph
requires:
  - phase: 05/06
    provides: "the switch + two static proxies that flip both HTTP:9092 and SSH:22 via one flip.sh reload"
provides:
  - "section_rollback in scripts/smoke.sh — proves instant rollback (VAL-03) and byte-unchanged static proxies (VAL-04) over one live flip cycle"
  - "section_preserve in scripts/smoke.sh — non-destructive git-plumbing proof that the v1.0 tag preserves the single-proxy demo (MIG-03)"
  - "both sections wired into the make test all-chain and dispatchable standalone"
affects: [07-02, milestone-audit, walkthrough]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "shasum -a 256 triple-capture (before == after-flip == after-rollback) as a byte-identity proof over one live flip cycle"
    - "worker-PID-unchanged (pgrep -f 'nginx: worker') as a not-even-reloaded corroboration alongside StartedAt-unchanged"
    - "read-only git plumbing (rev-parse/show/cat-file) as a non-destructive tag-content assertion — never a checkout"

key-files:
  created: []
  modified:
    - "scripts/smoke.sh - added section_rollback (VAL-03+VAL-04), section_preserve (MIG-03), dispatch arms, all-chain wiring, usage string"

key-decisions:
  - "Reused the existing flip.sh reload as the rollback mechanism — the plan adds assertions only, no new runtime mechanism"
  - "Corroborated StartedAt-unchanged with worker-PID-unchanged so a silent proxy reload cannot hide behind an equal config hash"
  - "MIG-03 asserts the v1.0 tag's CONTENT via git plumbing rather than adding a compose.v1.yaml (which would collide on 9092/9093)"

patterns-established:
  - "Destructive smoke section discipline: restore_flip_state trap at top, finish_flip_state at exit, rig left on OLD"
  - "Non-destructive smoke section: header + assert one-liners, no restore trap, reads only"

requirements-completed: [VAL-03, VAL-04, MIG-03]

coverage:
  - id: D1
    description: "section_rollback proves a cutover-then-rollback returns both HTTP:9092 and SSH:22 to OLD with no container teardown (instant rollback)"
    requirement: "VAL-03"
    verification:
      - kind: integration
        ref: "sh scripts/smoke.sh rollback"
        status: pass
    human_judgment: false
  - id: D2
    description: "section_rollback proves the two static-proxy configs are byte-identical (shasum -a 256, three points) and their workers never respawned across the cycle — the old proxy is never touched"
    requirement: "VAL-04"
    verification:
      - kind: integration
        ref: "sh scripts/smoke.sh rollback"
        status: pass
    human_judgment: false
  - id: D3
    description: "section_preserve proves the v1.0 tag holds a self-contained single-proxy demo via read-only git plumbing (no checkout)"
    requirement: "MIG-03"
    verification:
      - kind: integration
        ref: "sh scripts/smoke.sh preserve"
        status: pass
    human_judgment: false
  - id: D4
    description: "both sections wired into make test; full suite green with preserve early and rollback after ssh, hostkey last, rig left on OLD"
    verification:
      - kind: integration
        ref: "make test (256 passed, 0 failed)"
        status: pass
    human_judgment: false

# Metrics
duration: 20min
completed: 2026-07-22
status: complete
---

# Phase 7 Plan 01: Instant Rollback + v1 Preservation Assertions Summary

**Two new smoke sections make "the old proxy is never touched" a checksum-proven fact: section_rollback asserts a live cutover-then-rollback returns both protocols to OLD with byte-identical static configs and no teardown, and section_preserve proves the v1.0 tag still holds the single-proxy demo — both via read-only/non-destructive idioms and both green in make test.**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-07-22T04:30Z (approx)
- **Completed:** 2026-07-22T04:50:43Z
- **Tasks:** 3
- **Files modified:** 1 (scripts/smoke.sh)

## Accomplishments
- `section_rollback` runs one real `flip.sh new` → `flip.sh old` cycle and asserts: both HTTP:9092 and SSH:22 land `OLD server-old` after rollback (VAL-03); no container's `.State.StartedAt` changed across the cycle (VAL-03/04); the two static-proxy configs are byte-identical via `shasum -a 256` at three points (VAL-04); and their nginx worker PIDs never respawned — the proxies were not even reloaded (VAL-04).
- `section_preserve` proves MIG-03 non-destructively via git plumbing only (`git rev-parse` / `git show` / `git cat-file`): the `v1.0` tag exists, its compose has a `proxy:` service and no `switch:`, ships `proxy/nginx.conf` + `proxy/active-backend.conf`, and has an `up:` Makefile target — no `git checkout`, no working-tree mutation.
- Both sections wired into `make test`: `section_preserve` early among the pure readers (after redirect, before cutover), `section_rollback` after `section_ssh` and before walkthrough/hostkey (hostkey still last). Full suite green: **256 passed, 0 failed**, rig left on OLD.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add section_rollback (VAL-03 + VAL-04) + dispatch case** - `c02f4dc` (test)
2. **Task 2: Add non-destructive section_preserve (MIG-03) + dispatch case** - `53e5579` (test)
3. **Task 3: Wire both into the all chain and usage string** - `c9e3458` (test)

## Files Created/Modified
- `scripts/smoke.sh` - added `section_rollback` (destructive, one flip cycle, trap/restore discipline), `section_preserve` (non-destructive git plumbing), `rollback)`/`preserve)` dispatch arms, all-chain wiring, and the updated usage string + header comment.

## Decisions Made
- Reused the existing `flip.sh` reload as the rollback mechanism — this plan adds assertions over an unchanged runtime, no new mechanism (per plan key_links).
- Corroborated `StartedAt`-unchanged (catches a restart) with worker-PID-unchanged (catches a reload) so a silent proxy reload cannot false-pass behind an equal config hash (T-07-01 mitigation).
- Kept `v1.0` as the canonical preserved form and asserted its content via git plumbing rather than adding a `compose.v1.yaml` (port collision on 9092/9093).

## Deviations from Plan

None - plan executed exactly as written.

The one adjustment worth noting was not a deviation from plan intent: a code comment in `section_rollback` originally contained the literal string `sha256sum` (while explaining why the code avoids it), which tripped the plan's own region-scoped guard `grep -c 'sha256sum' == 0`. The comment was reworded to describe the macOS-native tool without naming the GNU variant. No behavior change.

## Issues Encountered
- `make test` exceeds a 120s single-command window (the SSH-heavy sections are slow); ran it in the background and confirmed exit 0 with 256 passed, 0 failed.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- 07-02 (the v2 walkthrough lockstep: `section_walkthrough` + `WALKTHROUGH.md`) is unblocked — this plan touched neither and left the suite green.
- The rig is left on OLD, the precondition every section expects.

## Self-Check: PASSED

- SUMMARY.md present on disk
- All three task commits present in history (c02f4dc, 53e5579, c9e3458)
- section_rollback and section_preserve both defined in scripts/smoke.sh
- `make test`: 256 passed, 0 failed, exit 0; rig left on OLD

---
*Phase: 07-instant-rollback-v1-preservation-and-the-v2-walkthrough*
*Completed: 2026-07-22*
