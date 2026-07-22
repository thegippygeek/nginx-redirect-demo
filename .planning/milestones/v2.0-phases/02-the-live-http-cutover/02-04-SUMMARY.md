---
phase: 02-the-live-http-cutover
plan: 04
subsystem: design-contract-enforcement-and-presenter-docs
tags: [smoke-tests, ui-token-audit, regression-guard, presenter-docs, visual-audit, spec-correction]

# Dependency graph
requires:
  - phase: 02-the-live-http-cutover
    plan: 03
    provides: "status/index.html — the file the token audit greps. Running the audit before it existed would have passed vacuously"
  - phase: 02-the-live-http-cutover
    plan: 01
    provides: "scripts/flip.sh and section_cutover() — both extended here"
provides:
  - "The mechanical half of UI-SPEC's thirteen executor acceptance tests, as 21 permanent suite assertions rather than one-time implementation-time checks"
  - "scripts/flip.sh with the D1 race removed structurally: the reset direction seeds nothing and therefore requests nothing"
  - "README.md's Phase 2 presenter surface — status page, the two readings, the four states, the between-takes reset, troubleshooting, the known 9092/9093 asymmetry"
  - "02-UI-SPEC.md corrected in three places so the contract no longer contradicts the shipped artifact"
affects: [phase 03 stream/SSH work, phase 04 WALK-01 walkthrough which extends this README]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Design-contract-as-test: typography, colour, layout and render-discipline rules are asserted by the same suite that gates routing behaviour, so the projector legibility the design rests on cannot regress silently"
    - "Teeth-proving: every class of guard is validated by introducing a deliberate violation, confirming red, and reverting — a guard never demonstrated to fail is not a guard"
    - "Self-reference discipline in a suite that greps its own directory: assertion labels and patterns are written so the audit cannot match its own text"
    - "Spec correction in place with the arithmetic, rather than silent divergence between contract and artifact"

key-files:
  created: []
  modified:
    - scripts/smoke.sh
    - scripts/flip.sh
    - README.md
    - .planning/phases/02-the-live-http-cutover/02-UI-SPEC.md

key-decisions:
  - "D1 is closed by removing the confirming request in the reset direction, not by reordering it. Truncate-then-request would leave one evidence line and break three CUT-05 assertions; the reset has nothing to seed by definition"
  - "The token audit lives in section_cutover rather than a fifth section, because the file it reads is written by the same phase and a section that could run before that file exists would pass vacuously"
  - "UI-SPEC's row height corrected 68px -> 52px and its edge bar accent -> #ffffff, in the document rather than only in the summary, so the contract stops contradicting the artifact"
  - "Two plan acceptance criteria are unsatisfiable as literally written (the set -e count and the sudo count); both are self-referential transcription problems, and each was verified in a corrected form that preserves the substance"

patterns-established:
  - "A mechanical guard is only accepted once a deliberate violation has been shown to turn it red"

requirements-completed: [EVID-02, EVID-03, CUT-05]

