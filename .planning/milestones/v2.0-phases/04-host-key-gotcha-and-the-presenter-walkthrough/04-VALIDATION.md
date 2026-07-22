---
phase: 4
slug: host-key-gotcha-and-the-presenter-walkthrough
status: complete
nyquist_compliant: true
wave_0_complete: true
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
| Quick run command | `sh scripts/smoke.sh hostkey` / `sh scripts/smoke.sh walkthrough` (both sections now present) |
| Full suite command | `sh scripts/smoke.sh` — **231 passed, 0 failed** at the phase gate (186 inherited + 20 `section_hostkey` + 25 `section_walkthrough`) |
| Independent oracle | `sh scripts/verify.sh <old\|new>` — deliberately *cannot* see host-key state (test mode). Useful as a control, never as the KEY-0x assertion |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| KEY-01 | The two backends carry different host keys | unit | `sh scripts/smoke.sh backends` — assertion `KEY-01 precondition: backends have DIFFERENT ssh host keys` | ✅ present and passing |
| KEY-01 | `make rearm` restores the differing state from a fixed state | integration | `sh scripts/smoke.sh hostkey` | ✅ `section_hostkey` — passing |
| KEY-02 | Post-flip presenter-mode ssh exits non-zero **and** prints the warning | integration | `sh scripts/smoke.sh hostkey` | ✅ `section_hostkey` — passing |
| KEY-02 | Negative control — test mode is unaffected in the same state | integration | `sh scripts/smoke.sh hostkey` | ✅ `section_hostkey` — passing |
| KEY-03 | After `make fix-hostkeys`, both backends report the same ed25519 fingerprint | integration | `sh scripts/smoke.sh hostkey` | ✅ `section_hostkey` — passing |
| KEY-03 | The fix signals sshd, not just the filesystem (guard: a copy without HUP must NOT pass) | integration | `sh scripts/smoke.sh hostkey` | ✅ `section_hostkey` — passing |
| KEY-04 | Same command succeeds against NEW after the fix | integration | `sh scripts/smoke.sh hostkey` | ✅ `section_hostkey` — passing |
| KEY-04 | `known_hosts` md5 identical across the fix | integration | `sh scripts/smoke.sh hostkey` | ✅ `section_hostkey` — passing |
| WALK-01 | `WALKTHROUGH.md` exists and its step headings appear in the D-55 order | doc-lint | `sh scripts/smoke.sh walkthrough` | ✅ `section_walkthrough` — passing |
| WALK-02 | Every fenced `bash` command in `WALKTHROUGH.md` is either a defined `make` target or a command that exists | doc-lint | `sh scripts/smoke.sh walkthrough` | ✅ `section_walkthrough` — passing |
| WALK-02 | Every file path referenced in `WALKTHROUGH.md` exists in the repo | doc-lint | `sh scripts/smoke.sh walkthrough` | ✅ `section_walkthrough` — passing |
| WALK-03 | Every step section contains all three blocks (command / expect / say) | doc-lint | `sh scripts/smoke.sh walkthrough` | ✅ `section_walkthrough` — passing |
| WALK-03 | The traps named in D-57 each appear in `WALKTHROUGH.md` | doc-lint | `sh scripts/smoke.sh walkthrough` | ✅ `section_walkthrough` — passing |

### Sampling Rate

- **Per task commit:** `sh scripts/smoke.sh hostkey` and/or `sh scripts/smoke.sh walkthrough` — the sections owned by the task
- **Per wave merge:** `sh scripts/smoke.sh` (full, 186 + new) **and** `sh scripts/smoke.sh proxy` (the 17/17 guard, asserted exactly)
- **Phase gate:** full suite green, selector left on `old`, `git status` clean, before `/gsd-verify-work`

**Phase gate, as run** (04-04 Task 2, from a cold `make reset`):

