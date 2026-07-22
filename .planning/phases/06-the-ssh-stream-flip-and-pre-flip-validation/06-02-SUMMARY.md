---
phase: 06-the-ssh-stream-flip-and-pre-flip-validation
plan: 02
subsystem: infra
tags: [nginx, stream, ssh, docker-compose, pre-flip-validation, smoke-tests, posix-sh, verify]

# Dependency graph
requires:
  - phase: 06
    plan: 01
    provides: "switch flips BOTH HTTP:9092 and SSH:22 from one active-proxy.conf selector; static proxy-old/proxy-new with the app-new.demo.test Docker-DNS alias live on proxy-new (HTTP:80 + SSH:22 stream)"
provides:
  - "scripts/verify.sh --target app-new mode: both probes from the client container against app-new.demo.test (HTTP:80, SSH:22), expectation fixed NEW — the pre-flip proof, exit 0 while the switch is still on OLD"
  - "make verify-new-stack: the presenter surface for the pre-flip check"
  - "section_validate in scripts/smoke.sh (VAL-01/VAL-02/EV2-04): non-destructive proof the new stack is live over both protocols BEFORE cutover; wired into make test after section_cutover"
affects: [phase-07-v1-preservation, migration, ssh, cutover, demo-walkthrough]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pre-flip validation via the Docker-DNS alias: app-new.demo.test is resolvable ONLY on the demo network, so both probes run via docker compose exec -T client and HTTP lands on proxy-new's :80, not the switch's 9092"
    - "One verdict machine, two targets: verify.sh keeps the through-switch positional <old|new> mode + 0/1/2/3 exit vocabulary and adds --target app-new via an HTTP_EXEC prefix that moves the HTTP probe into the client container"
    - "Non-destructive test section: section_validate reads only, asserts the switch is on OLD as a precondition rather than flipping to reach it, and installs no restore trap"

key-files:
  created: []
  modified:
    - "scripts/verify.sh — added --target app-new mode (HTTP_EXEC client-container prefix, SSH_TARGET=app-new.demo.test, expectation fixed NEW); positional through-switch mode + exit vocabulary preserved byte-for-byte"
    - "Makefile — added verify-new-stack target (and to .PHONY)"
    - "scripts/smoke.sh — added non-destructive section_validate (VAL-01/VAL-02/EV2-04) + dispatch case + all-runner entry after section_cutover; usage strings updated"
    - ".planning/REQUIREMENTS.md — VAL-01, VAL-02, EV2-04 marked Complete (checkbox + traceability)"

key-decisions:
  - "section_validate asserts the switch is on OLD as a precondition and never flips — the milestone claim (new stack live BEFORE cutover) is only meaningful with live traffic still on OLD, so forcing OLD would defeat the proof"
  - "VAL-01 asserts app-new=NEW and switch=OLD together in ONE condition; splitting them would let a half-truth pass"
  - "verify.sh --target app-new reuses the existing SSH probe unchanged (already client-side) and only moves the HTTP probe into the client container via an unquoted HTTP_EXEC prefix — the through-switch mode is untouched"

patterns-established:
  - "The pre-flip proof: curl+ssh app-new.demo.test -> NEW on both protocols from the client container, while app.demo.test/localhost:9092 -> OLD, taken without touching the switch selector"

requirements-completed: [VAL-01, VAL-02, EV2-04]

