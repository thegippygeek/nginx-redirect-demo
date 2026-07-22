---
phase: 07-instant-rollback-v1-preservation-and-the-v2-walkthrough
verified: 2026-07-22T00:00:00Z
status: passed
score: 4/4 must-haves verified (comprehensibility cold-read PASSED by user 2026-07-22)
behavior_unverified: 0
overrides_applied: 0
human_verification:
  - test: |
      Cold-read comprehensibility of WALKTHROUGH.md (ROADMAP Phase 7 criterion 4 / MIG-02).
      Open WALKTHROUGH.md and read it end to end as someone who has NEVER seen the demo — do not
      consult any other file. For each of the 11 beats confirm the command, the expected output,
      and the audience takeaway are present, correct, and in the v2 order:
        1. Validate the new stack, pre-cutover   (make verify-new-stack)
        2. Show OLD through the switch            (make verify)
        3. The redirect contrast                  (make contrast)
        4. Prime the SSH trust on OLD             (make ssh)
        5. The flip — one word, one reload        (make flip-new; diff shows switch/active-proxy.conf)
        6. The gotcha                             (make ssh → REMOTE HOST IDENTIFICATION HAS CHANGED)
        7. The wrong fix                          (ssh-keygen -R … then make ssh)
        8. The right fix                          (make fix-hostkeys then make ssh)
        9. Instant rollback — no teardown         (make flip-old then make verify)
        10. The old proxy was never touched       (make proxies-untouched)
        11. Reset for the next take               (make reset)
      Optionally run the beats top-to-bottom against the live rig (start from `make reset`) to confirm
      a first-timer can reproduce every beat without prior knowledge.
    expected: >
      A presenter who has never seen the demo can follow the doc top to bottom and reproduce every
      beat, and the narrative reads as a coherent v2 story (validate → show old → redirect contrast →
      prime → flip → gotcha → wrong fix → right fix → rollback → old-proxy-untouched → reset).
    why_human: >
      "A room can follow it" is a judgement no assertion can make. The section_walkthrough lint proves
      self-containment and executability only (11 beats, real targets, resolvable paths, Run/Expect/Say
      order, traps) — never comprehensibility. This is the explicit blocking human checkpoint the plan
      deferred to the end-of-phase gate (Phase 4 / T-04-16 precedent).
---

# Phase 7: Instant Rollback, v1 Preservation, and the v2 Walkthrough — Verification Report

**Phase Goal:** Close the milestone's story — instant rollback (flip the switch back, no teardown), the two static proxies shown byte-unchanged across the whole cutover ("the old proxy is never touched" = a verifiable checksum), v1 kept runnable from its preserved form (git tag `v1.0`), and the presenter walkthrough rewritten for the v2 narrative.
**Verified:** 2026-07-22
**Status:** passed (comprehensibility cold-read PASSED by user 2026-07-22)
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth (Success Criterion) | Status | Evidence |
|---|---------------------------|--------|----------|
| 1 | After a cutover to NEW, flipping the switch selector back to `old` and reloading returns BOTH HTTP and SSH to OLD — instant rollback, no container teardown (VAL-03) | ✓ VERIFIED | Live `sh scripts/smoke.sh rollback` → 5 passed, 0 failed. After a real `flip.sh new` → `flip.sh old` cycle: HTTP `localhost:9092/whoami` → `OLD server-old`; SSH banner (non-piped capture) → `OLD server-old`; `.State.StartedAt` of all 5 containers unchanged before==after (no restart) |
| 2 | The two static-proxy configs are byte-identical before and after the whole cutover-and-rollback cycle — verifiable checksum, not a claim (VAL-04) | ✓ VERIFIED | Live rollback section: `shasum -a 256` of `proxy-old/nginx.conf`+`proxy-new/nginx.conf` equal at three real points (before==after-flip==after-rollback); corroborated by `pgrep -f 'nginx: worker'` unchanged (proxies not even reloaded). Falsifiability spot-checked: triple-equality returns FAIL when any sample differs |
| 3 | The v1 single-proxy demo still comes up from its preserved form (git tag `v1.0`), unbroken by the v2 restructure (MIG-03) | ✓ VERIFIED | Live `sh scripts/smoke.sh preserve` → 4 passed, 0 failed. `v1.0` tag resolves (a5f8280); `compose.yaml` has `proxy:` and no `switch:`; ships `proxy/nginx.conf` + `proxy/active-backend.conf`; Makefile has `up:` target — all via read-only git plumbing, working tree unchanged after run |
| 4 | A rewritten walkthrough runs the full v2 narrative in order — each beat with command, expected output, takeaway (MIG-02) | ⚠️ SPLIT: automated VERIFIED / comprehensibility HUMAN-NEEDED | Automated: live `sh scripts/smoke.sh walkthrough` → 26 passed, 0 failed. 11 beats numbered 1..11 in the fixed v2 order; every `make` target in `.PHONY`; every path resolves; Run/Expect/Say order + six traps present; no stale v1 residue (`demo-old/demo-new/demo-proxy/active-backend` = 0 hits). Comprehensibility ("a room can follow it") is a blocking human cold-read — see Human Verification |

