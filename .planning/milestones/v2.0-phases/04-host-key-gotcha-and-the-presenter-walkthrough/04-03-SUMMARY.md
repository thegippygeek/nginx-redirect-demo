---
phase: 04-host-key-gotcha-and-the-presenter-walkthrough
plan: 03
subsystem: docs
tags: [walkthrough, presenter, readme, ssh, host-keys, documentation]

requires:
  - phase: 04-host-key-gotcha-and-the-presenter-walkthrough
    plan: "01"
    provides: "make ssh (presenter mode), make fix-hostkeys and make rearm — the three targets this document narrates, and the exact output text they print"
provides:
  - "WALKTHROUGH.md — the runnable presenter script: pre-flight checklist, eight numbered beats in the D-55 order, each with Run/Expect/Say, and a traps section"
  - "README.md corrected — the SSH example now routes through make ssh, the two named connection modes are documented with the consequence of confusing them, and a Phase 4 reference section covers the gotcha, the fix and the re-arm"
affects: [04-04 section_walkthrough doc-lint, 04-04 criterion-5 human checkpoint]

tech-stack:
  added: []
  patterns:
    - "The three-block walkthrough step: Run / Expect / Say under every numbered heading, always in that order, so a presenter finds the block by position rather than by reading"
    - "Two documents with two jobs — README is reference material read out of order, WALKTHROUGH is a script read top to bottom; each points at the other and neither copies it"

key-files:
  created:
    - WALKTHROUGH.md
  modified:
    - README.md

key-decisions:
  - "The wrong fix is written as demonstration-then-contrast, never as condemnation: ssh-keygen -R is shown succeeding with no editorial, then contrasted on two verified facts (two steps not one; the second was a blind trust decision) and closed with the fleet-scale question to the room"
  - "make reset is the documented headline re-arm (~16 s) and make rearm is the between-takes footnote (~1 s), with both measured timings stated so the presenter's choice is informed"
  - "A ninth structural element was added that the plan did not name: beat 6 carries an explicit four-command route back to the armed state, because demonstrating the wrong fix destroys the precondition beat 7 needs"
  - "The fingerprint lines in every transcribed output block are shown as varying rather than as literals — a literal would make a correct run look wrong to a careful reader, and would be the only place a transcript could leak key-adjacent material"
  - "The README's Layout tree was deliberately left unmodified even though it now omits two scripts, because the plan's acceptance criteria require the diff to touch only the SSH section, the new Phase 4 section, the command reference and the walkthrough pointer"

patterns-established:
  - "Every command block contains only executable lines — no comment lines, no shell builtins, no ellipses — so a doc-lint can extract and check the set without special-casing"
  - "Prohibited literals are avoided at the source rather than filtered afterwards: the blanket host-key-disable form is never spelled in WALKTHROUGH.md, and the phrase 'make' is never used as a prose verb where a lint would read the next word as a target"

requirements-completed: [WALK-01, WALK-02, WALK-03, KEY-01, KEY-02, KEY-03, KEY-04]