coverage:
  - id: D1
    description: "UI-SPEC's binding token rules are permanent suite assertions: exactly 4 font sizes and 2 weights, the accents as fills only, panel separation carried by the 2px border, the valid root-scale form present and the invalid one absent"
    requirement: "EVID-02"
    verification:
      - kind: command
        ref: "sh scripts/smoke.sh cutover — 9 typography/colour/scale assertions PASS"
        status: pass
      - kind: command
        ref: "teeth: fifth font size, third font weight, accent-as-text-colour, stripped panel border, divide-by-a-length root scale — each introduced deliberately, each caught, each reverted"
        status: pass
    human_judgment: false
  - id: D2
    description: "The render discipline (T-02-01) and the offline guarantee (ENV-03 / UI-SPEC 2) cannot be undone by a later edit"
    requirement: "EVID-03"
    verification:
      - kind: command
        ref: "zero markup-parsing sinks (innerHTML|outerHTML|insertAdjacentHTML|document.write|createContextualFragment), exactly one textContent funnel, zero src/href, zero CDN, zero foreign origin"
        status: pass
      - kind: command
        ref: "teeth: innerHTML reintroduced into the txt() helper and an external stylesheet added — 5 assertions went red across the two"
        status: pass
    human_judgment: false
  - id: D3
    description: "Deferred item D1 closed structurally: flip.sh's reset direction can no longer flash the convergence sequence"
    requirement: "CUT-05"
    verification:
      - kind: command
        ref: "3 D1 assertions in section_cutover: forward issues exactly 1 confirming request, reset issues 0, the evidence ends at 0 bytes with no post-truncation row"
        status: pass
      - kind: integration
        ref: "driven live: flip new -> confirming request printed; flip old -> evidence cleared, 0 bytes, /api/status reports NO_TRAFFIC / AWAITING_FIRST_REQUEST"
        status: pass
    human_judgment: false
  - id: D4
    description: "The evidence volume's whole lifecycle including its removal by the teardown (CUT-05)"
    requirement: "CUT-05"
    verification:
      - kind: command
        ref: "make reset && make test from cold — 116 passed, 0 failed"
        status: pass
    human_judgment: false
  - id: D5
    description: "A presenter who has never seen the demo can find every Phase 2 command, both log views, the status page and its two readings, the between-takes reset and both live failure modes in README.md"
    requirement: "EVID-02"
    verification:
      - kind: command
        ref: "9094, flip-old, flip-new, logs-demo, clear-evidence all documented; make -n over all 11 documented targets exits 0; every app.demo.* token is the reserved .test form"
        status: pass
    human_judgment: true
    rationale: "Whether the prose actually works 60 seconds before walking on stage is a judgment about a reader, not a grep. The mechanical half — every named command exists, every port and reset path is documented — is asserted."
  - id: D6
    description: "The long-path backstop: a path over 28 characters truncates with an ellipsis, never wraps, and every row keeps the same height so the boundary rule's pixel position is unchanged"
    verification:
      - kind: integration
        ref: "human + orchestrator: re-tested with an 82-character path SEGMENT after the original query-string command was found to test nothing. Server stores the full string; truncation verified client-side"
        status: pass
      - kind: command
        ref: "4 static assertions: overflow:hidden + white-space:nowrap on .row span, text-overflow:ellipsis on .row .c-path, the fixed 38.75rem column, and shortPath()/PATH_MAX=28 wired into the render path"
        status: pass
    human_judgment: false
  - id: D7
    description: "The zero-one-many backstop: two or more flips inside the 8-row window render exactly one boundary rule, the most recent"
    verification:
      - kind: integration
        ref: "orchestrator-driven double flip: /api/status reported exactly one boundary object (from NEW to OLD) with row_index 2 for the 2 post-flip rows above it; traffic OLD, config OLD, sync IN_SYNC"
        status: pass
      - kind: command
        ref: "EVID-03 suite assertion: two transitions in the window yield exactly ONE boundary, the most recent"
        status: pass
    human_judgment: false
  - id: D8
    description: "The visual half of the design contract: greyscale distinguishability, legibility at projection distance, four states pairwise distinguishable, the reduced-motion ring, partial-failure collapse, offline rendering, and whether the flip reads as an event to a fresh observer"
    verification: []
    human_judgment: true
    rationale: "Seven of the nine audit items are judgments a human makes with their eyes at distance, in a room, watching another human's reaction. All seven were confirmed approved. UI-SPEC's projector-overscan item remains genuinely unresolved and is carried forward, not closed."

# Metrics
duration: 71 min
completed: 2026-07-21
status: complete
---

# Phase 2 Plan 04: Closing the Phase — the Token Audit, the Presenter Surface, and the Visual Sign-off Summary

**UI-SPEC's design contract stopped being a document and became 21 assertions in the same suite that gates the routing behaviour — each one demonstrated to go red against a deliberate violation — while the two contradictions the contract carried were corrected in place, the one structural race left over from Wave 3 was closed at its source in `flip.sh`, and the nine visual items no grep can check were put in front of a human and approved.**

## Performance

