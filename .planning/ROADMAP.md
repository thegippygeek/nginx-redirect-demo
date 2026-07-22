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
- [ ] **Phase 7: Instant Rollback, v1 Preservation, and the v2 Walkthrough** - Flip the switch back for an instant teardown-free rollback, prove the static proxies were never touched, keep v1 runnable, and rewrite the walkthrough for the v2 story

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

### Phase 5: The Switch and Two Static Proxies — HTTP Cutover Re-Homed

**Goal**: Replace v1's single flip-in-place proxy with a blue-green tier — a front `switch` nginx and two *static* single-upstream proxies (`proxy-old`→`server-old`, `proxy-new`→`server-new`, aliased `app-old`/`app-new.demo.test`). The client still hits `app.demo.test:9092` exactly as in v1, HTTP lands on OLD through `switch → proxy-old → server-old`, and one edit-and-reload of the switch's one-line map flips HTTP to NEW. The status page and evidence log are re-sourced from the **switch**, which sees the client's real `remote_addr` while the backend's own `X-Backend` identity still flows back up the chain.
**Mode:** mvp
**Depends on**: Phase 4
**Requirements**: SW-01, SW-02, SW-04, PROX-01, PROX-02, PROX-03, EV2-01, EV2-02, EV2-03, MIG-01
**Success Criteria** (what must be TRUE):

  1. `docker compose up` brings up the switch, `proxy-old`, `proxy-new`, `server-old`, `server-new`, and status together with one command, and `curl http://localhost:9092` lands on OLD through the switch and the static proxy — the client's hostname and port unchanged from v1
  2. Editing the one-line `default old`→`new` map in `switch/active-proxy.conf` and reloading the switch (`nginx -s reload`) flips HTTP to NEW using the identical client command — no client-side change, the same map-flip + reload mechanism as v1's CUT-01/CUT-02
  3. The status page reads the **switch's** log: recent-request rows show the client's real `remote_addr` (not a downstream proxy's address), and `backend=OLD/NEW` is carried back from the backend's own `X-Backend` header through the proxy chain, asserted by no proxy tier
  4. The status page shows the current switch selector (which proxy is active) and recent requests with the backend that answered each — the v1 EVID-02/03 guarantees, re-sourced from the switch

**Plans**: 3 plans
**UI hint**: yes

Plans:
**Wave 1**

- [x] 05-01-PLAN.md — The three nginx tiers: switch (flip surface + evidence writer, upstreams re-pointed, +remote field) and two static single-upstream proxies, each config-tested under nginx -t (SW-01, SW-02, PROX-01, PROX-02, EV2-01, EV2-02)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 05-02-PLAN.md — The rig comes up: compose split into switch + proxy-old + proxy-new with the health cascade, alias moved to the switch, evidence re-sourced (client remote_addr rendered), make up re-pointed, topology smoke sections reconciled (SW-01, PROX-01/02/03, EV2-01/02/03, MIG-01)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 05-03-PLAN.md — The flip re-homed: flip.sh + make reset re-pointed to the switch, section_cutover reconciled, make test green across the HTTP surface with the switch-SSH sections deferred to Phase 6 (SW-04, EV2-03)

### Phase 6: The SSH Stream Flip and Pre-Flip Validation

**Goal**: Extend the switch's single one-line selector to govern the SSH:22 `stream` path as well as HTTP:9092, so one edit flips both protocols — then deliver the milestone's new payoff: the presenter can `curl app-new.demo.test` and `ssh app-new.demo.test` to prove the new stack is live *before* any cutover (while live traffic on `app.demo.test` still lands on OLD), with the verify script re-pointed at the switch and able to target `app-new.demo.test` directly.
**Mode:** mvp
**Depends on**: Phase 5
**Requirements**: SW-03, VAL-01, VAL-02, EV2-04
**Success Criteria** (what must be TRUE):

  1. `ssh app.demo.test` on port 22 lands on the active backend through `switch → proxy → server`, and the same one-line selector edit that flips HTTP also flips SSH — one edit, both protocols, the switch reloaded the same way as v1
  2. Before any cutover, `curl app-new.demo.test` returns NEW and `ssh app-new.demo.test` shows `server-new`'s banner, while `app.demo.test` still lands on OLD — the new stack is provably live over both protocols before the presenter commits to the flip
  3. The verify script asserts over both HTTP and SSH which backend answered *through the switch*, exits non-zero on mismatch, and can be pointed at `app-new.demo.test` to validate the new stack pre-flip

**Plans**: 2 plans

Plans:
**Wave 1**

- [x] 06-01-PLAN.md — Re-home v1's SSH:22 stream block onto the switch (3 string edits) and reconcile + re-enable section_ssh / section_hostkey; one selector edit flips both protocols (SW-03, finalizes SW-01)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 06-02-PLAN.md — Pre-flip validation over both protocols: verify.sh `--target app-new` mode + `make verify-new-stack` and a non-destructive section_validate proving `curl`/`ssh app-new.demo.test` → NEW while `app.demo.test` → OLD (VAL-01, VAL-02, EV2-04)

### Phase 7: Instant Rollback, v1 Preservation, and the v2 Walkthrough

**Goal**: Close the milestone's story. After a cutover the presenter rolls back to OLD instantly by flipping the switch selector back and reloading — no teardown; the two static proxies are shown byte-unchanged across the whole cutover so "the old proxy is never touched" is literally true; the v1 single-proxy demo stays runnable from its preserved form (git tag `v1.0` / a kept compose file); and the presenter walkthrough is rewritten for the v2 narrative — validate the new stack → flip the switch → land on new → (host-key gotcha, inherited from v1) → roll back → the old proxy was never touched.
**Mode:** mvp
**Depends on**: Phase 6
**Requirements**: VAL-03, VAL-04, MIG-02, MIG-03
**Success Criteria** (what must be TRUE):

  1. After a cutover to NEW, the presenter flips the switch selector back to `old` and reloads, and both HTTP and SSH return to landing on OLD — an instant rollback with no teardown of any container
  2. The two static proxies' config files are shown byte-identical before and after the whole cutover-and-rollback cycle — "the old proxy is never touched" is a verifiable checksum, not a claim
  3. The v1 single-proxy demo still comes up and runs from its preserved form (git tag `v1.0` or a kept compose file), unbroken by the v2 restructure
  4. A rewritten walkthrough runs the full v2 narrative in order — validate `app-new.demo.test` → flip the switch → land on new → host-key gotcha (inherited from v1, surfaced not re-scoped) → roll back → the old proxy was never touched — each beat with its command, expected output, and takeaway

**Plans**: TBD

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
| 7. Instant Rollback, v1 Preservation, and the v2 Walkthrough | 0/TBD | Not started | - |

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