coverage:
  - id: D1
    description: "WALKTHROUGH.md exists at the repository root, opens with a pre-flight checklist and closes with a traps section, and carries at least six numbered step headings"
    requirement: "WALK-01"
    verification:
      - kind: static
        ref: "plan 04-03 Task 1 <verify>: test -f, two heading greps, grep -cE '^#{2,3} [0-9]+\\.' >= 6 (returned 8)"
        status: pass
    human_judgment: false
  - id: D2
    description: "The eight step headings appear in the fixed D-55 narrative order — show old, redirect contrast, prime, flip, gotcha, wrong fix, right fix, reset"
    requirement: "WALK-01"
    verification:
      - kind: static
        ref: "grep -nE '^#{2,3} [0-9]+\\.' WALKTHROUGH.md — headings enumerated and read in order"
        status: pass
    human_judgment: false
  - id: D3
    description: "Every numbered step carries all three blocks (Run, Expect, Say), in that fixed order, adjacent, under its own heading — 8 headings, 8 of each block"
    requirement: "WALK-02, WALK-03"
    verification:
      - kind: static
        ref: "awk step/block association over WALKTHROUGH.md — 24 blocks, 3 per step, ordering Run->Expect->Say in all eight"
        status: pass
    human_judgment: false
  - id: D4
    description: "The gotcha step's expected output is the transcribed thirteen-line warning with the non-zero exit status stated inside that step's block, and the fingerprint shown as varying"
    requirement: "WALK-02, KEY-02"
    verification:
      - kind: static
        ref: "grep -q 'REMOTE HOST IDENTIFICATION HAS CHANGED' && grep -A 40 <that line> | grep -cE '(^|[^0-9])255([^0-9]|$)' >= 1"
        status: pass
    human_judgment: false
  - id: D5
    description: "Every make target named in WALKTHROUGH.md exists in the Makefile's phony list, and every repository path it names resolves to a real file"
    requirement: "WALK-02"
    verification:
      - kind: static
        ref: "11 extracted targets checked against ^.PHONY:; 4 extracted paths checked with test -e (README.md, proxy/active-backend.conf, scripts/fix-hostkeys.sh, scripts/rearm.sh)"
        status: pass
    human_judgment: false
  - id: D6
    description: "No blanket host-key-disable form appears anywhere in WALKTHROUGH.md, and the document states in words that recording an unseen host on first sight is not the same thing as switching the check off"
    requirement: "KEY-02"
    verification:
      - kind: static
        ref: "test \"$(grep -c 'StrictHostKeyChecking=no' WALKTHROUGH.md)\" = 0; the distinction is stated in beat 3's closing note"
        status: pass
    human_judgment: false
  - id: D7
    description: "The traps section names all five D-57 traps: the incognito window, the client-container prefix, port 9093 not following the flip, make reset as the re-arm path, and the verify script's structural blindness to host keys"
    requirement: "WALK-03"
    verification:
      - kind: static
        ref: "greps for 'incognito', '9093', 'make reset', 'make verify', 'DOCKER_CLI_HINTS' all present; traps section read in full"
        status: pass
    human_judgment: false
  - id: D8
    description: "The README references WALKTHROUGH.md above the command reference, carries a row each for make ssh / fix-hostkeys / rearm, names both connection modes with the consequence of confusing them, and states that the fix must signal the running daemon"
    requirement: "KEY-01, KEY-02, KEY-03, KEY-04"
    verification:
      - kind: static
        ref: "plan 04-03 Task 2 <verify>: all nine greps plus the phony-list loop over the post-SSH region — PASS"
        status: pass
    human_judgment: false
  - id: D9
    description: "The previously-documented bare SSH command that a fresh rig does not reproduce no longer appears as a copy-pasteable example claiming a clean login"
    requirement: "KEY-02"
    verification:
      - kind: static
        ref: "test \"$(grep -c 'docker compose exec client ssh demo@app.demo.test$' README.md)\" = 0"
        status: pass
    human_judgment: false
  - id: D10
    description: "This plan disturbed no part of the rig its wave-2 sibling was driving"
    verification:
      - kind: static
        ref: "git diff --name-only HEAD~2..HEAD -- scripts/ Makefile compose.yaml proxy/ backend/ client/ status/ — empty; the plan's two commits touch WALKTHROUGH.md and README.md only"
        status: pass
    human_judgment: false
  - id: D11
    description: "A colleague who has never seen the demo can run WALKTHROUGH.md cold, without the author in the room (ROADMAP criterion 5)"
    verification: []
    human_judgment: true
    rationale: "Whether the takeaway prose lands with a room, and whether a cold reader ever has to guess, is a judgement no assertion can make. Owned by 04-04's blocking human checkpoint; the doc-lint is explicitly not accepted as a substitute."
  - id: D12
    description: "The wrong fix reads as demonstration-then-contrast rather than as condemnation, and the framing suits the presenter's own preference"
    verification: []
    human_judgment: true
    rationale: "Tone is the one thing 04-CONTEXT flagged as a presentation judgement the user may want to set personally; 04-04's checkpoint item 6 surfaces it for confirmation."

duration: 14min
completed: 2026-07-21
status: complete
---

# Phase 4 Plan 03: The Presenter Walkthrough Summary

**`WALKTHROUGH.md` is the eight-beat script a colleague can run cold — pre-flight, the narrative in its fixed order, each beat carrying the command, the transcribed output and the sentence to say — and the README no longer documents an SSH outcome a fresh rig does not produce.**

## Performance

- **Duration:** ~14 min
- **Tasks:** 2 of 2
- **Files modified:** 2 (1 created, 1 modified)

## Accomplishments

- **The script exists and has a fixed shape.** Eight numbered beats in the D-55 order — show OLD, the 301 contrast, prime the trust, flip, the gotcha, the wrong fix, the right fix, reset — each with exactly three blocks under its heading in the order **Run**, **Expect**, **Say**. Eight headings, eight of each block, verified by extraction rather than by reading. That fixed shape is the thing that lets a presenter find what they need by position while a room watches.
- **The outputs are transcribed, not paraphrased.** The gotcha block is the literal thirteen-line warning with `exit status: 255` stated immediately beneath it and `known_hosts:1` named; the flip block is the real diff plus the config test and the confirming request; the contrast, verify and fix blocks come from the recorded runs in `04-RESEARCH.md` and `04-01-SUMMARY.md`. Every fingerprint is shown as varying, because printing a literal would make a correct run look wrong to a careful reader.
- **The wrong fix is demonstrated, then contrasted.** `ssh-keygen -R` is shown succeeding, verbatim, with no editorial in the expected-output block. The takeaway carries the two verified facts — two commands rather than one, the second of which trusted whatever answered next without checking — and closes on the question about how many laptops, runners, jump boxes and controllers hold that same record. The audience draws the conclusion.
- **The pre-flight checklist is eight actionable items**, including the `DOCKER_CLI_HINTS` export that research measured appearing on a projector and never in the suite, directly under the failure the room is meant to be reading.
- **The traps section carries all five**, including the sharpest one: `make verify` pins test mode and was measured exiting zero at the same moment presenter-mode SSH was failing with status 255. It is framed as a feature — it answers *"did the routing land?"*, not *"does the client trust what it landed on?"* — with an explicit instruction never to use it to diagnose the gotcha.
- **The README's pre-existing inaccuracy is fixed.** Both SSH examples now route through `make ssh`, and the post-flip example carries the caveat that a primed client gets the refusal rather than a clean login. The two connection modes are documented as a table with the consequence of confusing them stated plainly, along with the sentence that `accept-new` is not the same thing as switching host-key verification off.
- **The rig was not touched.** `git diff --name-only` across both commits, restricted to `scripts/ Makefile compose.yaml proxy/ backend/ client/ status/`, is empty — the mechanical proof that this plan could not have disturbed the shared Docker rig its wave-2 sibling was driving.