- **Duration:** 71 min
- **Started:** 2026-07-21T09:40Z
- **Completed:** 2026-07-21T10:51Z
- **Tasks:** 2 planned, executed as 6 commits (the plan's two tasks plus the inherited D1 fix, the spec correction, and two defects found during verification)
- **Files modified:** 4

## Accomplishments

- **The design contract has teeth, and the teeth were proven.** Twenty-one static assertions now cover UI-SPEC's mechanical acceptance tests 2, 10 and 11 plus T-02-01, T-02-16 and D-22. Every class was validated by introducing a real violation and confirming red: a fifth font size (2 red), a third font weight (1), an accent used as a text colour (1), a stripped panel border (1), a divide-by-a-length root scale (2), `innerHTML` back in the render funnel (2), an external stylesheet (3), and a `sudo` in a recipe position (1). All reverted; the tree is byte-identical to HEAD afterwards.
- **Deferred item D1 is closed structurally, not probabilistically.** `flip.sh` issued a real confirming request on OLD and truncated the evidence roughly a second later, so the traffic reading genuinely moved NEW → OLD inside that window and a 1 s poll landing in it fired the status page's convergence sequence — the money shot, spent on a reset, measured at 1 occurrence in 3. The reset direction now truncates and issues no request at all. The page cannot see a truncation coming, so no client-side guard could ever make this deterministic; removing the request removes the window itself.
- **UI-SPEC no longer contradicts the artifact it specifies.** Row height corrected 68px → 52px with the full arithmetic (the honest minimum stack came to ~1267px against a 1080px frame the same document declares must never scroll), and the edge bar corrected from accent to `#ffffff` (an accent bar on an accent row is invisible, which deletes the Shape channel — mandatory, not decorative, because the two accents are isoluminant).
- **A vacuous test was caught before it could be trusted.** UI-SPEC's own example for the long-path backstop was `/whoami?trace=…`. The evidence log records `path` from `$uri`, which has the query string stripped, so that URL logs as `/whoami` — 7 characters — and the check would have passed without ever reaching the 28-character threshold. Corrected in the spec, in the README, and pinned by four assertions covering the three truncation prerequisites.
- **The README now works cold.** A presenter who has never seen the demo can find the status page and its port, what its two readings mean and why they are deliberately not merged, the three sync captions, the four states, both log views, the between-takes reset, the two failure modes they will actually hit with recovery commands, and the known asymmetry where 9092 follows the cutover and 9093 does not.
- **The full lifecycle is green from cold.** `make reset && make test` — a complete teardown including removal of the evidence volume, a rebuild, and all four sections — reports `--- 116 passed, 0 failed ---`. Phase 1's regression guard, `sh scripts/smoke.sh proxy`, still reports exactly `--- 17 passed, 0 failed ---`.

## Task Commits

1. **Deferred D1 — the reset direction seeds nothing, so it requests nothing** — `6a97fb8` (fix)
2. **Task 1: the UI-SPEC token audit as a permanent regression guard** — `5e0fc48` (feat)
3. **The UI-SPEC corrections carried from Wave 3** — `30495e8` (docs)
4. **Task 2: the presenter's Phase 2 surface, and T-02-16 re-asserted** — `9138c9a` (docs)
5. **The long-path backstop's test command, which could not exercise it** — `f386fe2` (fix)
6. **The healthcheck-silence assertion's latent flake** — `30844a9` (fix)

## Files Modified

- **`scripts/smoke.sh`** (+~150 lines) — three D1 assertions; the UI-SPEC token audit block (typography, colour-as-fill, panel border, root scale, offline, render discipline, long-text truncation, D-22 hostname); T-02-16 split into three checks; one settle added to a pre-existing assertion. Section count unchanged at four. Still POSIX `sh`, still deliberately not `set -e`.
- **`scripts/flip.sh`** — step 6 split by direction: forward issues one confirming request as before, reset truncates and issues none, with the reasoning recorded at the point of the branch.
- **`README.md`** (+~180 lines) — the status page section, the two readings and the rejected merge, the honest UNAVAILABLE state, the four states, the between-takes reset on screen, troubleshooting, the 9092/9093 asymmetry; plus the 9094 port row, the updated mnemonic, the layout tree, and the command reference.
- **`02-UI-SPEC.md`** — three corrections in place, each with its arithmetic and its consequence.

## Decisions Made

- **D1 is closed by removing the request, not by reordering it.** The deferred item offered both. Truncate-then-request leaves exactly one evidence line, which breaks the CUT-05 assertions that the reset leaves the log at 0 bytes and the page at `NO_TRAFFIC` with zero rows and a null boundary. The reset direction exists to leave every reading at zero; it has nothing to seed by definition.
- **The token audit lives in `section_cutover()`.** A fifth section could be invoked before the file it greps exists, and would then pass vacuously — the worst possible failure mode for a regression guard.
- **T-02-16 is three assertions, not one.** An audit that greps its own directory has to be written so it cannot match its own text. The executable trio (Makefile, `flip.sh`, `compose.yaml`) is pinned to exactly one occurrence and that occurrence is required to be printed rather than run; the suite file itself is covered by a structural command-position check that holds regardless of how the audit is worded.
- **The visual audit's verdicts are recorded per item**, with the two backstop considerations resolved explicitly rather than assumed, and the one unresolved consideration left unresolved.

## The Nine-Item Visual Audit — verdicts

| # | Item | UI-SPEC test | Verdict |
|---|------|--------------|---------|
| 1 | Greyscale: which backend is active, and where the flip happened | 1 (non-negotiable) | **PASS** |
| 2 | Distance: Hero word and boundary caption at ~10 m | 3, 5 | **PASS** |
| 3 | Four states pairwise distinguishable with no caption | 5 | **PASS** |
| 4 | Reduced motion: a visible white ring still marks the flip | 9 | **PASS** |
| 5 | **Long path truncates, never wraps, row height uniform** | backstop | **PASS — backstop RESOLVED** (see below) |
| 6 | **Double flip renders exactly one boundary rule** | backstop | **PASS — backstop RESOLVED** |
| 7 | Partial failure collapses to FULL unavailable | 13 | **PASS** |
| 8 | Offline: identical rendering, zero failed requests | 2 | **PASS** |
| 9 | A fresh observer can narrate what happened unprompted | 02-VALIDATION | **PASS** |

**Item 6 detail.** After `flip-new` → request → manual edit back to `old` → `make reload` → request, `/api/status` reported exactly **one** boundary object (`from: NEW, to: OLD`), not two, with `row_index: 2` — correct for the two post-flip rows above it — and `traffic: OLD, config: OLD, sync: IN_SYNC`. The "only the most recent boundary renders" rule holds; two white rules would have read as a striped table rather than as one event.

**Item 5 detail, and a defect in how it was being tested.** The command originally proposed for this item used a long *query string*, which cannot exercise the rule at all — see "Issues Encountered". Re-tested with an 82-character path *segment*. The server stores the full string, which is correct: truncating evidence at the source is lossy. Truncation is client-side, and all three prerequisites are present and now asserted — `overflow:hidden` + `white-space:nowrap` on `.row span`, `text-overflow:ellipsis` on `.row .c-path`, and a fixed `38.75rem` grid column, plus `shortPath()` with `PATH_MAX = 28` in the render path. `nowrap` is the load-bearing one: it is what guarantees the uniform row height the boundary rule's pixel position depends on.

## Wave 3's Carried Items — how each was closed

| Carried from 02-03 | Resolution | Commit |
|---|---|---|
| UI-SPEC's vertical budget does not sum; 52px shipped against a stale 68px contract | Corrected in `02-UI-SPEC.md` in three places, with the full arithmetic and the note that uniformity is load-bearing while magnitude is not | `30495e8` |
| The edge bar is white, not accent; the contract asked for both and would render it invisible | Corrected in `02-UI-SPEC.md` in two places, with the isoluminance reason the Shape channel is mandatory | `30495e8` |
| Deferred D1: `flip.sh old` fires the convergence animation ~1 time in 3 | Fixed at source in `scripts/flip.sh`; pinned by three assertions | `6a97fb8` |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical] The long-path backstop's test command could not exercise the rule it tested**

