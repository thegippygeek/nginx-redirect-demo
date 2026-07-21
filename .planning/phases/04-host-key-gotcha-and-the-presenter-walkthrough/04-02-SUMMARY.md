---
phase: 04-host-key-gotcha-and-the-presenter-walkthrough
plan: 02
subsystem: testing
tags: [smoke, ssh, host-keys, known_hosts, traps, sighup, posix-sh, negative-control]

requires:
  - phase: 03-ssh-through-the-stream-proxy
    provides: "The smoke harness (assert, settle_flip, selector_now, set_active, keyscan_fp, hostkey_fp), the capture idiom, and the test-mode option set whose deliberate complement presenter mode is"
  - phase: 04-host-key-gotcha-and-the-presenter-walkthrough
    provides: "Plan 04-01's scripts/fix-hostkeys.sh and scripts/rearm.sh — the real presenter targets this section drives rather than reimplements"
provides:
  - "section_hostkey in scripts/smoke.sh — 20 assertions running the five beats of the host-key narrative for real against the live rig (KEY-01..KEY-04)"
  - "sh scripts/smoke.sh hostkey — a first-class section, ~16 s, destructive and self-restoring"
  - "The suite's answer to 'is the gotcha armed and does the fix still work?' in under twenty seconds, instead of finding out in front of people"
affects: [04-03 WALKTHROUGH.md and README, 04-04 sign-off]

tech-stack:
  added: []
  patterns:
    - "A deliberate-failure assertion tests BOTH halves — non-zero status AND the warning text — and is always paired with a negative control in the identical state"
    - "A destructive section restores by driving the rig FORWARD to the suite's invariant state (flip.sh old), not by restoring a snapshot taken on entry"
    - "Region-scoped static guards strip full-line comments first and assert the stripped region non-empty before counting anything negative"

key-files:
  created: []
  modified:
    - scripts/smoke.sh

key-decisions:
  - "The section's traps restore the selector by running scripts/flip.sh old rather than restoring an entry snapshot — guard_check()'s snapshot idiom is wrong here and produced a real bug during execution"
  - "The concurrency probe uses TEST mode deliberately: the question is whether the daemon drops an in-flight session, not whether the client trusts the key"
  - "The concurrency probe and the fingerprint-equality assertions share ONE fix run, so the section applies the fix exactly once"
  - "Phase 3's test-mode pins are asserted present from inside this section — the section whose existence creates the temptation to remove them"

patterns-established:
  - "Pattern 1: both-halves failure assertion + same-state negative control"
  - "Pattern 2: restore-forward, not restore-snapshot, for sections whose contract is an end state"
  - "Pattern 3: a destructive section proves its own restore by being interrupted"

requirements-completed: [KEY-01, KEY-02, KEY-03, KEY-04]

