---
phase: 04-host-key-gotcha-and-the-presenter-walkthrough
plan: 01
subsystem: infra
tags: [ssh, openssh, host-keys, known_hosts, docker-compose, make, sighup, tar, nginx]

requires:
  - phase: 01-the-rig
    provides: "Host keys generated at container start (never in a build layer), so the two backends already present different identities — the mismatch this plan makes reachable"
  - phase: 03-ssh-through-the-stream-proxy
    provides: "SSH through the stream proxy from the client container, and the test-mode option set (StrictHostKeyChecking=no + UserKnownHostsFile=/dev/null) whose deliberate complement presenter mode is"
provides:
  - "scripts/fix-hostkeys.sh — the documented fix: streams server-old's six host-key files into server-new and SIGHUPs the running daemon, proving it landed by fingerprint equality"
  - "scripts/rearm.sh — the in-place, ~1 s re-arm: delete-then-regenerate server-new's host keys, SIGHUP, clear the client's trust record, prove the fingerprints differ"
  - "make ssh — presenter mode, the only mode in which the host-key gotcha is reachable"
  - "make fix-hostkeys and make rearm — the two new presenter commands"
affects: [04-02 smoke section_hostkey, 04-03 WALKTHROUGH.md and README, 04-04 sign-off]

tech-stack:
  added: []
  patterns:
    - "Presenter mode vs test mode: two named, mutually exclusive ssh option sets, each commenting the other by name"
    - "Cryptographic material moves as a tar stream between two `docker compose exec -T` calls — never through a host path"
    - "State changes that live in a daemon's memory are proven by what the daemon PRESENTS (fingerprint), never by a file listing"

key-files:
  created:
    - scripts/fix-hostkeys.sh
    - scripts/rearm.sh
  modified:
    - Makefile

key-decisions:
  - "Presenter mode is an option set on a make target, not an env var or a config file — command-line -o outranks the client's ssh config, and the justification sits directly above the target where a presenter and an audience can both read it"
  - "Both re-arm paths ship: `make reset` stays the documented headline (16.5 s, full rebuild), `make rearm` is the between-takes fast path (~1 s, in place)"
  - "The re-arm regenerates in place and never recreates the container — nginx resolved its upstreams at config-parse time and this rig declares no runtime resolver"
  - "Both new destructive targets are argument-free and hard-wired to one named backend (T-04-01)"
  - "compose.yaml is deliberately unmodified — no volume, no mount, no storage mechanism for the client's trust record (D-48 as corrected by research)"
  - "DOCKER_CLI_HINTS=false is set inside the ssh recipe only, because Compose's hint block appears only in a TTY — never in the suite, always on the projector"

patterns-established:
  - "Pattern 1: presenter mode as an option set (accept-new + UpdateHostKeys=no), not a mechanism"
  - "Pattern 2: the fix as a stream (tar | tar over two container execs) plus a daemon signal, never a staging directory"
  - "Pattern 3: destructive presenter targets take no arguments and gate before mutating"

requirements-completed: [KEY-01, KEY-02, KEY-03, KEY-04]

