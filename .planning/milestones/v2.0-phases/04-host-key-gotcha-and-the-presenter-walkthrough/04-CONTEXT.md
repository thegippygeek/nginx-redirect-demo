# Phase 4: Host-Key Gotcha and the Presenter Walkthrough - Context

**Gathered:** 2026-07-21
**Status:** Ready for planning
**Mode:** AUTO — the user selected fully-autonomous execution, so the decisions below were chosen by Claude. Each carries its rationale and the alternative it beat.

<domain>
## Phase Boundary

The final phase, and the one carrying the demo's most valuable lesson. The presenter deliberately triggers the SSH host-key mismatch after a cutover, fixes it live without the client touching anything, and can run the entire demo from a written script.

Requirements: KEY-01, KEY-02, KEY-03, KEY-04, WALK-01, WALK-02, WALK-03.

**Nothing is deferred past this phase** — this closes v1.

</domain>

<decisions>
## Implementation Decisions (auto-selected)

### Staging the mismatch (KEY-01, KEY-02)

- **D-47 [AUTO]:** The mismatch is **already the default state and needs no staging work** — Phase 1 deliberately generates SSH host keys at container runtime rather than build time, so `server-old` and `server-new` have differed since day one. Phase 3's verifier reproduced `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!` live through the proxy. This phase's job is to make the failure *reachable on demand*, not to create it.
  - *This is the payoff of a Phase 1 decision made specifically to keep this option open.* Building keys at image time would have made the two backends identical and this phase impossible.

- **D-48 [AUTO — CORRECTED BY RESEARCH 2026-07-21]:** ~~The client must persist `known_hosts` across the flip via a new mechanism.~~ **Research proved the opposite, and the original decision would have broken the demo.**

  The `client` container's writable layer *already* holds `/root/.ssh/known_hosts`, and its lifetime is automatically coupled to the backends' host-key lifetime — every Compose operation that regenerates backend keys also recreates the client. **No new persistence mechanism is needed, and adding one is actively harmful:** a named volume survives `docker compose down` and would make the gotcha fire *before* the flip; a bind mount would additionally defeat `make reset` as the re-arm path and write host state the project forbids.

  The second connection mode is still real, but it is about **ssh options**, not storage. Presenter mode uses a real `known_hosts` with strict checking; test mode keeps Phase 3's `-o UserKnownHostsFile=/dev/null` pins so all 186 existing assertions stay untouched.

- **D-58 [FROM RESEARCH]:** Presenter-mode SSH must pin **`-o UpdateHostKeys=no`**. OpenSSH defaults `UpdateHostKeys` to `yes`, and the first successful post-fix connection silently appended RSA and ECDSA keys — measured 95 → 837 bytes, plus a `known_hosts.old`, with the presenter touching nothing. Pinning it off makes the file provably byte-identical across the whole narrative, turning KEY-04's "no client-side edit" from a claim about intent into a mechanical assertion.

### The fix (KEY-03, KEY-04)

- **D-49 [AUTO]:** The documented fix is **transferring `server-old`'s host keys to `server-new`**, not editing the client's `known_hosts`. This is the whole point: in a real migration you cannot reach into every client on the network and tell them to forget a key. Making the *new server present the old server's identity* is what a real cutover does.
  - `ssh-keygen -R` on the client is the WRONG fix and must be explicitly named as such in the walkthrough — it is what people reach for, it works for one client, and it does not scale. Showing why it is wrong is worth as much as showing the right answer.
- **D-59 [FROM RESEARCH]:** **Copying the key files is not the fix.** A connection attempted after a verified successful transfer *still* failed on the old in-memory fingerprint — sshd loads host keys once at startup. `kill -HUP $(cat /run/sshd.pid)` is required and sufficient: it preserves the PID and leaves supervisord undisturbed. Whole fix measured at 0.44s, and it survives `docker compose restart`, so the presenter cannot be ambushed mid-demo.

- **D-50 [AUTO]:** The fix is applied by a **`make` target** (e.g. `make fix-hostkeys`) that copies the keys and restarts sshd on the target, so the presenter runs one memorable command rather than a multi-line pipeline live. The underlying commands stay visible in the walkthrough for the audience.
- **D-51 [AUTO]:** The fix must be **reversible**, so the gotcha can be re-armed for the next take. `make reset` already rebuilds from scratch, which regenerates distinct keys — that is the re-arm path, and it should be stated explicitly rather than left to inference.

### Demo mode vs test mode

- **D-52 [AUTO]:** Two explicit, named connection modes, documented as such:
  - **presenter mode** — real `known_hosts`, strict checking, the mode that produces the gotcha
  - **test mode** — `UserKnownHostsFile=/dev/null`, the mode all 186 existing assertions use
  The distinction must be visible in the README, because a presenter who runs the test-mode command on stage will silently get no gotcha and will not know why.

### The walkthrough (WALK-01, WALK-02, WALK-03)