- **Found during:** the human checkpoint, raised by the orchestrator
- **Issue:** UI-SPEC's own worked example for this backstop is `/whoami?trace=…`. The evidence log records `path` from `$uri`, which has the query string **stripped** (`$request_uri` keeps it in a separate field), so that URL logs as `/whoami` — 7 characters, nowhere near the 28-character threshold. Any run driven from that example reports PASS without truncation ever occurring. A green check that cannot go red is worse than no check, because it is trusted.
- **Fix:** the example corrected in `02-UI-SPEC.md` with the reason and the working replacement; the same caveat added to README in presenter language; four static assertions added pinning the three truncation prerequisites and the 28-character helper being wired into the render path. Teeth confirmed by removing `white-space:nowrap` and watching the assertion go red.
- **Files modified:** `.planning/phases/02-the-live-http-cutover/02-UI-SPEC.md`, `README.md`, `scripts/smoke.sh`
- **Committed in:** `f386fe2`

**2. [Rule 1 - Bug] A pre-existing assertion was intermittently red**

- **Found during:** the closing verification run of `section_cutover`
- **Issue:** `EVID-03 three healthcheck intervals with no user traffic change no reading` measures both counters and the evidence line count across a 10 s silent window. The block above it ends with a `curl` whose evidence line is not necessarily visible to the next read yet. When it landed between the two snapshots the assertion reported a reading change during the silence and blamed the healthchecks for traffic the suite had issued itself. Observed once; reproduced as a timing race, not a behaviour change.
- **Fix:** a 0.5 s settle before the first snapshot, with the reason recorded beside it. In scope because a suite whose entire value is "green means green" cannot carry a flaky assertion out of the phase that finalises it.
- **Files modified:** `scripts/smoke.sh`
- **Verification:** `sh scripts/smoke.sh cutover` → `--- 78 passed, 0 failed ---`
- **Committed in:** `30844a9`

