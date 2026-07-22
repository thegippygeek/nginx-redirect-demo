---
phase: 03-ssh-through-the-stream-proxy
plan: 03
subsystem: verification
tags: [verify, evidence, exit-codes, posix-sh, smoke-tests, d-44, d-45, evid-04, evid-05]

requires:
  - "03-01: the pre-auth identity banner and non-interactive key auth from the client container"
  - "03-02: the stream block — SSH reaching the selected backend through app.demo.test:22"
  - "Phase 1/2 scripts/flip.sh and scripts/smoke.sh — the POSIX-sh idiom this script extends"
provides:
  - "EVID-04: one command issues an HTTP request and an SSH connection and reports which backend answered each, on labelled lines, in a fixed order, in every outcome"
  - "EVID-05: non-zero on any disagreement — exit 1 against the expectation, exit 3 when the two protocols disagree with each other"
  - "scripts/verify.sh — the phase's assertion tool, and its own test subject"
  - "make verify / make verify EXPECT=new — the presenter's command surface, completed"
  - "VERIFY_SSH_HOST — a documented test seam that makes the D-45 branch reachable by real disagreement rather than simulation"
  - "scripts/smoke.sh section_ssh — 18 further assertions (66 in the section, 186 in the suite)"
affects:
  - "Phase 4 KEY-01..04: verify.sh pins both host-key options with the reason named in a comment, so the staged mismatch cannot silently turn routing assertions into host-key assertions"
  - "Phase 4 WALK-01/02/03: the README's Phase 3 section is deliberately beat-level only — the end-to-end narrative is left untouched"

tech-stack:
  added: []
  patterns:
    - "capture-then-read-status: an ssh invocation assigned with command substitution, `rc=$?` on the very next line, never on the left of a pipe"
    - "a distinct exit code per failure MEANING (usage / mismatch / cross-protocol disagreement), not per failure site"
    - "an env-var test seam that produces a GENUINE failure state, so a failure branch is proven reachable rather than mocked"
    - "static guards over a comment-stripped script, with a non-empty assertion beside them so a missing file cannot pass them all vacuously"

key-files:
  created:
    - scripts/verify.sh
  modified:
    - scripts/smoke.sh
    - Makefile
    - README.md

key-decisions:
  - "Exit-code vocabulary 0/1/2/3, with usage deliberately NOT sharing a code with mismatch: on stage a fumbled invocation must never be readable as a failed cutover, and a distinct code for the cross-protocol disagreement is what lets the smoke suite prove D-45's branch is reachable rather than merely present in the source."
  - "The disagreement check runs FIRST in the verdict. Both readings are individually valid in that case, so the mismatch branch would also fire — and would discard the only information the presenter needs, which is that the flip landed on exactly one of the two protocols."
  - "Two readings per SSH probe from ONE capture: the banner is the contractual identity claim (the backend asserting who it is) and the remote command's stdout corroborates that a shell really ran there. The two disagreeing is itself a mismatch with its own words — a banner is rendered from an env var while a hostname comes from the kernel."
  - "The script runs from the HOST and shells out for the SSH half via one `docker compose exec -T client` line, matching flip.sh exactly. The HTTP half already needs a host-side request against the published port; splitting the script across two execution contexts would be worse than one exec line."
  - "Every reading is a GREP of the captured variable, never an equality comparison: the host-key options make ssh emit a `Permanently added ...` notice on stderr on every single run."
  - "The concurrency-edge assertion uses the host `timeout` only when it exists (`command -v`), because a stock macOS does not ship one — the outer bound is a tripwire, and the assertion proper is that the run ended under its own power inside 45s."

requirements-completed: [EVID-04, EVID-05]