coverage:
  - id: D1
    description: "scripts/fix-hostkeys.sh transfers server-old's six host keys into server-new AND signals the running daemon; proven by ed25519 fingerprint equality, not by a file listing"
    requirement: "KEY-03"
    verification:
      - kind: integration
        ref: "sh scripts/fix-hostkeys.sh; ssh-keygen -lf on both backends compared (plan 04-01 Task 1 <verify>)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Applying the fix twice on an already-fixed rig exits 0 and leaves the presented fingerprint byte-identical (KEY-03 idempotency edge)"
    requirement: "KEY-03"
    verification:
      - kind: integration
        ref: "second `sh scripts/fix-hostkeys.sh` invocation; fingerprint compared to first run (plan 04-01 Task 1 <verify>)"
        status: pass
    human_judgment: false
  - id: D3
    description: "scripts/rearm.sh restores the differing-key state in place in about a second, with no rebuild and no container recreate, and proves the fingerprints now differ"
    requirement: "KEY-01"
    verification:
      - kind: integration
        ref: "sh scripts/rearm.sh; fingerprints asserted different; curl -fsS http://localhost:9092/whoami still succeeds (plan 04-01 Task 2 <verify>)"
        status: pass
    human_judgment: false
  - id: D4
    description: "After a flip, presenter mode fails with a non-zero exit AND the REMOTE HOST IDENTIFICATION HAS CHANGED banner emitted by the real client"
    requirement: "KEY-02"
    verification:
      - kind: integration
        ref: "full narrative run by hand: rc=255 captured on the line after the invocation, banner grepped from captured output (plan 04-01 Task 3 <verify>)"
        status: pass
    human_judgment: false
  - id: D5
    description: "After the fix the identical presenter-mode command succeeds, shows the NEW banner, and the client's trust record is byte-identical either side of the fix"
    requirement: "KEY-04"
    verification:
      - kind: integration
        ref: "md5sum /root/.ssh/known_hosts compared across the fix (e0f64991149737716e09f30a73e33b3d both sides); output grepped for 'NEW server-new'"
        status: pass
    human_judgment: false
  - id: D6
    description: "Phase 3's 186 assertions and the 17 proxy assertions still pass; compose.yaml is byte-unmodified"
    verification:
      - kind: integration
        ref: "make test -> '--- 186 passed, 0 failed ---'; sh scripts/smoke.sh proxy -> '--- 17 passed, 0 failed ---'; git diff --quiet -- compose.yaml"
        status: pass
    human_judgment: false
  - id: D7
    description: "The presenter-mode target reads correctly on a projector — the comment distinguishes accept-new from disabling host-key checking, and the failure banner is the last thing on screen"
    verification: []
    human_judgment: true
    rationale: "Whether the on-screen register teaches the right lesson to a room is a judgment about audience, not a mechanical property; 04-04 signs it off."

duration: 24min
completed: 2026-07-21
status: complete
---

# Phase 4 Plan 01: The Host-Key Gotcha Mechanism Summary

**The host-key failure is now reachable, fixable and re-armable from three `make` targets — and the fix signals the running daemon rather than merely copying files, which is the difference between a working demo and a presenter debugging on stage.**

## Performance

- **Duration:** ~24 min
- **Started:** 2026-07-21T13:14Z
- **Completed:** 2026-07-21T13:38Z
- **Tasks:** 3 of 3
- **Files modified:** 3 (2 created, 1 modified)

## Accomplishments

