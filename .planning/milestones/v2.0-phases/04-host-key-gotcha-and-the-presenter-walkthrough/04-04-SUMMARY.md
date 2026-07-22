---
phase: 04-host-key-gotcha-and-the-presenter-walkthrough
plan: 04
subsystem: test-harness
tags: [walkthrough, doc-lint, smoke, phase-gate, criterion-5, honesty, ssh, host-keys]

requires:
  - phase: 04-host-key-gotcha-and-the-presenter-walkthrough
    plan: "02"
    provides: "section_hostkey and the dispatcher/all-chain shape this plan extends; the 186+20 baseline the gate measures against"
  - phase: 04-host-key-gotcha-and-the-presenter-walkthrough
    plan: "03"
    provides: "WALKTHROUGH.md with its exact labels — ### N. headings, **Run**/**Expect**/**Say** at line start, ## Pre-flight checklist, ## Known traps — which section_walkthrough lints against"
provides:
  - "section_walkthrough in scripts/smoke.sh — the four-part executable contract over WALKTHROUGH.md (WALK-01/02/03), 25 assertions, non-destructive, wired before section_hostkey"
  - "sh scripts/smoke.sh walkthrough — the doc-lint command"
  - "The phase gate: 231/231 from a cold make reset, 17/17 proxy guard intact, rig left armed on old"
  - "04-VALIDATION.md signed off honestly — criterion 5 recorded as owner-judgement acceptance, not mechanical verification and not an independent cold read"
affects: [milestone-v1-close]

tech-stack:
  added: []
  patterns:
    - "Doc-lint by extraction, not by hand-maintained list: the section pulls commands and paths out of the document itself and checks each against the repository, so it cannot describe a document that no longer exists"
    - "Non-vacuity asserted before counting: every extracted set is proven non-empty first, because a check over zero items is indistinguishable from one that passes"
    - "Proven-red-before-trusted: the lint was deliberately broken four ways and watched fail, then reverted, before the section was accepted"

key-files:
  created: []
  modified:
    - scripts/smoke.sh
    - .planning/phases/04-host-key-gotcha-and-the-presenter-walkthrough/04-VALIDATION.md

key-decisions:
  - "Criterion 5's comprehensibility dimension is recorded as accepted on OWNER judgement 2026-07-21, with an explicit note that an independent cold read was NOT performed — the owner watched the whole build, so their sign-off is a decision recorded beside the structured backstop, never a conversion of the doc-lint into a mechanical pass (T-04-16)"
  - "The doc-lint extracts from the document rather than grepping a hand-maintained list, so the check cannot drift from the document it describes"
  - "section_walkthrough runs before section_hostkey in the all chain — it is a pure reader and disturbs nothing, and the destructive section must stay last"
  - "The 04-VALIDATION.md edit was committed BEFORE the phase gate ran, so the scoped cleanliness assertion could not be made unsatisfiable by this task's own mutation"

patterns-established:
  - "Absolute paths in a walkthrough (/etc/hosts, /root/.ssh/known_hosts) are deliberately excluded from the path-existence lint — they are the host's and the client container's, not this repository's, and asserting them would produce a false red on a fresh machine"
  - "Narrative order is matched on a per-heading keyword rather than the heading text, so rewording a heading is allowed and reordering one turns the suite red"

requirements-completed: [WALK-01, WALK-02, WALK-03]