coverage:
  - deliverable: "EVID-04 — one command, two protocols, one labelled line each, fixed order, every outcome"
    verification:
      - kind: test
        ref: "scripts/smoke.sh#section_ssh EVID-04 verify.sh old on an OLD rig exits 0 and reports BOTH protocols"
        status: pass
      - kind: test
        ref: "scripts/smoke.sh#section_ssh EVID-04 ordering edge: the HTTP reading line precedes the SSH reading line"
        status: pass
      - kind: test
        ref: "scripts/smoke.sh#section_ssh EVID-04 adjacency edge: an unreachable SSH target still prints both labelled lines"
        status: pass
      - kind: test
        ref: "scripts/smoke.sh#section_ssh EVID-04 empty edge: no argument / an unrecognised argument prints usage and exits 2 (2 assertions)"
        status: pass
      - kind: test
        ref: "scripts/smoke.sh#section_ssh EVID-04 concurrency edge: an unreachable SSH target ends the run promptly, under its own power"
        status: pass
      - kind: command
        ref: "sh scripts/verify.sh old -> rc=0, HTTP and SSH lines both naming OLD server-old"
        status: pass
    human_judgment: false
  - deliverable: "EVID-05 — non-zero on mismatch, a distinct code and distinct words on cross-protocol disagreement (D-45)"
    verification:
      - kind: test
        ref: "scripts/smoke.sh#section_ssh EVID-05 mismatch: verify.sh new on an OLD rig exits 1 and names the mismatch"
        status: pass
      - kind: test
        ref: "scripts/smoke.sh#section_ssh EVID-05/D-45 disagreement: HTTP on OLD and SSH on NEW exits 3, not 1"
        status: pass
      - kind: test
        ref: "scripts/smoke.sh#section_ssh EVID-05/D-45 the disagreement message names which protocol reported which backend"
        status: pass
      - kind: test
        ref: "scripts/smoke.sh#section_ssh EVID-05 end to end: verify.sh new / verify.sh old exit 0 across a real flip (2 assertions)"
        status: pass
      - kind: command
        ref: "sh scripts/verify.sh new on an OLD rig -> rc=1; VERIFY_SSH_HOST=server-new sh scripts/verify.sh old -> rc=3"
        status: pass
    human_judgment: false
  - deliverable: "T-03-11 — the script cannot report success on a total SSH failure"
    verification:
      - kind: test
        ref: "scripts/smoke.sh#section_ssh EVID-05 guard: no ssh invocation sits on the left of a pipe in verify.sh (comment-stripped)"
        status: pass
      - kind: test
        ref: "scripts/smoke.sh#section_ssh EVID-05 guard: the comment-stripped verify.sh is a non-empty script"
        status: pass
      - kind: test
        ref: "scripts/smoke.sh#section_ssh EVID-04 guard: no quiet, log-level-lowering or forced-pty ssh option in verify.sh"
        status: pass
    human_judgment: false
  - deliverable: "T-03-04 — the relaxed host-key options carry their reason, so the repo does not normalise them"
    verification:
      - kind: test
        ref: "scripts/smoke.sh#section_ssh T-03-04 verify.sh carries both host-key options"
        status: pass
      - kind: test
        ref: "scripts/smoke.sh#section_ssh T-03-04 verify.sh explains those options and names the phase that needs them"
        status: pass
    human_judgment: false
  - deliverable: "T-03-13 — a hung SSH probe can never block verify.sh or the suite"
    verification:
      - kind: test
        ref: "scripts/smoke.sh#section_ssh T-03-13 guard: every ssh invocation in verify.sh is wrapped in an external timeout"
        status: pass
      - kind: command
        ref: "VERIFY_SSH_HOST=no-such-backend.invalid sh scripts/verify.sh old -> rc=1 in 0.3s, both lines printed"
        status: pass
    human_judgment: false
  - deliverable: "The presenter's command surface and the Phase 3 README beats"
    verification:
      - kind: command
        ref: "make verify -> rc=0; make verify EXPECT=new on an OLD rig -> recipe fails, the mismatch line is printed"
        status: pass
      - kind: command
        ref: "grep 'make verify' README.md / grep 'app.demo.test' README.md / grep -ci 'REMOTE HOST IDENTIFICATION' README.md -> 0"
        status: pass
    human_judgment: false
  - deliverable: "Regression surface intact"
    verification:
      - kind: command
        ref: "sh scripts/smoke.sh proxy -> 17 passed, 0 failed (before and after the Makefile edit)"
        status: pass
      - kind: command
        ref: "make test -> 186 passed, 0 failed; anchored gate '--- [0-9]+ passed, 0 failed ---' matched over the whole output"
        status: pass
    human_judgment: false
  - deliverable: "D-37 on stage: whether `docker compose exec client ssh …` reads as the honest command or as a cheat"
    human_judgment: true
    rationale: "The plan's human-check asks a presenter to run the Phase 3 beats cold and report whether the client-container framing is acceptable to the intended audience. That is the one auto-selected decision flagged as worth revisiting and no assertion can answer it."