- **D-53 [AUTO]:** A **separate `WALKTHROUGH.md`**, not another README section. The README is reference material; the walkthrough is a script read in order, under time pressure, in front of people. Different documents with different jobs.
- **D-54 [AUTO]:** Every step carries **three things**: the exact command to run, the output to expect, and the audience takeaway — the last being what the presenter actually says out loud. WALK-02 and WALK-03 require the first two; the third is what makes it usable cold.
- **D-55 [AUTO]:** The narrative order is fixed by the roadmap: **show old → flip → show new → SSH gotcha → fix.** The 301-redirect contrast from Phase 1 slots in before the flip as the conceptual setup.
- **D-56 [AUTO]:** The walkthrough includes a **pre-flight checklist** — `/etc/hosts` entry present, `make status` green, incognito window open, evidence cleared. Every one of these has already bitten during development; a presenter discovering them live is the failure mode this document exists to prevent.
- **D-57 [AUTO]:** It also documents the **known traps** discovered across all four phases: browser 301 caching requiring incognito, the client-container prefix for SSH, the fact that 9093 does not follow the flip, and that `make reset` is the re-arm path.

### Claude's Discretion

- ~~The mechanism for persisting the client's `known_hosts`~~ — settled by research: none is needed, and adding one breaks the demo. See D-48.
- Whether presenter mode is a separate `make` target, an env var, or a documented `ssh` invocation.
- How host keys are copied in `make fix-hostkeys` (docker cp, exec + tar, or a shared volume).
- Whether `WALKTHROUGH.md` also gets a printable/condensed cue-card form.

</decisions>

<canonical_refs>
## Canonical References

- `.planning/phases/03-ssh-through-the-stream-proxy/03-VERIFICATION.md` — confirms the mismatch mechanism works and is unstaged; host key fingerprints differ.
- `.planning/phases/03-ssh-through-the-stream-proxy/03-CONTEXT.md` — D-37..D-46. **D-37: the `client` container is the canonical SSH source.**
- `.planning/phases/01-demo-up-http-lands-on-old/01-CONTEXT.md` — D-01..D-22. **D-22: hostname is `app.demo.test`. D-16/D-18: one image, runtime host keys — the reason this phase is possible.**
- `.planning/phases/02-the-live-http-cutover/02-CONTEXT.md` — D-23..D-36, the flip and status page the walkthrough narrates.
- `README.md` — existing presenter reference; `WALKTHROUGH.md` complements rather than duplicates it.
- `.planning/ROADMAP.md` §"Phase 4" — the five success criteria, including criterion 5: someone who has never seen the demo can follow it cold.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **Runtime-generated, deliberately-differing host keys** on both backends — asserted in the suite since Phase 1. The whole phase rests on this.
- **`scripts/verify.sh`** and `make verify` — the walkthrough can use these as the "prove it" beat.
- **`scripts/flip.sh`**, `make flip` / `flip-old` / `flip-new` — the cutover the walkthrough narrates.
- **The status page** at `:9094` — the projected evidence surface.
- **`scripts/smoke.sh`** — 186 assertions, section-dispatched. Phase 4 adds a section.
- **`make reset`** — full teardown and rebuild; regenerates host keys, so it is the gotcha re-arm path (D-51).

### Integration Points

- The `client` container gains a persistent `known_hosts` for presenter mode (D-48) without disturbing test mode.
- `Makefile` gains the fix target and possibly a presenter-mode ssh target.
- `README.md` gains a pointer to `WALKTHROUGH.md` and the presenter/test mode distinction.

### Constraints inherited

- **`sh scripts/smoke.sh proxy` must stay at exactly 17/17** — it has survived all three prior phases.
- **All 186 existing assertions must keep passing.** Phase 3's `-o UserKnownHostsFile=/dev/null` pins exist precisely so this phase cannot break them; do not remove them.
- Published ports remain 9090/9091/9092/9093/9094 — no port 22 on the host.
- The repo never modifies host state.

</code_context>

<specifics>
## Specific Ideas

- **The `ssh-keygen -R` moment is the teaching moment.** Most people's instinct is to fix the client. Showing that instinct, then showing why it does not scale to a real fleet, is the most valuable 30 seconds in the demo.
- The walkthrough should read like something a colleague could pick up and run without the author in the room — that is literally success criterion 5.
- The pre-flight checklist exists because every item on it has already caused a real failure during this project's own development.

</specifics>

<deferred>
## Deferred Ideas

- A printable one-page cue card derived from `WALKTHROUGH.md` — nice, not required.
- Automated walkthrough playback with narration pauses — explicitly out of scope for v1 (PROJECT.md).
- Making the 9093 redirect follow the flip — still deliberately static.
- An SSH connection counter on the status page (Phase 3's D-46) — still deferred.

</deferred>

<open_concerns>
## Open Concerns

- **These decisions were auto-selected, not user-answered.** D-49 (fix by transferring host keys to the new server rather than clearing the client) is the phase's core teaching claim. It is the correct real-world answer and the roadmap requires it, but the *framing* — how hard to lean on "`ssh-keygen -R` is the wrong fix" — is a presentation judgement the user may want to set themselves.
- Criterion 5 ("someone who has never seen the demo can follow it cold") cannot be mechanically verified. It will need either a human reviewer or an explicit acknowledgement that it rests on judgement.

</open_concerns>

---

*Phase: 4-Host-Key Gotcha and the Presenter Walkthrough*
*Context gathered: 2026-07-21 (auto mode)*