coverage:
  - id: D1
    description: "scripts/verify.sh --target app-new: both probes from the client container against app-new.demo.test (HTTP:80, SSH:22), expectation fixed NEW; through-switch positional <old|new> mode and 0/1/2/3 exit vocabulary preserved; make verify-new-stack surface"
    requirement: "EV2-04"
    verification:
      - kind: integration
        ref: "sh scripts/verify.sh --target app-new -> exit 0, HTTP + SSH lines both report NEW server-new while the switch is on OLD"
        status: pass
      - kind: integration
        ref: "sh scripts/verify.sh old -> 0; sh scripts/verify.sh new (OLD rig) -> 1; sh scripts/verify.sh (no args) -> usage, exit 2; --target bogus/--target (missing) -> exit 2"
        status: pass
      - kind: integration
        ref: "make verify-new-stack -> exit 0; grep verify-new-stack Makefile present and in .PHONY; no ssh on the left of a pipe (count 0)"
        status: pass
    human_judgment: false
  - id: D2
    description: "section_validate (non-destructive) proves app-new.demo.test -> NEW over HTTP:80 and SSH:22 from the client container while app.demo.test/localhost:9092 stay OLD, and that verify.sh --target app-new exits 0; wired into make test after section_cutover"
    requirement: "VAL-01"
    verification:
      - kind: integration
        ref: "sh scripts/smoke.sh validate -> 6 passed, 0 failed (VAL precondition OLD; VAL-01 HTTP; VAL-02 banner+hostname+concurrent OLD; EV2-04)"
        status: pass
      - kind: integration
        ref: "non-destructive proof: no flip.sh new|toggle inside section_validate (count 0); no ssh on the left of a pipe (count 0)"
        status: pass
    human_judgment: false
  - id: D3
    description: "VAL-02 SSH pre-flip path: ssh app-new.demo.test shows server-new's banner from the client container before cutover, corroborated by a hostname reading of server-new"
    requirement: "VAL-02"
    verification:
      - kind: integration
        ref: "section_validate VAL-02 banner (true -> NEW server-new) + corroboration (hostname -> server-new) + concurrent (ssh app.demo.test -> OLD server-old) all pass"
        status: pass
    human_judgment: false
  - id: D4
    description: "Full regression green with section_validate added and the Wave-1 SSH sections intact"
    requirement: "EV2-04"
    verification:
      - kind: integration
        ref: "make test -> 247 passed, 0 failed, exit 0 (241 Wave-1 + 6 new validate assertions) on a clean-reset rig"
        status: pass
    human_judgment: false

# Metrics
duration: ~40min
completed: 2026-07-22
status: complete
---

# Phase 6 Plan 02: Pre-Flip Validation and the app-new verify target Summary

**The presenter can now prove the new stack is live over BOTH protocols BEFORE committing to the flip: `verify.sh --target app-new` (surfaced as `make verify-new-stack`) and a non-destructive `section_validate` show `curl`/`ssh app-new.demo.test` -> NEW over HTTP:80 and SSH:22 from the client container, while `app.demo.test`/`localhost:9092` still land on OLD — with the switch selector never touched. `make test` is green at 247/0.**

## Performance

- **Duration:** ~40 min
- **Completed:** 2026-07-22
- **Tasks:** 2
- **Files modified:** 4 (scripts/verify.sh, Makefile, scripts/smoke.sh, .planning/REQUIREMENTS.md)

