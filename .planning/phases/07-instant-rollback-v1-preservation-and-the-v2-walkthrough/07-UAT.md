---
status: testing
phase: 07-instant-rollback-v1-preservation-and-the-v2-walkthrough
source: [07-VERIFICATION.md]
started: 2026-07-22T00:00:00Z
updated: 2026-07-22T00:00:00Z
---

## Current Test

number: 1
name: WALKTHROUGH.md comprehensibility cold-read (MIG-02 criterion 4)
expected: |
  A presenter who has never seen the demo can follow WALKTHROUGH.md top to bottom and reproduce
  every one of the 11 beats, and the narrative reads as a coherent v2 story:
  validate → show old → redirect contrast → prime → flip → gotcha → wrong fix → right fix →
  rollback → old-proxy-untouched → reset.
awaiting: user response

## Tests

### 1. WALKTHROUGH.md comprehensibility cold-read
expected: |
  Read WALKTHROUGH.md end to end as a first-timer (do NOT consult any other file). For each of the
  11 beats, confirm the command, the expected output, and the audience takeaway are present, correct,
  and in the v2 order:
    1.  Validate the new stack, pre-cutover   (make verify-new-stack)
    2.  Show OLD through the switch            (make verify)
    3.  The redirect contrast                  (make contrast)
    4.  Prime the SSH trust on OLD             (make ssh)
    5.  The flip — one word, one reload        (make flip-new; diff shows switch/active-proxy.conf)
    6.  The gotcha                             (make ssh → REMOTE HOST IDENTIFICATION HAS CHANGED)
    7.  The wrong fix                          (ssh-keygen -R … then make ssh)
    8.  The right fix                          (make fix-hostkeys then make ssh)
    9.  Instant rollback — no teardown         (make flip-old then make verify)
    10. The old proxy was never touched        (make proxies-untouched)
    11. Reset for the next take                (make reset)
  Optionally run the beats top-to-bottom against the live rig (start from `make reset`) to confirm a
  first-timer can reproduce every beat without prior knowledge.
why_human: |
  "A room can follow it" is a judgement no assertion can make. The section_walkthrough lint proves
  self-containment and executability only (11 beats, real targets, resolvable paths, Run/Expect/Say
  order, traps) — never comprehensibility. Explicit blocking human checkpoint (Phase 4 / T-04-16
  precedent).
result: [pending]

## Summary

total: 1
passed: 0
issues: 0
pending: 1
skipped: 0
blocked: 0

## Gaps