coverage:
  - id: W1
    description: "section_walkthrough asserts WALKTHROUGH.md is self-contained and executable — every command a real target or binary, every path resolving, no ungiven prerequisite, every step carrying Run/Expect/Say in that fixed order"
    requirement: "WALK-01, WALK-02, WALK-03"
    verification:
      - kind: static
        ref: "sh scripts/smoke.sh walkthrough — 25 passed, 0 failed; 25 WALK-labelled assertions"
        status: pass
    human_judgment: false
  - id: W2
    description: "The doc-lint is non-vacuous and proven capable of failing before it is trusted"
    requirement: "WALK-02, WALK-03"
    verification:
      - kind: static
        ref: "four deliberate breakages each turned the suite red and were reverted: document moved aside (15 fail), Say label removed from beat 4 (2 fail), make target renamed in the doc only (1 fail), beats 6 and 7 swapped (1 fail); every extracted set asserted non-empty before counting"
        status: pass
    human_judgment: false
  - id: W3
    description: "The phase gate is green from cold: full suite > 186 with zero failures, proxy exactly 17/17, selector on old, gotcha armed, demo source tree clean"
    verification:
      - kind: static
        ref: "make reset then sh scripts/smoke.sh -> 231 passed, 0 failed; sh scripts/smoke.sh proxy -> 17 passed, 0 failed; selector=old; server-old/server-new ed25519 fingerprints differ; git status --porcelain over the shipped source paths empty"
        status: pass
    human_judgment: false
  - id: W4
    description: "ROADMAP criterion 5 — someone who has never seen the demo can follow WALKTHROUGH.md cold"
    verification: []
    human_judgment: true
    rationale: "Accepted on OWNER judgement 2026-07-21; an independent cold read by a fresh, never-seen-it reader was NOT performed. The doc-lint proves self-containedness and executability only; comprehensibility is not mechanically verifiable and is nowhere claimed as such. The structured backstop remains authored so a verifier abstains and escalates rather than inferring a pass."
---

# Phase 4 Plan 04: The Executable Contract and the Honest Sign-Off Summary

**`section_walkthrough` makes `WALKTHROUGH.md` unable to rot — 25 assertions proving every command is a real target or binary, every path resolves, no step meets an ungiven prerequisite, and every beat carries Run/Expect/Say in order — and the phase closes honestly: the doc-lint proves the document is self-contained and executable, and criterion 5's comprehensibility claim is recorded as accepted on owner judgement, not as an independent cold read.**

## Performance

- **Duration:** ~20 min
- **Tasks:** 3 of 3 (Task 3 a blocking human checkpoint, resolved by owner approval)
- **Files modified:** 2 (`scripts/smoke.sh`, `04-VALIDATION.md`)

## Accomplishments

- **The document can no longer drift from the rig silently.** `section_walkthrough` extracts the commands from the document's fenced ` ```bash ` blocks and the repository paths from its own backticked tokens, then checks each against the Makefile's phony list, `command -v`, and the filesystem. 11 command lines, 6 distinct targets, 1 binary, 4 paths — all resolve. A renamed target, a moved file, a dropped block or a reordered beat now turns the suite red.
- **The four-part contract landed in full.** (1) Every command runnable verbatim — targets against `.PHONY`, other commands against `command -v`, and a guard that no block carries an ellipsis or placeholder. (2) Every referenced path resolves. (3) No undefined prerequisite — per step, every `make` target named anywhere inside it must already be in the union of the pre-flight targets and earlier steps' Run-block targets; 0 unintroduced. (4) Structural completeness — 8 headings, 8 Run, 8 Expect, 8 Say, with the per-step sequence compared against the literal `RES` so a step carrying two Says and no Expect cannot be balanced by its neighbour, plus heading numbers `1..8` ascending and heading keywords in the D-55 order.
- **The lint is non-vacuous and was proven capable of failing before it was trusted.** Every extracted set is asserted non-empty before anything is counted (T-04-17). Four deliberate breakages, each reverted: the document moved aside (15 failures), a `**Say**` label removed from beat 4 (2), a `make` target renamed in the document only (1), and beats 6 and 7 swapped (1).
- **The five D-57 traps are each asserted present by name** — the incognito window, the client-container SSH prefix and unpublished port 22, port 9093 not following the flip, `make reset` as the re-arm path, and `make verify`'s structural blindness to host keys.
- **The section is a reader, and stays one.** It executes nothing it extracts (a guard asserts no `eval`, no `sh "$WT_TMP"`, no `xargs` in its body — T-04-19), and it runs before `section_hostkey` in the `all` chain precisely because it disturbs no rig state; the destructive section stays last.
- **The phase gate is closed from cold.** `make reset`, then the full suite at **231 passed, 0 failed** (186 inherited + 20 `section_hostkey` + 25 `section_walkthrough`, so the new assertions ran and every inherited one still passes), then `sh scripts/smoke.sh proxy` at exactly `--- 17 passed, 0 failed ---` — the canonical guard, unchanged across four phases and never adjusted to match a result. The rig is left selecting `old` with the two backends' ed25519 fingerprints differing (armed), and `git status --porcelain` over the demo's shipped source is empty.
- **The `04-VALIDATION.md` edit was committed before the gate ran**, so the scoped cleanliness assertion could not be made unsatisfiable by this task's own mutation.