coverage:
  - id: D1
    description: "The five beats — prime on OLD, flip, the failure, the fix, the success — execute for real inside the suite against the live rig"
    requirement: "KEY-01..KEY-04"
    verification:
      - kind: integration
        ref: "sh scripts/smoke.sh hostkey -> '--- 20 passed, 0 failed ---'"
        status: pass
    human_judgment: false
  - id: D2
    description: "The gotcha assertion checks a non-zero exit status AND the changed-identification warning text, with no ssh invocation on the left of a pipe"
    requirement: "KEY-02"
    verification:
      - kind: integration
        ref: "assertion 'KEY-02 the gotcha: a non-zero exit AND the changed-identification warning' (rc=255 measured)"
        status: pass
      - kind: static
        ref: "region-scoped guard: comment-stripped section_hostkey contains 0 lines matching 's[s]h .*|'"
        status: pass
    human_judgment: false
  - id: D3
    description: "A negative control proves the failure is specific: in the identical armed state test mode connects cleanly and reports NEW"
    requirement: "KEY-02"
    verification:
      - kind: integration
        ref: "assertion 'KEY-02 negative control: test mode connects cleanly and reports NEW in the same state'"
        status: pass
    human_judgment: false
  - id: D4
    description: "The fix is asserted by presented ed25519 fingerprint equality read from the running daemon, plus a positive check that the presented value actually CHANGED to the peer's — never by a file listing"
    requirement: "KEY-03"
    verification:
      - kind: integration
        ref: "assertions 'KEY-03 the fix: both backends now present the SAME ed25519 fingerprint' and 'KEY-03 the fix landed in the DAEMON'"
        status: pass
    human_judgment: false
  - id: D5
    description: "KEY-03 concurrency edge: a session opened before the fix and still running when it lands completes and still names its own backend (the daemon re-execs on SIGHUP rather than restarting)"
    requirement: "KEY-03"
    verification:
      - kind: integration
        ref: "assertion 'KEY-03 concurrency edge: a session open across the fix completes and still names its own backend' (rc 0, output 'server-new')"
        status: pass
    human_judgment: false
  - id: D6
    description: "The client's trust record is byte-identical across the fix, asserted by md5 comparison — the mechanical form of KEY-04's 'no client-side edit' claim"
    requirement: "KEY-04"
    verification:
      - kind: integration
        ref: "assertion 'KEY-04 the client's trust record is byte-identical across the fix' (md5 e0f64991149737716e09f30a73e33b3d both sides)"
        status: pass
    human_judgment: false
  - id: D7
    description: "The re-arm is asserted, not assumed: afterwards the two presented fingerprints differ again and the client's trust record is gone"
    requirement: "KEY-01"
    verification:
      - kind: integration
        ref: "assertions 'KEY-01 the re-arm restores the DIFFERING fingerprints' and 'KEY-01 the re-arm clears the client's trust record'"
        status: pass
    human_judgment: false
  - id: D8
    description: "The section is destructive-safe: an interrupted run leaves the rig exactly as a completed one does — selector on old, gotcha re-armed, client trust record cleared, proxy serving"
    verification:
      - kind: integration
        ref: "SIGTERM sent 6 s in (mid-narrative, just past the flip to NEW): trap exited 1; selector 'old', fingerprints differ, known_hosts absent, curl :9092/whoami -> 'OLD server-old', working tree clean"
        status: pass
    human_judgment: false
  - id: D9
    description: "Phase 3's test-mode pins survive untouched in section_ssh and scripts/verify.sh, and all 186 inherited assertions still pass"
    verification:
      - kind: integration
        ref: "sh scripts/smoke.sh proxy -> '--- 17 passed, 0 failed ---'; full suite -> '--- 206 passed, 0 failed ---'; git diff shows 0 lines changed in scripts/verify.sh and no deletions inside section_ssh"
        status: pass
    human_judgment: false
  - id: D10
    description: "The section is a first-class dispatcher entry and runs last in the all chain"
    verification:
      - kind: integration
        ref: "sh scripts/smoke.sh hostkey dispatches; sh scripts/smoke.sh nonsense exits 2 naming hostkey; awk over the all) branch shows section_hostkey as the last section_ call"
        status: pass
    human_judgment: false

duration: 15min
completed: 2026-07-21
status: complete
---

# Phase 4 Plan 02: The Narrative as a Test Result Summary

**The demo's central claim — the host-key failure is real, reachable on demand, and fixable without touching a single client — is now a test result rather than a description: `sh scripts/smoke.sh hostkey` runs all five beats against the live rig in about sixteen seconds and restores it afterwards even when killed mid-narrative.**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-07-21T13:27Z
- **Completed:** 2026-07-21T13:42Z
- **Tasks:** 2 of 2
- **Files modified:** 1 (`scripts/smoke.sh`, +303 / −2)

## Accomplishments

