# Phase 3: SSH Through the Stream Proxy - Context

**Gathered:** 2026-07-21
**Status:** Ready for planning
**Mode:** AUTO — the user selected fully-autonomous execution, so the decisions below were chosen by Claude rather than answered by the user. Each carries its rationale and the alternative it beat. **Any of these can be overridden before execution.**

<domain>
## Phase Boundary

Prove the cutover is not an HTTP trick. The presenter `ssh`es on port 22, lands on whichever backend is active, and after the flip the identical `ssh` command lands on `server-new` — with a script that asserts both protocols automatically.

Requirements: BACK-04, BACK-05, SSH-01, SSH-02, SSH-03, CUT-04, EVID-04, EVID-05.

**Not this phase:** the host-key mismatch failure and its fix, and the written presenter walkthrough (Phase 4). This phase must *enable* Phase 4 — distinct host keys already exist per container — but must not stage the failure.

</domain>

<decisions>
## Implementation Decisions (auto-selected)

### Where SSH is reached from

- **D-37 [AUTO]:** The **`client` container is the canonical SSH source**, exactly as it is for HTTP. The presenter runs `docker compose exec client ssh demo@app.demo.test`. Inside the Docker network the proxy genuinely listens on **port 22**, so the "SSH on port 22" claim is literally true, not a workaround.
  - *Beat:* publishing `127.0.0.1:22` on the host. Host port 22 is free on this machine (verified), but binding a privileged port is host-state-dependent, would fail on any machine running its own sshd, and adds a privilege question the demo does not need. The client container needs no host privilege and works everywhere.
  - *Reinforced by:* Phase 1's D-02 already makes the client container the canonical client, and Phase 4's `known_hosts` manipulation is far safer inside a container the presenter can reset than in the presenter's real `~/.ssh/known_hosts`.
  - **This is the single most consequential auto-decision in the phase.** It was flagged as an open concern from roadmapping onward, and Phase 1's research recommended exactly this.

- **D-38 [AUTO]:** Port 22 is **not published to the host**. Nothing in the repo may bind a privileged host port. Consistent with Phase 1's threat T-01-06 (loopback-only publishing) and with the project's "never modify host state" prohibition.

### The stream block (D-13's payoff)

- **D-39 [AUTO]:** The `stream` block reuses **the same `proxy/active-backend.conf` include** the HTTP side uses. This is precisely why D-13 chose a `map` over an `upstream` — `map` is valid in both the `http` and `stream` contexts, while `upstream` is not shareable between them. `upstream` blocks are declared per-context; the *selector* is shared.
  - The presenter can therefore say truthfully: **one file, one word, both protocols.** That is the strongest possible version of the Phase 3 claim.
- **D-40 [AUTO]:** `worker_shutdown_timeout` stays **unset**, and the comment Phase 2 left in `nginx.conf` gets resolved here. An in-flight SSH session surviving the reload is a *feature* worth narrating ("existing sessions are undisturbed; new ones land on NEW") and matches nginx's default graceful behaviour. Setting a timeout to sever live sessions would be a deliberate act requiring justification the demo does not have.

### Authentication

- **D-41 [AUTO]:** **Key-based auth from the client container**, with the keypair generated at build or first run and the public key installed on both backends. No password prompt on stage — a prompt is dead air and a fumble risk in front of an audience.
  - Password auth for the `demo` user stays enabled as a documented fallback, so a presenter who wants to demonstrate from their own terminal still can.
  - The key is a **demo credential with no value**, and it never leaves the compose network (D-38 keeps SSH off the host).

### Identity signal (BACK-04, SSH-03)

- **D-42 [AUTO]:** The SSH **login banner** names the backend as `OLD` or `NEW` with its hostname, in the same visual register as the HTTP banner — the word carries the signal, colour is decoration only. Driven by the same `BACKEND_ID` env var as everything else (D-16), so the two identity surfaces cannot drift.
- **D-43 [AUTO]:** The banner must appear **before** the shell prompt and be visible even for a non-interactive `ssh … <command>` invocation, because the verify script (EVID-04) reads it programmatically.

### The verify script (EVID-04, EVID-05)

- **D-44 [AUTO]:** `scripts/verify.sh <expected>` — issues an HTTP request and an SSH connection, reports which backend answered each, and **exits non-zero on any mismatch**. Extends the existing POSIX-shell idiom rather than introducing a second one; `scripts/smoke.sh` already established it and Phase 1's research anticipated this exact extension.
- **D-45 [AUTO]:** The script asserts **both protocols agree with each other**, not just each against the expectation. HTTP on NEW while SSH is still on OLD is the interesting failure and the one worth catching.

