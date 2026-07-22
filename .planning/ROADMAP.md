# Roadmap: Server Migration Redirect Demo

## Overview

The demo is built as four vertical slices, each one a bigger piece of the on-stage narrative. Phase 1 gets the whole rig up with one command and lands HTTP on `server-old` through nginx — including the 301 redirect contrast that sets up the conceptual point. Phase 2 delivers the money shot: the live upstream flip, with logs and a status page proving where traffic went. Phase 3 extends the same cutover to SSH over nginx's `stream` module and adds an automated verify script that asserts which backend answered over both protocols. Phase 4 stages the SSH host-key failure, fixes it, and wraps the whole thing in a written walkthrough the presenter can run cold.

**v2.0 — Two-Proxy Switch Topology** (Phases 5–7) restructures the shipped v1 demo without changing what the client sees. v1's single flip-in-place proxy becomes a blue-green tier: a front `switch` nginx flips traffic between two *static* single-upstream proxies (`proxy-old`, `proxy-new`), each aliased `app-old`/`app-new.demo.test`. The map-flip + `nginx -s reload` *mechanism* is identical to v1 — the on-stage flip action is unchanged — but the architecture around it buys two new payoffs: the presenter can validate the new stack (`curl`/`ssh app-new.demo.test`) *before* flipping, and rollback is instant, so "the old proxy is never touched" becomes literally true. Phase 5 stands up the topology with the HTTP flip working and evidence re-sourced from the switch. Phase 6 extends the switch's one-line selector to the SSH:22 stream and delivers pre-flip validation over both protocols plus the re-pointed verify script. Phase 7 closes the story: instant rollback, provably-untouched static proxies, the preserved v1 demo, and the rewritten walkthrough.

Every phase ends in something demoable in front of an audience.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Demo Up, HTTP Lands on OLD** - One command brings up nginx + two backends; port 9092 proxies to `server-old` and a second port shows the 301 redirect contrast
- [x] **Phase 2: The Live HTTP Cutover** - Edit upstream, reload, and HTTP lands on NEW with logs and a status page as proof
- [x] **Phase 3: SSH Through the Stream Proxy** - `ssh` on port 22 lands on the active backend across the same cutover, with a verify script asserting both protocols
- [x] **Phase 4: Host-Key Gotcha and the Presenter Walkthrough** - The `REMOTE HOST IDENTIFICATION HAS CHANGED` failure staged, fixed, and documented as a runnable narrative

**v2.0 — Two-Proxy Switch Topology** *(subsequent milestone; v1 shipped as Phases 1–4 above, preserved at git tag `v1.0`)*

- [x] **Phase 5: The Switch and Two Static Proxies — HTTP Cutover Re-Homed** - A front `switch` flips HTTP between two static proxies; the client still hits `app.demo.test:9092` unchanged and the status page is re-sourced from the switch (completed 2026-07-22)
- [x] **Phase 6: The SSH Stream Flip and Pre-Flip Validation** - The switch's one-line selector governs SSH:22 too, and the presenter can `curl`/`ssh app-new.demo.test` to prove the new stack live before flipping — with the verify script re-pointed (completed 2026-07-22)
- [x] **Phase 7: Instant Rollback, v1 Preservation, and the v2 Walkthrough** - Flip the switch back for an instant teardown-free rollback, prove the static proxies were never touched, keep v1 runnable, and rewrite the walkthrough for the v2 story (completed 2026-07-22)

## Phase Details

### Phase 1: Demo Up, HTTP Lands on OLD

**Goal**: Presenter runs one command and can immediately show a browser/curl hitting nginx on port 9092, landing on `server-old`, with the URL unchanged — and show the redirect approach alongside it changing the URL
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: ENV-01, ENV-02, ENV-03, ENV-04, BACK-01, BACK-02, BACK-03, HTTP-01, HTTP-02, HTTP-03, HTTP-04
**Success Criteria** (what must be TRUE):

  1. Presenter runs `docker compose up` and nginx, `server-old`, and `server-new` all come up healthy with no cloud account, credentials, or prior setup
  2. `curl http://localhost:9092` returns a body that names the backend as OLD with its hostname, and the client's address and port are unchanged in the request
  3. Hitting the redirect port returns a 3xx with a `Location` header, and `curl -L` visibly ends up on a different URL than the one requested — the contrast with the proxied port is showable side by side
  4. Presenter runs one teardown command and can bring the demo back to the identical clean starting state
  5. `nginx -V` inside the proxy container shows the `stream` module is compiled in, so port 22 proxying is possible later

**Plans**: 3/3 plans executed

Plans:
**Wave 1**