**Score:** 3/4 truths fully verified; criterion 4 automated executable-contract VERIFIED, comprehensibility human-pending. Full suite `make test` → **257 passed, 0 failed**, rig left on OLD.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `section_rollback` (scripts/smoke.sh:2375) | Destructive VAL-03+VAL-04 over one flip cycle, trap/restore discipline | ✓ VERIFIED | 5 assertions, `restore_flip_state` at top / `finish_flip_state` at exit, leaves rig on OLD; ran live 5/0 |
| `section_preserve` (scripts/smoke.sh:2345) | Non-destructive MIG-03 git-plumbing | ✓ VERIFIED | 4 assertions, no trap, no working-tree-mutating git (checkout/switch/stash/reset = 0); ran live 4/0 |
| `section_walkthrough` (scripts/smoke.sh:1821) constants | v2 lockstep: WT_STEPS=11, 1..11, v2 keyword order, six traps | ✓ VERIFIED | Constants match rewritten doc; extraction machinery + two reader-guards untouched; ran live 26/0 |
| `WALKTHROUGH.md` | v2 11-beat narrative, Run/Expect/Say + takeaway, pre-flight, traps | ✓ VERIFIED (structure) | 455 lines, 11 beats in v2 order, `switch/active-proxy.conf` (6 refs), no stale residue; WR-01 (beat-11 status table) confirmed fixed |
| `make proxies-untouched` (Makefile:219) | `.PHONY` target printing `shasum -a 256` of the two configs | ✓ VERIFIED | Recipe `@shasum -a 256 proxy-old/nginx.conf proxy-new/nginx.conf`; declared in `.PHONY:12`; no `sha256sum` |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `section_rollback` | `flip.sh old\|new` | Existing rollback mechanism + settle_flip + restore/finish trap | ✓ WIRED | No new mechanism — assertions over the unchanged flip; ran live |
| VAL-03 no-teardown | `docker inspect .State.StartedAt` | Host-side, no Docker socket (D-29) | ✓ WIRED | StartedAt captured at two points, before==after |
| VAL-04 byte-identity | `shasum -a 256 … \| awk` | Three independent captures | ✓ WIRED | before==mid==after; robust to any single-point change |
| `section_preserve` | `v1.0` tag content | `git rev-parse`/`git show`/`git cat-file` — never checkout | ✓ WIRED | Working tree unchanged after run |
| WALKTHROUGH.md ↔ `section_walkthrough` | Lockstep lint | Landed in ONE commit (0988d94) | ✓ WIRED | No red-lint intermediate; 26/0 against the rewritten doc |
| Doc `make` targets ↔ `.PHONY` | `proxies-untouched` etc. | Target-closure check | ✓ WIRED | All doc targets ⊆ `.PHONY`; walkthrough lint green |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Instant rollback returns both protocols to OLD, no teardown (VAL-03) | `sh scripts/smoke.sh rollback` | 5 passed, 0 failed | ✓ PASS |
| Static proxies byte-unchanged + not reloaded (VAL-04) | (same section) | shasum triple-equal, worker PIDs unchanged | ✓ PASS |
| v1 preserved at v1.0 tag (MIG-03) | `sh scripts/smoke.sh preserve` | 4 passed, 0 failed; tree unchanged | ✓ PASS |
| Walkthrough executable-contract (MIG-02 automated) | `sh scripts/smoke.sh walkthrough` | 26 passed, 0 failed | ✓ PASS |
| Full suite green, rig on OLD | `make test` then `curl …/whoami` | 257 passed, 0 failed; `OLD server-old` | ✓ PASS |
| Section ordering (preserve early, rollback after ssh, hostkey last) | `sh scripts/smoke.sh all \| grep '^--- '` | preserve→cutover→validate→ssh→rollback→walkthrough→hostkey | ✓ PASS |
| Falsifiability: triple-equality catches a changed sample | simulated `test a=b && b=CHANGED` | FAIL as expected | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| VAL-03 | 07-01 | Roll back by flipping the switch selector back, no teardown | ✓ SATISFIED (Complete) | Live rollback 5/0; StartedAt unchanged; both protocols OLD |
| VAL-04 | 07-01 | Static proxy configs provably unchanged across the cutover | ✓ SATISFIED (Complete) | shasum triple-equality + worker-PID unchanged, live |
| MIG-03 | 07-01 | v1 single-proxy demo remains available and unbroken | ✓ SATISFIED (Complete) | Live preserve 4/0; v1.0 tag self-contained |
| MIG-02 | 07-02 | Walkthrough narrates the v2 story in order | ⚠️ PARTIAL — automated SATISFIED, comprehensibility NEEDS HUMAN | Walkthrough lint 26/0; comprehensibility cold-read pending (REQUIREMENTS.md row: Pending) |

