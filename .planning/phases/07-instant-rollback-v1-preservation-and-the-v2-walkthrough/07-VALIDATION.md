---
phase: 7
slug: instant-rollback-v1-preservation-and-the-v2-walkthrough
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-22
---

# Phase 7 — Validation Strategy

> Per-phase validation contract. Milestone close-out: rollback + byte-unchanged checksum + v1 preservation + walkthrough rewrite. Mechanisms already exist — the work is assertions + a documentation rewrite kept in lockstep with its executable-contract lint.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | POSIX `sh` assertion harness (`scripts/smoke.sh`, `assert <label> <condition>`), no external deps |
| **Config file** | none — self-contained |
| **Quick run command** | `sh scripts/smoke.sh <section>` (new `rollback` / `preserve`, plus `walkthrough`) |
| **Full suite command** | `make test` (== `sh scripts/smoke.sh all`) |
| **Estimated runtime** | ~90 seconds (compose up, SSH handshakes, a flip cycle) |

---

## Sampling Rate

- **After every task commit:** the specific new section (`sh scripts/smoke.sh rollback` / `preserve` / `walkthrough`)
- **After every plan wave:** `make test`
- **Before `/gsd-verify-work`:** `make test` green **AND** a blocking human cold-read of the rewritten `WALKTHROUGH.md` (criterion 4 comprehensibility)
- **Max feedback latency:** ~90 seconds

---

## Per-Requirement Verification Map

| Req | Wave | Behavior | Test Type | Automated Command | Exists |
|-----|------|----------|-----------|-------------------|--------|
| VAL-03 | 1 | rollback returns BOTH protocols to OLD, no teardown | integration | `sh scripts/smoke.sh rollback` — flip new→old; `curl :9092`==OLD, test-mode `ssh app.demo.test` banner==OLD, container `StartedAt` unchanged | ❌ W0 |
| VAL-04 | 1 | static proxy configs byte-identical across cutover+rollback | integration | same section — `shasum -a 256` triple-equality (before == after-flip == after-rollback) over proxy-old/nginx.conf + proxy-new/nginx.conf, + proxy-old/new `StartedAt` + nginx worker-PID unchanged | ❌ W0 |
| MIG-03 | 1 | v1 preserved form comes up unbroken | static (non-destructive) | `sh scripts/smoke.sh preserve` — `git rev-parse v1.0`; `git show v1.0:compose.yaml \| grep 'proxy:'`; `git cat-file -e v1.0:proxy/nginx.conf`; v1 Makefile `up:` target present | ❌ W0 |
| MIG-02 | 2 | walkthrough is self-contained & executable for the v2 narrative | doc-lint | `sh scripts/smoke.sh walkthrough` — **updated** `section_walkthrough` (new beat count/order/targets/traps, in lockstep with the doc) | ⚠️ exists, rewrite in lockstep |
| MIG-02 | 2 | walkthrough is **comprehensible** (a room can follow it) | **manual (blocking)** | Human cold-read of `WALKTHROUGH.md` — a judgement no assertion can make (Phase 4 / T-04-16 precedent) | Human checkpoint |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] New `section_rollback` in `scripts/smoke.sh` — VAL-03 + VAL-04 over one flip cycle (`shasum -a 256`, NOT `sha256sum` — absent on stock macOS)
- [ ] New `section_preserve` in `scripts/smoke.sh` — MIG-03 git-tag assertions, **non-destructive** (git plumbing only — never `git checkout` mid-suite)
- [ ] Wire both new sections into the dispatch `case` and the `all` chain
- [ ] Update `section_walkthrough` expectations (`WT_STEPS`, `WT_NUMSEQ`, `WT_NARRATIVE` keywords, trap assertions) to the v2 beat list — in the SAME change as the `WALKTHROUGH.md` rewrite
- [ ] Any new presenter make target (rollback framing / checksum) added to `.PHONY`

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| The rewritten `WALKTHROUGH.md` reads clearly enough that a presenter can run the v2 demo cold in front of a room | MIG-02 (criterion 4) | Comprehensibility is a human judgement no assertion can make (Phase 4 precedent — 04-VALIDATION "On ROADMAP criterion 5") | Cold-read `WALKTHROUGH.md` end to end; for each beat confirm the command, expected output, and takeaway are present, correct, and in the right narrative order (validate app-new → show old → flip → land new → host-key gotcha → fix → roll back → old-proxy-untouched → reset) |

*This is a blocking human checkpoint — the phase is not fully verified until the cold-read passes.*

---

## Validation Sign-Off

- [ ] VAL-03 / VAL-04 / MIG-03 have automated `<automated>` verify sections
- [ ] MIG-02 executable-contract lint (`section_walkthrough`) updated in lockstep and green
- [ ] MIG-02 comprehensibility cold-read passed (blocking human checkpoint)
- [ ] `make test` green including the new sections; no watch-mode flags
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
