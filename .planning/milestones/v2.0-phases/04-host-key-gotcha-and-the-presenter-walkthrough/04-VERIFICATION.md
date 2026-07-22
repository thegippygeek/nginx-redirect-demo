---
phase: 04-host-key-gotcha-and-the-presenter-walkthrough
verified: 2026-07-22T00:15:00Z
status: passed
score: 5/5 roadmap criteria verified (criterion 5 mechanical dimension verified; comprehensibility dimension owner-accepted and honestly recorded)
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: none
  note: "Initial verification. 04-VALIDATION.md exists as a validation-strategy artifact, not a prior VERIFICATION.md with a gaps section."
---

# Phase 4: Host-Key Gotcha and the Presenter Walkthrough — Verification Report

**Phase Goal:** Presenter can deliberately trigger the SSH host-key mismatch after cutover, fix it live without touching the client, and run the entire demo from a written script.
**Verified:** 2026-07-22
**Status:** PASSED
**Re-verification:** No — initial verification. Every KEY-0x claim was re-run by hand against the live rig rather than read from a SUMMARY.

## Goal Achievement

### Observable Truths (ROADMAP criteria — the contract)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Presenter can start in a state where `server-new` has different host keys from `server-old` | ✓ VERIFIED | Live rig armed at entry: old `SHA256:Lim1vqCMy73…`, new `SHA256:FJ6icLK2p6Xk…` (differ). `make rearm` re-derived the differing state (new → `SHA256:96FCxbf33K…`). `KEY-01 precondition` + `KEY-01 the re-arm restores the DIFFERING fingerprints` pass. |
| 2 | After cutover, the client's ssh fails visibly with `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED` | ✓ VERIFIED | Ran presenter-mode ssh (`accept-new`,`UpdateHostKeys=no`) after `flip-new`: **rc=255**, output contained the exact `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED` banner and `Host key verification failed.` No pipe on the ssh invocation. |
| 3 | The documented fix makes the same ssh succeed against `server-new` with no `known_hosts` edit | ✓ VERIFIED | `scripts/fix-hostkeys.sh` streamed six key files and `kill -HUP $(cat /run/sshd.pid)`; both backends then presented `SHA256:Lim1…` (old's fp). The identical presenter command returned rc=0, banner `NEW server-new`. |
| 4 | A written walkthrough covers the full narrative in order with command, expected output, takeaway per step | ✓ VERIFIED | `WALKTHROUGH.md`: 8 numbered beats in D-55 order (show-old → redirect-contrast → prime → flip → gotcha → wrong-fix → right-fix → reset; "show new" folded into the flip beat), each with Run/Expect/Say, plus pre-flight checklist and 5 named traps. All 25 `section_walkthrough` assertions pass. |
| 5 | Someone who has never seen the demo can follow it cold and reproduce every beat | ✓ VERIFIED (split) | Mechanical dimension (self-contained + executable) proven by 25 `section_walkthrough` assertions. Comprehensibility dimension is **owner-accepted 2026-07-21, independent cold read not performed** — honestly recorded in 04-VALIDATION.md and 04-04-SUMMARY.md, nowhere claimed as mechanical. Per phase contract this recorded state is not a gap. |

**Score:** 5/5 criteria verified (0 behavior-unverified). Criteria 1–4 re-run mechanically by the verifier; criterion 5 mechanical dimension verified, comprehensibility dimension owner-accepted per the phase's blocking human checkpoint.

### Load-Bearing / Trap Checks (explicitly requested)

| Check | Status | Evidence |
|-------|--------|----------|
| KEY-04 mechanically — `known_hosts` byte-identical across the fix | ✓ VERIFIED | md5 before = md5 after = `76eeb648412599dbcbb89764259abf2b`; file stayed 95 bytes, one line; **no `known_hosts.old` created**. This is because `make ssh` pins `-o UpdateHostKeys=no` (Makefile:173). |
| Fix is a HUP, not just a copy | ✓ VERIFIED | `scripts/fix-hostkeys.sh:124` does `kill -HUP $(cat /run/sshd.pid)` after the tar transfer, and proves by fingerprint equality read from the running daemon. Smoke assertion `KEY-03 the fix landed in the DAEMON: the presented fingerprint actually changed` would fail on a copy-only implementation. Reasoned: removing the HUP leaves sshd presenting the in-memory old fp → gotcha persists. |
| No new `known_hosts` persistence (corrected D-48) | ✓ VERIFIED | `compose.yaml` volumes are only `demo-logs` and `demo-keys`; `client` mounts only `demo-keys:/keys`; no bind mount or volume references `known_hosts`. `client/entrypoint.sh` writes only `/root/.ssh/config`, never `known_hosts`. Trust record lives in the container writable layer. |
| Gotcha genuinely re-armable | ✓ VERIFIED | `make rearm` (~1s): fingerprints differ again, client trust record cleared. `make reset` is the documented full path. |
| Exit code is real (255), no pipe | ✓ VERIFIED | Gotcha attempt returned rc=255. No `ssh … \|` anywhere in Makefile, scripts, or WALKTHROUGH demo path. Smoke guard `KEY-02 no ssh invocation sits on the left of a pipe` passes. |
| Phase 3's 186 assertions still pass with `/dev/null` pins intact | ✓ VERIFIED | Full suite 231, of which inherited = 13(backends)+17(proxy)+12(redirect)+78(cutover)+66(ssh) = 186, all green. `section_ssh` and `scripts/verify.sh` still pin `UserKnownHostsFile=/dev/null` (verify.sh:58). |
| `make verify` blind to host keys by design | ✓ VERIFIED | With rig armed (keys differ) and flipped to NEW — the exact state presenter-mode ssh fails 255 in — `make verify EXPECT=new` reported `OK both protocols report NEW` and exited 0. |
| Criterion 5 honest recording exists (not converted to a mechanical pass) | ✓ VERIFIED | 04-VALIDATION.md and 04-04-SUMMARY.md both state the doc-lint proves self-containedness/executability only, comprehensibility accepted on owner judgement, independent cold read not performed. Not over-claimed. |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `scripts/fix-hostkeys.sh` | Transfer + SIGHUP + fingerprint proof | ✓ VERIFIED | Six-file tar stream, `kill -HUP`, fingerprint-equality gate. Ran clean (rc=0). |
| `scripts/rearm.sh` | Fast in-place re-arm | ✓ VERIFIED | Delete-then-regenerate, HUP, clear client trust, prove differing fps. Ran clean. |
| `Makefile` (`ssh`,`fix-hostkeys`,`rearm`) | Presenter mode + fix + re-arm targets | ✓ VERIFIED | `ssh` pins `accept-new` + `UpdateHostKeys=no`, no `/dev/null`. Targets in `.PHONY`. |
| `WALKTHROUGH.md` | 8-beat script, pre-flight, traps | ✓ VERIFIED | Present at repo root; 25 doc-lint assertions green. |
| `scripts/smoke.sh` (`section_hostkey`,`section_walkthrough`) | 20 + 25 assertions | ✓ VERIFIED | Both sections present, dispatched, in `all` chain; hostkey placed last and self-restores. |

### Behavioral Spot-Checks (re-run against live rig)

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Prime on OLD (presenter mode) | ssh accept-new … hostname | rc=0, `OLD server-old` | ✓ PASS |
| Gotcha after flip | ssh … after flip-new | rc=255 + full WARNING + `Host key verification failed.` | ✓ PASS |
| The fix | `sh scripts/fix-hostkeys.sh` | rc=0, both fps = `SHA256:Lim1…` | ✓ PASS |
| Post-fix success | ssh … hostname | rc=0, `NEW server-new` | ✓ PASS |
| known_hosts byte-identical | md5sum before/after | identical, 95 bytes, no `.old` | ✓ PASS |
| Re-arm | `make rearm` | fps differ, trust cleared | ✓ PASS |
| verify blind | `make verify EXPECT=new` (armed) | `OK … NEW`, rc=0 | ✓ PASS |

### Probe / Suite Execution

| Suite | Command | Result | Status |
|-------|---------|--------|--------|
| Full smoke | `sh scripts/smoke.sh` | `--- 231 passed, 0 failed ---` (rc=0) | ✓ PASS |
| Proxy guard | `sh scripts/smoke.sh proxy` | `--- 17 passed, 0 failed ---` | ✓ PASS |

### Requirements Coverage

| Requirement | Description | Status | Evidence |
|-------------|-------------|--------|----------|
| KEY-01 | Runnable in a differing-host-key state | ✓ SATISFIED | Armed at entry; `make rearm` restores it; smoke KEY-01 assertions |
| KEY-02 | Post-cutover ssh fails with the warning | ✓ SATISFIED | rc=255 + banner, re-run by hand |
| KEY-03 | Documented fix transfers old's keys to new | ✓ SATISFIED | fix-hostkeys.sh transfer + HUP, fp equality |
| KEY-04 | Fix succeeds with no client `known_hosts` edit | ✓ SATISFIED | md5 byte-identical across fix, no `.old` |
| WALK-01 | Walkthrough documents full narrative in order | ✓ SATISFIED | 8 beats, D-55 order, doc-lint green |
| WALK-02 | Each step lists exact command + expected output | ✓ SATISFIED | Run/Expect blocks; all targets/paths resolve |
| WALK-03 | Walkthrough explains audience takeaway | ✓ SATISFIED | Say block per beat; 5 traps named |

### Anti-Patterns Found

None. No `TODO`/`FIXME`/`XXX`/placeholder markers in the Phase 4 shipped source. The scripts deliberately avoid `set -e` (documented, matches repo idiom) and the doc-lint section is guarded against executing extracted text.

### Human Verification Required

None outstanding. Criterion 5's comprehensibility dimension already went through the plan-04-04 blocking `checkpoint:human-verify` and was owner-accepted 2026-07-21. Per the phase contract and the verification brief, this owner-accepted state is the honest recorded outcome and is explicitly not a gap to reopen.

### Gaps Summary

No gaps. All five ROADMAP criteria hold in the codebase and against the live rig. Criteria 1–4 were re-executed by the verifier (not read from SUMMARY): the gotcha fires at rc=255 with the exact warning, the fix succeeds via transfer + SIGHUP, the identical command lands on NEW, and the client's trust record is byte-identical (md5 `76eeb648…`, no `known_hosts.old`). No `known_hosts` persistence mechanism was introduced (corrected D-48 honoured). The gotcha is re-armable, `make verify` is confirmed blind by design, Phase 3's 186 test-mode assertions remain green, and criterion 5 is recorded honestly as owner-judgement acceptance. Rig left as required: selector on OLD, gotcha armed (fingerprints differ), client trust record clean, shipped source unmodified.

---

_Verified: 2026-07-22_
_Verifier: Claude (gsd-verifier)_