- [x] 01-01-PLAN.md — Walking skeleton foundation: test harness, presenter Makefile, the one-image/two-identities backend, and `docker compose up` bringing both boxes up healthy (ENV-01/02/03, BACK-01/02/03)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 01-02-PLAN.md — nginx joins the stack: transparent reverse proxy on 9092 landing on `server-old` via `app.demo.test`, plus the flip include, log format, and invalid-selector guard (ENV-04, HTTP-01/02)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 01-03-PLAN.md — The 301 redirect contrast on 9093, the presenter README, and the human browser side-by-side verification (HTTP-03/04, ENV-03 inspection)

### Phase 2: The Live HTTP Cutover

**Goal**: Presenter flips the nginx upstream from old to new on stage, reloads, and the audience sees the same URL now answered by `server-new` — with independent evidence confirming it
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: CUT-01, CUT-02, CUT-03, CUT-05, EVID-01, EVID-02, EVID-03
**Success Criteria** (what must be TRUE):

  1. Presenter edits the nginx upstream and reloads, and the identical `curl http://localhost:9092` command — no client-side change of any kind — now returns a body naming the backend as NEW
  2. A live tail of nginx access logs shows each request and which upstream served it, visibly switching from old to new at the moment of the flip
  3. A status page shows which backend is currently active and lists recent requests with the backend that answered each
  4. Presenter can flip back to `server-old` and re-run the whole cutover without tearing anything down

**Plans**: 4/4 plans executed
**UI hint**: yes

Plans:
**Wave 1**

- [x] 02-01-PLAN.md — The flip pipeline: gate both backends, rewrite the one word, print the diff, reload, prove via the `:8081` oracle, settle; plus the dual evidence log and the two log views (CUT-01/02/03/05, EVID-01)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 02-02-PLAN.md — The stateless evidence service: a fourth container deriving config, traffic, counters and boundary from two read-only files plus a live proxy probe, exposed as `/api/status` (EVID-01/02/03, CUT-05)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 02-03-PLAN.md — The projected status page to `02-UI-SPEC.md`: the D-27 dual reading, the recent-requests table with its flip boundary, the stats rail, and the four states with the convergence sequence (EVID-02/03)

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 02-04-PLAN.md — UI token audit as a permanent regression guard, the presenter's Phase 2 README, and the human visual sign-off (EVID-02/03, CUT-05)

### Phase 3: SSH Through the Stream Proxy

**Goal**: Presenter SSHes to port 22 on the same host and lands on whichever backend is active, proving the cutover is not just an HTTP trick — with a script that asserts it automatically
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: BACK-04, BACK-05, SSH-01, SSH-02, SSH-03, CUT-04, EVID-04, EVID-05
**Success Criteria** (what must be TRUE):

  1. Presenter runs `ssh` against the nginx host on port 22 with a known credential or key and gets a shell on the active backend, whose login banner names it as OLD or NEW with its hostname
  2. The nginx config visibly uses a `stream` block proxying raw TCP — presenter can show it is a TCP proxy, not an HTTP redirect
  3. After the upstream flip, a new SSH session lands on `server-new` and its banner says NEW, using the identical `ssh` command as before
  4. A verify script issues an HTTP request and an SSH connection, reports which backend answered each, and exits non-zero when the observed backend does not match the expected one

**Plans**: 3/3 plans executed

Plans:
**Wave 1**

- [x] 03-01-PLAN.md — SSH into a backend and it says who it is: the `Banner` identity surface rendered from `BACKEND_ID`, the sshd drop-in that actually takes effect, and key distribution via the `demo-keys` volume (BACK-04/05)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 03-02-PLAN.md — The `stream` block: D-39's shared include in a second context, the stream access log to stdout, the flip over SSH, and the Phase 2 deferred question resolved with a measurement (SSH-01/02/03, CUT-04)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 03-03-PLAN.md — `scripts/verify.sh` and `make verify`: both protocols reported on every run, non-zero on mismatch and a distinct exit when the two protocols disagree with each other (EVID-04/05)

### Phase 4: Host-Key Gotcha and the Presenter Walkthrough

**Goal**: Presenter can deliberately trigger the SSH host-key mismatch after cutover, fix it live without touching the client, and run the entire demo from a written script
**Mode:** mvp
**Depends on**: Phase 3
**Requirements**: KEY-01, KEY-02, KEY-03, KEY-04, WALK-01, WALK-02, WALK-03
**Success Criteria** (what must be TRUE):

  1. Presenter can start the demo in a state where `server-new` has different SSH host keys from `server-old`
  2. After the cutover in that state, the client's `ssh` attempt fails visibly with `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED`
  3. Presenter applies the documented host-key transfer fix, and the same `ssh` command then succeeds against `server-new` with no edit to the client's `known_hosts`
  4. A written walkthrough covers the full narrative in order — show old → flip → show new → SSH gotcha → fix — with the exact command, the expected output, and the audience takeaway for each step
  5. Someone who has never seen the demo can follow the walkthrough top to bottom and reproduce every beat
     *(Judgement, not mechanically verifiable. The doc-lint in 04-04 proves the walkthrough is self-contained and executable; criterion 5 itself rests on the explicit cold-read human check in that plan.)*