metrics:
  duration: "40 min"
  tasks: 3
  files: 4
  completed: 2026-07-21

status: complete
---

# Phase 3 Plan 03: The Two-Protocol Verifier Summary

`scripts/verify.sh` — one command that issues an HTTP request and an SSH connection, reports which
backend answered each on its own labelled line, and **can say no** in three distinguishable ways,
including the one the demo actually cares about: one protocol flipped and the other did not.

## Accomplishments

- **`scripts/verify.sh`**, POSIX `sh`, following `flip.sh`'s conventions exactly — a header that
  gives each step its measured reason, `usage()` + exit 2, deliberately not `set -e` so both
  protocols are always reported. Exit vocabulary **0 / 1 / 2 / 3**: success, mismatch against the
  expectation, usage, and the two protocols disagreeing with each other.
- **The capture idiom, with the measurement inline.** The ssh invocation is assigned with command
  substitution and its status read on the very next line, never on the left of a pipe — the comment
  above it names the measured bug (`ssh … | head` returning `EXIT=0` while the output read
  `Host key verification failed.`) that would otherwise make EVID-05 a lie.
- **Two readings per protocol.** The SSH banner is the contractual identity claim; the remote
  command's own stdout corroborates that a shell really ran there. The two disagreeing is itself a
  mismatch, with its own sentence.
- **A real, non-simulated failure test.** `VERIFY_SSH_HOST` points the SSH half at a named backend
  while the selector says the other one. Both readings are then individually valid and they disagree
  — so exit 3 is proven **reachable**, not merely present in the source.
- **`make verify` / `make verify EXPECT=new`**, placed immediately after the flip targets so the
  presenter's command surface reads in narrative order.
- **18 further assertions in `section_ssh`** (66 in the section, 186 in the suite): the happy path,
  all four probe edges, both failure paths live, the end-to-end flip in both directions, and six
  static guards over the **comment-stripped** script.
- **The Phase 3 presenter section of the README** — the ssh command and why it runs from the client
  container, the cutover with the identical command, `make verify` and what each non-zero exit
  means, the shared `include` on screen, the rebuild note and the keys. Reference sections (command
  table, layout, section list, intro) brought up to date at the same time.

## Task Commits

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | RED EVID-04/EVID-05 assertions | `a8a09da` | `scripts/smoke.sh` |
| 2 | `scripts/verify.sh` + `make verify` | `d41621a` | `scripts/verify.sh`, `Makefile` |
| 3 | The Phase 3 presenter section | `2d18b71` | `README.md` |

TDD gates: `test(03-03)` at `a8a09da` (**14 FAIL, 52 PASS** — RED), `feat(03-03)` at `d41621a`
(**66 PASS, 0 FAIL** — GREEN). No refactor commit was needed.

## Verification Results

