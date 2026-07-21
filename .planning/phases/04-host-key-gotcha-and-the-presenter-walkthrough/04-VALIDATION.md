---
phase: 4
slug: host-key-gotcha-and-the-presenter-walkthrough
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-21
---

# Phase 4 — Validation Strategy

> Derived from `04-RESEARCH.md` § Validation Architecture. The researcher wrote and RAN the proposed
> smoke section this session — 7/7 candidate assertions passed against the live rig.

---


`workflow.nyquist_validation` is `true` in `.planning/config.json`, so this section applies.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | POSIX-`sh` assertion harness — `scripts/smoke.sh`, section-dispatched, custom `assert` helper. No third-party runner, deliberately |
| Config file | none — the script *is* the config. Sections dispatched by `case "$section"` at the foot |
| Quick run command | `sh scripts/smoke.sh hostkey` (the new section, once added) |
| Full suite command | `sh scripts/smoke.sh` — currently **186 passed, 0 failed** |
| Independent oracle | `sh scripts/verify.sh <old\|new>` — deliberately *cannot* see host-key state (test mode). Useful as a control, never as the KEY-0x assertion |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| KEY-01 | The two backends carry different host keys | unit | `sh scripts/smoke.sh backends` — assertion `KEY-01 precondition: backends have DIFFERENT ssh host keys` | ✅ already present and passing |
| KEY-01 | `make rearm` restores the differing state from a fixed state | integration | `sh scripts/smoke.sh hostkey` | ❌ Wave 0 — `section_hostkey` |
| KEY-02 | Post-flip presenter-mode ssh exits non-zero **and** prints the warning | integration | `sh scripts/smoke.sh hostkey` | ❌ Wave 0 |
| KEY-02 | Negative control — test mode is unaffected in the same state | integration | `sh scripts/smoke.sh hostkey` | ❌ Wave 0 |
| KEY-03 | After `make fix-hostkeys`, both backends report the same ed25519 fingerprint | integration | `sh scripts/smoke.sh hostkey` | ❌ Wave 0 |
| KEY-03 | The fix signals sshd, not just the filesystem (guard: a copy without HUP must NOT pass) | integration | `sh scripts/smoke.sh hostkey` | ❌ Wave 0 |
| KEY-04 | Same command succeeds against NEW after the fix | integration | `sh scripts/smoke.sh hostkey` | ❌ Wave 0 |
| KEY-04 | `known_hosts` md5 identical across the fix | integration | `sh scripts/smoke.sh hostkey` | ❌ Wave 0 |
| WALK-01 | `WALKTHROUGH.md` exists and its step headings appear in the D-55 order | doc-lint | `sh scripts/smoke.sh walkthrough` | ❌ Wave 0 |
| WALK-02 | Every fenced `bash` command in `WALKTHROUGH.md` is either a defined `make` target or a command that exists | doc-lint | `sh scripts/smoke.sh walkthrough` | ❌ Wave 0 |
| WALK-02 | Every file path referenced in `WALKTHROUGH.md` exists in the repo | doc-lint | `sh scripts/smoke.sh walkthrough` | ❌ Wave 0 |
| WALK-03 | Every step section contains all three blocks (command / expect / say) | doc-lint | `sh scripts/smoke.sh walkthrough` | ❌ Wave 0 |
| WALK-03 | The traps named in D-57 each appear in `WALKTHROUGH.md` | doc-lint | `sh scripts/smoke.sh walkthrough` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `sh scripts/smoke.sh hostkey` and/or `sh scripts/smoke.sh walkthrough` — the sections owned by the task
- **Per wave merge:** `sh scripts/smoke.sh` (full, 186 + new) **and** `sh scripts/smoke.sh proxy` (the 17/17 guard, asserted exactly)
- **Phase gate:** full suite green, selector left on `old`, `git status` clean, before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `section_hostkey` in `scripts/smoke.sh` — covers KEY-01..KEY-04. **Destructive** (flips the selector, arms and fixes the gotcha, writes the client's `known_hosts`); must follow `guard_check`'s trap-restore discipline exactly: back up state, `trap … EXIT INT TERM`, restore the selector to `old`, re-arm `server-new`'s keys, and clear `/root/.ssh/known_hosts*` on the way out.
- [ ] `section_walkthrough` in `scripts/smoke.sh` — the doc-lint section. This is the honest proxy for ROADMAP criterion 5 (see below).
- [ ] Dispatcher entries for both new sections, plus their placement in the `all` chain. Place `section_hostkey` **last**, after `section_ssh`, for the same reason `section_ssh` follows `section_cutover`: it is the most destructive and it leaves the rig in the state the next section expects.
- [ ] No framework install required — the harness already exists.

### On ROADMAP criterion 5 ("someone who has never seen the demo can follow it cold")

This cannot be mechanically verified and should not be claimed as verified. The honest proxy is a **four-part executable contract**, all of which `section_walkthrough` can assert:

1. **Every command is runnable verbatim.** Every fenced `bash` block in `WALKTHROUGH.md` is either a `make` target that exists in the `Makefile`'s `.PHONY` list, or a binary on `PATH`. No pseudo-commands, no `…`, no placeholders.
2. **Every referenced path exists.** Every `` `path/like/this` `` in the document resolves to a real file in the repo.
3. **No undefined prerequisite.** Every command appearing in a step is either in the pre-flight checklist or produced by an earlier step. Assertable as: the set of `make` targets used in steps ⊆ (pre-flight targets ∪ targets introduced by earlier steps).
4. **Structural completeness.** Every step heading is followed by all three D-54 blocks, and the step headings appear in the D-55 order.

Passing all four means the document is *self-contained and executable*. It does **not** mean it is *comprehensible* — whether the takeaway prose lands with a room of humans is a judgement no assertion can make. The plan should therefore carry an explicit `checkpoint:human-verify` task: **one person who has not seen the demo runs `WALKTHROUGH.md` top to bottom on a clean checkout and reports every point at which they had to guess.** That checkpoint is the only real evidence for criterion 5, and the VERIFICATION document should say so plainly rather than claiming mechanical coverage.

### On the full-run rehearsal (research question 10)

**Recommendation: yes, and it is already written.** `section_hostkey` as specified above *is* the end-to-end rehearsal — prime on OLD → flip → gotcha → fix → success — because those are the only steps that can prove KEY-01..KEY-04 anyway. It was executed in full in this session and all seven assertions passed. Adding it costs nothing beyond the assertions the requirements already demand.

Weighed honestly:
- **Slow?** No. Measured under 20 s, dominated by `docker compose exec` round-trips. It is comparable to `section_cutover`.
- **Destructive?** Yes — it flips the selector and arms/fixes the gotcha. But `section_cutover` and `guard_check` are already destructive and already trap-restored; this follows the same established idiom rather than introducing a new hazard.
- **Value:** it is the only thing that stops `WALKTHROUGH.md` rotting. A document that describes a five-step narrative, backed by a test that executes that same five-step narrative, cannot drift silently.

What it deliberately does **not** cover: the browser beats (incognito, the 301 contrast, the status page). Those are already human-verified from Phases 1–2 and re-automating them here would be scope creep.

---

## Validation Sign-Off

- [ ] `sh scripts/smoke.sh proxy` still returns exactly 17/17
- [ ] All 186 inherited assertions still pass
- [ ] Presenter-mode SSH pins `-o UpdateHostKeys=no` so KEY-04 is mechanically assertable (D-58)
- [ ] The gotcha assertion checks BOTH the warning text AND a non-zero exit code, without piping ssh
- [ ] The re-arm path is asserted, not assumed
- [ ] Criterion 5 has an explicit human checkpoint — it is not mechanically verifiable
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