**Plans**: 4/4 plans executed

Plans:
**Wave 1**

- [x] 04-01-PLAN.md — The mechanism: presenter mode (`make ssh`), the fix (`scripts/fix-hostkeys.sh` — transfer *and* signal the daemon), and the in-place re-arm (`scripts/rearm.sh`). The whole host-key narrative runnable by hand (KEY-01/02/03/04)

**Wave 2** *(blocked on Wave 1 completion; 04-02 holds **exclusive use of the Docker rig** for the whole wave — 04-03 is documentation and every check in it is static, so the two are safe to run together)*

- [x] 04-02-PLAN.md — `section_hostkey`: the five beats executed for real inside the suite — prime, flip, the failure on both halves with a negative control, the fix by fingerprint equality, the byte-identical trust record, and the asserted re-arm (KEY-01/02/03/04)
- [x] 04-03-PLAN.md — `WALKTHROUGH.md`: pre-flight, six beats each with command, expected output and takeaway, the wrong fix shown then contrasted, and the traps section; plus the README's corrected SSH example and the two named connection modes (WALK-01/02/03)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 04-04-PLAN.md — `section_walkthrough`: the four-part executable contract that stops the document rotting, the phase gate from cold, and the criterion-5 cold read as a **blocking human checkpoint** — `autonomous: false` (WALK-01/02/03)

---

*The phases below belong to milestone **v2.0 — Two-Proxy Switch Topology**. They continue the numbering from v1's Phase 4; Phases 1–4 above are shipped and unchanged.*

### Phases 5–7 — Milestone v2.0 (Two-Proxy Switch Topology) — ✅ SHIPPED 2026-07-22

Full phase details, plans, and success criteria archived in **`.planning/milestones/v2.0-ROADMAP.md`** (tag `v2.0`).

- **Phase 5** — The switch + two static proxies; HTTP cutover re-homed; evidence re-sourced from the switch.
- **Phase 6** — The switch's SSH:22 stream flip (one edit, both protocols) + pre-flip `app-new.demo.test` validation.
- **Phase 7** — Instant rollback (no teardown), the byte-unchanged checksum, v1 preserved at tag `v1.0`, and the v2 walkthrough rewrite.

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Demo Up, HTTP Lands on OLD | 3/3 | Complete | 2026-07-21 |
| 2. The Live HTTP Cutover | 4/4 | Complete | 2026-07-21 |
| 3. SSH Through the Stream Proxy | 3/3 | Complete | 2026-07-21 |
| 4. Host-Key Gotcha and the Presenter Walkthrough | 4/4 | Complete | 2026-07-22 |
| 5. The Switch and Two Static Proxies — HTTP Cutover Re-Homed | 3/3 | Complete    | 2026-07-22 |
| 6. The SSH Stream Flip and Pre-Flip Validation | 2/2 | Complete    | 2026-07-22 |
| 7. Instant Rollback, v1 Preservation, and the v2 Walkthrough | 2/2 | Complete    | 2026-07-22 |

## Requirement Coverage

| Phase | Requirements | Count |
|-------|--------------|-------|
| 1 | ENV-01, ENV-02, ENV-03, ENV-04, BACK-01, BACK-02, BACK-03, HTTP-01, HTTP-02, HTTP-03, HTTP-04 | 11 |
| 2 | CUT-01, CUT-02, CUT-03, CUT-05, EVID-01, EVID-02, EVID-03 | 7 |
| 3 | BACK-04, BACK-05, SSH-01, SSH-02, SSH-03, CUT-04, EVID-04, EVID-05 | 8 |
| 4 | KEY-01, KEY-02, KEY-03, KEY-04, WALK-01, WALK-02, WALK-03 | 7 |
| 5 | SW-01, SW-02, SW-04, PROX-01, PROX-02, PROX-03, EV2-01, EV2-02, EV2-03, MIG-01 | 10 |
| 6 | SW-03, VAL-01, VAL-02, EV2-04 | 4 |
| 7 | VAL-03, VAL-04, MIG-02, MIG-03 | 4 |

**v1: 33/33 requirements mapped (Phases 1–4). v2.0: 18/18 requirements mapped (Phases 5–7). No orphans, no duplicates. 51 total.**

---
*Roadmap created: 2026-07-21*
*Updated: 2026-07-22 — appended milestone v2.0 (two-proxy switch topology), Phases 5–7*