| Check | Result |
|-------|--------|
| `sh scripts/verify.sh old` (rig on OLD) | rc **0**, two labelled lines, both `OLD server-old` |
| `sh scripts/verify.sh new` (rig on OLD) | rc **1**, both lines still printed, `MISMATCH expected NEW; HTTP reported OLD, SSH reported OLD.` |
| `sh scripts/verify.sh` / `sh scripts/verify.sh bogus` | rc **2** each, usage line on stderr |
| `VERIFY_SSH_HOST=server-new sh scripts/verify.sh old` | rc **3**, `PROTOCOLS DISAGREE HTTP reported OLD, SSH reported NEW` |
| `VERIFY_SSH_HOST=no-such-backend.invalid …` | rc **1** in **0.29 s**, both labelled lines present, `SSH … -> UNREADABLE (exit 255)` |
| `make verify` | rc 0, the OK line |
| `make verify EXPECT=new` on an OLD rig | recipe fails loudly (`make: *** [verify] Error 1`) with the mismatch line printed |
| Comment-stripped guards: pipe / quiet / log-level / forced-pty | 0 occurrences each |
| Host-key options + a comment naming phase 4 and "demo-only" | present, both asserted |
| `grep -ci 'REMOTE HOST IDENTIFICATION' README.md` | **0** — nothing of Phase 4 staged or documented |
| `sh scripts/smoke.sh ssh` | **66 passed, 0 failed** |
| `sh scripts/smoke.sh proxy` | **17 passed, 0 failed** — the canonical tripwire, unmoved, after the Makefile edit |
| `make test` | **186 passed, 0 failed**; the anchored gate `--- [0-9]+ passed, 0 failed ---` matched over the whole output |
| Stack at hand-off | five services healthy, selector `old`, `sh scripts/verify.sh old` rc 0 |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] The concurrency-edge assertion cannot assume a host `timeout`**