- **The narrative executes.** `section_hostkey` runs the re-arm, primes the client on OLD through the proxied name, flips, catches the failure, applies the fix, connects again, and re-arms — 20 assertions, all driving Plan 04-01's real scripts (`scripts/rearm.sh`, `scripts/fix-hostkeys.sh`, `scripts/flip.sh`) rather than reimplementing their commands. A change to either presenter target now goes red here instead of being discovered on stage.
- **The failure assertion cannot lie.** It checks a non-zero status *and* the `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED` text, with the invocation captured into a variable and `$?` read on the very next line — never on the left of a pipe. A region-scoped, comment-stripped, non-vacuous static guard asserts that property over the section's own source, and a same-state negative control proves test mode still connects and reports `NEW server-new`, so a bug that broke SSH outright cannot masquerade as a passing gotcha.
- **The fix is asserted at the daemon, twice over.** Fingerprint equality between the two backends *plus* a positive check that `server-new`'s presented value actually changed to `server-old`'s — read from the running rig, never from a file listing, because copying the key files is measurably not the fix.
- **The KEY-03 concurrency edge landed** (deferred here from 04-01): a backgrounded, `timeout`-bounded session sleeps across the fix and still reports `server-new` with exit 0. sshd re-execs on SIGHUP rather than restarting, so an in-flight session is not dropped. It shares the single fix run with the fingerprint assertions, and it is waited for — no leaked session pins an old worker generation.
- **KEY-04 is a checksum, not a claim.** `md5sum /root/.ssh/known_hosts` is `e0f64991149737716e09f30a73e33b3d` on both sides of the fix, which only holds because presenter mode pins `UpdateHostKeys=no`. The comment above the assertion names the measured 95 → 837 byte rewrite a maintainer would cause by removing that pin.
- **Destructive-safe, proven by being killed.** SIGTERM six seconds in — mid-narrative, just past the flip to NEW — exited 1 through the interrupt trap and left the rig selector on `old`, the two fingerprints differing, the client's trust record gone, `:9092/whoami` answering `OLD server-old`, and the working tree clean. The normal-exit path was run four times back to back with identical results.
- **Nothing inherited moved.** `sh scripts/smoke.sh proxy` → `--- 17 passed, 0 failed ---`, exactly. Full suite → `--- 206 passed, 0 failed ---` (186 inherited + 20 new). `scripts/verify.sh` has zero changed lines; `section_ssh` has zero deletions. The only two removed lines in the whole plan are the two usage strings, replaced by their `hostkey` variants.

## Task Commits

1. **Task 1: `section_hostkey` — the five beats, asserted** — `f7746b2` (feat)
2. **Task 2: Wire the section into the dispatcher and the `all` chain** — `55270bf` (feat)

## Files Created/Modified

- `scripts/smoke.sh` (modified) — `section_hostkey()` added after `section_ssh()`: header comment block, `PRESENTER_OPTS` and `HK_TESTMODE_OPTS` exported, inline INT/TERM and EXIT traps, six beats, and six static guards. Head-of-file usage comment, dispatcher `case`, `all` chain (last position, with its reason) and the unrecognised-argument usage line all gained `hostkey`.

## Decisions Made

- **The traps restore *forward*, not from a snapshot.** This is the one place the plan's "mirror `guard_check()`" instruction had to be read rather than copied, and it was caught by execution rather than review. `guard_check()` writes a known-bad value and must put back whatever was there; this section's contract is that the rig ends on `old`. The first implementation took a `mktemp` snapshot on entry, and because the rig happened to be on `new` at that moment, the restore silently undid the section's own flip back to `old` — a passing assertion followed by a dirty working tree. The traps and the finish path now run `sh scripts/flip.sh old`, which is also the presenter's real tool and reloads the proxy on its own.
- **The concurrency probe uses test mode on purpose.** The question it asks is whether the daemon drops an in-flight session when signalled, not whether the client trusts the key. Using presenter mode there would have coupled two independent facts and made the assertion unreadable.
- **One fix run serves both KEY-03 assertions.** The in-flight session is started, the fix applied while it runs, then the fingerprints read — so the section applies the fix exactly once and the concurrency edge costs no extra time.
- **Phase 3's pins are guarded from *this* section.** `section_ssh`'s `UserKnownHostsFile=/dev/null` and `verify.sh`'s pair are asserted present here, because this section's existence is what creates the temptation to "unify the two modes" — and doing so would turn 186 routing assertions into host-key assertions.

## Deviations from Plan