| Check | Result |
|---|---|
| `make reset` exits zero | ✅ |
| `sh scripts/smoke.sh` | ✅ **231 passed, 0 failed** (> 186, so the new assertions ran *and* every inherited one still passes) |
| `sh scripts/smoke.sh proxy` | ✅ exactly `--- 17 passed, 0 failed ---` — the canonical regression guard, unchanged across four phases and never adjusted to match a result |
| Selector reads `old` | ✅ the demo opens where it closes |
| Gotcha armed (the two backends' ed25519 fingerprints differ) | ✅ |
| `git status --porcelain` over the demo's shipped source — `scripts/ Makefile compose.yaml proxy/ backend/ client/ status/ README.md WALKTHROUGH.md` | ✅ empty. Planning-directory churn is expected and is not asserted against |

### Wave 0 Gaps — all closed

- [x] `section_hostkey` in `scripts/smoke.sh` — covers KEY-01..KEY-04. **Destructive** (flips the selector, arms and fixes the gotcha, writes the client's `known_hosts`); must follow `guard_check`'s trap-restore discipline exactly: back up state, `trap … EXIT INT TERM`, restore the selector to `old`, re-arm `server-new`'s keys, and clear `/root/.ssh/known_hosts*` on the way out.
- [x] `section_walkthrough` in `scripts/smoke.sh` — the doc-lint section, 25 assertions. It is a proxy for *self-containedness*, **not** for criterion 5 (see below).
- [x] Dispatcher entries for both new sections, plus their placement in the `all` chain. Place `section_hostkey` **last**, after `section_ssh`, for the same reason `section_ssh` follows `section_cutover`: it is the most destructive and it leaves the rig in the state the next section expects. `section_walkthrough` sits immediately before it — it is a pure reader and disturbs nothing.
- [x] No framework install required — the harness already exists.

### On ROADMAP criterion 5 ("someone who has never seen the demo can follow it cold")

This cannot be mechanically verified and should not be claimed as verified. The honest proxy is a **four-part executable contract**, all of which `section_walkthrough` can assert:

1. **Every command is runnable verbatim.** Every fenced `bash` block in `WALKTHROUGH.md` is either a `make` target that exists in the `Makefile`'s `.PHONY` list, or a binary on `PATH`. No pseudo-commands, no `…`, no placeholders.
2. **Every referenced path exists.** Every `` `path/like/this` `` in the document resolves to a real file in the repo.
3. **No undefined prerequisite.** Every command appearing in a step is either in the pre-flight checklist or produced by an earlier step. Assertable as: the set of `make` targets used in steps ⊆ (pre-flight targets ∪ targets introduced by earlier steps).
4. **Structural completeness.** Every step heading is followed by all three D-54 blocks, and the step headings appear in the D-55 order.

Passing all four means the document is *self-contained and executable*. It does **not** mean it is *comprehensible* — whether the takeaway prose lands with a room of humans is a judgement no assertion can make. The plan should therefore carry an explicit `checkpoint:human-verify` task: **one person who has not seen the demo runs `WALKTHROUGH.md` top to bottom on a clean checkout and reports every point at which they had to guess.** That checkpoint is the only real evidence for criterion 5, and the VERIFICATION document should say so plainly rather than claiming mechanical coverage.

#### As built

All four parts are asserted by `section_walkthrough`, and the section's own header comment states in
its second paragraph what it does **not** prove. The four parts landed as follows:

1. Commands are extracted from the document's fenced ` ```bash ` blocks; `make` targets are checked
   against the `Makefile`'s `.PHONY` list, all other commands against `command -v`. 11 command lines
   extracted, 6 distinct targets, 1 distinct binary — all resolve.
2. Repository-relative paths are extracted from the document's own backticked tokens. 4 extracted, all
   resolve. Absolute paths (`/etc/hosts`, `/root/.ssh/known_hosts`) are deliberately excluded: they are
   the host's and the client container's, not this repository's.
3. Prerequisite closure is asserted per step: every `make` target named anywhere inside step *N* must
   already be in (pre-flight targets ∪ Run-block targets of steps 1..*N*). 0 unintroduced.
4. 8 headings, 8 Run, 8 Expect, 8 Say, with the per-step sequence compared against the literal `RES`
   so a step carrying two Says and no Expect cannot be balanced out by its neighbour. Heading numbers
   asserted `1..8` ascending and the heading keywords asserted in the D-55 order.

Every extracted set is asserted non-empty before anything is counted (T-04-17), and the lint was proven
capable of failing before it was trusted — four deliberate breakages, each turning the suite red and
each reverted: the document moved aside (15 failures), a `**Say**` label removed from beat 4 (2), a
`make` target renamed in the document only (1), and beats 6 and 7 swapped (1).

**What this does not license.** Passing all 25 assertions means `WALKTHROUGH.md` is self-contained and
executable. It is **not** evidence for ROADMAP criterion 5 and must never be cited as such. Criterion 5
is carried by the blocking `checkpoint:human-verify` task in plan 04-04 (Task 3) and by nothing else.

**Outcome of the checkpoint (2026-07-21).** The gate halted as designed and the project **owner**
approved. Because the owner watched the entire build, this is an **owner-judgement acceptance**, not an
independent cold read — no fresh, never-seen-it reader ran the document top to bottom. The
comprehensibility dimension of criterion 5 is accepted on that owner judgement; the self-containedness
and executability dimensions are mechanically verified by `section_walkthrough`. No reader guess-points
were supplied, so there are no verbatim gaps recorded against `WALKTHROUGH.md`. The structured backstop
truth in 04-04's must-haves stays authored as-is: a verifier reading the automated evidence should still
abstain and escalate to a human rather than infer a pass — the owner's acceptance is a decision recorded
beside it, not a conversion of it.

### On the full-run rehearsal (research question 10)

**Recommendation: yes, and it is already written.** `section_hostkey` as specified above *is* the end-to-end rehearsal — prime on OLD → flip → gotcha → fix → success — because those are the only steps that can prove KEY-01..KEY-04 anyway. It was executed in full in this session and all seven assertions passed. Adding it costs nothing beyond the assertions the requirements already demand.

Weighed honestly:
- **Slow?** No. Measured under 20 s, dominated by `docker compose exec` round-trips. It is comparable to `section_cutover`.
- **Destructive?** Yes — it flips the selector and arms/fixes the gotcha. But `section_cutover` and `guard_check` are already destructive and already trap-restored; this follows the same established idiom rather than introducing a new hazard.
- **Value:** it is the only thing that stops `WALKTHROUGH.md` rotting. A document that describes a five-step narrative, backed by a test that executes that same five-step narrative, cannot drift silently.

What it deliberately does **not** cover: the browser beats (incognito, the 301 contrast, the status page). Those are already human-verified from Phases 1–2 and re-automating them here would be scope creep.

---

## Validation Sign-Off

Every item below is ticked only against a check that was actually run and named. Nothing is ticked
because everything around it is green.

- [x] `sh scripts/smoke.sh proxy` still returns exactly 17/17 — asserted as an anchored exact match, never a substring, and never adjusted to match a result (T-04-18)
- [x] All 186 inherited assertions still pass — the full suite reports 231, and 231 − 20 (`section_hostkey`) − 25 (`section_walkthrough`) = 186
- [x] Presenter-mode SSH pins `-o UpdateHostKeys=no` so KEY-04 is mechanically assertable (D-58) — `Makefile:173`, and `KEY-04 the client's trust record is byte-identical across the fix` is the assertion that depends on it
- [x] The gotcha assertion checks BOTH the warning text AND a non-zero exit code, without piping ssh — `KEY-02 the gotcha: a non-zero exit AND the changed-identification warning`, with `KEY-02 guard: no ssh invocation sits on the left of a pipe in this section` asserting the pipeline hazard stays absent
- [x] The re-arm path is asserted, not assumed — `KEY-01 the re-arm restores the DIFFERING fingerprints` and `KEY-01 the re-arm clears the client's trust record`
- [x] **Criterion 5 has an explicit human checkpoint — it is not mechanically verifiable.** *criterion 5: accepted on owner judgement 2026-07-21; independent cold read not performed.* The checkpoint **existed and halted** as designed: plan 04-04 Task 3 is a `checkpoint:human-verify` with `gate="blocking"`, 04-04 is `autonomous: false`, and execution genuinely stopped there. The project **owner** — who watched the entire build — reviewed and **approved**. That is an **owner-judgement acceptance**, *not* evidence that someone who has never seen the demo can follow `WALKTHROUGH.md` cold: no independent fresh reader performed the cold read. The comprehensibility dimension of criterion 5 is therefore accepted on owner judgement, recorded as a decision alongside the structured backstop — **not** a conversion of the backstop into a mechanical pass. `section_walkthrough`'s 25 assertions prove the document is self-contained and executable; they are not, and are nowhere cited as, evidence for comprehensibility (T-04-16). No reader guess-points were supplied, so there are no verbatim gaps to record against `WALKTHROUGH.md`.
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** signed off. Mechanical gate green (231/231 from cold, 17/17 proxy guard intact).
**Criterion 5:** accepted on owner judgement 2026-07-21; independent cold read not performed. The
doc-lint proves self-containedness and executability only; comprehensibility rests on the owner's
acceptance, and the structured backstop remains authored so the verifier abstains and escalates to a
human rather than inferring a pass on the automated evidence.