## Accomplishments
- Added a `--target app-new` mode to `scripts/verify.sh`: both probes run inside the client container against the Docker-DNS-only `app-new.demo.test` alias (HTTP on proxy-new's :80 via a new `HTTP_EXEC` prefix, SSH on :22 — the existing probe was already client-side), expectation fixed NEW. The through-switch positional `<old|new>` mode and its 0/1/2/3 exit vocabulary are preserved byte-for-byte; a fumbled `--target` is a usage error (exit 2), never a mismatch.
- Added `make verify-new-stack` (and to `.PHONY`) as the presenter surface for the pre-flip check — exit 0 while the switch is on OLD.
- Added a non-destructive `section_validate` to `scripts/smoke.sh` proving, with the switch on OLD, that `app-new.demo.test` answers NEW over HTTP:80 and SSH:22 from the client container while `app.demo.test`/`localhost:9092` stay OLD, and that `verify.sh --target app-new` exits 0. It reads only — never flips the selector, installs no restore trap, and asserts OLD as a precondition. Wired into the `all` runner immediately after `section_cutover` and before `section_ssh`; dispatch case + usage strings updated.
- Marked VAL-01, VAL-02, EV2-04 Complete in REQUIREMENTS.md (checkbox + traceability).

## Task Commits

1. **Task 1: verify.sh --target app-new mode + make verify-new-stack** - `cc57b6d` (feat)
2. **Task 2: non-destructive section_validate (VAL-01/VAL-02/EV2-04)** - `b358b81` (test)

**Plan metadata:** committed separately with this SUMMARY + REQUIREMENTS.md.

## Files Created/Modified
- `scripts/verify.sh` - Added the `--target app-new` mode. New `HTTP_EXEC` prefix (empty in switch mode = host-side curl; `docker compose exec -T client` in app-new mode) moves only the HTTP probe into the client container onto port 80; SSH_TARGET becomes `app-new.demo.test`; expectation fixed NEW. Arg parse handles `--target app-new` first so the positional `<old|new>` form and its exit-2 usage path survive unchanged. The capture-then-read-`$?` ssh idiom (no pipe), the external `timeout`, the demo-only host-key options, and the 0/1/2/3 vocabulary are untouched.
- `Makefile` - Added the `verify-new-stack` target (`@sh scripts/verify.sh --target app-new`) with a full comment on the pre-flip payoff; added `verify-new-stack` to `.PHONY`. The existing `verify` target (positional EXPECT) is unchanged.
- `scripts/smoke.sh` - Added `section_validate()` (6 assertions: OLD precondition, VAL-01 HTTP, VAL-02 banner + hostname corroboration + concurrent-OLD, EV2-04 verify.sh). Restated the demo-only `SSH_OPTS` locally so `sh scripts/smoke.sh validate` runs standalone. Added the `validate)` dispatch case, the `all`-runner entry after `section_cutover`, and `validate` to both usage strings.
- `.planning/REQUIREMENTS.md` - VAL-01, VAL-02, EV2-04 marked Complete (checkboxes + traceability rows).

## Decisions Made
- **Non-destructive precondition, not a forced flip.** `section_validate` asserts the switch is on OLD and reports a genuine failure if it is not, rather than running `flip.sh old` to reach it. The whole point of the pre-flip proof is "new stack live WHILE live traffic is still on OLD" — forcing the state would hollow out the claim. Ordering (after `section_cutover`, which leaves the rig on OLD) supplies the precondition for free in `make test`.
- **VAL-01 asserted as one atomic condition** (app-new=NEW AND switch=OLD), so a half-truth cannot pass.
- **Reused the existing client-side SSH probe** in verify.sh and only re-homed the HTTP probe via `HTTP_EXEC`; minimal delta keeps the through-switch mode provably untouched.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Reset the shared rig to a clean state before the final `make test`**
- **Found during:** Task 2 (running the full `make test`)
- **Issue:** The shared demo rig drifted mid-execution — the selector was observed flipping from OLD to NEW between probes, and a `make test` run reported 2 failures (`KEY-01` "backends have DIFFERENT ssh host keys" and `CUT-04` "host-key reading CHANGED with the selector"). Both are host-key preconditions in the untouched `section_ssh`/`section_hostkey`, not in the new `section_validate`. The drift is consistent with external churn on the shared rig (and an earlier 2-minute command timeout that SIGTERM'd the destructive `section_hostkey` mid-restore).
- **Fix:** `make reset` (down -v + rebuild + regenerate both backends' host keys + selector -> old), then re-ran `make test`.
- **Files modified:** none (runtime rig state only)
- **Verification:** live host-key fingerprints differ (correct KEY-01 precondition); `make test` -> 247 passed, 0 failed, exit 0.
- **Committed in:** n/a (no file change)

---

**Total deviations:** 1 (rig-state reset; no code impact)
**Impact on plan:** No scope change. The failures were transient shared-rig churn, not defects in this plan's changes — `section_validate` passed 6/6 both standalone and inside the clean full run, and verify.sh's through-switch mode is unchanged.

## Issues Encountered
- The full `make test` takes longer than a 2-minute command window; run it with an extended timeout to a log file. A mid-suite SIGTERM can interrupt the destructive `section_hostkey` restore and leave the rig needing a `make reset` (matches the Wave-1 note about shared-rig artifacts on Docker Desktop macOS).

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Milestone payoff delivered: the presenter can validate the new stack over both protocols before the cutover (`make verify-new-stack`) and the pre-flip proof is a permanent regression (`make test` -> `--- validate ---` 6/0).
- Phase 7 (MIG-03) v1 preservation untouched: `proxy/` is not modified; no compose `ports:` entry added for the static proxies (app-new stays Docker-DNS-only, T-06-04).
- Note for future runs: reset the shared rig (`make reset`) before a full `make test` if the selector or host keys may have drifted; run the suite with an extended timeout.

## Known Stubs
None - POSIX-sh test + shell utility changes only; no placeholder or empty-value stubs introduced.

## Self-Check: PASSED

- scripts/verify.sh, Makefile, scripts/smoke.sh, 06-02-SUMMARY.md — all present on disk
- Task commits cc57b6d, b358b81 — both present in git history

---
*Phase: 06-the-ssh-stream-flip-and-pre-flip-validation*
*Completed: 2026-07-22*