**3. [Rule 3 - Blocking] Two assertions were self-referential and reported on their own text**

- **Found during:** Task 1
- **Issue:** the D-22 hostname audit greps `scripts/`, which includes `smoke.sh`, so spelling the token in the assertion's own label made the check match itself. The T-02-16 escalation audit had the same problem in a subtler form: its filter happened to work only because the audit line coincidentally contained the word it filtered on, which is not a property to depend on.
- **Fix:** the D-22 label reworded to avoid the literal token, with a comment saying why. T-02-16 split into three: an exact count over the executable trio, a check that the single occurrence is printed rather than run, and a structural command-position check (`^\s*sudo ` or after `;&(`) that holds for the suite file regardless of wording. Teeth confirmed against a fake recipe in both the Makefile and `flip.sh`.
- **Files modified:** `scripts/smoke.sh`
- **Committed in:** `5e0fc48`, `9138c9a`

---

**Total deviations:** 3 auto-fixed (1 bug, 1 missing-critical, 1 blocking), plus the inherited D1 fix and the UI-SPEC corrections, both of which were assigned to this plan rather than discovered by it.
**Impact on plan:** no change to the file inventory, the architecture or the command surface. Deviation 1 is the only one that changes what is believed to be true: one backstop was, until it was caught, being verified by a command that could not fail.

## Authentication Gates

None — nothing in this plan touches an authenticated service. No package was installed; the plan wrote shell assertions and Markdown only, so no package-legitimacy checkpoint arose.

## Issues Encountered

- **Two of the plan's acceptance criteria are unsatisfiable as literally written.** Both are self-referential transcription problems of exactly the kind 02-03 recorded, and each was verified in a corrected form preserving the substance:
  1. `grep -c 'set -e' scripts/smoke.sh` is 0 — the file's own header comment reads "Deliberately NOT `set -e`", which is the explanation the criterion exists to protect. Verified instead as `grep -v '^[[:space:]]*#' scripts/smoke.sh | grep -c 'set -e'` → **0**. No executable `set -e` exists.
  2. `grep -v '^[[:space:]]*#' Makefile scripts/*.sh compose.yaml | grep -c 'sudo'` is 0 — the same plan's threat model explicitly permits the token in `make status`'s printed remediation line, which is a non-comment line. Verified as: the executable trio carries exactly **one** occurrence, that occurrence is inside an `echo`, and the token appears in a command position in **zero** files. All three are now permanent assertions.
- **`grep -oE 'https?://...' | grep -vc 'localhost'` is 0** conflicts with UI-SPEC's mandatory empty-state copy, exactly as 02-03 reported. The copy ships verbatim; the assertion allows `localhost` and the D-22 demo host and is otherwise zero. `app.demo.test` is a string the presenter reads aloud, not an origin the page contacts — separately proven by the zero-`src`/`href` assertion, which is the stronger claim.
- **UI-SPEC's projector-overscan consideration remains genuinely unresolved.** It cannot be settled without the venue hardware. Carried forward honestly rather than auto-backstopped; see below.

## Known Stubs

None. Nothing was placeheld, mocked or deferred in this plan.

## Threat Flags