**1. [Rule 1 - Bug] The entry-snapshot restore left the selector on `new`**
- **Found during:** Task 1, first live run of the section
- **Issue:** The section backed the selector file up on entry and restored that snapshot on the way out, mirroring `guard_check()`. The rig was on `new` when the section started (left there by the pre-execution probes), so the restore overwrote the `old` the section had just flipped to — leaving `proxy/active-backend.conf` dirty and the next section reading a selector it did not expect. The section's own "leaves the rig selecting old" assertion passed, because it runs *before* the restore.
- **Fix:** Replaced the snapshot with `sh scripts/flip.sh old` in both traps and dropped the `mktemp`/`cp`/`rm` entirely. The reasoning, and the fact that this was a bug rather than a style choice, is recorded in the section's comment so the next reader does not "correct" it back.
- **Files modified:** `scripts/smoke.sh`
- **Verification:** Selector reads `old` and `git status --porcelain proxy/active-backend.conf` is empty after a normal run, after a full-suite run, and after a SIGTERM mid-run.
- **Commit:** `f7746b2`

**2. [Rule 3 - Blocker] Task 1's `<verify>` requires the Task 2 dispatcher**
- **Found during:** Task 1 verification
- **Issue:** Task 1's acceptance criteria and `<verify>` open with `sh scripts/smoke.sh hostkey`, but the dispatcher branch that makes that argument reachable is Task 2's work. Adding the branch early would have hollowed out Task 2; skipping the check would have left Task 1 unverified.
- **Fix:** Task 1 was verified by generating a throwaway harness — `sed '/^section=\${1:-all}/,$d' scripts/smoke.sh` plus a `section_hostkey` call and the suite's own anchored summary line — which runs the real section against the real rig with no change to any tracked file. Every static half of the `<verify>` chain was run unmodified. Task 2 then ran the full `sh scripts/smoke.sh hostkey` for real.
- **Files modified:** none (scratchpad only)
- **Verification:** Harness run → `--- 20 passed, 0 failed ---`; after wiring, `sh scripts/smoke.sh hostkey` → the same 20/20.
- **Commit:** n/a (verification method, no code change)

**Total deviations:** 2 auto-fixed (1 bug, 1 blocker). **Impact:** the bug fix strengthened the plan's own restore requirement — the section now restores to the *contracted* state rather than to an arbitrary entry state, which is what the plan's prohibition actually asked for.

## Issues Encountered

None outstanding. Both deviations above were resolved within Task 1.

Two shapes worth recording for future sections, both discovered while writing the guards:

- A bare `grep -q ` inside an assertion condition would trip this section's own "no quiet option" guard. Every grep in the section uses a combined flag (`-qF`, `-qE`, `-qx`).
- `sh scripts/smoke.sh hostkey` sets `DOCKER_CLI_HINTS=false` because the gotcha assertion runs a `docker compose exec` that is *meant* to fail; the hint block only appears in a TTY, which is the projector and never the suite.

## User Setup Required

None.

## Next Phase Readiness

Ready for 04-03 and 04-04:

- **04-03** (`WALKTHROUGH.md` + the README correction) can now cite `sh scripts/smoke.sh hostkey` as the presenter's pre-flight confidence check — the D-56 checklist item that answers "is the gotcha armed and does the fix still work?" in ~16 s. `section_walkthrough` is 04-03's to add; the dispatcher, the usage comment and the usage line now have a worked example of how a new section is wired in three places.
- **04-04** signs off the projector register (04-01's D7) and ROADMAP criterion 5.

**Rig state left behind:** stack running, five services healthy, selector on `old`, the two backends presenting different ed25519 fingerprints (gotcha armed), client's `known_hosts` absent, no accumulated shutting-down proxy workers, working tree clean apart from `.planning/`.

---
*Phase: 04-host-key-gotcha-and-the-presenter-walkthrough*
*Completed: 2026-07-21*

## Self-Check: PASSED

`scripts/smoke.sh` exists on disk and carries `section_hostkey`; both task commits (`f7746b2`, `55270bf`) are present in git history.