No orphaned requirements — all four Phase 7 IDs (VAL-03, VAL-04, MIG-02, MIG-03) are claimed by the plans and mapped in ROADMAP/REQUIREMENTS.

### Anti-Patterns Found

None. No debt markers (TBD/FIXME/XXX/TODO) introduced. No `sha256sum` (portable `shasum -a 256` only). No stub/placeholder in command blocks. No `ssh` on the left of a pipe in `section_rollback`. No working-tree-mutating git in `section_preserve`. Prior code review (07-REVIEW.md): 0 critical, WR-01 warning FIXED, IN-01/IN-02 are optional non-blocking info items (Expect-block context cosmetics and a defense-in-depth guard unreachable in practice).

### Scope-Fence Honesty

| Check | Status | Evidence |
|-------|--------|----------|
| Host-key gotcha SURFACED (inherited v1), not re-engineered | ✓ | Walkthrough reuses existing `make ssh`/`make fix-hostkeys`/`rearm.sh` (Phase 4, e62fa1b); no new mechanism |
| Static proxies never reconfigured during rollback | ✓ | Phase 7 commits touch only Makefile, WALKTHROUGH.md, scripts/smoke.sh, planning files — no proxy config |
| Orphaned `proxy/` dir on main left untouched (MIG-03 uses the tag) | ✓ | No Phase 7 commit touches `proxy/`; MIG-03 asserts the v1.0 tag's content only |
| No `compose.v1.yaml` / `make up-v1` added | ✓ | v1.0 tag is the canonical preserved form; no colliding topology introduced |

### Human Verification Required

**1. WALKTHROUGH.md comprehensibility cold-read (BLOCKING — ROADMAP criterion 4 / MIG-02)**

This is the single gate keeping the phase from being fully sealed. All automated evidence (self-containment, executability, narrative order, resolvable paths, traps) is green — but "a room can follow it" is a judgement no assertion can make. See the `human_verification` block in the frontmatter for exact presenter instructions (read all 11 beats cold, confirm command/expected/takeaway per beat in v2 order; optionally run the beats top-to-bottom from `make reset`).

### Gaps Summary

No gaps. Every automated must-have is verified against the live rig: rollback returns both protocols to OLD with no teardown and byte-identical static proxies (VAL-03/VAL-04), v1 is preserved at the `v1.0` tag (MIG-03), and the v2 walkthrough passes its executable-contract lint (MIG-02 automated half). The full suite is green (257/0) and the rig is left on OLD. The phase is not `passed` solely because MIG-02's comprehensibility criterion is a deliberate blocking human cold-read — the honest status is `human_needed`, routing to `/gsd-verify-work` rather than silently sealing the milestone's final phase.

---

_Verified: 2026-07-22_
_Verifier: Claude (gsd-verifier)_