## Task Commits

1. **Task 1: `section_walkthrough` — the four-part executable contract** — `f3a0bd1` (test)
2. **Task 2: the phase gate and honest sign-off in `04-VALIDATION.md`** — `f669441` (docs)
3. **Task 3: ROADMAP criterion 5 cold read** — blocking human checkpoint; resolved by owner approval (recorded in this SUMMARY and in `04-VALIDATION.md`, committed with the plan-completion metadata)

## Files Created/Modified

- `scripts/smoke.sh` (modified) — `section_walkthrough()` added before `section_hostkey()` (253 insertions), plus the head-of-file usage comment, the `walkthrough` dispatcher branch, the usage line, and the `all`-chain entry placed immediately before `section_hostkey`. No existing section was touched.
- `.planning/phases/04-host-key-gotcha-and-the-presenter-walkthrough/04-VALIDATION.md` (modified) — `nyquist_compliant: true`, `wave_0_complete: true`, `status: complete`; test-map rows closed against the sections that carry them; an "As built" record of the four-part contract; the phase-gate results table; and the sign-off list, with criterion 5 recorded honestly (see below).

## ROADMAP criterion 5 — recorded honestly

The blocking `checkpoint:human-verify` task (Task 3) halted execution as designed. The project **owner** reviewed and **approved**.

- **What is mechanically verified:** `WALKTHROUGH.md` is self-contained and executable. The 25 `section_walkthrough` assertions prove every command resolves to a real target or binary, every path exists, no step meets an ungiven prerequisite, and every beat carries Run/Expect/Say in order.
- **What is NOT mechanically verified, and is nowhere claimed as such:** that the document is *comprehensible* — that someone who has never seen the demo can follow it cold. **No independent fresh reader performed the cold read.** The person approving is the project owner, who watched the entire build, so their sign-off is an **owner-judgement acceptance** (recorded as *"criterion 5: accepted on owner judgement 2026-07-21; independent cold read not performed"*), not evidence for the never-seen-it claim.
- The structured backstop truth in the plan's must-haves stays authored as-is: a verifier reading the automated evidence should still abstain and escalate to a human rather than infer a pass. The owner's acceptance is a decision recorded beside the backstop, not a conversion of it into a mechanical pass (T-04-16).
- **No reader guess-points were supplied**, so there are no verbatim gaps to record against `WALKTHROUGH.md`.

## Deviations from Plan

None — plan executed as written. Task 3's resolution is an owner-judgement acceptance rather than an independent fresh-reader cold read; per the plan's own instruction that is a recognised outcome, recorded in those words rather than approved on the strength of the doc-lint.

## Issues Encountered

None. Every automated verification passed. Both task-1 and task-2 `<verify>` command lines returned PASS; the four teeth-proving breakages behaved exactly as intended.

## Known Stubs

None.

## Project publication (informational)

The project has been published to a public GitHub repository: **github.com/thegippygeek/nginx-redirect-demo**, `main` branch. Recorded here so a later reader knows the demo's code is public. This is informational only and had no effect on this plan's execution.

## Next Phase Readiness

This is the final plan of v1. The mechanical gate is closed — the suite is green from cold at 231/231, the 17/17 proxy guard is intact, the rig opens armed on `old`, and no stray edit sits in the demo's shipped source. Criterion 5 is signed off on owner judgement with its limitation stated plainly. The milestone is ready to close.

---
*Phase: 04-host-key-gotcha-and-the-presenter-walkthrough*
*Completed: 2026-07-22*

## Self-Check: PASSED

`scripts/smoke.sh`, `04-VALIDATION.md` and `04-04-SUMMARY.md` all exist on disk; both task commits (`f3a0bd1`, `f669441`) are present in git history; the `section_walkthrough` symbol is present in `scripts/smoke.sh`. The phase gate was re-run from a cold `make reset` and reported 231 passed, 0 failed with `proxy` at exactly 17/17.