- **Found during:** Task 1
- **Issue:** The plan specifies wrapping the concurrency-edge invocation in a generous `timeout` on
  the host. Every other `timeout` in this repo runs **inside** the client container, where busybox
  supplies it. A stock macOS ships no `timeout` at all (the one on this machine is Homebrew's), so
  the assertion as literally written would have failed on a clean presenter laptop for a reason
  entirely unrelated to what it tests.
- **Fix:** The assertion uses `command -v timeout` and falls back to a bare invocation, and the
  substantive check is an elapsed-time bound (`< 45 s`) plus `rc` being neither 0 nor a SIGTERM/124
  status. The outer `timeout` is the tripwire; "the run ended under its own power" is the assertion.
- **Files modified:** `scripts/smoke.sh`
- **Commit:** `a8a09da`

**2. [Rule 2 - Missing critical functionality] The banner/hostname corroboration needed a verdict, not just a printed value**

- **Found during:** Task 2
- **Issue:** The plan requires two readings from the one SSH capture but does not say what happens
  when they disagree. Printing both and acting only on the banner would have made the corroborating
  reading decorative — a backend whose banner claimed `NEW server-new` while the shell actually ran
  on `server-old` would have passed.
- **Fix:** A `CORROBORATED` check that emits its own mismatch sentence naming both readings and
  exits 1.
- **Files modified:** `scripts/verify.sh`
- **Commit:** `d41621a`

**3. [Rule 1 - Bug] The README's `## SSH` reference section still said SSH was "not routed and not demoed in this phase"**

- **Found during:** Task 3
- **Issue:** Written in Phase 1 as a forward-looking note; false as of Plan 03-02. A reader arriving
  at the reference section would have been told the opposite of what the presenter section says.
- **Fix:** Rewritten to describe the live behaviour and to link to the new presenter section. The
  command table, layout tree, smoke-section list and intro paragraph were corrected in the same pass
  (all four omitted Phase 3 artefacts that now exist).
- **Files modified:** `README.md`
- **Commit:** `2d18b71`

**Total deviations:** 3 auto-fixed (2 × Rule 2, 1 × Rule 1). **Impact:** none on plan intent; all
three strengthen assertions or correct documentation the plan's own gates would not have caught.

## Implementation Notes for Later Plans

- **Two of the static guards pass VACUOUSLY when `scripts/verify.sh` is missing** — observed for
  real during RED, where "no ssh invocation on the left of a pipe" and "no quiet option" both
  reported PASS against a file that did not exist. This is Plan 02's lesson recurring: any
  negative check over an empty input is satisfied. The `comment-stripped verify.sh is a non-empty
  script` assertion sits immediately before them for exactly this reason and must not be removed.
- **`section_ssh` cannot contain a bare `grep -q "…"`.** Its own guard for quiet ssh options matches
  `-q` delimited by whitespace, so every grep in that section must use a combined flag (`-qE`,
  `-qx`, `-qi`, `-cE`). The same applies to `scripts/verify.sh`, which the guards audit the same
  way. This is not stylistic — a bare `-q` will turn a passing suite red with a confusing label.
- **Static guards that name what they forbid must write the literal with a bracket expression**
  (`s[s]h`, `LogL[e]vel=`, `t[i]meout`), or the assertion's own source line satisfies the pattern it
  audits. Every new guard in this plan follows the idiom `section_cutover` established.
- **`make verify EXPECT=new` failing exits Make with status 2, not 1.** The script's own exit code is
  1; Make reports a failed recipe as 2. Anything asserting the script's vocabulary must call the
  script, not the Make target.
- **The verdict order is load-bearing.** Disagreement is checked before mismatch. Reversing them
  would make exit 3 unreachable whenever the expectation is also wrong — which is most of the time
  in practice.

## Flagged Assumption Status

- **EVID-05 `[probe: unclassified]`** — the planner's judgement was that the boundary here is an
  exit-status edge rather than a data edge, and that it has a measured failure mode. That is now
  closed from both sides: a static guard over the comment-stripped script proves the pipeline shape
  is absent, and four live assertions (mismatch, disagreement, both usage forms) prove the non-zero
  exits are genuinely reachable. The residual unclassified risk — some *other* boundary shape for
  "the observed backend does not match the expected one" — is unchanged and surfaced for the
  verifier.

## Known Stubs

None. Every branch of `scripts/verify.sh` is reached by a live assertion in `section_ssh`.

## Issues Encountered

None outstanding.

## Next Phase Readiness

Phase 3 is complete: SSH into a backend (01), SSH through the proxy (02), and the assertion that both
protocols followed the same word (03). The phase gate is green — `make test` at 186/0, `sh
scripts/smoke.sh proxy` at 17/17, `sh scripts/verify.sh old` at rc 0 and `sh scripts/verify.sh new`
at rc 1 — and the rig is left running, healthy and selecting `old`.

Ready for **Phase 4** (KEY-01..04, WALK-01..03). Nothing of Phase 4 is staged or documented, as
planned: `grep -ci 'REMOTE HOST IDENTIFICATION' README.md` is 0. `scripts/verify.sh` pins both
host-key options with the reason named in a comment and asserted by the suite, so the staged mismatch
will not silently convert this phase's routing assertions into host-key assertions.

Untouched by this plan: `proxy/nginx.conf`, `proxy/active-backend.conf`, `scripts/flip.sh`,
`compose.yaml`, `backend/**`, `client/**`, `status/**`.

## Self-Check: PASSED

- `scripts/verify.sh` — FOUND, executable path exercised across all four exit codes
- `scripts/smoke.sh` — FOUND, `section_ssh` reports 66/66
- `Makefile` — FOUND, `verify` target present and in `.PHONY`
- `README.md` — FOUND, Phase 3 section present, Phase 4 content absent
- Commits `a8a09da`, `d41621a`, `2d18b71` — all FOUND in `git log --all`
- `sh scripts/smoke.sh proxy` re-run at close — 17 passed, 0 failed