### Evidence

- **D-46 [AUTO]:** SSH connections are **not** added to the status page's request table. The table is HTTP-shaped (path, status) and the projected layout is already at its vertical budget. The `stream` module's logging is separate and lands in `make logs`.
  - *Deferred, not rejected:* an SSH connection counter on the status page. If Phase 4 wants it, it is a small addition — but it is not needed to prove CUT-04.

### Claude's Discretion

- Which SSH client image the `client` container uses, and whether `openssh-client` is already present from Phase 1 (it was installed there deliberately — check before adding).
- The `stream` log format and where it writes, subject to `make logs` surfacing it.
- How the client's public key reaches both backends (build-time copy, entrypoint, or a mounted authorized_keys).
- Whether the verify script shells out to `docker compose exec` or runs inside the client container.

</decisions>

<canonical_refs>
## Canonical References

- `.planning/phases/01-demo-up-http-lands-on-old/01-CONTEXT.md` — D-01..D-22. **D-22: hostname is `app.demo.test`.** D-16 (one image, env-driven identity), D-17 (web+sshd co-located), D-18 (sshd built in Phase 1).
- `.planning/phases/02-the-live-http-cutover/02-CONTEXT.md` — D-23..D-36, especially D-33/D-34 (flip command shape) which this phase extends to SSH.
- `.planning/phases/02-the-live-http-cutover/02-01-SUMMARY.md` — `scripts/flip.sh`, the `:8081` oracle, the evidence sink.
- `.planning/phases/01-demo-up-http-lands-on-old/01-RESEARCH.md` — the `map`-not-`upstream` finding that D-39 depends on, and the runtime host-key generation that Phase 4 depends on.
- `.planning/ROADMAP.md` §"Phase 3" and §"Phase 4" — Phase 4 stages the host-key mismatch; do not stage it here, but do not prevent it either.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`proxy/active-backend.conf`** — the shared `map`. D-39 includes it from the `stream` block too. The file must stay five lines and keep its presenter comments.
- **`backend/` image** — already runs sshd alongside nginx under a supervisor (D-17/D-18), with **host keys generated at runtime so the two backends differ** (the Phase 4 precondition, asserted in the smoke suite).
- **`client/`** — already has `openssh-client` installed, deliberately, in Phase 1.
- **`scripts/smoke.sh`** — 120 assertions, section-dispatched, `assert` helper, trap-based restore discipline. Phase 3 adds a section; `scripts/verify.sh` follows the same idiom.
- **`scripts/flip.sh`** — the flip pipeline. If the flip needs to reload the stream side too, it already reloads nginx wholesale, so this may be free.

### Integration Points

- `proxy/nginx.conf` gains a top-level `stream { }` block — the first time this phase's namespace is touched. It must not disturb the `http` block or the 17/17 Phase 1 guard.
- `compose.yaml` — no new published ports (D-38).

### Known constraints inherited

- **`sh scripts/smoke.sh proxy` must stay at exactly 17/17.** It has survived every phase so far and is the canonical regression guard.
- Published ports bind `127.0.0.1` only.
- The repo never modifies host state; `sudo` appears only in printed remediation text.

</code_context>

<deferred>
## Deferred Ideas

- SSH connection counter on the status page (D-46) — small, not needed for CUT-04.
- Publishing port 22 to the host (D-37/D-38) — would make `ssh -p 22 app.demo.test` work from the presenter's own terminal. Rejected for privilege and portability, but a documented opt-in could be added if a venue demands it.
- Severing in-flight SSH sessions on reload via `worker_shutdown_timeout` (D-40) — a deliberate act needing its own justification.

</deferred>

<open_concerns>
## Open Concerns

- **These decisions were auto-selected, not user-answered.** D-37 in particular (client container as the canonical SSH source rather than publishing port 22) determines how the demo is narrated on stage. It is the option Phase 1's research recommended and the only one that keeps CUT-02 fully honest with no client-side flag — but it means the presenter types `docker compose exec client ssh …` rather than plain `ssh …`. If that reads as a cheat to the intended audience, D-37 is the decision to revisit.

</open_concerns>

---

*Phase: 3-SSH Through the Stream Proxy*
*Context gathered: 2026-07-21 (auto mode)*