## Task Commits

1. **Task 1: `WALKTHROUGH.md` — the runnable script** — `fb7df21` (docs)
2. **Task 2: README — correct the SSH example, name the two modes, point at the walkthrough** — `cc41794` (docs)

## Files Created/Modified

- `WALKTHROUGH.md` (new) — WALK-01/02/03. Opening paragraph and timing, the eight-item pre-flight checklist, eight numbered beats with Run/Expect/Say, and a six-item traps section. Closes with a pointer back to the README and to the two scripts that carry the fix and the re-arm in full.
- `README.md` (modified) — seven hunks, all within the four regions the plan authorises: the walkthrough pointer near the top, the SSH command and its explanation, the cutover-over-SSH example plus its new gotcha caveat, the two-connection-modes subsection, the new Phase 4 reference section, and three new command-reference rows.

## Decisions Made

Both researcher open questions this plan owned were resolved as the plan specified (demonstration-then-contrast for the wrong fix; `make reset` as the headline re-arm with `make rearm` as the footnote, both timings stated). Two decisions were exercised beyond the plan's text and are worth recording:

- **Beat 6 needed a route back.** Demonstrating the wrong fix destroys the precondition beat 7 requires — after `ssh-keygen -R` the client has blind-accepted the new server's key, so the gotcha has nothing left to contradict. The step therefore carries an explicit four-command return (`make rearm`, `make flip-old`, `make ssh`, `make flip-new`), named as beats 3 and 4 replayed. Without it a presenter following the document top to bottom reaches beat 7 and finds nothing to fix, which is precisely the failure mode criterion 5 exists to catch.
- **Command blocks contain only executable lines.** No comment lines, no shell builtins such as `exit`, no ellipses or placeholders. Instructions that are not commands — "type `exit` to come back", the browser URL to have open — live in the Expect block's lead-in instead. This keeps 04-04's command-extraction lint able to treat every extracted line as a real command with no special cases.

## Deviations from Plan

None — plan executed exactly as written. Two writing-level constraints were self-imposed to keep the document lintable and are noted under Decisions rather than as deviations: the executable-only command blocks, and the avoidance of "make" as a prose verb anywhere a target-extraction regex would read the following word as a target name.

## Issues Encountered

None. Both tasks' automated verification passed on first execution.

## Known Stubs

None. Neither document contains a placeholder, a TODO, or a command that does not exist.

## Next Phase Readiness

Ready for 04-04:

- `section_walkthrough` has a concrete document to lint. Its block labels are `**Run**`, `**Expect**` and `**Say**` at the start of a line; its step headings are `### N. …`; its pre-flight and traps headings are `## Pre-flight checklist` and `## Known traps`. The lint must match this document rather than a document imagined at planning time — the plan says so explicitly.
- The four-part contract is satisfiable as written: 11 distinct `make` targets appear and all are in the phony list; 4 repository paths appear and all resolve; every step's targets are introduced either in the pre-flight checklist or by an earlier step (`make rearm` is named in pre-flight precisely so beat 5's heading and beat 6's recovery note do not meet it cold).
- The two human-judgment items above (D11 criterion 5, D12 the wrong-fix framing) are 04-04's blocking checkpoint, and the doc-lint must not be accepted as a substitute for either.

**Rig state left behind:** untouched by this plan. Whatever state 04-02 left is what is there.

---
*Phase: 04-host-key-gotcha-and-the-presenter-walkthrough*
*Completed: 2026-07-21*

## Self-Check: PASSED

Both files exist on disk (`WALKTHROUGH.md`, `README.md`) and both task commits are present in git history (`fb7df21`, `cc41794`). Both tasks' full `<verify>` command lines were re-run after the final edits and both returned PASS. The plan-level rig-exclusivity assertion — `git diff --name-only` over `scripts/ Makefile compose.yaml proxy/ backend/ client/ status/` across this plan's commits — returned empty.