None. This plan introduces no network endpoint, no auth path, no file access and no schema change. It strengthens three existing mitigations — T-02-01 (render discipline, now a permanent assertion covering five markup sinks rather than one), T-02-15 (the token audit itself, with its teeth demonstrated), and T-02-16 (host-state escalation, re-asserted three ways after Phase 2's additions).

## Verification Results

| Check | Result |
|-------|--------|
| `sh scripts/smoke.sh` (all four sections) | `--- 116 passed, 0 failed ---` |
| `sh scripts/smoke.sh proxy` (Phase 1 regression guard) | `--- 17 passed, 0 failed ---` |
| `sh scripts/smoke.sh cutover` (after the final two fixes) | `--- 78 passed, 0 failed ---` |
| `sh scripts/smoke.sh backends` / `redirect` | `13 passed, 0 failed` / `12 passed, 0 failed` |
| `make reset && make test` from cold | `--- 116 passed, 0 failed ---` |
| `sh -n scripts/smoke.sh`, `sh -n scripts/flip.sh` | exit 0 |
| Executable `set -e` in `scripts/smoke.sh` | 0 |
| Distinct font sizes / `--fs-` tokens / font weights | 4 / 4 / 2 (400 and 700 exactly) |
| Accents used as text or border colour (hex or token) | 0 |
| `.panel` 2px hairline border, and panels using it | present, 3 |
| Root scale: valid form / invalid divide-by-a-length | 1 / 0 |
| Markup-parsing sinks in `status/index.html` | 0 across five sink names; exactly 1 `textContent` funnel |
| `src`/`href` attributes / CDN references / foreign origins | 0 / 0 / 0 |
| Demo-hostname tokens across `status/ scripts/ proxy/ Makefile compose.yaml README.md` | all `app.demo.test` |
| Escalation token in a command position, four files | 0 |
| Guard teeth: 8 deliberate violations across 7 classes | all caught; tree reverted byte-identical |
| `make -n flip flip-old flip-new logs logs-demo clear-evidence up down reset test status` | exit 0 |
| README coverage: `9094` / `flip-old` / `flip-new` / `logs-demo` / `clear-evidence` | 3 / 5 / 3 / 3 / 3 |
| `curl http://localhost:9094/` | `200`, 27,815 bytes |
| Nine-item human visual audit | **approved**, all nine PASS |

Final state: five services up, four healthy plus `client`, selector on **OLD**, evidence cleared, `GET /` serving the page. Working tree clean apart from the orchestrator-owned `.planning/config.json`.

## Next Phase Readiness

**Phase 2 is complete. All four ROADMAP criteria are demonstrable end to end from a cold start.**

What Phase 3 inherits:

- **A four-section suite at 116 assertions**, including a design-contract audit that will go red if a later phase edits `status/index.html` carelessly. Phase 3 adds the `stream` block for SSH; ENV-04 already asserts the module is compiled in, and nothing in the token audit constrains stream configuration.
- **A stable presenter vocabulary in README.md.** Phase 4's WALK-01 walkthrough extends this rather than duplicating it — the port narration ("90 old, 91 new, 92 proxies, 93 redirects, 94 shows you"), the three flip command shapes, and the between-takes reset are the terms that walkthrough should reference.
- **The 9092/9093 asymmetry is now documented rather than folklore.** If Phase 3 or 4 changes it, the README section is the place that has to move with it.
- **One genuinely unresolved item, carried forward honestly:** UI-SPEC's projector-overscan consideration. The assumption is that a 48px inset is sufficient for typical keystone correction and overscan; it cannot be verified without the actual venue projector. If the venue crops harder, `--safe` is the single value to raise — it is declared once as a token and no other geometry depends on its magnitude. This is not closed and should not be recorded as closed.
- **The 12px edge-bar cap** (raised by 02-03) rendered and survived the distance check as part of item 2, but it remains reinforcement rather than load-bearing: the word, the rail position and the boundary rule each carry the OLD/NEW signal independently.

No blockers.

## Self-Check: PASSED

All four modified files verified present on disk. All six commits (`6a97fb8`, `5e0fc48`, `30495e8`, `9138c9a`, `f386fe2`, `30844a9`) verified present in git history on `gsd/phase-02-the-live-http-cutover`.

---
*Phase: 02-the-live-http-cutover*
*Completed: 2026-07-21*