- **The fix is real, and it is not a file copy.** `scripts/fix-hostkeys.sh` streams the six host-key files out of `server-old` and into `server-new` via `tar -cf - | tar -xf -` across two `docker compose exec -T` calls — no host path, no temp file, modes and ownership carried through — and then `kill -HUP $(cat /run/sshd.pid)` on `server-new`. Without the signal the transfer is a measured silent no-op, because sshd loads host keys once at startup. The script proves the fix landed by comparing what each daemon *presents* (`ssh-keygen -lf`), and exits non-zero if they differ.
- **The gotcha can be put back in about a second.** `scripts/rearm.sh` deletes `server-new`'s host keys *before* invoking `ssh-keygen -A` — the entrypoint's generator only fills gaps, so a generate-only re-arm would silently leave the rig fixed while looking armed — then SIGHUPs, clears the client's trust record, and asserts the two fingerprints now differ. In place, no rebuild, no recreate.
- **Presenter mode exists as a named second connection mode.** `make ssh` pins `StrictHostKeyChecking=accept-new` (records an unseen host silently — no prompt, no dead air — while still refusing a *changed* key) and `UpdateHostKeys=no` (without which OpenSSH rewrites the client's own trust record on the first successful post-fix connection), and sets `DOCKER_CLI_HINTS=false` so Compose's hint block never lands under the failure on the projector.
- **The full narrative was run by hand on this machine and works end to end.** Prime on OLD → flip to NEW → `rc=255` with the 13-line `REMOTE HOST IDENTIFICATION HAS CHANGED` banner → `make fix-hostkeys` → the identical command succeeds and prints `NEW server-new`, with `known_hosts` md5 `e0f64991149737716e09f30a73e33b3d` on *both* sides of the fix.
- **Nothing inherited was disturbed.** `make test` → `--- 186 passed, 0 failed ---`. `sh scripts/smoke.sh proxy` → `--- 17 passed, 0 failed ---`. `compose.yaml` byte-unmodified.

## Task Commits

1. **Task 1: The fix — transfer the identity, then tell the daemon** — `b175af1` (feat)
2. **Task 2: The re-arm — put the gotcha back in about a second** — `e62fa1b` (feat)
3. **Task 3: Presenter mode — the three targets that make the narrative runnable** — `9a3e177` (feat)

## Files Created/Modified

- `scripts/fix-hostkeys.sh` (new) — KEY-03/KEY-04. Gate both backends, announce, stream six host-key files, SIGHUP the daemon, prove by fingerprint equality, report. Argument-free, hard-wired `server-old` → `server-new`. Never touches the client.
- `scripts/rearm.sh` (new) — KEY-01. Gate, announce, delete-then-regenerate on `server-new`, SIGHUP, clear the client's `known_hosts*`, prove the fingerprints differ, report. Argument-free. Leaves `/root/.ssh/config` alone.
- `Makefile` (modified) — three targets added (`ssh`, `fix-hostkeys`, `rearm`), `.PHONY` extended by all three. The `ssh` comment block names test mode explicitly and states that `accept-new` is not the same thing as switching host-key checking off.

## Decisions Made

All eight plan-level decisions were implemented as written. Worth restating the two that most invert instinct:

- **No `known_hosts` persistence mechanism was added, deliberately.** The client's trust record lives in the container's writable layer, and that is precisely what keeps its lifetime in step with the backends' key lifetime. A named volume would survive `docker compose down` and make the gotcha fire *before* the flip; a bind mount would defeat `make reset` and write host state. `compose.yaml` is byte-unmodified — asserted, not assumed.
- **`UpdateHostKeys=no` is load-bearing, not tidiness.** Left at its default, the first successful post-fix connection rewrites the client's trust record on its own. Pinning it off converts KEY-04's "no client-side edit" from a claim about presenter intent into a checksum comparison — measured identical either side of the fix in this session.

## Deviations from Plan

None — plan executed exactly as written. One cosmetic adjustment during Task 2 (aligning the two fingerprint lines in `rearm.sh`'s report, which is projected output) was folded into that task's commit before it was made.

## Issues Encountered

None. Every acceptance criterion in all three tasks passed on first execution.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

Ready for 04-02, 04-03 and 04-04:

- **04-02** (`section_hostkey` in the smoke suite) has its mechanism: it can call `scripts/rearm.sh` directly rather than a full teardown, which is what makes a destructive, trap-restored section feasible from inside the suite. KEY-03's **concurrency** edge — the fix applied while a session is already open — is deliberately *not* asserted here and is owned by 04-02, as the plan records.
- **04-03** (`WALKTHROUGH.md` and the README correction) has the target the corrected README SSH example must route through: the existing README lines 411–445 show a bare `ssh` that a fresh rig does not reproduce, and `make ssh` is the fix.
- **04-04** signs off D7 above (the projector register) and the criterion-5 checkpoint.

**Rig state left behind:** stack running, five services healthy, selector on `old`, the two backends presenting different ed25519 fingerprints (gotcha armed), client's `known_hosts` absent.

---
*Phase: 04-host-key-gotcha-and-the-presenter-walkthrough*
*Completed: 2026-07-21*

## Self-Check: PASSED

All three created/modified files exist on disk and all three task commits are present in git history.
